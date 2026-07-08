# Vendored: Prism

- Source: github.com/ethindp/prism, version 0.16.6. This exact DLL is proven
  working inside a 64-bit game process with NVDA and JAWS on this machine.
- License: MPL-2.0 (see LICENSE-MPL-2.0.txt and NOTICE).
- x64 only. Self-contained: screen-reader clients (including the NVDA
  controller) are statically linked; no tolk.dll or nvdaControllerClient.dll
  needed.

## ABI invariants (audit prism.h on any upgrade)

- Calling convention `__cdecl` on every function (PRISM_CALL).
- All boundary strings are null-terminated UTF-8.
- C `bool` is one byte.
- `PrismContext*` / `PrismBackend*` are opaque. `prism_registry_create_best`
  returns an OWNED backend (free with `prism_backend_free`);
  `prism_registry_acquire*` is non-owning (do not free).
- Prefer `prism_backend_output` (speech + braille) over `prism_backend_speak`
  (TTS only); fall back to speak when output is unsupported/not implemented.
- The `PrismError` enum ordering in this header differs from older
  third-party bindings. Always code against this header, not a binding.

The shim (src/shim/vw_speech.c) loads prism.dll dynamically by full path
(next to vw_speech.dll) via LoadLibrary/GetProcAddress, so a missing or
broken prism.dll degrades to capture-only speech (the log still writes)
instead of failing the shim's own DLL load.
