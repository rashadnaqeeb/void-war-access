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
  `scrVwaCore.gml` (speech chokepoint, logging, shim binding),
  `scrVwaInput.gml` (input layer: actions, categories, shadowing, typematic
  repeat, suppression watchdog, stale-key unstick, text-safe speech controls
  that survive the game's text-field mode; the one sanctioned
  home of raw `keyboard_check`), `scrVwaGraph.gml` (control graph: two-tier
  node identity, menu/raw builder, row groups (a multi-item row synthesizes
  a labeled context that counts as ONE vertical entry; members keep their
  in-row "x of k"), Tab stops, focus reconciliation; PURE - no game or
  global references), `scrVwaAnnounce.gml` (parts, control types
  as data, path-diff compose returning parts arrays, generic group word via
  hooks.groupText for unnamed row groups; PURE),
  `scrVwaScreens.gml` (screen registry, per-frame poll-and-diff stack and
  focus sync driven from the input tick, navigator actions, once-per-frame
  announce observe + live-part watch), `scrVwaMenus.gml` (the real game
  screens: main menu, announcements popup, the generic widget adapter
  (y-then-x rows, vtable per widget family, activation mirrors that read
  press sounds BEFORE callbacks - a destroyed button's dead id crashes
  post-callback reads) and the settings family: settings, pause menu,
  confirmation dialogue, dropdown child screen with opt-in onBack Escape
  consume; all gated on `!global.gameIsLoading`), and `scrVwaDev.gml`
  (dev-driver eval-lite interpreter, dev builds only) each become a new
  global script;
  `*.append.gml` files append to the named code entry (`*.dev.append.gml`
  marks dev-only appends).
  build-mod also QueueFindReplace-patches the game's `scrKeybinds` so
  `input_check*` honor `global.vwaSuppressGameKeys`, with a post-import
  decompile assert (find-replace no-ops silently on no match).
- `src/lang/` - mod strings as `vwa--`-prefixed CSV rows, merged into the
  game's own lang CSVs at build time (all mod speech is localized).
- `vendor/prism/` - Prism 0.16.6 + header + license; ABI notes in its README.
- `tools/` - build and launch scripts, UTMT CLI, decompile scripts.
- `build/` - patched `data-test.win` + mirrored support files (gitignored).
- `decompiled/` - full game decompile, regenerable via `tools/dump-all.csx`
  (gitignored). **Look game facts up here, never guess from memory.**

## Build, run, verify

Rashad has granted standing permission to run the project's PowerShell
scripts; `.claude/settings.json` allows `powershell -NoProfile -File
tools/*` and `scripts/*` (with or without `-ExecutionPolicy Bypass`). Invoke
them exactly in that form from the repo root - no `cd ... &&` prefix and no
other flag order, or the permission rule won't match.

- `tools/build-shim.ps1` - build + RUN the shim's host-side tests, then the
  DLL. Zero-warning policy (`-Wall -Wextra -Werror`), never suppress.
- `tools/build-mod.ps1` - shim + lang CSV merge + patched `build\data-test.win`
  via UTMT CLI (about a minute). Original `data.win` is never modified.
- `tools/run-game.ps1` - the iteration loop. Run as a BACKGROUND task; it
  rebuilds, launches through Steam, polls `/health`, and blocks until game
  exit. It refuses to start while another launcher is alive (lock file).
  `-Speech` voices output; default is capture-only so unattended runs don't
  drive the screen reader. To stop a run, `taskkill //F //IM "Void War.exe"`
  (the launcher wakes and cleans up). Cancelling the background task instead
  ORPHANS the game (it is Steam's child, and a hard cancel skips finally) -
  self-healing on the next launcher run, but prefer taskkill.
- Dev driver: `http://127.0.0.1:8772` - `GET /health` (also reports
  `bgKeepalive`), `GET /speech?since=N` (monotonic cursor; how you observe TTS
  you can't hear), `GET /gui/raw[?obj=oThing]` (game-truth UI dump),
  `GET /gui/mod` (the mod's interpreted view: screen stack, focused screen's
  nodes with resolved parts/positions/edges, focused key - diff against
  /gui/raw to find what the mod is losing), `GET /screenshot` (PNG to the
  save dir), `GET /state` (input layer: live categories, actions,
  shadowing), `POST /input` (body = action key; fires through real dispatch,
  refused when its category isn't live), `POST /cmd`.
  The `/cmd` eval-lite vocabulary (in `scrVwaDev`, dev builds only): `ping`,
  `say <text>`, `room`, `get <path>`, `set <path> <value>`,
  `dump <path> [depth]`, `instances <obj>`, `call <script|path> [args...]`,
  `gui.raw [obj]`, `gui.mod`, `screenshot`, `state`, `input <actionKey>`,
  `help`. Paths: `global.x`, `oObject.var` (first live instance), a numeric
  id, chained with `.member` and `[n]`. `call` on a dotted path invokes the
  bound method DIRECTLY, max 4 args - `script_execute_ext` on a method value
  silently runs an unrelated script index (bit us session 5).
  A JSON reply is content-typed JSON;
  errors are `ERROR:` text and never crash the pump. Never `var` a GML
  builtin name (`depth`, `x`, ...) in injected code - it is a hard compile
  error. Dev helpers via `call`: `vwa_dev_test_screen <cats|none>`
  (graph-less screen making categories live; trailing `!` = exclusive
  modal), `vwa_dev_test_menu <on|off>` (the synthetic navigator test menu),
  `vwa_dev_menu_focus <skey>` / `vwa_dev_menu_rename <old> <new>` (focus
  jump / tier-1 identity test on it), `vwa_dev_register_test_actions`,
  `vwa_dev_arm_input_fault` (watchdog test), `vwa_dev_key_direct <vk>`
  (runner vs OS key state), `vwa_dev_suppression_probe <bind>` (one-frame
  suppression proof; self-heals stale runner key state, so retry only on
  `live:false` with `kbDirect:true` - a human really holding a key;
  `keyboard_key_press` does NOT work in this runner),
  `vwa_dev_dismiss_start_popup` (the announcements popup's click/Escape
  dismissal for scripted runs, honoring the saved double-spawn quirk),
  `vwa_dev_spawn <objName>` (spawn by object name; oMenuPause verified safe
  at the main menu - pause_game no-ops with no run live).
- User hotkeys (Global category, registered in `scrVwaInput`): Ctrl stop
  speech, Shift+F11 panic speech-stack reset. UI category (live only while
  a mod screen is focused, `scrVwaScreens`): arrows navigate (left/right
  adjust sliders; Ctrl+left/right large steps), Enter activates, Tab /
  Shift+Tab cycle control groups with remembered positions, Home/End jump
  to the focused group's first/last control, Escape fires nav-back
  (opt-in per-screen onBack;
  consumed via keyboard_clear ONLY when a screen claims it - the dropdown
  child screen - otherwise the game's own Escape handling runs untouched).
  Actions carry a bindings LIST (any chord fires; WotR parity). Tooltips
  have NO key: a widget's tooltipStr is an announcement part, read inline
  with the control (Void War tooltips are flat strings - verified, no
  layered/nested tooltips anywhere - so inline covers the whole surface,
  unlike WotR's Pathfinder drill-in reader).
- Regression checks against a live game at the main menu:
  `scripts/drive-smoke.ps1` (dev driver), `scripts/input-smoke.ps1` (input
  layer), `scripts/screens-smoke.ps1` (framework core: exact speech
  transcript over the synthetic test menu), `scripts/mainmenu-smoke.ps1`
  (real screens: main menu, real settings screen, announcements popup;
  profile-agnostic - expected speech derives from /gui/mod), and
  `scripts/settings-smoke.ps1` (session 6: generic widget adapter, settings
  incl. checkbox/slider/dropdown/tooltip, confirmation dialogue via the
  beta-language flow, dev-spawned pause menu; restores every setting it
  touches). Run all five after touching the shim, the pump, `scrVwaInput`,
  or any framework or screen script. `tools/run-game.ps1 -WaitMainMenu`
  blocks until /gui/mod shows the main-menu screen - use it before smoke
  runs.
- Background-run works: the shim subclasses the game window's WndProc to swallow
  deactivation, so the autonomous loop runs unattended (drive over HTTP with the
  game backgrounded). The documented pause is a BOOT freeze - frozen until the
  window is focused once - which Steam's `-applaunch` clears by itself, so no
  human focus is normally needed; if `/health` still stalls, ask Rashad to focus
  the window once. The keepalive is OPT-IN since session 7 (`bg=1` in the
  cfg, which run-game.ps1 writes by default; `-NoBg` writes `bg=0`): a launch
  with no cfg keeps the game's own pause-on-focus-loss, so a shipped install
  never runs combat unheard in the background.
- Logs: shim -> `build\vw_speech.log`; GML mod log -> save dir
  (`%AppData%\Roaming\Void_War\vwa-mod.log`); every spoken line also lands in
  `vwa-speech.log` there. `show_debug_message` does NOT reach `-debugoutput`;
  files and the dev driver are the only channels out of GML.

## Invariants (the session-8 audit checks these)

- **No silent failures.** Every guarded failure path logs. Prefer
  let-it-crash over defensive guards where a value isn't expected to be
  missing. Sanctioned swallow-and-log spots only: the dev pump watchdog;
  the input tick watchdog (which clears `global.vwaSuppressGameKeys` so a
  mod bug can never leave the game's keyboard dead); the screen-callback
  quarantine in `vwa_screens_tick` (a broken isActive/name/build logs once
  per activation and the screen goes inert, so one bad screen can't kill
  the framework); the part-resolve guard in `scrVwaAnnounce` (logs and
  speaks "error" in the part's place); and `vwa_shim_init` degrading to
  log-only speech when the DLL is absent (logs, never-strand).
- **One speech chokepoint.** All speech flows through `vwa_speak(parts,
  interrupt)`; parts is an array (strings or `{text:...}` structs); joining
  happens only there. No direct shim calls from feature code (sanctioned
  non-speech shim calls: the input layer's typematic delay/rate reads, the
  dev pump's poll/reply, and the Game End teardown via `vwa_shim_shutdown`).
- **Hooks never speak.** Patched game events set state or enqueue; speech
  happens once per frame from the pump/diff.
- **Never cache game state.** Re-query at speak time; stale speech is worse
  than none.
- **Never strand the user.** Prism -> SAPI fallback in the shim; no DLL at
  all still writes the speech log. Shift+F11 panic-resets the speech stack
  (`vwa_speech_panic` -> `vw_reset_speech`).
- **Activation calls the game's own stored callbacks** (`onClick` etc.),
  never a reimplementation. The dev driver drives real code paths, never OS
  synthetic input.
- **Every mod string is localized** via `vwa--` rows in the lang CSVs through
  `vwa_t(key)`. Sole exception: dev-driver and log text.
- **Never interrupt speech by default**; interrupt only on genuine focus
  movement, on direct user-caused state feedback (the value a held key
  just changed - `vwa_nav_state_feedback`, WotR StateText parity: queued
  values would read behind a held slider key), and on the panic reset's
  confirmation.
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
