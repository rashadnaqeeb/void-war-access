# Void War Access - Claude Code Instructions

Makes **Void War** (Steam 2853590) playable by blind players. Speech is the
primary interface; there is no visual fallback. If something fails silently,
speaks stale data, or omits information, the player has no way to know. A
logged failure is actionable; a silent one is invisible.

Greenfield project: committing to `main` is fine.

**Feature specs do not live in this file.** Every `src/gml` script's header
is the authoritative spec of its module - read it before touching the
module, and put new behavior documentation there, not here. This file keeps
only what every session needs: environment facts, commands, gotchas, and
the hard rules.

## Game & environment (verified)

- **Engine:** GameMaker 2023.8, VM bytecode, x64 Windows. Patched with the
  UTMT (UndertaleModLib) CLI into `build\data-test.win`; the original
  `data.win` is never modified.
- **Launch only through Steam** (`steam.exe -applaunch 2853590 -game <win>`);
  direct exe launch trips the Steamworks relaunch check. Steam does NOT
  forward env vars to the game - the shim reads `build\vw_speech.cfg`
  (written by run-game.ps1).
- **Decompile:** `decompiled\` (gitignored, regenerable via
  `tools\dump-all.csx`). **Look game facts up there or live via the dev
  driver, never from memory.**
- **Game UI architecture:** no focus concept, no menu keyboard support.
  `global.menuToggle` names the open menu (verified value list in
  scrVwaMenus' header). Widget labels are plain instance variables; ad-hoc
  screens (main menu) expose label/callback structs; all gameplay key reads
  flow through `input_check*` in `scrKeybinds`. The mod's game-key gate is
  DEFAULT-DENY: build-mod patches those wrappers, and the verified
  player-facing raw `keyboard_check*` sites, to pass only keys on the mod's
  explicit allowlists (model and API in scrVwaInput's header; the raw-site
  list in build-mod.csx), every patch with a post-import decompile assert -
  a find-replace no-match no-ops silently.
- **Game text is markup-free** (bracket tokens are pre-substitution
  placeholders) and **tooltips are flat strings** (draw_label panels; no
  links or nesting), so speech needs no stripper and no drill-in reader.
- The game's lang CSVs have **no trailing newline** - appending rows blindly
  glues onto the last line (bit us; build-mod.ps1 guards it).

### UTMT / GML gotchas (each one verified, most bit us)

- UTMT 0.9.x CLI: no `ImportGMLString`; use
  `UndertaleModLib.Compiler.CodeImportGroup` (`QueueReplace`/`QueueAppend`,
  then `Import()`). `QueueReplace` on a nonexistent `gml_GlobalScript_*`
  name CREATES the script. Event suffixes: `Step_0` Step, `Step_1` Begin
  Step, `Step_2` End Step, `Draw_64` Draw GUI.
- GameMaker externals take/return ONLY doubles and null-terminated strings.
- `script_execute_ext` on a METHOD value silently runs an unrelated script
  index - invoke method values directly.
- Never `var` a GML builtin name (`depth`, `x`, ...) in injected code - hard
  compile error. A struct-literal FIELD named after a builtin (`room`)
  imports fine but crashes the literal at runtime ("incorrect type
  (undefined) expecting a Number") - rename the field.
- Cross-entry enum visibility is not guaranteed under the UTMT importer -
  use strings.
- `try/finally` is unverified under the importer - use restore-and-rethrow.
- GML struct `==` is reference equality (usable as an identity tier).
- `show_debug_message` does NOT reach `-debugoutput`; files in the save dir
  and the dev driver are the only channels out of GML.
- `keyboard_key_press` does not work in this runner; the dev driver drives
  real dispatch instead.
- GameMaker maps Return and numpad Enter both to `vk_enter`.
- PowerShell 5.1 `Invoke-RestMethod` JSON-decodes a text/plain body that
  parses as JSON (smoke scripts' CmdStr handles both).

## Speech: Prism

- `vendor/prism/` - Prism 0.16.6 (`prism.dll` + header + license); ABI notes
  in its README; re-audit the header on any upgrade.
- The shim `vw_speech.dll` (C, clang x64, `src/shim/`) owns everything
  pointer-shaped: the Prism context/backend, the speech ring buffer, the
  loopback HTTP dev server, and the command queue. **Prism only** - Prism's
  own registry covers SAPI, so there is no separate fallback tier; with no
  usable Prism the shim is capture-only and the GML side still writes the
  speech log. Pure protocol logic lives in `vw_protocol.c` (no OS deps),
  unit-tested host-side (`src/shim/tests/`).
- Speech is always voiced; there is no speech-off mode. Every line is also
  captured to the ring, so `/speech` and the speech log see everything even
  with no usable Prism. Sole exception, dev-driven runs: the agent-drive
  quiet window (a POST to `/cmd` or `/input` mutes VOICING for the next few
  seconds, refreshed per request; capture is unaffected), so smoke runs
  don't bombard whoever is at the machine while the player's own keys still
  speak. GETs never arm it; it self-expires (never strand the user).
  `quiet=<ms>` in the cfg, run-game `-QuietMs` (0 disables), `/health`
  reports `quietMsLeft`.
- The shim punctuates lines on the way into Prism (a line with no
  terminating punctuation gains a period, so the synthesizer sentence-breaks
  at newlines); the ring and both speech logs keep the raw chokepoint text.

## Layout

- `src/gml/` - GML source fragments, one script each; build-mod globs
  `scr*.gml`, so a new script is just a new file (no build-code change).
  `scrVwaCore` (speech chokepoint, logging, shim binding), `scrVwaInput`
  (action registry, suppression; the ONE sanctioned home of raw
  `keyboard_check`), `scrVwaGraph` (control graph + navigation engine;
  PURE), `scrVwaAnnounce` (announcement compose; PURE), `scrVwaSearch`
  (type-ahead matcher; PURE), `scrVwaScreens` (screen registry/stack,
  navigator, line review), `scrVwaText` (text edit layer), `scrVwaSheet`
  (crew sheet composer), `scrVwaShipLayer` (in-run ship layer: mode gate,
  per-hull state + geometry index, ship focus toggle, tile cursor with
  edge rules + section composer - an input
  MODE via scrVwaInput's mode providers, never on the screen stack),
  `scrVwaWidgets` (generic widget adapter, oButton
  activation mirror, dropdown child screen, auto-paging), `scrVwaMenus`
  (screen registration dispatcher + generic fallback) with one
  `scrVwaMenu*` file per screen family (Main, Settings, Commander,
  ShipSelect, Encounter - a new game screen family gets its own file),
  `scrVwaDev`,
  `scrVwaDevScreens` (synthetic test screens), and `scrVwaTest` (dev builds
  only). `*.append.gml` appends to the named code entry (`*.dev.append.gml`
  = dev-only); `*.replace.gml` replaces one wholesale (build-mod asserts
  each replacement landed).
- `src/lang/` - mod strings as `vwa--` CSV rows, merged into the game's lang
  CSVs at build time.
- `tools/` - build + launch scripts, UTMT CLI, decompile scripts.
  `build/` - patched game data (gitignored).

## Build, run, verify

Rashad has granted standing permission to run the project's PowerShell
scripts; invoke them exactly as `powershell -NoProfile -File tools/*` or
`scripts/*` from the repo root (with or without `-ExecutionPolicy Bypass`) -
any other form won't match the permission rule.

- `tools/build-shim.ps1` - host-side protocol tests, then the DLL.
- `tools/build-mod.ps1` - shim + lang merge + patched `build\data-test.win`
  (about a minute).
- `tools/run-game.ps1` - THE iteration loop. Run as a BACKGROUND task; it
  rebuilds, launches through Steam, polls `/health`, blocks until game exit,
  and refuses to start while another launcher holds the lock. Stop a run
  with `taskkill //F //IM "Void War.exe"` (the launcher wakes and cleans
  up); cancelling the background task instead ORPHANS the game.
  `-WaitMainMenu` blocks until /gui/mod shows the main menu - use before
  smoke runs. `-NoBg` disables the keepalive.
- **Background-run:** the shim subclasses the game window's WndProc so
  unattended runs never pause. The documented freeze is a BOOT freeze that
  Steam's `-applaunch` clears itself; if `/health` still stalls, ask Rashad
  to focus the window once. The keepalive is opt-in via cfg (`bg=1`, which
  run-game writes by default) so a shipped install never runs combat unheard.
- **Smokes** (against a live game at the main menu), three scripts:
  `scripts/drive-smoke` (dev driver plumbing), `scripts/input-smoke` (input
  layer + suppression), `scripts/smoke` (THE screen smoke). **Run all three
  after touching the shim, the pump, scrVwaInput, or any framework or
  screen script.** The assertions of `smoke` live IN THE GAME (scrVwaTest):
  `vwa_dev_selftest` unit-tests the pure modules on fixtures, and the
  walker (`vwa_dev_walk_start`) sweeps every node of a screen, verifying
  real speech against a fresh live resolve. The PS scripts are dumb runners.
- **Testing rules** (session-11 redesign; the old per-screen smokes burned
  whole sessions on expectation drift): a test asserts BEHAVIOR, never a
  snapshot of current content - no hardcoded composed speech strings, no
  hardcoded counts or whole-set equality where membership is the property
  under test. Expected values are DERIVED LIVE (from /gui/mod, game
  globals, `vwa_t` templates, or post-activation game state). New assertion
  logic goes in GML (scrVwaTest), not PowerShell. PS 5.1 gotchas when a
  runner change is unavoidable: nested arrays returned through a PS
  function collapse (fetch scalars); non-ASCII `.ps1` needs a UTF-8 BOM
  (edit with the Edit tool, never regex/rewrite passes); PS one-liners
  through bash lose `$` variables (use script files).
- **Logs:** shim -> `build\vw_speech.log`; GML -> `%AppData%\Roaming\
  Void_War\vwa-mod.log`; every spoken line -> `vwa-speech.log` there. The
  game writes no log of its own (that save dir is also where its saves and
  `gm_exports\` UIText dumps live). The mod log's unstick/watchdog lines
  around a repro window are often the fastest evidence of an input-layer
  problem - read them before theorizing.

## Dev driver (loopback HTTP, dev builds only)

`http://127.0.0.1:8772` - the agent's interface to the live game.
Endpoints: `GET /health` (answers even with GML wedged), `GET /speech?since=N`
(monotonic cursor - how you observe TTS you can't hear), `GET /gui/raw[?obj=oThing]`
(game truth), `GET /gui/mod` (the mod's interpreted view - diff against raw
to find what the mod loses), `GET /screenshot`, `GET /state` (input layer),
`GET /log?which=shim|mod|speech[&lines=N]` (log tail, no game round-trip),
`POST /input` (fires a mod action through real dispatch; refused when its
category isn't live), `POST /cmd`. **Game-touching calls are serialized** -
one in flight, a second gets 429 (deliberate; the pump runs one command per
frame).

`/cmd` is an eval-lite interpreter: send `help` for the vocabulary;
scrVwaDev's header documents paths and the JSON-ish compound literals.
Errors return as `ERROR:` text and never crash the pump.

Dev helpers are plain scripts invoked via `call`; discover them with
`scripts vwa_dev` (or `scripts vwa_dev_walk` etc.) and read each helper's
doc comment in scrVwaDev/scrVwaTest - the comment is its spec, including
the quirks. The testing entry points: `call vwa_dev_selftest` (pure-module
unit tests, one frame) and `call vwa_dev_walk_start <screenKey>` /
`vwa_dev_walk_status` (the screen walker: frame-driven sweep of the FOCUSED
screen; poll status until done).

## User keys

Global (always live, textSafe - they survive game text fields): **Ctrl**
stop speech, **Shift+F11** panic speech-stack reset. While a mod screen is
focused: **arrows** navigate (left/right adjust sliders first), **Enter**
activates, **Tab/Shift+Tab** cycle control groups, **Home/End** group ends,
**Ctrl+left/right** large slider steps, **Ctrl+up/down** submenu jumps,
**Alt+up/down** line review, **letters** type-ahead search, **Escape**
nav-back (consumed only when the mod actually acts; otherwise the game's
own Escape runs untouched). On encounter dialogues, **numbers 1-9** jump
to that choice without activating (the game's own silent number-commit is
patched out at build time; Enter commits). Text edit mode: **up/down** read the whole
text, **Enter** commits the edit, **Escape** cancels it (same operation on
fields whose text is live as typed). On the in-run ship layer (no menu, no
popup, not warping): **Tab** toggles which ship the tools look at, and
**arrows** move the tile cursor (walls and airlocks block, doors pass).

The authoritative behavior models live in the script headers: submenus and
jump edges in scrVwaGraph, type-ahead matching in scrVwaSearch, the
type-ahead key handling and the line review in scrVwaScreens, the text edit
model in scrVwaText, the crew sheet structure in scrVwaSheet, the widget
adapter and auto-paging in scrVwaWidgets, the real game screens in the
scrVwaMenu* family files (dispatcher and menuToggle registry in
scrVwaMenus), the in-run ship layer's mode, state, and cursor model in
scrVwaShipLayer.

## Hard rules (the audit command checks these)

- **No silent failures.** Every guarded failure path logs. Prefer
  let-it-crash over defensive guards where a value isn't expected to be
  missing. Sanctioned swallow-and-log spots ONLY: the dev pump watchdog; the
  input tick watchdog (which fails the game-key gate open via
  `global.vwaGameKeysOpen` so a mod bug can never leave the game's keyboard
  dead); the screen-callback
  quarantine in `vwa_screens_tick` (logs once per activation, screen goes
  inert); the part-resolve guard in scrVwaAnnounce (logs, speaks "error");
  `vwa_shim_init`'s log-only degrade when the DLL is absent.
- **One speech chokepoint.** All speech flows through `vwa_speak(parts,
  interrupt)`; parts is an ARRAY (flat = one spoken line; any element being
  an array makes every element a LINE - the shape the alt-arrow line review
  steps); joining happens only there (`vwa_speak_render`, its pure join).
  `global.vwaSpeakTap` is the sanctioned observation hook on the chokepoint
  (dev builds: the scrVwaTest walker); it observes, never speaks. No direct
  shim calls from feature code (sanctioned non-speech shim calls: the input
  layer's typematic delay/rate reads, the dev pump's poll/reply, the Game
  End teardown via `vwa_shim_shutdown`).
- **Hooks never speak.** Patched game events set state or enqueue; speech
  happens once per frame from the pump/diff. Sanctioned one-shot exception:
  the boot announcement in oInitGlobals Create.
- **Never cache game state.** Re-query at speak time; a live instance
  reference read on demand is the only acceptable cache. Stale speech is
  worse than none.
- **Never strand the user.** No DLL still writes the speech log; Shift+F11
  panic-resets the speech stack; the speech keys survive text-field mode.
- **Activation calls the game's own stored callbacks** and mirrors the real
  handler's guards, order, and sounds; press-sound ids are read BEFORE the
  callback (a destroyed button's dead id crashes post-callback reads).
  Sanctioned reimplementation: the volume-slider wheel-path mirror (the
  mirror preserves the wheel's clamp and update calls, not its coarseness).
  The dev driver drives real code paths, never OS synthetic input.
- **Surface only what's visible.** Mirror the game's own visibility, sort,
  and filter rules; mod-authored structure words ("n of m", the group word)
  are the sanctioned verbalized-visible-structure class.
- **Every mod string is localized** via `vwa--` rows through `vwa_t(key)`,
  in all four languages. Sole exception: dev-driver and log text.
- **Never interrupt speech by default**; interrupt only on genuine focus
  movement, on direct user-caused state feedback (`vwa_nav_state_feedback` -
  queued values would read behind a held slider key), and on the panic
  reset's confirmation.
- **All user-facing hotkeys go through the input layer**; no raw
  `keyboard_check` in feature code.
- Comments describe current state, never change history.
- Zero build warnings, C and UTMT import, never suppressed.
- **This file stays current in the same session** as any rule or
  architecture change - but new feature behavior documents itself in its
  script header, not here.
