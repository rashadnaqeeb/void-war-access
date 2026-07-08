# Void War Access: Build Plan

Roadmap for building the accessibility mod's core: five layers (speech, input, screens, control graph, announcer) plus the dev driver. The layers are interdependent and none is useful alone, so the work is sequenced so that every session ends with something verifiable end to end, even if small. Companion docs: `game-and-tooling.md` (verified game facts and toolchain), `../../wotr-access` (the reference mod whose UI architecture we are porting), `../../tangledeep` (whose CLAUDE.md is the authoritative description of the dev-driver model; WotR Access's server follows the same contract in source, but its CLAUDE.md predates it).

## How to use this doc

One section = one session. Each session has a goal, build items, verification steps, and exit criteria. Do not start a session's work until the previous session's exit criteria are met. At the end of every session, update the Status line of its section (and add notes for anything learned that changes later sections). Verification marked "agent" is done through the dev driver or file channel; verification marked "user" needs Rashad present with the game audible.

## The dev driver: what it is and why it comes first

Adopted wholesale from Tangledeep/WotR Access: an in-process server, part of the mod, loopback only, that is the agent's primary interface to the live game for the entire life of the project. It is how screens get reverse-engineered (dump the raw truth, poke at it live), how flows get driven (input through the game's own handlers, never OS synthetic keys), and how output gets verified (every spoken line readable over HTTP). The iteration loop it exists to serve: edit, kill game, relaunch via the launcher script (rebuild included), poll `/health`, drive with curl, read `/speech`. The goal state is that loop running with no human present.

GameMaker constraints shape the port, without changing the model:

- GML cannot compile code at runtime, so there is no true `/eval`. The replacement is an eval-lite command interpreter running in GML, built on GML's dynamic facilities: read/write any global or instance variable by name, enumerate instances of any object by name, recursively dump any struct/array/instance to JSON (`json_stringify` plus reflection over `variable_struct_get_names` / `variable_instance_get_names`), and call any named script or stored method with literal arguments (`asset_get_index`, `script_execute`, method variables). That covers the reverse-engineering workflow that matters: dump `oMainMenuControls.buttonList`, inspect a dropdown's entries, call an onClick, flip a global, without pre-building a command for each.
- GML has no async networking on any existing object, so the HTTP transport lives in the C shim on a background thread. Commands that touch game state are queued and pumped once per step on the GML side (`vw_poll`/`vw_reply`), with a blocking wait and a "game not pumping" timeout on the HTTP side - the same main-thread-marshaling model both references use. `/health` and `/speech` are served directly from the shim thread so diagnostics survive a wedged or paused GML side.
- The game pauses completely when its window loses focus (verified, runner-level). This directly blocks the autonomous loop, so defeating it is early foundational work, not a nice-to-have: the shim lives inside the process and will attempt to subclass the game window's message handling so the runner never observes deactivation. Until that works, the documented fallback is: the agent drives everything from background tasks over HTTP (which needs no terminal focus), and a human focuses the game window once after each launch.

Endpoint contract (mirroring the references): `GET /health`, `GET /speech?since=N` with monotonic cursor, `POST /cmd` (the eval-lite interpreter), `GET /gui/raw` (game-truth dump of live UI instances and their variables), `GET /gui/mod` (our screen graph and focus, once it exists; diff against raw to find what the mod is losing), `GET /screenshot` (via `screen_save`), `POST /input` (fire mod input actions through the real dispatch path, once the input layer exists), plus game-state conveniences later (the `/loadsave` equivalent for jumping into a run).

Gating, per the references: on by default in the dev build (`data-test.win`, which never ships), loopback only, port 8772 (`VWACCESS_DEV_PORT` overrides), opt out with `VWACCESS_NO_DEV=1`. The release build script simply omits the server pump and eval-lite injection. Speech through Prism is OFF by default in dev-driver launches (`-Speech` to voice it) so unattended runs don't drive the user's screen reader; the `/speech` tap is upstream of the backend and captures everything regardless.

## Standing constraints and conventions

Adopted from the convergent rules of both reference projects (WotR Access: CLAUDE.md plus .claude/commands/audit.md; Tanglebeep: CLAUDE.md, which carries them from hand-of-fate-access) and from verified Void War facts. These are the project's invariants; the session-8 audit checks against them, and our own CLAUDE.md (created in session 1) restates them for every future session.

Correctness philosophy (why the rules exist): speech is the primary interface and there is no visual fallback. If something fails silently, speaks stale data, or omits information, the player has no way to know. A logged failure is actionable; a silent one is invisible.

- No silent failures. Every guarded failure path logs (to the mod log file and, where relevant, the dev driver). Prefer let-it-crash over defensive guards where a value isn't expected to be missing: a crash is visible, a swallowed error silently kills a feature a blind player can't see fail. The sole sanctioned swallow-and-continue spots are the watchdogs that protect the game itself (input suppression, the dev pump), and those log loudly.
- One speech chokepoint. Every spoken string flows through a single GML function (`vwa_speak`), which calls the shim and appends to the speech log. No direct shim calls from feature code. The dev driver's `/speech` taps this chokepoint.
- Composition discipline at the chokepoint. Feature code hands the chokepoint structured parts (arrays of part structs), not pre-joined strings; joining happens once, in the compose/speak path. This is Tanglebeep's MessageBuilder rule and WotR's resolve-only-at-output-boundaries rule in GML form: it keeps separators uniform, lets the chokepoint post-process all speech, and keeps parts re-resolvable on a language change.
- Hooks never speak. Patched game events set state or enqueue; speech happens once per frame from the pump/diff. (Same rule as pull-based announcing: focus changes are detected by per-frame diff and spoken exactly once; no announce calls at input-handling sites.)
- Never strand the user. Shim falls back SAPI-direct if Prism finds no backend; if the DLL fails to load entirely, the GML side still writes the speech log file so behavior is diagnosable. A panic action re-initializes the speech stack.
- Never cache game state. Re-query at speak time; the only acceptable cache is a live instance reference whose variables are read on demand. Stale speech is worse than none.
- Activation calls the game's own stored callback (`onPress`, `onClick`, `buttonList[i].onClick`), never a reimplementation of what clicking does, and mirrors the real handler's side effects (UI sounds, state flags) and guards. Likewise the dev driver drives real code paths, never OS synthetic input.
- Surface only what's visible. Mirror the game's own visibility, sort, and filter rules; never invent readouts from state a sighted player can't currently see.
- Reuse the game's own strings (they are already localized); every mod-authored string goes through the game's CSV mechanism (`lang\UIText_<lang>.csv` rows with a `vwa--` key prefix, read through `localizedUIText_get`), never inline literals in feature code. Sole exception: dev-driver and log-file text.
- Never interrupt speech by default. Interrupt only on genuine focus movement so key repeat reads the landing item.
- All user-facing hotkeys are registered actions in the input layer (rebindable later, dumpable via `/state`); no raw `keyboard_check` calls in feature code outside the input layer itself.
- Look it up, don't guess. Game type/function/variable questions get answered from `decompiled\` (or live via the dev driver), never from memory of similar games. Facts recorded in docs are marked verified and dated; anything that bit us gets a "bit us" note so it's never re-litigated.

Engineering discipline:

- GameMaker native calls take and return only doubles and null-terminated strings. Every shim export must fit that shape.
- `show_debug_message` does not reach the `-debugoutput` log. File writes to the save dir (`%AppData%\Roaming\Void_War\`) and the dev driver are the only reliable channels out of GML.
- The original `data.win` is never modified. All patches build into `build\data-test.win`, launched via Steam with `-game`.
- Testable logic stays pure. GML framework logic (compose, path diff, row wiring) lives in scripts free of instance and global references so the in-game test screen plus scripted transcripts can exercise it deterministically; the shim's protocol logic (HTTP parsing, ring buffer, command queue) is separable from the server thread and unit-tested host-side with a tiny clang-built harness, no game needed.
- Zero build warnings, from the C compiler and from UTMT import; never suppressed, always fixed.
- Vendored third-party natives (prism.dll) carry version, license, and ABI notes; re-audit the header on any upgrade. Calling convention and string encoding at the shim boundary are documented in the shim source.
- Comments describe current state, never change history.
- Version control from session 1: git init, commit to main (greenfield), `.gitignore` excludes `decompiled\` (derived, huge), `build\data-test.win`, and logs. The decompile is regenerable via `tools\dump-all.csx`.
- Docs stay current: CLAUDE.md is the agent-facing invariant list and verified-fact store; this build plan's Status lines update every session; README (user-facing, created when there is something to use) must be updated in the same session as any key or feature change.
- Launcher lifecycle discipline (bit Tanglebeep, adopt from day one): run as a background task that blocks until game exit so a crash wakes the agent with the exit code; build failure aborts the launch so a stale build never silently runs; single-instance lock file holding the launcher PID, refusing to start while a live launcher holds it; kill orphaned game processes and wait for both process exit and the port to free before launching; the launcher's cleanup kills the game so cancelling the background task is the one true way to stop a run.

## Session 0: tooling and reconnaissance (DONE)

Decompile pipeline, UTMT CLI workflow, injection proof, launch workflow, game UI architecture investigation, WotR/Tangledeep reference study. Recorded in `game-and-tooling.md`. Key architectural findings driving everything below: the game has no focus concept and no menu keyboard support; `global.menuToggle` names the open menu; widget labels are plain instance variables; ad-hoc screens (main menu) expose label/callback structs; all gameplay key reads flow through `input_check`/`input_check_pressed`/`input_check_released` in `scrKeybinds`.

Status: complete.

## Session 1: speech shim and dev-driver transport

Goal: injected GML speaks through Prism, and the agent's loop exists in skeletal form: launch via script, poll `/health`, round-trip a command, read `/speech`.

Build:
- `src/shim/vw_speech.c`, built with clang to `vw_speech.dll` (x64). Exports, all double/string shaped: `vw_init()`, `vw_speak(text, interrupt)`, `vw_stop()`, `vw_backend_name()`, `vw_poll()`, `vw_reply(text)`, `vw_key_delay()`, `vw_key_rate()`, `vw_shutdown()`. Internally: Prism context/backend ownership (patterns from `wotr-access/src/Speech/PrismNative.cs`, vendored known-good `prism.dll`), the speech ring buffer with monotonic cursor, the loopback HTTP thread, the command queue with blocking waits and pump-timeout messages, and the no-speech gate (capture-only mode) controlled by env var.
- Endpoints live this session: `/health`, `/speech?since=N`, `/cmd` (plumbing only; the interpreter arrives in session 2 - this session it handles `ping` and `say <text>`).
- GML boot patch in `oInitGlobals` Create: `external_define` the DLL, `vw_init`, speak a localized boot announcement, append every spoken line to `vwa-speech.log` in the save dir. GML pump: one `vw_poll`/`vw_reply` round per step in a persistent object's Begin Step (`oInputManager` Step_1).
- `tools/build-mod.csx` v1 (assembles GML source fragments from `src/gml/` into `build/data-test.win`) and `tools/run-game.ps1` with the full lifecycle discipline from the standing constraints (lock, orphan kill, port wait, rebuild, launch, `/health` poll).
- Mod string mechanism: `vwa--` rows added to the lang CSVs in `build\lang\` by build-mod, and a `vwa_t(key)` wrapper over `localizedUIText_get`.
- Project hygiene, per the conventions: git init with `.gitignore` (decompiled, build outputs, logs) and first commits; project `CLAUDE.md` at the repo root in the references' style (verified facts, invariants, build/run/verify commands, pointers to this plan); host-side unit-test harness for the shim's protocol logic (ring buffer, HTTP parse, command queue) built and passing before the shim ever runs inside the game.

Verify (agent): shim host-side tests pass; launcher brings the game up and `/health` answers; `/speech?since=0` shows the boot announcement; `POST /cmd` with `say test` round-trips and appears in `/speech`; a second launcher invocation refuses while the first holds the lock; speech log file matches the ring buffer.
Verify (user): boot announcement audible with `-Speech`; `vw_backend_name` reports the expected backend.

Exit criteria: both verifications pass; `game-and-tooling.md` updated with shim/FFI gotchas.
Risks: Prism x64 behavior inside the GameMaker process; `external_define` calling-convention details; Steam relaunch not inheriting env vars (fall back to a marker file like WotR does).

Status: COMPLETE (2026-07-08). All build items done; 61 host-side protocol checks pass; live game verified: boot announcement (localized, via the CSV mechanism) in `/speech`, `ping`/`say` round-trip through the GML pump, speech log file matches the ring buffer, watchdogged pump, clean logs. The env-var risk materialized as predicted: the shim reads `build\vw_speech.cfg` written by the launcher instead. User verification passed by ear: boot announcement and a test line voiced through Prism (backend `prism:JAWS` on this machine). Launcher lifecycle verified live: lock refusal against a live launcher, stale-lock plus orphan recovery after a hard task cancel (cancelling the background task orphans the game - it is Steam's child; recovery is the next launch or taskkill, see run-game.ps1 header), wake-on-game-exit with clean lock release. Rashad granted standing permission to run the project's PowerShell scripts (recorded in `.claude/settings.json` and CLAUDE.md), so the full loop now runs with no human present. Notes: `vw_key_delay`/`vw_key_rate` exports are in place for session 3.

## Session 2: the dev driver proper - introspection and background running

Goal: the agent can see and touch everything in the live game without a human present. This is the tooling every later session's reverse-engineering depends on; it comes before any accessibility feature because it is how those features get built.

Build:
- Eval-lite interpreter behind `/cmd`, in GML: `get <target>` / `set <target> <value>` for globals and instance variables by name; `dump <target> [depth]` producing JSON via recursive reflection (structs, arrays, instances); `instances <objectName>` enumeration with ids and positions; `call <scriptOrMethod> [args...]` via `asset_get_index`/`script_execute` and stored method variables; `room` and other cheap state queries. Errors return as text, never crash the game (wrap dispatch in try/catch equivalent so a bad command cannot take down the pump).
- `GET /gui/raw`: the game-truth view - live instances of the known UI families (and any object by request) with their label/callback/hover variables, positions, and depth. This is the reverse-engineering dump; the mod's interpreted view arrives in session 4 to diff against it.
- `GET /screenshot` via `screen_save` to the scratch dir, returning the path.
- Background-run attempt: from inside the shim, subclass the game window's WndProc to stop the runner observing focus loss (swallow or rewrite the deactivate messages). Time-boxed investigation; success means the full loop runs unattended, failure means we document the human-focuses-once-per-launch fallback precisely and move on (revisit later; also probe `options.ini` and runner flags while in there).
- `scripts/drive-smoke.ps1`: a scripted end-to-end exercise (launch, dump main menu buttonList, call an onClick, screenshot, read speech) used as the regression check for the driver itself.

Verify (agent): from a cold start with no human touch (or one window focus if background-run failed): dump `oMainMenuControls.buttonList` and get the real labels; `set` a global and `get` it back; `call` a harmless script; `/gui/raw` lists the main menu's collision boxes; screenshot file is valid PNG.
Verify (user): none required this session (this is agent tooling), beyond confirming the game still plays normally with the driver active.

Exit criteria: the smoke script passes; background-run outcome (working, or precisely documented fallback) recorded here and in `game-and-tooling.md`.
Risks: WndProc subclassing may fight the runner's own message handling (crash or input weirdness - test thoroughly before relying on it); `json_stringify` may choke on self-referencing structs (depth-limit the dumper); method-variable invocation semantics on instances.

Status: COMPLETE (2026-07-08). Eval-lite interpreter (`scrVwaDev`, a new dev-only
global script) live: `ping`, `say`, `room`, `get`/`set`/`dump` over a path grammar
(`global.x`, `oObject.var`, numeric ids, `.member` and `[n]` chaining), `instances
<obj>`, `call <script|path> [args]`, `gui.raw [obj]`, `screenshot`, `help`. A
hand-rolled recursive JSON dumper (depth- and node-budget limited so a cyclic or
huge graph cannot wedge the frame) replaces `json_stringify` because it must
summarize methods/instances and because `string(real)` truncates numbers.
`GET /gui/raw` and `GET /screenshot` are shim-side sugar over the same interpreter.
Verified live at the main menu: dumped `oMainMenuControls.buttonList` and got the
real labels (New Game / Achievements / Settings / Exit / Announcements), set+got a
scratch global, called scripts and got typed returns (bool, localized string,
instance id from an onClick), enumerated instances, valid-PNG screenshot, and a
malformed command returned `ERROR:` without killing the pump. `scripts/drive-smoke.ps1`
(18 checks) passes end to end. Host-side protocol checks now 72 (added `vwp_query_str`).
Background-run: the shim subclasses the game window's WndProc (retried from `vw_poll`
each frame until the window exists; the window does not exist yet at `vw_init`) and
swallows deactivate messages; `bgKeepalive` shows in `/health`, `-NoBg` / `bg=0`
disables it. Outcome: the autonomous loop runs unattended TODAY - this whole session
drove the game over HTTP with it backgrounded and the pump never stalled. The
documented freeze is a BOOT freeze (frozen until the window is focused once), which
Steam's `-applaunch` clears by itself; I could not reproduce a steady-state
focus-loss freeze (Windows' foreground lock blocks a programmatic focus-steal - the
same lock that keeps anything from stealing the game's focus during an unattended
run), so whether the subclass is strictly load-bearing is unproven. It installs
cleanly, does no harm, uninstalls on shutdown, and is a cheap safeguard. Details in
`game-and-tooling.md`.

## Session 3: input layer

Goal: the WotR input model running in GML: actions, categories, focus-first shadowing, typematic repeat, and one-chokepoint suppression of game keys. Verified through the dev driver.

Build:
- `scrVwaInput`: action registry (`vwa_action_register(key, label, category, handler)`), bindings as key+modifier structs, `vwa_input_tick()` called from the pump object's Begin Step.
- Categories (enum): Global (always live), UI, Combat, Targeting (reserved), Dev. Live-set resolution walks the active screen stack focused-first once screens exist; this session a stub provides the stack (empty = Global only, plus a forced test screen via dev command).
- Shadowing: identical chords in two live categories resolve to the higher-priority category, per frame.
- Typematic repeat driven by the OS delay/rate via the session-1 shim exports.
- Suppression lever: patch `input_check`, `input_check_pressed`, `input_check_released` in `scrKeybinds` to early-return false while `global.vwaSuppressGameKeys` is true. Respect the game's `global.textFieldInputEnabled` in our own tick (never dispatch while typing). Watchdog: any error in our tick clears the suppression flag, so a mod bug can never leave the game's keyboard dead.
- `POST /input <actionKey>`: fires an action through the same dispatch path as a physical press. `GET /state`: live categories, registered actions, shadowing result.
- Global-category starter actions: repeat-last-spoken, speech-stop, panic shim re-init.

Verify (agent): `/input` fires handlers and results show in `/speech`; `/state` shows correct live sets and shadowing when the test screen flips category order; with suppression on, `get` of game state confirms a gameplay bind's key did not fire.
Verify (user): repeat-last and stop hotkeys by ear; no gameplay key leaks through while suppression is on in a real run.

Exit criteria: shadowing demonstrably resolves an intentionally-conflicting chord; suppression verified in-game; watchdog tested (inject a fault, confirm keys come back).
Risks: keyboard polling nuances (`keyboard_check_direct` vs `keyboard_check`); Begin Step ordering relative to the game's own input reads.

Status: agent verification COMPLETE (2026-07-08); user by-ear verification pending.
`scrVwaInput` (ships in release) carries the registry
(`vwa_action_register(key, labelKey, category, binding, repeats, handler)`),
string categories ("global"/"ui"/"combat"/"targeting"/"dev" - enums avoided,
cross-entry enum visibility is not guaranteed under the UTMT importer), the
screen-stack stub, chord matching with exact modifiers (a modifier that IS
the main key is exempt, so plain Ctrl binds), typematic repeat from the OS
settings via the shim, per-chord shadowing (earliest live category wins,
registration order tie-breaks), and the tick watchdog that clears
`global.vwaSuppressGameKeys` on any error. Suppression is a build-time
`QueueFindReplace` on scrKeybinds' three keyboard `input_check*` guards,
with a post-import decompile assert in build-mod.csx because a no-match
no-ops silently. Starter actions: repeat-last F11, speech-stop Ctrl,
panic-reset Shift+F11 (`vw_reset_speech` shim export). `/state` and
`POST /input` live; `scripts/input-smoke.ps1` (31 checks) covers liveness,
shadowing flip, suppression (one-frame probe: rebind to vk_nokey; simulated
keys never reach keyboard_check - see game-and-tooling), and the watchdog;
drive-smoke still passes. The risk that materialized was neither predicted
one: the runner's key bookkeeping reads "something held" for the first
minute after boot (probe retries outwait it). Typematic repeat is
machinery-verified only; physical-key feel is user verification here and
arrow-repeat gets exercised for real in sessions 4-5. User checks for
Rashad: launch with `-Speech`, F11 repeats the last line, Ctrl stops
speech mid-sentence, Shift+F11 says "Speech reset complete" plus backend.

## Session 4: screens, control graph, announcer

Goal: the framework core: poll-and-diff screen stack, immediate-mode node building, identity-based focus reconciliation, path-diff announcement composition. Verified against a synthetic test screen before any real game screen.

Build:
- `scrVwaScreens`: screen structs (key, layer, is_active function, name function, build function, input categories, exclusive flag), registry, per-frame resolve/diff/lifecycle, focused screen drives the input layer's live categories (replacing session 3's stub).
- `scrVwaGraph`: node structs (id with reference+structural tiers, label function, role, on_activate, on_adjust, tooltip function, position index/count), builder with menu mode (rows, auto-wiring, column preservation) and raw mode (explicit edges), Tab stops with remembered positions, parent stack for labeled contexts.
- `scrVwaAnnounce`: path-diff compose (newly entered levels outermost first, then landing control), part ordering as data per control role, auto "N of M" (localized), live-part re-speak on change while focused.
- Navigator: UI-category actions (arrows, Enter, Tab, Shift+Tab) move the cursor, reconcile after every rebuild, speak once per observed focus change.
- `GET /gui/mod`: the interpreted view - active screen stack, current render's nodes, focused id - now diffable against `/gui/raw` to find what the mod is losing.
- Synthetic test screen (Dev category gated): a fake menu of labeled rows and a two-item row, activated via dev command, exercising every navigator behavior.

Verify (agent): scripted `/input` walks of the test screen produce exactly the expected `/speech` transcript (entering contexts, sibling moves, N of M, no double announcements, Tab stop memory); `/gui/mod` matches.
Verify (user): the test screen sounds right by ear: ordering, no repetition, interrupt behavior on key repeat.

Exit criteria: full scripted transcript matches expectations; framework has zero references to any concrete game screen.
Risks: struct/closure identity semantics in GML for the reference tier of node identity (may need instance ids and explicit keys rather than reference equality).

Status: agent verification COMPLETE (2026-07-08); user by-ear verification pending.
Three new shipped scripts: `scrVwaGraph` (two-tier node identity, menu/raw
builder with column keys, Tab stops with remembered positions and
selected-member landing, parent-stack contexts, down-right total order,
three-tier focus reconciliation), `scrVwaAnnounce` (parts as data, control
types with kind ordering and role words, path-diff compose returning parts
arrays for the chokepoint, localized auto "n of m"), `scrVwaScreens`
(registry, per-frame poll-and-diff stack driven from the input tick before
dispatch, focus sync, navigator actions arrows/Enter/Tab/Shift+Tab in the ui
category, once-per-frame observe that speaks focus changes, live-part watch
speaking just the changed part). Screen structs carry key/layerNum/
isActive/name/build/categories/exclusive; exclusive modals block lower
screens' categories (session 3's stub replaced; vwa_dev_test_screen now goes
through the real registry). `GET /gui/mod` + eval-lite `gui.mod` dump the
interpreted view. `scripts/screens-smoke.ps1` (46 checks) asserts the exact
transcript on the synthetic dev test menu (`vwa_dev_test_menu`): screen
name, context entry outermost-first, sibling moves with "n of m", toggle and
slider live parts speaking only the changed value, row edges silent, Tab
memory both directions, no-action feedback, survivor fallback, tier-1
reference follow across a rename, exclusive blocking, focus restore on
uncover. The predicted identity risk did NOT materialize: GML struct `==` is
reference equality and works as the tier-1 ref (verified live). What did
bite: the bg keepalive swallows the focus-loss messages that clear runner
key state, so a modifier whose release went to another window reads held
forever (a stale Alt broke chord matching for a full smoke run) - fixed with
a per-tick unstick + probe self-heal via keyboard_check_direct, see
game-and-tooling. Interrupt policy (moves interrupt, screen names and live
parts do not) is implemented but only verifiable by ear - part of the user
check: run screens-smoke with `-Speech` and listen for ordering, no
repetition, and key-repeat interrupting cleanly on the test menu.

## Session 5: first real screens: main menu and patch notes

Goal: a blind player can boot Void War, hear the main menu, and reach New Game / Settings / Exit by keyboard.

Build:
- Patch-notes popup (`oGameStartMessage`): a screen that announces it and reads its text on demand, or suppress it entirely (decide in session; suppression is the fallback). Mind the double-spawn quirk.
- Main menu screen: is_active on `instance_exists(oMainMenuControls)`; build reads `buttonList[i].buttonStr` / `.onClick` (reverse-verified live via the dev driver first); activation calls the struct's onClick; conditional entries (Continue, Announcements) handled naturally by rebuilding from live state, with identity keyed on the label key, not the index.
- Screen-name announcements and any needed mod strings localized via the CSV mechanism.
- `run-game.ps1` grows `-WaitMainMenu`: launch, wait until `/gui/mod` shows the main menu screen active.

Verify (agent): scripted boot-to-main-menu run produces the expected transcript; arrows wrap correctly; Enter on Settings opens the settings menu (which will announce only its screen name until session 6).
Verify (user): full boot flow by ear, from launcher to hearing "Main menu, Continue, 1 of 8", navigating, and activating an entry.

Exit criteria: user can reach and activate every main-menu entry without sight; transcript verified.

Status: agent verification COMPLETE (2026-07-08); user by-ear verification pending.
`scrVwaMenus` (ships in release) registers the session's screens: the main
menu (immediate-mode build over the live `buttonList`, identity = entry
struct ref + `localizedLabelName` skey so conditional entries never break
focus; activation mirrors the game's click path - same overlay guards, same
click sound, then the stored onClick; arrows wrap via two explicit edges;
name reuses `global.label_mainMenu`), the announcements popup as a
read-on-demand screen (titles as buttons, Enter speaks the body, exclusive;
suppression not needed; dismissal stays the game's own Escape, and the
double-spawn quirk turned out to be once per PROFILE - saved flag), and
name-only exclusive placeholders for open game menus (settings/language via
the game's own label globals, generic "Menu" via the one new vwa-- row),
all gated on `!global.gameIsLoading` because menuToggle is nonzero
throughout boot loading (bit us: a stray "Menu" in every boot transcript).
`run-game.ps1 -WaitMainMenu` blocks until /gui/mod shows the screen;
`scripts/mainmenu-smoke.ps1` (33 checks) is profile-agnostic (expected
speech derives from /gui/mod) and covers wrap, walk-to-Settings, the
placeholder announce/close-with-focus-restore via the game's stored
closeMenu, popup open/read/dismiss with restore, raw-vs-mod label diff,
and a no-stray-boot-speech assert. The big catch: `script_execute_ext` on
a METHOD executes an unrelated script index instead of the method
(silently!) - the dev driver's `call` now invokes methods directly, and
session 2's "menus created via onClick don't survive" note was corrected
(the onClick had never run). input-smoke and screens-smoke updated for the
main menu keeping ui permanently live at the menu (the "ui dead" flip now
uses an exclusive dev screen). First README.md written (user-facing).
User checks for Rashad: launch with `-Speech`; boot should speak the boot
line, then "Main Menu", then "Continue, button, 1 of N" (or New Game on a
fresh profile); arrows navigate and wrap; Enter on Settings speaks
"Settings", Escape returns and re-announces; Enter on Announcements lists
titles, Enter reads a body, Escape (twice if it respawns once) returns;
Exit quits the game.

## Session 6: generic widget adapter and the settings family

Goal: the payoff of the framework: one generic builder covers every menu made of the standard widget families, proven on the settings, escape, confirmation, and language screens.

Build:
- Generic builder: enumerate live `oButton`, `oButton_menus`, `oMenuElement` instances belonging to the active menu, read `centerText`/`text`/`leftLabel`/`rightLabel`/`tooltipStr`, sort by y then x into rows, wire menu-mode.
- Widget-specific vtables, each reverse-engineered live through the dev driver before coding: checkboxes (`oSettings_checkbox_*`) as toggles with state parts; sliders (volume) with on_adjust; dropdowns (`oMenuElement` dropdown machinery: entries array, selected index) as a child screen pushed on open.
- Screens: settings (`menuToggle` 9), escape menu (8), confirmation dialogue (14, using its Yes/No `oButton_menus` and `onEscape`), language menu (10).
- Tooltip-on-demand action (reads the focused control's `tooltipStr`).

Verify (agent): scripted transcripts for each screen; toggle a checkbox and hear the state part change; adjust a volume slider; open and choose from a dropdown; confirm dialog Yes/No; diff `/gui/mod` against `/gui/raw` on each screen to catch dropped controls.
Verify (user): change a real setting end to end by ear, including a dropdown, and confirm it persisted after relaunch.

Exit criteria: all four screens fully navigable; the raw-vs-mod diff shows nothing missing that a sighted player can reach; generic-builder exceptions documented here.
Risks: dropdown closure state may need per-instance reads the generic pass can't infer; settings checkboxes are not children of `oMenuElement` and need their own enumeration.

Status: agent verification COMPLETE (2026-07-08); user by-ear verification pending.
The generic widget adapter lives in `scrVwaMenus` (`vwa_widgets_emit`: live
enumeration, y-then-x sort, 4px same-row grouping - the game's own alignment
tolerance - vertical wrap; `vwa_widget_add` vtable dispatch over
oSettings_checkbox toggles, oButton_menus buttons, oMenuElement
slider/combo/label, oButton framed buttons). Real screens registered:
settings (menuToggle 9; ownership = the three widget families at
`global.dpthSettingsMenu1` plus oButton_menus by parentID), pause/escape
menu (8, oMenuPause, all oButton_menus), confirmation dialogue (14, layer
50; live message text as a label node, then its buttons), and the dropdown
child screen (`vwa-dropdown`, layer 45: pushed when any oMenuElement flips
toggleDropdown, lands on the current selection via its "selected" part,
Enter commits through the stored select_dropdownEntry then closes, Escape
closes just the list). Escape handling is a new opt-in per-screen `onBack`:
the ui action nav-back consumes the press (`vwa_input_consume_escape`,
keyboard_clear in Begin Step before the game's Draw reads it) ONLY when a
screen claims it; everywhere else the game's own Escape behavior is
untouched. Second new ui action: nav-tooltip (F9) reads the focused
control's tooltipStr. New control type "combo".
Generic-builder exceptions, as predicted: (1) volume sliders have no
pointer-free game handler - `vwa_widget_slider_adjust` mirrors the mouse
wheel path's exact effect (0.05 step, clamp, music/master_volume_update)
per slider object; a new game slider means extending that dispatch. (2) The
language dropdown's per-entry beta hover tooltip is not surfaced; the same
warning arrives in the confirmation dialogue before a beta language
commits, so nothing is lost.
Deliberate divergence: the game's mouse flow leaves a dropdown list open
after clicking an entry; the keyboard flow closes on commit (combo-box
convention; closing is exactly what clicking the dropdown button again
does). Finding: the standalone language menu (menuToggle 10, oMenuLanguage)
is DEAD CODE in 1.4.0c - nothing instantiates it; the settings language
dropdown replaced it. It is still registered through the generic builder
(one call) in case the game revives it.
The catch this session (bit us): an onClick that destroys its own button
(Cancel destroys the dialogue, whose cleanup kills its buttons) crashes any
post-onClick read through the dead id from mod method scope - the game's
own Step survives only because a dying instance's running event keeps its
scope. Every activation mirror now reads the press-sound id before invoking
the callback; without the fix every keyboard Cancel tripped the input
watchdog. `vwa_dev_spawn <objName>` (dev-only) spawns screens otherwise
unreachable without a run - oMenuPause verified safe at the main menu
(pause_game no-ops with no run live; Resume reverts cleanly).
`scripts/settings-smoke.ps1` (70 checks) covers the whole session including
the raw-vs-mod widget diff and now asserts /input replies are not ERROR
(the dead-id crash initially hid behind an ignored reply). All five smokes
pass from a cold boot (194 checks total).
User checks for Rashad (launch with `-Speech`): open Settings from the main
menu and arrow through all 16 controls; the three window checkboxes read as
a row ("1 of 3" etc.) with left/right; Enter on Show Version Info speaks
just "checked"/"not checked"; left/right on Music Volume speaks the new
number; Enter on Window Size opens the list landing on the current entry
with "selected", Enter commits, and - the one thing scripts cannot press -
a PHYSICAL Escape with the list open must close just the list and leave
settings open (the consume path runs before the game's own Escape handler;
verified by machinery, needs the real key once); Enter on Language then a
beta language speaks the Confirmation dialogue, Cancel backs out; F9 on
Fullscreen reads its tooltip; Back returns to the main menu with focus on
Settings.

## Session 7: code review and hardening

Goal: an outside-eyes pass over everything built so far, then fixes.

Work:
- Run the code review skill (`/code-review`) at high effort over the shim C code, the build/launch scripts, and all injected GML (the GML lives as source fragments in `src/gml/`, assembled by build-mod, so it is reviewable like any code).
- Triage findings: fix confirmed correctness issues; log deliberate rejections with reasons here.
- Re-run all scripted verification transcripts from sessions 2 through 6 after fixes (they are scripts; rerunning is cheap).
- Specific review attention: shim thread-safety (ring buffer, command queue, WndProc subclass if present), GML struct lifetime across room changes, suppression-flag watchdog, eval-lite dispatch robustness (a malformed command must never crash the pump).
- Convention sweep alongside the functional review: grep every `vwa_speak` call site for pre-joined strings and unlocalized literals; grep feature code for raw `keyboard_check` and direct shim calls; confirm every guarded failure path logs; confirm zero build warnings.

Exit criteria: review findings addressed or explicitly rejected with rationale; all transcripts still pass; user smoke-tests the main menu and settings by ear.

Status: agent verification COMPLETE (2026-07-08); user by-ear smoke of the
main menu and settings pending.
The review ran as a 30-agent workflow (four finder angles plus an independent
verifier per finding, over the full committed tree): 26 verified candidates,
10 reported as the top findings. All 10 were fixed the same session:
(1) chord edge state was keyed by the full chord id, so releasing a fired
chord's modifier while the main key stayed held minted a fresh edge -
Shift+Tab with Shift released first fired nav-next straight back; state is
now keyed by the main vk and remembers which action fired (a different action
on a held key waits for a fresh press).
(2) text-field mode killed ALL hotkeys including speech-stop and the panic
reset; actions now carry `textSafe` (set on the three global speech controls,
whose chords cannot type) and dispatch plus /input filter on it while
`global.textFieldInputEnabled`.
(3) the stale-key unstick covered only modifiers; a non-modifier key whose
release went to another window under the bg keepalive repeated forever -
`vwa_input_unstick_keys` (renamed) now also clears a runner-held
`keyboard_key` that `keyboard_check_direct` denies.
(4) announcement node keys were the bare title, so a duplicate title in game
data would quarantine the whole popup via the graph's duplicate-key throw;
the list index is now part of the key.
(5) the shim's bg keepalive defaulted ON with no cfg, so any non-launcher
launch (a shipped install) would run real-time combat unheard in the
background; now opt-in (`g_bg_on` defaults 0, run-game.ps1 writes `bg=1`).
(6) the dev server had no send timeout, so one client that stopped draining
wedged every endpoint including /health until restart; SO_SNDTIMEO added.
(7) the suppression probe restored the zeroed game keybind and the
suppression flag only on the straight-line path; a throw mid-probe would have
left the game keyboard dead - restore now also runs on the throw path
(restore-and-rethrow; try/finally is unverified under the UTMT importer).
(8) dump's caller-supplied depth is clamped to 0..16: a huge depth over a
cyclic instance graph overflowed the GML VM stack, a hard process crash the
pump's catch cannot see.
(9) `vw_shutdown` was dead code in real runs; `vwa_shim_shutdown` is now
appended to oGlobal's Game End event (runs on quit and window close), so the
WndProc restore and server-thread stop actually execute - verified live in
the shim and mod logs on a real quit.
(10) `vw_key_delay`/`vw_key_rate` silently swallowed SystemParametersInfoW
failure; both log before falling back.
Rejected or deferred, with reasons (all review-verified, none correctness):
shim tier-selection block duplicated between vw_init and vw_reset_speech,
/cmd body copied three times, /speech serializing the ring under g_lock, the
instance-summary JSON header built in three dev-only places, build-mod's
script list repeated in its asserts - all cosmetic or dev-only cost, explicit
code preferred; the five smoke scripts' duplicated helper blocks - they are
the regression net itself, consolidation churn right after a hardening pass
is the wrong trade, revisit alongside session 8; double rerender on the
adjust-to-move fallthrough and the dropdown screen's triple instance scan -
menus are tiny, no measurable cost; edge transition labels as dead plumbing -
reserved for future announcer wording; vertical wrap wired twice - the main
menu's ad-hoc buttonList cannot use the widget adapter; io_clear wiping all
key state on unstick - documented trade-off, fires only on a detected runner
lie and logs; the widgets_emit empty-row case - theoretical, every present
family has a vtable and a new one surfaces in the raw-vs-mod diff; the
WndProc install "race" - the install runs on the window's owning thread
(ownerTid==myTid in the log), so the new proc cannot run before
g_orig_wndproc is assigned; the input layer's direct keyDelay/keyRate shim
reads - sanctioned by this plan's session 3, CLAUDE.md's invariant now names
the sanctioned non-speech shim calls explicitly.
Convention sweep: clean. Every vwa_speak call site passes a parts array of
localized or game-live strings (dev text exempt); raw keyboard_check only in
scrVwaInput plus dev key-state diagnostics; every catch logs or is a
sanctioned watchdog; zero build warnings; 72 host-side protocol checks.
All five smokes re-run green after the fixes (198 checks: drive 19, input 31,
screens 45, mainmenu 33, settings 70), and the Game End teardown was
additionally observed live on a real quit.
User checks for Rashad (launch with `-Speech`): the session 5 and 6 by-ear
lists still stand, plus two new behaviors from this session's fixes: the
speech keys (Ctrl, F11, Shift+F11) keep working while a game text field is
focused, and Shift+Tab must move exactly one control group backward even when
Shift is released a beat before Tab.
Session-7 addendum (same day, from Rashad's first by-ear pass): landing on
the settings window-mode trio spoke a bare "1 of 3" - the in-row position -
while the trio was invisible in the vertical count, blurring the two
numbering axes. Fix, per Rashad's design: a multi-item row IS a group. The
graph synthesizes a non-focusable context per multi row (vwa_gb_synth_groups;
start_row grew a groupLabel arg) that counts as ONE entry in the vertical
"n of m" (stamping is now per ROW), so arriving announces the group -
its label, or the localized generic word (vwa--group-radio, "Radio group")
via the new hooks.groupText when unnamed - plus its vertical position, then
the landing member with its in-row "x of k". Moves within the row stay
group-silent (path diff). Settings now reads 14 vertical entries with the
trio as entry 2; the confirmation dialogue's Confirm/Cancel row groups the
same way. Members keep the checkbox role (game truth: they are independent
toggles whose "off" falls back to borderless, not real radios - the game
draws no group header, so the group word is mod-authored, the same
verbalized-visible-structure class as "n of m"). The dev test menu's
OK/Cancel row carries an explicit label ("Actions") so both label paths are
smoke-covered. All five smokes re-run green (198 checks; screens- and
settings-smoke expectations updated). By-ear recheck for Rashad: down-arrow
through settings hears "Radio group, 2 of 14, Fullscreen, checkbox, ...,
1 of 3" at the trio, left/right move within it, and the vertical counts now
include it.

## Session 8: parity audit against the references

Goal: systematic comparison of this mod against the reference architectures, producing a gap list and fixes, so the foundation is trustworthy before expanding coverage to the rest of the game.

Work:
- Walk `wotr-access/.claude/commands/audit.md` (the reference's own architectural invariant checklist) and evaluate each invariant against this codebase: chokepoint discipline, live resolution, one-announce diffing, localization coverage (grep every `vwa_speak` call site for unlocalized literals), activation contracts, interrupt policy, never-strand fallbacks.
- Compare subsystem by subsystem against the reference implementations: speech chain vs `wotr-access/src/Speech/`, input vs `src/Input/` plus the category model, screens vs `src/Screens/ScreenManager.cs`, graph/announcer vs `src/UI/Graph/`, dev driver vs Tangledeep's `Tanglebeep/Dev/` and CLAUDE.md contract (endpoint by endpoint, plus the threading model and launcher discipline) and WotR's `src/Dev/`.
- Write the result into `docs/parity-audit.md`: per subsystem, what we match, what we deliberately diverge on (with the GML/GameMaker reason), what is missing and whether it matters yet (per-part user announcement settings, type-ahead search, and the `/loadsave` equivalent are post-foundation features, not gaps).
- Fix anything found that violates a standing constraint; fold new lessons into this doc and `game-and-tooling.md`.
- Turn the outcome into a recurring check: write our own `.claude/commands/audit.md` in the WotR style, encoding this project's invariants (the standing conventions above plus whatever the parity audit sharpened) as the periodic architectural-health command for all future sessions.

Exit criteria: `parity-audit.md` exists and every divergence is either fixed or documented as deliberate; our audit command exists; the next-phase backlog (in-run screens, combat, encounters, scanner equivalent, background-run if still unsolved) is drafted at the bottom of that doc.

Status: agent verification COMPLETE (2026-07-08); user by-ear verification pending.
Ran as seven parallel review passes (five subsystem comparisons, the WotR
invariant-checklist walk, and a UI-infrastructure inventory for the
completeness backlog Rashad asked for), triggered by his report of missing
Home/End and tooltip gaps. `docs/parity-audit.md` holds the full result;
`.claude/commands/audit.md` now encodes the invariants as the recurring
architectural-health command. Eight unintended divergences found, all fixed
same session: (1) Home/End jump to the focused stop's first/last control
(`vwa_graph_move_ends`); (2) Tab/Shift+Tab now repeat while held (reference
marks both Repeating); (3) actions carry a bindings ARRAY (register accepts
struct or array; dispatch and /state iterate) - the substrate rebinding UI
needs; (4) synchronous value feedback (`vwa_nav_state_feedback`, WotR
StateText): adjust/activate speaks the changed live part immediately WITH
interrupt and rebaselines the watch - previously a held slider key read
queued stale values one frame behind; guarded by the screen's own isActive
so an activation that closes its screen (Cancel/Back) never rebuilds a dead
graph; the CLAUDE.md interrupt invariant was widened to name this case;
(5) dropdown entries got the new "option" control type and role word;
(6) enabled/disabled and dropdown-selected state parts are LIVE now;
(7) the live-part watch rebaselines silently when the part COUNT changes
instead of index-comparing across shapes; (8) the generic group word is the
neutral "group" (vwa--group-generic, was "Radio group" - it also labels
button rows like Confirm/Cancel; Rashad can veto the wording). Plus F10
read-current-control (WotR AnnounceCurrent as a user key, fresh composition
vs F11's verbatim replay). Tooltip mystery resolved: F9 works on all 16
settings controls; the settings buttons have NO tooltip in game truth
(oButton_menus has no tooltipStr at all), so "No tooltip" is correct - the
felt gap is the key divergence (WotR Space/F1 vs our F9, deliberate: the
game binds both). Verified non-gaps recorded in parity-audit.md (numpad
Enter = vk_enter; no rich-text markup in game strings; WotR's help system
is unwired on its side too). Deliberate divergences documented (Tab wrap,
"No action" feedback, dropdown-as-screen, single-command-in-flight 429,
string categories, textSafe survivors). The invariant walk found the
sanctioned swallow-and-log list understated - CLAUDE.md now names all five
spots - and a version label in a shipped log line (fixed). Dev test-action
chord pair moved F10 -> F8 (nav-read-current owns F10; input-smoke
updated). All five smokes green post-fix (198 checks). By-ear for Rashad
(launch with `-Speech`, in settings): Home/End jump to Window Size / Back;
F10 re-reads the focused control in full; holding Tab cycles groups
repeatedly; holding right on Music Volume reads values AT the slider's
position (no lag/queue); the window-mode trio now says "group" instead of
"Radio group"; dropdown entries say "option" before "selected".
Session-8 addendum (same day, Rashad's binding review): F9, F10, and F11
removed. Tooltips became an inline announcement part on every widget
carrying a game tooltipStr (verified flat - no layered tooltips anywhere
in the game, unlike WotR's Pathfinder; see game-and-tooling), replacing
tooltip-on-demand outright; the graph's onTooltip plumbing, repeat-last
with its last-spoken tracking, and read-current went with them, plus
their five lang rows in all four languages. Global keys are now just
Ctrl (stop speech) and Shift+F11 (panic); UI is arrows, Enter,
Tab/Shift+Tab, Home/End, Escape. input-smoke and settings-smoke updated
(inline-tooltip assertions replace the F9 checks); all five smokes green
(196 checks). By-ear recheck: settings controls now read their tooltip
after their state (e.g. "Fullscreen, toggle, not checked, Toggles
fullscreen mode ON/OFF., 1 of 3").

## After the foundation

Not planned in detail yet, deliberately: in-run menus (crew, cargo, shop, upgrade, armament, maps), the ship/combat screen (sonification-grade feedback, the hardest design problem), text encounters (the `oEncounter` family), meta screens (ship/commander select, archives), the `/loadsave` equivalent (jump into a run in one call), and background-run if the session 2 attempt failed. These get planned in `parity-audit.md`'s backlog once the foundation is proven.

One lead to carry forward from the references: Tanglebeep's biggest early gameplay win was piping the game's centralized event log to speech. Void War has a persistent `oShipLog` global object; investigate it early in the in-run phase as the likely analog.
