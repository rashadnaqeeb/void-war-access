# Void War Access - Claude Code Instructions

Makes **Void War** (Steam 2853590) playable by blind players. Speech is the
primary interface; there is no visual fallback. If something fails silently,
speaks stale data, or omits information, the player has no way to know. A
logged failure is actionable; a silent one is invisible.

Greenfield project: committing to `main` is fine.

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
  flow through `input_check*` in `scrKeybinds` (build-mod patches those to
  honor `global.vwaSuppressGameKeys`, with a post-import decompile assert -
  a find-replace no-match no-ops silently).
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
  compile error.
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
- Speech is OFF by default in dev launches (capture-only) so unattended runs
  don't drive the screen reader; `-Speech` voices it. `/speech` taps
  upstream of the gate and captures everything regardless.

## Layout

- `src/gml/` - GML source fragments assembled by build-mod, one script each;
  every script's header is the authoritative spec of its module - read it
  before touching the module. `scrVwaCore` (speech chokepoint, logging,
  shim binding), `scrVwaInput` (action registry, typematic repeat,
  suppression; the ONE sanctioned home of raw `keyboard_check`),
  `scrVwaGraph` (control graph, builder, navigation engine; PURE),
  `scrVwaAnnounce` (announcement parts, path-diff compose; PURE),
  `scrVwaSearch` (type-ahead matcher; PURE), `scrVwaScreens` (screen
  registry and stack, navigator, type-ahead glue, alt-arrow line review),
  `scrVwaText` (text edit layer: edit-mode tracker, edit feedback, keyboard
  exit), `scrVwaSheet` (crew sheet composer: a crew instance's categorized
  spoken lines - stats/type/traits/innate/slots/extras - reused by every
  crew-reading surface), `scrVwaMenus` (the real game screens + the generic
  widget adapter), `scrVwaDev` (dev driver, dev builds only). `*.append.gml`
  appends to the named code entry (`*.dev.append.gml` = dev-only).
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
  smoke runs. `-Speech` voices output; `-NoBg` disables the keepalive.
- **Background-run:** the shim subclasses the game window's WndProc so
  unattended runs never pause. The documented freeze is a BOOT freeze that
  Steam's `-applaunch` clears itself; if `/health` still stalls, ask Rashad
  to focus the window once. The keepalive is opt-in via cfg (`bg=1`, which
  run-game writes by default) so a shipped install never runs combat unheard.
- **Smokes** (against a live game at the main menu): `scripts/drive-smoke`,
  `input-smoke`, `screens-smoke`, `mainmenu-smoke`, `settings-smoke`,
  `typeahead-smoke`, `textedit-smoke`, `commander-smoke` - profile-agnostic
  where possible (expected speech derives from /gui/mod; note nested arrays
  returned through a PowerShell function collapse - fetch scalars).
  **Run all eight after touching the shim, the pump, scrVwaInput, or any
  framework or screen script.**
- **Logs:** shim -> `build\vw_speech.log`; GML -> `%AppData%\Roaming\
  Void_War\vwa-mod.log`; every spoken line -> `vwa-speech.log` there.

## Dev driver (loopback HTTP, dev builds only)

`http://127.0.0.1:8772` - the agent's interface to the live game.
Endpoints: `GET /health` (answers even with GML wedged; reports pumpAgeMs,
bgKeepalive), `GET /speech?since=N` (monotonic cursor - how you observe TTS
you can't hear), `GET /gui/raw[?obj=oThing]` (game truth), `GET /gui/mod`
(the mod's interpreted view - diff against raw to find what the mod loses),
`GET /screenshot`, `GET /state` (input layer),
`GET /log?which=shim|mod|speech[&lines=N]` (plain-text log tail, served by
the shim with no game round-trip), `POST /input` (fires a mod action
through real dispatch; refused when its category isn't live), `POST /cmd`.
**Game-touching calls are serialized** - one in flight, a second gets 429
(deliberate; the pump runs one command per frame).

`/cmd` vocabulary: `ping`, `say <text>`, `room`, `get <path>`,
`set <path> <value>`, `dump <path> [depth]`, `instances <obj>`,
`globals [filter]` / `scripts [filter]` (discovery; case-insensitive
name-substring filter), `call <script|path> [args...]` (methods invoked
directly, max 4 args), `gui.raw [obj]`, `gui.mod`, `screenshot`, `state`,
`input <actionKey>`, `help`. Paths: `global.x`, `oObject.var`, numeric ids,
`.member`, `[n]`. `set` values and `call` args take JSON-ish compound
literals (`[1, "two words"]`, `{a: 1, b: [2]}`) alongside scalars; bare
words are strings. Errors return as `ERROR:` text and never crash the pump.

Dev helpers via `call`: `vwa_dev_test_screen <cats|none>` (trailing `!` =
exclusive), `vwa_dev_test_menu <on|off>`, `vwa_dev_test_submenu <on|off>`,
`vwa_dev_menu_focus <skey>`,
`vwa_dev_menu_rename <old> <new>`, `vwa_dev_register_test_actions`,
`vwa_dev_arm_input_fault`, `vwa_dev_key_direct <vk>`,
`vwa_dev_typeahead <text>` / `vwa_dev_search_state` (drive/inspect the
type-ahead layer below the raw keyboard read),
`vwa_dev_type <text>` / `vwa_dev_text_state` (inject into keyboard_string /
inspect the text edit layer; injected chars only reach a field's text while
a physical key is held),
`vwa_dev_suppression_probe <bind>` (retry only on `live:false` with
`kbDirect:true`), `vwa_dev_dismiss_start_popup` (honors the once-per-profile
double-spawn quirk), `vwa_dev_close_commander_select` (the commander
screen's Escape-branch mirror; rmCommanderSelect only), `vwa_dev_spawn
<objName>` (oMenuPause verified safe at the main menu).

## User keys

Global (always live, textSafe - they survive game text fields): **Ctrl**
stop speech, **Shift+F11** panic speech-stack reset. UI (live while a mod
screen is focused): **arrows** navigate (left/right adjust sliders first),
**Enter** activates, **Tab/Shift+Tab** cycle control groups, **Home/End**
jump to the group's first/last control, **Ctrl+left/right** large slider
steps, **Ctrl+up/down** submenu jumps (grid screens will reuse the chord
for region jumps), **Alt+up/down** line review (announcements are
line-structured: control summary first, then each tooltip/sheet line; the
chord re-speaks one line per press, resolved live, with Top/Bottom at the
ends), **letters** (and space once a buffer exists) type-ahead
search over the focused Tab stop, **Escape** nav-back (consumed ONLY when
an active search clears or a screen claims it via onBack; otherwise the
game's own Escape runs untouched). Tooltips have NO key: a widget's
tooltipStr is an announcement part, read inline with the control - on its
own line, steppable by the line review. Actions
carry a bindings LIST (any chord fires); screens can opt out of type-ahead
via `allowsTypeahead: false` (reserve it for screens whose letters are
hotkeys).

Text edit mode (while the game's text-field input is active): typing is
echoed by the screen reader itself and backspace speaks the deleted
character; **up/down** read the whole text, **Enter/Escape** stop editing.
There is deliberately NO review cursor: the game has no movable caret, no
selection, and no clipboard - every edit lands at the END of the text, and
a cursor that cannot place edits teaches a false model.

The behavior models live in the script headers: submenus and
jump edges in scrVwaGraph, type-ahead matching in scrVwaSearch, the
type-ahead key handling and the line review in scrVwaScreens, the text
edit model (and the game's text-field mechanics it wraps) in scrVwaText,
the crew sheet structure (Rashad's categorized read: stats, type, traits,
innate abilities, one line per equipment slot, extras) in scrVwaSheet, the
commander select screen in scrVwaMenus.

## Hard rules (the audit command checks these)

- **No silent failures.** Every guarded failure path logs. Prefer
  let-it-crash over defensive guards where a value isn't expected to be
  missing. Sanctioned swallow-and-log spots ONLY: the dev pump watchdog; the
  input tick watchdog (which clears `global.vwaSuppressGameKeys` so a mod
  bug can never leave the game's keyboard dead); the screen-callback
  quarantine in `vwa_screens_tick` (logs once per activation, screen goes
  inert); the part-resolve guard in scrVwaAnnounce (logs, speaks "error");
  `vwa_shim_init`'s log-only degrade when the DLL is absent.
- **One speech chokepoint.** All speech flows through `vwa_speak(parts,
  interrupt)`; parts is an ARRAY (flat = one spoken line; any element being
  an array makes every element a LINE - the shape the alt-arrow line review
  steps); joining happens only there. No direct shim
  calls from feature code (sanctioned non-speech shim calls: the input
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
  architecture change.
