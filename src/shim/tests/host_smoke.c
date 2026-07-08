// Host-side smoke driver for vw_speech.dll: loads the real DLL, initializes
// it, and runs a pump loop that mimics the GML side (poll/reply once per
// tick, answering "ping" and "say <text>"). While it runs, hit the HTTP
// endpoints from another shell:
//
//   curl http://127.0.0.1:8772/health
//   curl "http://127.0.0.1:8772/speech?since=0"
//   curl -X POST --data "ping" http://127.0.0.1:8772/cmd
//   curl -X POST --data "say hello" http://127.0.0.1:8772/cmd
//
// Usage: host_smoke.exe <path-to-vw_speech.dll> [seconds-to-run]
// Speech stays capture-only unless vw_speech.cfg next to the DLL enables it.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef double (*fn_d_void)(void);
typedef double (*fn_d_sd)(const char *, double);
typedef double (*fn_d_s)(const char *);
typedef const char *(*fn_s_void)(void);

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: host_smoke.exe <vw_speech.dll> [seconds]\n");
        return 2;
    }
    int seconds = argc > 2 ? atoi(argv[2]) : 30;

    HMODULE mod = LoadLibraryA(argv[1]);
    if (!mod) {
        fprintf(stderr, "LoadLibrary(%s) failed (%lu)\n", argv[1], GetLastError());
        return 1;
    }
    fn_d_void vw_init = (fn_d_void)(void *)GetProcAddress(mod, "vw_init");
    fn_d_sd vw_speak = (fn_d_sd)(void *)GetProcAddress(mod, "vw_speak");
    fn_s_void vw_poll = (fn_s_void)(void *)GetProcAddress(mod, "vw_poll");
    fn_d_s vw_reply = (fn_d_s)(void *)GetProcAddress(mod, "vw_reply");
    fn_s_void vw_backend_name = (fn_s_void)(void *)GetProcAddress(mod, "vw_backend_name");
    fn_d_void vw_shutdown = (fn_d_void)(void *)GetProcAddress(mod, "vw_shutdown");
    fn_d_void vw_key_delay = (fn_d_void)(void *)GetProcAddress(mod, "vw_key_delay");
    fn_d_void vw_key_rate = (fn_d_void)(void *)GetProcAddress(mod, "vw_key_rate");
    fn_d_void vw_reset_speech = (fn_d_void)(void *)GetProcAddress(mod, "vw_reset_speech");
    if (!vw_init || !vw_speak || !vw_poll || !vw_reply || !vw_backend_name ||
        !vw_shutdown || !vw_key_delay || !vw_key_rate || !vw_reset_speech) {
        fprintf(stderr, "missing export\n");
        return 1;
    }

    double tier = vw_init();
    printf("vw_init -> %g, backend=%s, key_delay=%gms key_rate=%gms\n", tier,
           vw_backend_name(), vw_key_delay(), vw_key_rate());

    vw_speak("smoke: boot line", 0);
    vw_speak("smoke: second line", 0);

    printf("pumping for %d seconds at ~60Hz...\n", seconds);
    ULONGLONG end = GetTickCount64() + (ULONGLONG)seconds * 1000;
    while (GetTickCount64() < end) {
        const char *cmd = vw_poll();
        if (cmd[0]) {
            printf("cmd: %s\n", cmd);
            if (strcmp(cmd, "ping") == 0) {
                vw_reply("pong");
            } else if (strncmp(cmd, "say ", 4) == 0) {
                vw_speak(cmd + 4, 1);
                vw_reply("ok");
            } else {
                vw_reply("unknown command");
            }
        }
        Sleep(16);
    }
    vw_shutdown();
    printf("done\n");
    return 0;
}
