// vw_speech.c - the Void War Access native shim.
//
// GameMaker can only pass doubles and null-terminated strings across
// external_call, so this DLL owns everything pointer-shaped: the Prism
// speech context/backend (with a SAPI COM fallback), the speech ring buffer
// the dev driver reads, and the loopback HTTP server thread.
//
// Threading model: GML calls every vw_* export from the game's main thread.
// The HTTP server runs on one background thread and talks to the main thread
// only through g_ring and g_cmd under g_lock (commands wait on g_cmd_cv).
// Prism/SAPI calls happen exclusively on the main thread. The log has its own
// innermost lock and is safe to call from anywhere.
//
// String returns to GameMaker point at static buffers, valid until the next
// call of the same export - GameMaker copies the string immediately.
//
// Configuration comes from vw_speech.cfg next to this DLL (written by the
// launcher; Steam does not forward the launcher's environment to the game),
// overridable by env vars when present: VWACCESS_DEV_PORT, VWACCESS_NO_DEV,
// VWACCESS_SPEECH.

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#define COBJMACROS
#include <sapi.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../vendor/prism/prism.h"
#include "vw_protocol.h"

#define VW_SHIM_VERSION "0.2.0"
#define VW_DEFAULT_PORT 8772
#define VW_CMD_TIMEOUT_MS 5000
#define VW_EXPORT __declspec(dllexport)

// ---- state ----

static CRITICAL_SECTION g_lock;          // ring + cmd slot + poll tick
static CONDITION_VARIABLE g_cmd_cv;
static CRITICAL_SECTION g_log_lock;      // innermost; never take g_lock inside
static VwRing g_ring;
static VwCmdSlot g_cmd;

static int g_inited = 0;
static double g_init_result = -1;
static int g_speech_on = 0;
static int g_dev_on = 1;
static int g_port = VW_DEFAULT_PORT;
static ULONGLONG g_last_poll_tick = 0;   // 0 = never polled
static char g_dll_dir[MAX_PATH] = "";
static char g_backend_desc[160] = "uninitialized";

static HANDLE g_server_thread = NULL;
static SOCKET g_listen_sock = INVALID_SOCKET;
static volatile LONG g_running = 0;

// Background-run: the runner pauses the whole game when its window
// deactivates, which kills unattended dev loops. We subclass the game
// window's WndProc and swallow the deactivation messages so the runner
// never observes focus loss. Dev-build workaround, config-gated (bg=0 /
// VWACCESS_BG=0 disables). Known trade-off: the game also keeps reading
// global key state (keyboard_check_direct) while unfocused.
static int g_bg_on = 1;
static WNDPROC g_orig_wndproc = NULL;
static HWND g_game_hwnd = NULL;

// Prism, loaded dynamically so a missing prism.dll degrades instead of
// breaking our own DLL load.
static HMODULE g_prism_mod = NULL;
static PrismContext *g_prism_ctx = NULL;
static PrismBackend *g_prism_backend = NULL;
static uint64_t g_prism_features = 0;

typedef PrismConfig (PRISM_CALL *vw_fn_config_init)(void);
typedef PrismContext *(PRISM_CALL *vw_fn_init)(PrismConfig *);
typedef void (PRISM_CALL *vw_fn_shutdown)(PrismContext *);
typedef PrismBackend *(PRISM_CALL *vw_fn_create_best)(PrismContext *);
typedef void (PRISM_CALL *vw_fn_backend_free)(PrismBackend *);
typedef const char *(PRISM_CALL *vw_fn_backend_name)(PrismBackend *);
typedef uint64_t (PRISM_CALL *vw_fn_backend_get_features)(PrismBackend *);
typedef PrismError (PRISM_CALL *vw_fn_backend_initialize)(PrismBackend *);
typedef PrismError (PRISM_CALL *vw_fn_backend_speak)(PrismBackend *, const char *, bool);
typedef PrismError (PRISM_CALL *vw_fn_backend_output)(PrismBackend *, const char *, bool);
typedef PrismError (PRISM_CALL *vw_fn_backend_stop)(PrismBackend *);
typedef const char *(PRISM_CALL *vw_fn_error_string)(PrismError);

static vw_fn_config_init p_config_init;
static vw_fn_init p_init;
static vw_fn_shutdown p_shutdown;
static vw_fn_create_best p_create_best;
static vw_fn_backend_free p_backend_free;
static vw_fn_backend_name p_backend_name;
static vw_fn_backend_get_features p_backend_get_features;
static vw_fn_backend_initialize p_backend_initialize;
static vw_fn_backend_speak p_backend_speak;
static vw_fn_backend_output p_backend_output;
static vw_fn_backend_stop p_backend_stop;
static vw_fn_error_string p_error_string;

// SAPI fallback
static const CLSID VW_CLSID_SpVoice =
    {0x96749377, 0x3391, 0x11D2, {0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96}};
static const IID VW_IID_ISpVoice =
    {0x6C44DF74, 0x72B9, 0x4992, {0xA1, 0xEC, 0xEF, 0x99, 0x6E, 0x04, 0x22, 0xD4}};
static ISpVoice *g_sapi = NULL;

// ---- logging (no silent failures: every guarded path reports here) ----

static void vw_logf(const char *fmt, ...)
{
    EnterCriticalSection(&g_log_lock);
    char path[MAX_PATH + 32];
    snprintf(path, sizeof path, "%svw_speech.log", g_dll_dir);
    FILE *f = fopen(path, "ab");
    if (f) {
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "%02u:%02u:%02u.%03u [%lu] ", st.wHour, st.wMinute, st.wSecond,
                st.wMilliseconds, GetCurrentThreadId());
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fputc('\n', f);
        fclose(f);
    }
    LeaveCriticalSection(&g_log_lock);
}

static const char *prism_err_str(PrismError e)
{
    const char *s = p_error_string ? p_error_string(e) : NULL;
    return s ? s : "(unknown prism error)";
}

// ---- config ----

static void read_config_file(void)
{
    char path[MAX_PATH + 32];
    snprintf(path, sizeof path, "%svw_speech.cfg", g_dll_dir);
    FILE *f = fopen(path, "rb");
    if (!f) {
        vw_logf("config: %s not found, using defaults", path);
        return;
    }
    char line[256];
    while (fgets(line, sizeof line, f)) {
        char *eq = strchr(line, '=');
        if (!eq)
            continue;
        *eq = '\0';
        int val = atoi(eq + 1);
        if (strcmp(line, "port") == 0 && val > 0 && val < 65536)
            g_port = val;
        else if (strcmp(line, "speech") == 0)
            g_speech_on = val != 0;
        else if (strcmp(line, "nodev") == 0)
            g_dev_on = val == 0;
        else if (strcmp(line, "bg") == 0)
            g_bg_on = val != 0;
    }
    fclose(f);
}

static void read_config_env(void)
{
    char v[32];
    if (GetEnvironmentVariableA("VWACCESS_DEV_PORT", v, sizeof v) > 0) {
        int p = atoi(v);
        if (p > 0 && p < 65536)
            g_port = p;
    }
    if (GetEnvironmentVariableA("VWACCESS_NO_DEV", v, sizeof v) > 0 && atoi(v) != 0)
        g_dev_on = 0;
    if (GetEnvironmentVariableA("VWACCESS_SPEECH", v, sizeof v) > 0)
        g_speech_on = atoi(v) != 0;
    if (GetEnvironmentVariableA("VWACCESS_BG", v, sizeof v) > 0)
        g_bg_on = atoi(v) != 0;
}

// ---- background-run (focus-pause defeat) ----

static LRESULT CALLBACK vw_wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    switch (m) {
    case WM_ACTIVATE:
        if (LOWORD(w) == WA_INACTIVE)
            return 0; // runner never learns it was deactivated
        break;
    case WM_ACTIVATEAPP:
        if (!w)
            return 0;
        break;
    case WM_KILLFOCUS:
        return 0;
    default:
        break;
    }
    return CallWindowProcW(g_orig_wndproc, h, m, w, l);
}

struct vw_find_wnd {
    HWND best;    // GameMaker's own window class (visible or not)
    HWND any;     // otherwise the first visible candidate
};

static BOOL CALLBACK vw_find_wnd_cb(HWND h, LPARAM lp)
{
    struct vw_find_wnd *fw = (struct vw_find_wnd *)lp;
    char cls[64];
    if (GetClassNameA(h, cls, sizeof cls) && strcmp(cls, "YYGameMakerYY") == 0) {
        fw->best = h;
        return FALSE;
    }
    if (!fw->any && IsWindowVisible(h))
        fw->any = h;
    return TRUE;
}

static BOOL CALLBACK vw_find_proc_wnd_cb(HWND h, LPARAM lp)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(h, &pid);
    if (pid != GetCurrentProcessId())
        return TRUE;
    return vw_find_wnd_cb(h, lp);
}

// The window does not exist yet when vw_init runs (oInitGlobals Create, in
// the preload room - observed live), so installation retries from vw_poll
// once per frame until the window appears.
#define VW_BG_MAX_ATTEMPTS 1800 // ~30s at 60fps
static int g_bg_attempts = 0;

static void try_install_bg(void)
{
    if (!g_bg_on || g_game_hwnd || g_bg_attempts >= VW_BG_MAX_ATTEMPTS)
        return;
    g_bg_attempts++;
    struct vw_find_wnd fw = {NULL, NULL};
    EnumThreadWindows(GetCurrentThreadId(), vw_find_wnd_cb, (LPARAM)&fw);
    if (!fw.best && !fw.any)
        EnumWindows(vw_find_proc_wnd_cb, (LPARAM)&fw);
    HWND h = fw.best ? fw.best : fw.any;
    if (!h) {
        if (g_bg_attempts == VW_BG_MAX_ATTEMPTS)
            vw_logf("bg: no game window found after %d attempts; focus-pause defeat unavailable",
                    g_bg_attempts);
        return;
    }
    char cls[64] = "", title[128] = "";
    GetClassNameA(h, cls, sizeof cls);
    GetWindowTextA(h, title, sizeof title);
    DWORD owner_tid = GetWindowThreadProcessId(h, NULL);
    SetLastError(0);
    g_orig_wndproc = (WNDPROC)SetWindowLongPtrW(h, GWLP_WNDPROC, (LONG_PTR)vw_wndproc);
    if (!g_orig_wndproc) {
        vw_logf("bg: SetWindowLongPtr failed (error %lu)", GetLastError());
        return;
    }
    g_game_hwnd = h;
    vw_logf("bg: subclassed window %p (class=%s title=%s ownerTid=%lu myTid=%lu attempt=%d); "
            "deactivation messages swallowed",
            (void *)h, cls, title, owner_tid, GetCurrentThreadId(), g_bg_attempts);
}

// ---- speech backends ----

static int load_prism(void)
{
    char path[MAX_PATH + 32];
    snprintf(path, sizeof path, "%sprism.dll", g_dll_dir);
    g_prism_mod = LoadLibraryA(path);
    if (!g_prism_mod) {
        vw_logf("prism: LoadLibrary(%s) failed (error %lu)", path, GetLastError());
        return 0;
    }
#define VW_PROC(var, name) var = (void *)GetProcAddress(g_prism_mod, name)
    VW_PROC(p_config_init, "prism_config_init");
    VW_PROC(p_init, "prism_init");
    VW_PROC(p_shutdown, "prism_shutdown");
    VW_PROC(p_create_best, "prism_registry_create_best");
    VW_PROC(p_backend_free, "prism_backend_free");
    VW_PROC(p_backend_name, "prism_backend_name");
    VW_PROC(p_backend_get_features, "prism_backend_get_features");
    VW_PROC(p_backend_initialize, "prism_backend_initialize");
    VW_PROC(p_backend_speak, "prism_backend_speak");
    VW_PROC(p_backend_output, "prism_backend_output");
    VW_PROC(p_backend_stop, "prism_backend_stop");
    VW_PROC(p_error_string, "prism_error_string");
#undef VW_PROC
    if (!p_init || !p_shutdown || !p_create_best || !p_backend_free ||
        !p_backend_name || !p_backend_get_features || !p_backend_speak ||
        !p_backend_stop) {
        vw_logf("prism: required export missing from %s", path);
        FreeLibrary(g_prism_mod);
        g_prism_mod = NULL;
        return 0;
    }

    PrismConfig cfg;
    if (p_config_init) {
        cfg = p_config_init();
    } else {
        memset(&cfg, 0, sizeof cfg);
        cfg.version = PRISM_CONFIG_VERSION;
    }
    g_prism_ctx = p_init(&cfg);
    if (!g_prism_ctx) {
        vw_logf("prism: prism_init returned NULL");
        return 0;
    }
    g_prism_backend = p_create_best(g_prism_ctx);
    if (!g_prism_backend) {
        vw_logf("prism: no usable backend on this machine");
        p_shutdown(g_prism_ctx);
        g_prism_ctx = NULL;
        return 0;
    }
    if (p_backend_initialize) {
        PrismError e = p_backend_initialize(g_prism_backend);
        if (e != PRISM_OK && e != PRISM_ERROR_ALREADY_INITIALIZED)
            vw_logf("prism: backend_initialize -> %s (continuing; create_best backends usually arrive initialized)",
                    prism_err_str(e));
    }
    g_prism_features = p_backend_get_features(g_prism_backend);
    const char *name = p_backend_name(g_prism_backend);
    snprintf(g_backend_desc, sizeof g_backend_desc, "prism:%s", name ? name : "(unnamed)");
    vw_logf("prism: backend acquired: %s (features 0x%llx)", g_backend_desc,
            (unsigned long long)g_prism_features);
    return 1;
}

static int load_sapi(void)
{
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        vw_logf("sapi: CoInitializeEx failed (0x%08lx)", (unsigned long)hr);
        return 0;
    }
    hr = CoCreateInstance(&VW_CLSID_SpVoice, NULL, CLSCTX_ALL, &VW_IID_ISpVoice,
                          (void **)&g_sapi);
    if (FAILED(hr)) {
        vw_logf("sapi: CoCreateInstance(SpVoice) failed (0x%08lx)", (unsigned long)hr);
        g_sapi = NULL;
        return 0;
    }
    snprintf(g_backend_desc, sizeof g_backend_desc, "sapi");
    vw_logf("sapi: fallback voice created");
    return 1;
}

// Release every speech backend (Prism module included) so a reset can start
// from nothing. Main thread only; dangling p_* pointers are nulled because
// prism_err_str would otherwise call into an unloaded module.
static void unload_speech_backends(void)
{
    if (g_prism_backend) {
        p_backend_free(g_prism_backend);
        g_prism_backend = NULL;
    }
    if (g_prism_ctx) {
        p_shutdown(g_prism_ctx);
        g_prism_ctx = NULL;
    }
    if (g_prism_mod) {
        FreeLibrary(g_prism_mod);
        g_prism_mod = NULL;
        p_config_init = NULL;
        p_init = NULL;
        p_shutdown = NULL;
        p_create_best = NULL;
        p_backend_free = NULL;
        p_backend_name = NULL;
        p_backend_get_features = NULL;
        p_backend_initialize = NULL;
        p_backend_speak = NULL;
        p_backend_output = NULL;
        p_backend_stop = NULL;
        p_error_string = NULL;
        g_prism_features = 0;
    }
    if (g_sapi) {
        ISpVoice_Release(g_sapi);
        g_sapi = NULL;
    }
}

static WCHAR *utf8_to_wide(const char *s)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0)
        return NULL;
    WCHAR *w = malloc((size_t)n * sizeof(WCHAR));
    if (w)
        MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

// Speak on the active backend. Returns 1 voiced, 0 not voiced (gate off /
// no backend), -1 backend error (logged).
static int backend_speak(const char *text, int interrupt)
{
    if (!g_speech_on)
        return 0;
    if (g_prism_backend) {
        PrismError e;
        // Prefer output (speech + braille) when the backend supports it.
        if (p_backend_output && (g_prism_features & PRISM_BACKEND_SUPPORTS_OUTPUT)) {
            e = p_backend_output(g_prism_backend, text, interrupt != 0);
            if (e == PRISM_OK)
                return 1;
            if (e != PRISM_ERROR_NOT_IMPLEMENTED) {
                vw_logf("prism: output failed: %s (falling through to speak)", prism_err_str(e));
            }
        }
        e = p_backend_speak(g_prism_backend, text, interrupt != 0);
        if (e == PRISM_OK)
            return 1;
        vw_logf("prism: speak failed: %s", prism_err_str(e));
        return -1;
    }
    if (g_sapi) {
        WCHAR *w = utf8_to_wide(text);
        if (!w) {
            vw_logf("sapi: utf8 conversion failed");
            return -1;
        }
        DWORD flags = SPF_ASYNC | (interrupt ? SPF_PURGEBEFORESPEAK : 0);
        HRESULT hr = ISpVoice_Speak(g_sapi, w, flags, NULL);
        free(w);
        if (FAILED(hr)) {
            vw_logf("sapi: Speak failed (0x%08lx)", (unsigned long)hr);
            return -1;
        }
        return 1;
    }
    return 0;
}

// ---- http server ----

static int send_all(SOCKET s, const char *data, size_t len)
{
    while (len > 0) {
        int n = send(s, data, (int)(len > 1 << 20 ? 1 << 20 : len), 0);
        if (n <= 0)
            return -1;
        data += n;
        len -= (size_t)n;
    }
    return 0;
}

static void http_respond(SOCKET s, const char *status, const char *ctype,
                         const char *body, size_t body_len)
{
    VwBuf hdr;
    vwp_buf_init(&hdr);
    vwp_buf_appendf(&hdr,
                    "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\n"
                    "Connection: close\r\n\r\n",
                    status, ctype, body_len);
    if (!hdr.oom) {
        if (send_all(s, hdr.data, hdr.len) == 0)
            send_all(s, body, body_len);
    }
    vwp_buf_free(&hdr);
}

static void http_respond_text(SOCKET s, const char *status, const char *body)
{
    http_respond(s, status, "text/plain; charset=utf-8", body, strlen(body));
}

static void handle_health(SOCKET s)
{
    char backend[sizeof g_backend_desc];
    EnterCriticalSection(&g_lock);
    unsigned long long spoken = (unsigned long long)g_ring.total;
    ULONGLONG last_poll = g_last_poll_tick;
    // vw_reset_speech rewrites g_backend_desc under g_lock; copy it out here
    // so this thread never reads a half-written buffer.
    memcpy(backend, g_backend_desc, sizeof backend);
    LeaveCriticalSection(&g_lock);
    long long pump_age = last_poll ? (long long)(GetTickCount64() - last_poll) : -1;

    VwBuf b;
    vwp_buf_init(&b);
    vwp_buf_appendf(&b,
                    "{\"status\":\"ok\",\"version\":\"%s\",\"backend\":\"",
                    VW_SHIM_VERSION);
    vwp_json_escape(&b, backend);
    vwp_buf_appendf(&b,
                    "\",\"speechOn\":%s,\"spoken\":%llu,\"pumpAgeMs\":%lld,\"port\":%d,"
                    "\"bgKeepalive\":%s}",
                    g_speech_on ? "true" : "false", spoken, pump_age, g_port,
                    g_game_hwnd ? "true" : "false");
    if (!b.oom)
        http_respond(s, "200 OK", "application/json", b.data, b.len);
    vwp_buf_free(&b);
}

static void handle_speech(SOCKET s, const char *query)
{
    uint64_t since = vwp_query_u64(query, "since", 0);
    VwBuf b;
    vwp_buf_init(&b);
    EnterCriticalSection(&g_lock);
    int rc = vwp_ring_json(&g_ring, since, &b);
    LeaveCriticalSection(&g_lock);
    if (rc == 0)
        http_respond(s, "200 OK", "application/json", b.data, b.len);
    else
        http_respond_text(s, "500 Internal Server Error", "out of memory");
    vwp_buf_free(&b);
}

// Run one command through the GML pump and answer with its reply. The reply
// is JSON when it looks like JSON (the eval-lite commands answer JSON, but
// errors and ping/say answer plain text; the shim cannot know which).
static void handle_gml(SOCKET s, const char *cmd_text)
{
    char *reply = NULL;
    char *cmd = vwp_strdup(cmd_text);
    if (!cmd) {
        http_respond_text(s, "500 Internal Server Error", "out of memory");
        return;
    }
    EnterCriticalSection(&g_lock);
    if (vwp_cmd_submit(&g_cmd, cmd) != 0) {
        LeaveCriticalSection(&g_lock);
        free(cmd);
        http_respond_text(s, "429 Too Many Requests", "a command is already in flight");
        return;
    }
    ULONGLONG deadline = GetTickCount64() + VW_CMD_TIMEOUT_MS;
    for (;;) {
        if (g_cmd.state == VWP_CMD_REPLIED) {
            reply = vwp_cmd_take_reply(&g_cmd);
            break;
        }
        ULONGLONG now = GetTickCount64();
        if (now >= deadline)
            break;
        SleepConditionVariableCS(&g_cmd_cv, &g_lock, (DWORD)(deadline - now));
    }
    if (!reply)
        vwp_cmd_abandon(&g_cmd);
    LeaveCriticalSection(&g_lock);
    free(cmd);

    if (reply) {
        int looks_json = reply[0] == '{' || reply[0] == '[';
        http_respond(s, "200 OK",
                     looks_json ? "application/json" : "text/plain; charset=utf-8",
                     reply, strlen(reply));
        free(reply);
    } else {
        vw_logf("cmd: timed out after %d ms (game not pumping?)", VW_CMD_TIMEOUT_MS);
        http_respond_text(s, "504 Gateway Timeout",
                          "game not pumping (no vw_poll reply within 5s; is the game "
                          "window focused at least once since launch?)");
    }
}

static void handle_cmd(SOCKET s, const char *body, size_t body_len)
{
    if (body_len == 0) {
        http_respond_text(s, "400 Bad Request", "empty command");
        return;
    }
    char *cmd = malloc(body_len + 1);
    if (!cmd) {
        http_respond_text(s, "500 Internal Server Error", "out of memory");
        return;
    }
    memcpy(cmd, body, body_len);
    cmd[body_len] = '\0';
    handle_gml(s, cmd);
    free(cmd);
}

// POST /input: fire a registered input action by key through the GML input
// layer's dispatch path (which validates category liveness). Sugar over the
// "input <actionKey>" eval-lite command.
static void handle_input(SOCKET s, const char *body, size_t body_len)
{
    if (body_len == 0) {
        http_respond_text(s, "400 Bad Request", "empty action key");
        return;
    }
    char *cmd = malloc(body_len + 7);
    if (!cmd) {
        http_respond_text(s, "500 Internal Server Error", "out of memory");
        return;
    }
    memcpy(cmd, "input ", 6);
    memcpy(cmd + 6, body, body_len);
    cmd[body_len + 6] = '\0';
    handle_gml(s, cmd);
    free(cmd);
}

static void handle_connection(SOCKET s)
{
    DWORD timeout = 2000;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof timeout);

    size_t cap = VWP_MAX_HEADER + VWP_MAX_BODY + 16;
    char *buf = malloc(cap);
    if (!buf) {
        closesocket(s);
        return;
    }
    size_t got = 0;
    VwHttpReq req;
    for (;;) {
        vwp_http_parse(buf, got, &req);
        if (req.complete || req.bad)
            break;
        if (got >= cap - 1) {
            req.bad = 1;
            break;
        }
        int n = recv(s, buf + got, (int)(cap - 1 - got), 0);
        if (n <= 0) {
            req.bad = 1;
            break;
        }
        got += (size_t)n;
    }

    if (req.complete) {
        if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/health") == 0)
            handle_health(s);
        else if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/speech") == 0)
            handle_speech(s, req.query);
        else if (strcmp(req.method, "POST") == 0 && strcmp(req.path, "/cmd") == 0)
            handle_cmd(s, req.body, req.body_len);
        else if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/gui/raw") == 0) {
            // sugar over the eval-lite command; ?obj=oThing narrows the dump
            char obj[80], cmd[96];
            vwp_query_str(req.query, "obj", obj, sizeof obj);
            snprintf(cmd, sizeof cmd, "gui.raw%s%s", obj[0] ? " " : "", obj);
            handle_gml(s, cmd);
        }
        else if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/gui/mod") == 0)
            handle_gml(s, "gui.mod"); // the mod's interpreted view; diff against /gui/raw
        else if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/screenshot") == 0)
            handle_gml(s, "screenshot");
        else if (strcmp(req.method, "GET") == 0 && strcmp(req.path, "/state") == 0)
            handle_gml(s, "state"); // input layer: live categories, actions, shadowing
        else if (strcmp(req.method, "POST") == 0 && strcmp(req.path, "/input") == 0)
            handle_input(s, req.body, req.body_len);
        else
            http_respond_text(s, "404 Not Found", "unknown endpoint");
    } else if (req.bad && got > 0) {
        http_respond_text(s, "400 Bad Request", "malformed request");
    }
    free(buf);
    shutdown(s, SD_SEND);
    closesocket(s);
}

static DWORD WINAPI server_main(LPVOID arg)
{
    (void)arg;
    vw_logf("server: listening on 127.0.0.1:%d", g_port);
    while (InterlockedCompareExchange(&g_running, 0, 0)) {
        SOCKET conn = accept(g_listen_sock, NULL, NULL);
        if (conn == INVALID_SOCKET) {
            if (InterlockedCompareExchange(&g_running, 0, 0))
                vw_logf("server: accept failed (%d)", WSAGetLastError());
            break;
        }
        handle_connection(conn);
    }
    vw_logf("server: thread exiting");
    return 0;
}

static int start_server(void)
{
    WSADATA wsa;
    int rc = WSAStartup(MAKEWORD(2, 2), &wsa);
    if (rc != 0) {
        vw_logf("server: WSAStartup failed (%d)", rc);
        return 0;
    }
    g_listen_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_listen_sock == INVALID_SOCKET) {
        vw_logf("server: socket() failed (%d)", WSAGetLastError());
        return 0;
    }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)g_port);
    // Loopback only - the dev driver must never be reachable off-machine.
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(g_listen_sock, (struct sockaddr *)&addr, sizeof addr) != 0) {
        vw_logf("server: bind(127.0.0.1:%d) failed (%d) - port in use? another instance?",
                g_port, WSAGetLastError());
        closesocket(g_listen_sock);
        g_listen_sock = INVALID_SOCKET;
        return 0;
    }
    if (listen(g_listen_sock, 4) != 0) {
        vw_logf("server: listen failed (%d)", WSAGetLastError());
        closesocket(g_listen_sock);
        g_listen_sock = INVALID_SOCKET;
        return 0;
    }
    InterlockedExchange(&g_running, 1);
    g_server_thread = CreateThread(NULL, 0, server_main, NULL, 0, NULL);
    if (!g_server_thread) {
        vw_logf("server: CreateThread failed (%lu)", GetLastError());
        InterlockedExchange(&g_running, 0);
        closesocket(g_listen_sock);
        g_listen_sock = INVALID_SOCKET;
        return 0;
    }
    return 1;
}

// ---- GameMaker exports ----
// All exports: doubles and null-terminated strings only.

static void locate_dll_dir(void)
{
    HMODULE self = NULL;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)&locate_dll_dir, &self);
    DWORD n = GetModuleFileNameA(self, g_dll_dir, sizeof g_dll_dir);
    if (n == 0 || n >= sizeof g_dll_dir) {
        g_dll_dir[0] = '\0';
        return;
    }
    char *slash = strrchr(g_dll_dir, '\\');
    if (slash)
        slash[1] = '\0'; // keep trailing backslash for direct concatenation
    else
        g_dll_dir[0] = '\0';
}

// Returns the speech tier: 2 prism, 1 sapi, 0 capture-only. Idempotent.
VW_EXPORT double vw_init(void)
{
    if (g_inited)
        return g_init_result;
    g_inited = 1;

    InitializeCriticalSection(&g_lock);
    InitializeCriticalSection(&g_log_lock);
    InitializeConditionVariable(&g_cmd_cv);
    vwp_ring_init(&g_ring);
    vwp_cmd_init(&g_cmd);
    locate_dll_dir();

    read_config_file();
    read_config_env();
    vw_logf("init: shim %s starting (speech=%d dev=%d port=%d dir=%s)",
            VW_SHIM_VERSION, g_speech_on, g_dev_on, g_port, g_dll_dir);

    double tier = 0;
    if (g_speech_on) {
        if (load_prism())
            tier = 2;
        else if (load_sapi())
            tier = 1;
        else
            snprintf(g_backend_desc, sizeof g_backend_desc, "none (all backends failed)");
    } else {
        snprintf(g_backend_desc, sizeof g_backend_desc, "off (capture only)");
    }

    if (g_dev_on) {
        if (!start_server())
            vw_logf("init: dev server failed to start; /speech and /cmd unavailable this run");
    } else {
        vw_logf("init: dev server disabled by config");
    }

    if (g_bg_on)
        try_install_bg(); // usually too early; vw_poll retries every frame
    else
        vw_logf("init: background-run keepalive disabled by config");

    vw_logf("init: done, backend=%s tier=%d", g_backend_desc, (int)tier);
    g_init_result = tier;
    return tier;
}

// Speak text. interrupt != 0 cuts off current speech. Always captured to the
// ring; voiced only when the speech gate is on.
// Returns 1 voiced, 0 captured only, -1 backend error, -2 not initialized.
VW_EXPORT double vw_speak(const char *text, double interrupt)
{
    if (!g_inited || !text)
        return -2;
    EnterCriticalSection(&g_lock);
    vwp_ring_push(&g_ring, text);
    LeaveCriticalSection(&g_lock);
    return backend_speak(text, interrupt != 0);
}

VW_EXPORT double vw_stop(void)
{
    if (!g_inited)
        return -2;
    if (g_prism_backend) {
        PrismError e = p_backend_stop(g_prism_backend);
        if (e != PRISM_OK) {
            vw_logf("prism: stop failed: %s", prism_err_str(e));
            return -1;
        }
        return 1;
    }
    if (g_sapi) {
        HRESULT hr = ISpVoice_Speak(g_sapi, L"", SPF_ASYNC | SPF_PURGEBEFORESPEAK, NULL);
        if (FAILED(hr)) {
            vw_logf("sapi: purge failed (0x%08lx)", (unsigned long)hr);
            return -1;
        }
        return 1;
    }
    return 0;
}

VW_EXPORT const char *vw_backend_name(void)
{
    return g_backend_desc;
}

// The panic action: tear down and re-create the speech backends without
// touching the ring, the server, or the command slot. Main thread only, like
// every speech call. Holds g_lock across the reload because the HTTP thread
// reads g_backend_desc for /health. Returns the new tier (2/1/0) or -2.
VW_EXPORT double vw_reset_speech(void)
{
    if (!g_inited)
        return -2;
    vw_logf("reset: speech stack reset requested");
    EnterCriticalSection(&g_lock);
    unload_speech_backends();
    double tier = 0;
    if (g_speech_on) {
        if (load_prism())
            tier = 2;
        else if (load_sapi())
            tier = 1;
        else
            snprintf(g_backend_desc, sizeof g_backend_desc, "none (all backends failed)");
    } else {
        snprintf(g_backend_desc, sizeof g_backend_desc, "off (capture only)");
    }
    LeaveCriticalSection(&g_lock);
    g_init_result = tier;
    vw_logf("reset: done, backend=%s tier=%d", g_backend_desc, (int)tier);
    return tier;
}

// One pump round: returns the pending dev command, or "" when idle.
VW_EXPORT const char *vw_poll(void)
{
    static char buf[VWP_MAX_BODY + 1];
    if (!g_inited)
        return "";
    try_install_bg(); // main thread, once per frame, no-op once installed
    EnterCriticalSection(&g_lock);
    g_last_poll_tick = GetTickCount64();
    const char *cmd = vwp_cmd_poll(&g_cmd);
    if (cmd) {
        strncpy(buf, cmd, VWP_MAX_BODY);
        buf[VWP_MAX_BODY] = '\0';
    } else {
        buf[0] = '\0';
    }
    LeaveCriticalSection(&g_lock);
    return buf;
}

VW_EXPORT double vw_reply(const char *text)
{
    if (!g_inited || !text)
        return -2;
    EnterCriticalSection(&g_lock);
    int rc = vwp_cmd_reply(&g_cmd, text);
    WakeAllConditionVariable(&g_cmd_cv);
    LeaveCriticalSection(&g_lock);
    if (rc != 0)
        vw_logf("reply: no command awaiting a reply (HTTP side timed out?)");
    return rc == 0 ? 1 : -1;
}

// OS typematic settings, for the input layer's key-repeat (session 3).
VW_EXPORT double vw_key_delay(void)
{
    UINT val = 0; // 0..3 -> 250..1000 ms
    if (!SystemParametersInfoW(SPI_GETKEYBOARDDELAY, 0, &val, 0))
        return 500;
    return (double)((val + 1) * 250);
}

VW_EXPORT double vw_key_rate(void)
{
    DWORD val = 0; // 0..31 -> ~2.5..30 repeats/sec; return the period in ms
    if (!SystemParametersInfoW(SPI_GETKEYBOARDSPEED, 0, &val, 0))
        return 50;
    double per_sec = 2.5 + (double)val * (27.5 / 31.0);
    return 1000.0 / per_sec;
}

VW_EXPORT double vw_shutdown(void)
{
    if (!g_inited)
        return 0;
    vw_logf("shutdown: begin");
    if (g_game_hwnd && IsWindow(g_game_hwnd) && g_orig_wndproc) {
        SetWindowLongPtrW(g_game_hwnd, GWLP_WNDPROC, (LONG_PTR)g_orig_wndproc);
        g_game_hwnd = NULL;
    }
    if (g_server_thread) {
        InterlockedExchange(&g_running, 0);
        if (g_listen_sock != INVALID_SOCKET) {
            closesocket(g_listen_sock); // unblocks accept()
            g_listen_sock = INVALID_SOCKET;
        }
        WaitForSingleObject(g_server_thread, 2000);
        CloseHandle(g_server_thread);
        g_server_thread = NULL;
        WSACleanup();
    }
    unload_speech_backends();
    vw_logf("shutdown: done");
    return 1;
}
