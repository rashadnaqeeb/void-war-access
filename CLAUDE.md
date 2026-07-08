# Void War Access - Claude Code Instructions

This project makes **Void War** (Steam app 2853590, GameMaker 2023.8 VM
bytecode) playable by blind players. Speech is the primary interface; there is
no visual fallback. If something fails silently, speaks stale data, or omits
information, the player has no way to know. A logged failure is actionable; a
silent one is invisible.

Greenfield project: committing to `main` is fine.

Read `docs/build-plan.md` (the session-by-session roadmap - keep its Status
lines current) and `docs/game-and-tooling.md` (verified game facts and
toolchain; every fact there was checked against the real game). Reference
mods: `../wotr-access` (UI architecture we are porting), `../tangledeep`
(dev-driver contract in its CLAUDE.md), `../factorio-access`.

## Layout

- `src/shim/` - the native shim `vw_speech.dll` (C, clang x64): Prism speech
  with SAPI fallback, speech ring buffer, loopback HTTP dev server, command
  queue. Pure protocol logic lives in `vw_protocol.c` (no OS deps) and is
  unit-tested host-side (`src/shim/tests/`).
- `src/gml/` - GML source fragments assembled into the game by build-mod.
  `scrVwaCore.gml` becomes a new global script; `*.append.gml` files append to
  the named code entry.
- `src/lang/` - mod strings as `vwa--`-prefixed CSV rows, merged into the
  game's own lang CSVs at build time (all mod speech is localized).
- `vendor/prism/` - Prism 0.16.6 + header + license; ABI notes in its README.
- `tools/` - build and launch scripts, UTMT CLI, decompile scripts.
- `build/` - patched `data-test.win` + mirrored support files (gitignored).
- `decompiled/` - full game decompile, regenerable via `tools/dump-all.csx`
  (gitignored). **Look game facts up here, never guess from memory.**

## Build, run, verify

- `tools/build-shim.ps1` - build + RUN the shim's host-side tests, then the
  DLL. Zero-warning policy (`-Wall -Wextra -Werror`), never suppress.
- `tools/build-mod.ps1` - shim + lang CSV merge + patched `build\data-test.win`
  via UTMT CLI (about a minute). Original `data.win` is never modified.
- `tools/run-game.ps1` - the iteration loop. Run as a BACKGROUND task; it
  rebuilds, launches through Steam, polls `/health`, and blocks until game
  exit. Cancelling the task kills the game. It refuses to start while another
  launcher is alive (lock file). `-Speech` voices output; default is
  capture-only so unattended runs don't drive the screen reader.
- Dev driver: `http://127.0.0.1:8772` - `GET /health`, `GET /speech?since=N`
  (monotonic cursor; how you observe TTS you can't hear), `POST /cmd` (body:
  `ping` or `say <text>`; eval-lite arrives session 2).
- **The game pauses until its window is focused once per launch**
  (runner-level, verified). `/health` answers only after that. Until the
  WndProc workaround (session 2), ask Rashad to focus the window.
- Logs: shim -> `build\vw_speech.log`; GML mod log -> save dir
  (`%AppData%\Roaming\Void_War\vwa-mod.log`); every spoken line also lands in
  `vwa-speech.log` there. `show_debug_message` does NOT reach `-debugoutput`;
  files and the dev driver are the only channels out of GML.

## Invariants (the session-8 audit checks these)

- **No silent failures.** Every guarded failure path logs. Prefer
  let-it-crash over defensive guards where a value isn't expected to be
  missing. Sanctioned swallow-and-log spots only: the dev pump watchdog and
  (later) input suppression.
- **One speech chokepoint.** All speech flows through `vwa_speak(parts,
  interrupt)`; parts is an array (strings or `{text:...}` structs); joining
  happens only there. No direct shim calls from feature code.
- **Hooks never speak.** Patched game events set state or enqueue; speech
  happens once per frame from the pump/diff.
- **Never cache game state.** Re-query at speak time; stale speech is worse
  than none.
- **Never strand the user.** Prism -> SAPI fallback in the shim; no DLL at
  all still writes the speech log. Speech-stack panic reset arrives session 3.
- **Activation calls the game's own stored callbacks** (`onClick` etc.),
  never a reimplementation. The dev driver drives real code paths, never OS
  synthetic input.
- **Every mod string is localized** via `vwa--` rows in the lang CSVs through
  `vwa_t(key)`. Sole exception: dev-driver and log text.
- **Never interrupt speech by default**; interrupt only on genuine focus
  movement.
- **All user-facing hotkeys go through the input layer** (session 3+); no raw
  `keyboard_check` in feature code.
- GameMaker externals take/return ONLY doubles and null-terminated strings.
- Comments describe current state, never change history.
- Docs stay current in the same session as the change: build-plan Status
  lines, game-and-tooling facts (marked verified, dated; "bit us" notes),
  README (once it exists) for any key/feature change.

## GameMaker gotchas (verified)

- UTMT 0.9.x CLI: no `ImportGMLString`; use
  `UndertaleModLib.Compiler.CodeImportGroup` (`QueueReplace`/`QueueAppend`,
  then `Import()`). `QueueReplace` on a nonexistent `gml_GlobalScript_*` name
  CREATES the script (verified session 1).
- Launch only through Steam (`steam.exe -applaunch 2853590 -game <win>`);
  direct exe launch trips the Steamworks relaunch check.
- Steam does NOT forward the launcher's env vars to the game; the shim reads
  `build\vw_speech.cfg` (written by run-game.ps1) instead.
- The game's lang CSVs have no trailing newline - appending rows blindly
  glues onto the last line (bit us session 1; build-mod.ps1 guards it).
- UTMT event suffixes: `Step_0` Step, `Step_1` Begin Step, `Step_2` End Step,
  `Draw_64` Draw GUI.
