// vw_protocol.h - pure protocol logic for the Void War Access shim.
//
// Everything in this module is single-threaded and OS-free (no winsock, no
// windows.h) so it can be unit-tested host-side with a plain clang build.
// The DLL layer (vw_speech.c) owns all locking; callers of the command slot
// and ring must hold their own lock.

#ifndef VW_PROTOCOL_H
#define VW_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

// ---- growable text buffer ----

typedef struct {
    char *data;   // null-terminated
    size_t len;
    size_t cap;
    int oom;      // sticky: any failed allocation poisons the buffer
} VwBuf;

void vwp_buf_init(VwBuf *b);
void vwp_buf_free(VwBuf *b);
int vwp_buf_append(VwBuf *b, const char *s, size_t n);   // 0 ok, -1 oom
int vwp_buf_appendz(VwBuf *b, const char *s);
int vwp_buf_appendf(VwBuf *b, const char *fmt, ...);

// Append s as JSON string content (escaped, without surrounding quotes).
int vwp_json_escape(VwBuf *b, const char *s);

// ---- speech ring buffer with monotonic cursor ----

#define VWP_RING_CAP 512

typedef struct {
    char *lines[VWP_RING_CAP];  // owned; slot i holds entry (total - k) where recent entries wrap
    uint64_t total;             // count of lines ever pushed; cursor space
} VwRing;

void vwp_ring_init(VwRing *r);
void vwp_ring_free(VwRing *r);
void vwp_ring_push(VwRing *r, const char *line);
// Write {"next":N,"dropped":D,"lines":[...]} covering entries with index >= since.
// "dropped" counts requested entries that have already been overwritten.
int vwp_ring_json(const VwRing *r, uint64_t since, VwBuf *out);

// ---- minimal HTTP/1.x request parsing ----

#define VWP_MAX_HEADER 8192
#define VWP_MAX_BODY 65536

typedef struct {
    char method[8];
    char path[128];
    char query[256];        // "" if none
    const char *body;       // points into the caller's buffer
    size_t body_len;
    int complete;           // request line + headers + full body present
    int bad;                // malformed or over limits; drop the connection
    size_t total_len;       // bytes consumed when complete
} VwHttpReq;

// Parse from buf/len. complete=0 && bad=0 means "need more bytes".
void vwp_http_parse(const char *buf, size_t len, VwHttpReq *out);

// Find key=<u64> in a query string ("a=1&b=2"). Returns fallback if absent or unparsable.
uint64_t vwp_query_u64(const char *query, const char *key, uint64_t fallback);

// ---- single-slot command exchange (HTTP thread <-> GML pump) ----
//
// One command in flight at a time; HTTP submits, the GML pump polls it out,
// replies, and HTTP takes the reply. Caller provides all locking/waiting.

typedef enum {
    VWP_CMD_IDLE = 0,
    VWP_CMD_PENDING,   // submitted, not yet seen by the pump
    VWP_CMD_TAKEN,     // pump has it, reply outstanding
    VWP_CMD_REPLIED    // reply ready for the HTTP side
} VwCmdState;

typedef struct {
    VwCmdState state;
    char *cmd;    // owned
    char *reply;  // owned
} VwCmdSlot;

void vwp_cmd_init(VwCmdSlot *s);
void vwp_cmd_free(VwCmdSlot *s);
int vwp_cmd_submit(VwCmdSlot *s, const char *cmd);   // 0 ok, -1 slot busy
const char *vwp_cmd_poll(VwCmdSlot *s);              // command text (valid until reply/abandon) or NULL
int vwp_cmd_reply(VwCmdSlot *s, const char *reply);  // 0 ok, -1 no command taken
char *vwp_cmd_take_reply(VwCmdSlot *s);              // malloc'd reply (caller frees), slot -> IDLE; NULL if none
void vwp_cmd_abandon(VwCmdSlot *s);                  // HTTP side gave up; slot -> IDLE

// malloc+copy; NULL only on oom
char *vwp_strdup(const char *s);

#endif
