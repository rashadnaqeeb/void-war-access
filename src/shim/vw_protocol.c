// vw_protocol.c - pure protocol logic for the Void War Access shim.
// See vw_protocol.h for the threading and ownership contract.

#include "vw_protocol.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char *vwp_strdup(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p)
        memcpy(p, s, n);
    return p;
}

// ---- buffer ----

void vwp_buf_init(VwBuf *b)
{
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
    b->oom = 0;
}

void vwp_buf_free(VwBuf *b)
{
    free(b->data);
    vwp_buf_init(b);
}

static int buf_reserve(VwBuf *b, size_t extra)
{
    if (b->oom)
        return -1;
    size_t need = b->len + extra + 1;
    if (need <= b->cap)
        return 0;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < need)
        cap *= 2;
    char *p = realloc(b->data, cap);
    if (!p) {
        b->oom = 1;
        return -1;
    }
    b->data = p;
    b->cap = cap;
    return 0;
}

int vwp_buf_append(VwBuf *b, const char *s, size_t n)
{
    if (buf_reserve(b, n) != 0)
        return -1;
    memcpy(b->data + b->len, s, n);
    b->len += n;
    b->data[b->len] = '\0';
    return 0;
}

int vwp_buf_appendz(VwBuf *b, const char *s)
{
    return vwp_buf_append(b, s, strlen(s));
}

int vwp_buf_appendf(VwBuf *b, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (n < 0 || buf_reserve(b, (size_t)n) != 0)
        return -1;
    va_start(ap, fmt);
    vsnprintf(b->data + b->len, (size_t)n + 1, fmt, ap);
    va_end(ap);
    b->len += (size_t)n;
    return 0;
}

int vwp_json_escape(VwBuf *b, const char *s)
{
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        int rc;
        switch (*p) {
        case '"':  rc = vwp_buf_appendz(b, "\\\""); break;
        case '\\': rc = vwp_buf_appendz(b, "\\\\"); break;
        case '\b': rc = vwp_buf_appendz(b, "\\b"); break;
        case '\f': rc = vwp_buf_appendz(b, "\\f"); break;
        case '\n': rc = vwp_buf_appendz(b, "\\n"); break;
        case '\r': rc = vwp_buf_appendz(b, "\\r"); break;
        case '\t': rc = vwp_buf_appendz(b, "\\t"); break;
        default:
            if (*p < 0x20)
                rc = vwp_buf_appendf(b, "\\u%04x", *p);
            else
                rc = vwp_buf_append(b, (const char *)p, 1);
            break;
        }
        if (rc != 0)
            return -1;
    }
    return 0;
}

// ---- ring ----

void vwp_ring_init(VwRing *r)
{
    memset(r, 0, sizeof *r);
}

void vwp_ring_free(VwRing *r)
{
    for (size_t i = 0; i < VWP_RING_CAP; i++)
        free(r->lines[i]);
    memset(r, 0, sizeof *r);
}

void vwp_ring_push(VwRing *r, const char *line)
{
    size_t slot = (size_t)(r->total % VWP_RING_CAP);
    free(r->lines[slot]);
    r->lines[slot] = vwp_strdup(line);
    // On oom the slot holds NULL; the reader emits "" for it rather than lying
    // about the cursor.
    r->total++;
}

int vwp_ring_json(const VwRing *r, uint64_t since, VwBuf *out)
{
    uint64_t first = r->total > VWP_RING_CAP ? r->total - VWP_RING_CAP : 0;
    if (since > r->total)
        since = r->total;
    uint64_t start = since < first ? first : since;
    uint64_t dropped = start - since;

    vwp_buf_appendf(out, "{\"next\":%llu,\"dropped\":%llu,\"lines\":[",
                    (unsigned long long)r->total, (unsigned long long)dropped);
    for (uint64_t i = start; i < r->total; i++) {
        if (i > start)
            vwp_buf_appendz(out, ",");
        vwp_buf_appendz(out, "\"");
        const char *line = r->lines[(size_t)(i % VWP_RING_CAP)];
        vwp_json_escape(out, line ? line : "");
        vwp_buf_appendz(out, "\"");
    }
    vwp_buf_appendz(out, "]}");
    return out->oom ? -1 : 0;
}

// ---- http ----

static int ci_eq_n(const char *a, const char *b, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        char ca = a[i], cb = b[i];
        if (ca >= 'A' && ca <= 'Z')
            ca += 32;
        if (cb >= 'A' && cb <= 'Z')
            cb += 32;
        if (ca != cb)
            return 0;
    }
    return 1;
}

void vwp_http_parse(const char *buf, size_t len, VwHttpReq *out)
{
    memset(out, 0, sizeof *out);

    // header terminator
    size_t hdr_end = 0;
    int found = 0;
    size_t scan = len < VWP_MAX_HEADER ? len : VWP_MAX_HEADER;
    for (size_t i = 0; i + 3 < scan; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n') {
            hdr_end = i;
            found = 1;
            break;
        }
    }
    if (!found) {
        if (len >= VWP_MAX_HEADER)
            out->bad = 1;
        return; // need more bytes
    }

    // request line: METHOD SP TARGET SP HTTP/...
    size_t i = 0;
    size_t m = 0;
    while (i < hdr_end && buf[i] != ' ') {
        if (m + 1 >= sizeof out->method) {
            out->bad = 1;
            return;
        }
        out->method[m++] = buf[i++];
    }
    out->method[m] = '\0';
    if (i >= hdr_end || m == 0) {
        out->bad = 1;
        return;
    }
    i++; // space

    size_t p = 0, q = 0;
    int in_query = 0;
    while (i < hdr_end && buf[i] != ' ') {
        char c = buf[i++];
        if (!in_query && c == '?') {
            in_query = 1;
            continue;
        }
        if (in_query) {
            if (q + 1 >= sizeof out->query) {
                out->bad = 1;
                return;
            }
            out->query[q++] = c;
        } else {
            if (p + 1 >= sizeof out->path) {
                out->bad = 1;
                return;
            }
            out->path[p++] = c;
        }
    }
    out->path[p] = '\0';
    out->query[q] = '\0';
    if (i >= hdr_end || p == 0 || !ci_eq_n(buf + i, " HTTP/", 6)) {
        out->bad = 1;
        return;
    }

    // headers: only Content-Length matters
    size_t content_len = 0;
    size_t line = 0;
    // advance to first header line
    while (line + 1 < hdr_end && !(buf[line] == '\r' && buf[line + 1] == '\n'))
        line++;
    line += 2;
    while (line < hdr_end) {
        size_t eol = line;
        while (eol + 1 < hdr_end + 2 && !(buf[eol] == '\r' && buf[eol + 1] == '\n'))
            eol++;
        static const char cl[] = "content-length:";
        size_t cln = sizeof cl - 1;
        if (eol - line > cln && ci_eq_n(buf + line, cl, cln)) {
            size_t v = line + cln;
            while (v < eol && buf[v] == ' ')
                v++;
            content_len = 0;
            int any = 0;
            while (v < eol && buf[v] >= '0' && buf[v] <= '9') {
                content_len = content_len * 10 + (size_t)(buf[v] - '0');
                if (content_len > VWP_MAX_BODY) {
                    out->bad = 1;
                    return;
                }
                v++;
                any = 1;
            }
            if (!any) {
                out->bad = 1;
                return;
            }
        }
        line = eol + 2;
    }

    size_t body_off = hdr_end + 4;
    if (len < body_off + content_len)
        return; // need more bytes
    out->body = buf + body_off;
    out->body_len = content_len;
    out->total_len = body_off + content_len;
    out->complete = 1;
}

uint64_t vwp_query_u64(const char *query, const char *key, uint64_t fallback)
{
    size_t klen = strlen(key);
    const char *p = query;
    while (*p) {
        if (strncmp(p, key, klen) == 0 && p[klen] == '=') {
            const char *v = p + klen + 1;
            if (*v < '0' || *v > '9')
                return fallback;
            uint64_t n = 0;
            while (*v >= '0' && *v <= '9')
                n = n * 10 + (uint64_t)(*v++ - '0');
            return n;
        }
        while (*p && *p != '&')
            p++;
        if (*p == '&')
            p++;
    }
    return fallback;
}

int vwp_query_str(const char *query, const char *key, char *out, size_t outsz)
{
    if (outsz == 0)
        return 0;
    out[0] = '\0';
    size_t klen = strlen(key);
    const char *p = query;
    while (*p) {
        if (strncmp(p, key, klen) == 0 && p[klen] == '=') {
            const char *v = p + klen + 1;
            size_t n = 0;
            while (v[n] && v[n] != '&' && n < outsz - 1) {
                out[n] = v[n];
                n++;
            }
            out[n] = '\0';
            return 1;
        }
        while (*p && *p != '&')
            p++;
        if (*p == '&')
            p++;
    }
    return 0;
}

size_t vwp_tail_offset(const char *data, size_t len, unsigned lines)
{
    if (len == 0 || lines == 0)
        return len;
    size_t i = len;
    if (data[i - 1] == '\n')
        i--;
    unsigned seen = 0;
    while (i > 0) {
        if (data[i - 1] == '\n') {
            seen++;
            if (seen == lines)
                return i;
        }
        i--;
    }
    return 0;
}

// ---- command slot ----

void vwp_cmd_init(VwCmdSlot *s)
{
    memset(s, 0, sizeof *s);
}

void vwp_cmd_free(VwCmdSlot *s)
{
    free(s->cmd);
    free(s->reply);
    memset(s, 0, sizeof *s);
}

int vwp_cmd_submit(VwCmdSlot *s, const char *cmd)
{
    if (s->state != VWP_CMD_IDLE)
        return -1;
    char *copy = vwp_strdup(cmd);
    if (!copy)
        return -1;
    free(s->cmd);
    s->cmd = copy;
    s->state = VWP_CMD_PENDING;
    return 0;
}

const char *vwp_cmd_poll(VwCmdSlot *s)
{
    if (s->state != VWP_CMD_PENDING)
        return NULL;
    s->state = VWP_CMD_TAKEN;
    return s->cmd;
}

int vwp_cmd_reply(VwCmdSlot *s, const char *reply)
{
    if (s->state != VWP_CMD_TAKEN)
        return -1;
    char *copy = vwp_strdup(reply);
    if (!copy)
        return -1;
    free(s->reply);
    s->reply = copy;
    s->state = VWP_CMD_REPLIED;
    return 0;
}

char *vwp_cmd_take_reply(VwCmdSlot *s)
{
    if (s->state != VWP_CMD_REPLIED)
        return NULL;
    char *out = s->reply;
    s->reply = NULL;
    s->state = VWP_CMD_IDLE;
    return out;
}

void vwp_cmd_abandon(VwCmdSlot *s)
{
    free(s->cmd);
    free(s->reply);
    s->cmd = NULL;
    s->reply = NULL;
    s->state = VWP_CMD_IDLE;
}
