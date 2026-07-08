// Host-side unit tests for vw_protocol.c. No game, no Prism, no sockets.
// Build and run via tools/build-shim.ps1; exits nonzero on any failure.

#include "../vw_protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond) do { \
    g_checks++; \
    if (!(cond)) { \
        g_failures++; \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
    } \
} while (0)

#define CHECK_STR(actual, expected) do { \
    g_checks++; \
    const char *a_ = (actual); \
    const char *e_ = (expected); \
    if (!a_ || strcmp(a_, e_) != 0) { \
        g_failures++; \
        fprintf(stderr, "FAIL %s:%d: got \"%s\" want \"%s\"\n", __FILE__, __LINE__, \
                a_ ? a_ : "(null)", e_); \
    } \
} while (0)

static void test_buf(void)
{
    VwBuf b;
    vwp_buf_init(&b);
    CHECK(vwp_buf_appendz(&b, "hello") == 0);
    CHECK(vwp_buf_appendf(&b, " %d %s", 42, "world") == 0);
    CHECK_STR(b.data, "hello 42 world");
    CHECK(b.len == strlen("hello 42 world"));
    vwp_buf_free(&b);

    // growth across many appends
    vwp_buf_init(&b);
    for (int i = 0; i < 1000; i++)
        vwp_buf_appendz(&b, "0123456789");
    CHECK(b.len == 10000);
    CHECK(b.data[10000] == '\0');
    vwp_buf_free(&b);
}

static void test_json_escape(void)
{
    VwBuf b;
    vwp_buf_init(&b);
    vwp_json_escape(&b, "a\"b\\c\nd\te\x01" "f");
    CHECK_STR(b.data, "a\\\"b\\\\c\\nd\\te\\u0001f");
    vwp_buf_free(&b);

    // UTF-8 passes through untouched
    vwp_buf_init(&b);
    vwp_json_escape(&b, "caf\xc3\xa9");
    CHECK_STR(b.data, "caf\xc3\xa9");
    vwp_buf_free(&b);
}

static void test_ring_basic(void)
{
    VwRing r;
    vwp_ring_init(&r);
    vwp_ring_push(&r, "one");
    vwp_ring_push(&r, "two");
    CHECK(r.total == 2);

    VwBuf b;
    vwp_buf_init(&b);
    vwp_ring_json(&r, 0, &b);
    CHECK_STR(b.data, "{\"next\":2,\"dropped\":0,\"lines\":[\"one\",\"two\"]}");
    vwp_buf_free(&b);

    vwp_buf_init(&b);
    vwp_ring_json(&r, 1, &b);
    CHECK_STR(b.data, "{\"next\":2,\"dropped\":0,\"lines\":[\"two\"]}");
    vwp_buf_free(&b);

    // cursor at head: empty
    vwp_buf_init(&b);
    vwp_ring_json(&r, 2, &b);
    CHECK_STR(b.data, "{\"next\":2,\"dropped\":0,\"lines\":[]}");
    vwp_buf_free(&b);

    // cursor beyond head clamps
    vwp_buf_init(&b);
    vwp_ring_json(&r, 99, &b);
    CHECK_STR(b.data, "{\"next\":2,\"dropped\":0,\"lines\":[]}");
    vwp_buf_free(&b);

    vwp_ring_free(&r);
}

static void test_ring_wrap(void)
{
    VwRing r;
    vwp_ring_init(&r);
    char line[80];
    for (int i = 0; i < VWP_RING_CAP + 10; i++) {
        snprintf(line, sizeof line, "line%d", i);
        vwp_ring_push(&r, line);
    }
    CHECK(r.total == VWP_RING_CAP + 10);

    // asking from 0: the first 10 are gone
    VwBuf b;
    vwp_buf_init(&b);
    vwp_ring_json(&r, 0, &b);
    CHECK(strstr(b.data, "\"dropped\":10,") != NULL);
    CHECK(strstr(b.data, "\"line10\"") != NULL);   // oldest survivor
    CHECK(strstr(b.data, "\"line9\"") == NULL);
    snprintf(line, sizeof line, "\"line%d\"", VWP_RING_CAP + 9);
    CHECK(strstr(b.data, line) != NULL);           // newest
    vwp_buf_free(&b);

    // incremental read from the tail sees only the newest
    vwp_buf_init(&b);
    vwp_ring_json(&r, r.total - 1, &b);
    snprintf(line, sizeof line,
             "{\"next\":%llu,\"dropped\":0,\"lines\":[\"line%d\"]}",
             (unsigned long long)r.total, VWP_RING_CAP + 9);
    CHECK_STR(b.data, line);
    vwp_buf_free(&b);

    vwp_ring_free(&r);
}

static void test_http_get(void)
{
    const char *req = "GET /speech?since=17 HTTP/1.1\r\nHost: x\r\n\r\n";
    VwHttpReq h;
    vwp_http_parse(req, strlen(req), &h);
    CHECK(h.complete && !h.bad);
    CHECK_STR(h.method, "GET");
    CHECK_STR(h.path, "/speech");
    CHECK_STR(h.query, "since=17");
    CHECK(h.body_len == 0);
    CHECK(h.total_len == strlen(req));
    CHECK(vwp_query_u64(h.query, "since", 0) == 17);
}

static void test_http_post(void)
{
    const char *req =
        "POST /cmd HTTP/1.1\r\nHost: x\r\nContent-Length: 8\r\n\r\nsay test";
    VwHttpReq h;
    vwp_http_parse(req, strlen(req), &h);
    CHECK(h.complete && !h.bad);
    CHECK_STR(h.method, "POST");
    CHECK_STR(h.path, "/cmd");
    CHECK_STR(h.query, "");
    CHECK(h.body_len == 8);
    CHECK(h.body && strncmp(h.body, "say test", 8) == 0);

    // case-insensitive content-length
    const char *req2 =
        "POST /cmd HTTP/1.1\r\ncontent-length: 4\r\n\r\nping";
    vwp_http_parse(req2, strlen(req2), &h);
    CHECK(h.complete && h.body_len == 4);
}

static void test_http_partial_and_bad(void)
{
    VwHttpReq h;

    // headers not finished yet
    const char *partial = "GET /health HTTP/1.1\r\nHost:";
    vwp_http_parse(partial, strlen(partial), &h);
    CHECK(!h.complete && !h.bad);

    // body not fully received yet
    const char *short_body =
        "POST /cmd HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc";
    vwp_http_parse(short_body, strlen(short_body), &h);
    CHECK(!h.complete && !h.bad);

    // garbage request line
    const char *garbage = "NONSENSE\r\n\r\n";
    vwp_http_parse(garbage, strlen(garbage), &h);
    CHECK(h.bad);

    // not HTTP
    const char *not_http = "GET /x FTP/9\r\n\r\n";
    vwp_http_parse(not_http, strlen(not_http), &h);
    CHECK(h.bad);

    // oversized declared body
    const char *huge =
        "POST /cmd HTTP/1.1\r\nContent-Length: 9999999\r\n\r\n";
    vwp_http_parse(huge, strlen(huge), &h);
    CHECK(h.bad);
}

static void test_query(void)
{
    CHECK(vwp_query_u64("a=1&since=42&b=3", "since", 7) == 42);
    CHECK(vwp_query_u64("a=1&b=3", "since", 7) == 7);
    CHECK(vwp_query_u64("since=abc", "since", 7) == 7);
    CHECK(vwp_query_u64("", "since", 7) == 7);
    CHECK(vwp_query_u64("insince=9", "since", 7) == 7);
    CHECK(vwp_query_u64("since=0", "since", 7) == 0);

    char v[8];
    CHECK(vwp_query_str("a=1&obj=oButton&b=2", "obj", v, sizeof v) == 1);
    CHECK_STR(v, "oButton");
    CHECK(vwp_query_str("obj=oMainMenuControls", "obj", v, sizeof v) == 1);
    CHECK_STR(v, "oMainMe"); // truncated to outsz-1
    CHECK(vwp_query_str("a=1&b=2", "obj", v, sizeof v) == 0);
    CHECK_STR(v, "");
    CHECK(vwp_query_str("obj=", "obj", v, sizeof v) == 1);
    CHECK_STR(v, "");
    CHECK(vwp_query_str("xobj=zz", "obj", v, sizeof v) == 0);
    CHECK(vwp_query_str("obj=tail", "obj", v, sizeof v) == 1);
    CHECK_STR(v, "tail");
}

static void test_cmd_slot(void)
{
    VwCmdSlot s;
    vwp_cmd_init(&s);

    // nothing pending
    CHECK(vwp_cmd_poll(&s) == NULL);
    CHECK(vwp_cmd_take_reply(&s) == NULL);
    CHECK(vwp_cmd_reply(&s, "x") == -1);

    // normal round trip
    CHECK(vwp_cmd_submit(&s, "ping") == 0);
    CHECK(vwp_cmd_submit(&s, "again") == -1); // busy
    const char *cmd = vwp_cmd_poll(&s);
    CHECK_STR(cmd, "ping");
    CHECK(vwp_cmd_poll(&s) == NULL);          // only handed out once
    CHECK(vwp_cmd_reply(&s, "pong") == 0);
    CHECK(vwp_cmd_reply(&s, "pong2") == -1);  // only one reply
    char *reply = vwp_cmd_take_reply(&s);
    CHECK_STR(reply, "pong");
    free(reply);
    CHECK(s.state == VWP_CMD_IDLE);

    // abandon while pending
    CHECK(vwp_cmd_submit(&s, "late") == 0);
    vwp_cmd_abandon(&s);
    CHECK(s.state == VWP_CMD_IDLE);
    CHECK(vwp_cmd_poll(&s) == NULL);

    // abandon while taken: pump's reply after the fact fails cleanly
    CHECK(vwp_cmd_submit(&s, "slow") == 0);
    CHECK(vwp_cmd_poll(&s) != NULL);
    vwp_cmd_abandon(&s);
    CHECK(vwp_cmd_reply(&s, "too late") == -1);

    vwp_cmd_free(&s);
}

int main(void)
{
    test_buf();
    test_json_escape();
    test_ring_basic();
    test_ring_wrap();
    test_http_get();
    test_http_post();
    test_http_partial_and_bad();
    test_query();
    test_cmd_slot();

    if (g_failures) {
        fprintf(stderr, "%d of %d checks FAILED\n", g_failures, g_checks);
        return 1;
    }
    printf("all %d checks passed\n", g_checks);
    return 0;
}
