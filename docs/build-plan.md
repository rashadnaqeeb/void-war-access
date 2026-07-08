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

Status: agent verification complete (2026-07-08). All build items done; 61 host-side protocol checks pass; live game verified: boot announcement (localized, via the CSV mechanism) in `/speech`, `ping`/`say` round-trip through the GML pump, speech log file matches the ring buffer, watchdogged pump, clean logs. The env-var risk materialized as predicted: the shim reads `build\vw_speech.cfg` written by the launcher instead. Outstanding for session close: user verification by ear (`run-game.ps1 -Speech`: boot announcement audible, `vw_backend_name` sensible) and the double-launcher lock refusal check (the agent's environment denies running PowerShell, so the launcher script itself runs only by the user's hand; its logic mirrors Tanglebeep's proven pattern). Notes: no separate `tools/build-mod.csx` marker-file mechanism was needed; `vw_key_delay`/`vw_key_rate` exports are in place for session 3.

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

Status: not started.

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

Status: not started.

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

Status: not started.

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

Status: not started.

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

Status: not started.

## Session 7: code review and hardening

Goal: an outside-eyes pass over everything built so far, then fixes.

Work:
- Run the code review skill (`/code-review`) at high effort over the shim C code, the build/launch scripts, and all injected GML (the GML lives as source fragments in `src/gml/`, assembled by build-mod, so it is reviewable like any code).
- Triage findings: fix confirmed correctness issues; log deliberate rejections with reasons here.
- Re-run all scripted verification transcripts from sessions 2 through 6 after fixes (they are scripts; rerunning is cheap).
- Specific review attention: shim thread-safety (ring buffer, command queue, WndProc subclass if present), GML struct lifetime across room changes, suppression-flag watchdog, eval-lite dispatch robustness (a malformed command must never crash the pump).
- Convention sweep alongside the functional review: grep every `vwa_speak` call site for pre-joined strings and unlocalized literals; grep feature code for raw `keyboard_check` and direct shim calls; confirm every guarded failure path logs; confirm zero build warnings.

Exit criteria: review findings addressed or explicitly rejected with rationale; all transcripts still pass; user smoke-tests the main menu and settings by ear.

Status: not started.

## Session 8: parity audit against the references

Goal: systematic comparison of this mod against the reference architectures, producing a gap list and fixes, so the foundation is trustworthy before expanding coverage to the rest of the game.

Work:
- Walk `wotr-access/.claude/commands/audit.md` (the reference's own architectural invariant checklist) and evaluate each invariant against this codebase: chokepoint discipline, live resolution, one-announce diffing, localization coverage (grep every `vwa_speak` call site for unlocalized literals), activation contracts, interrupt policy, never-strand fallbacks.
- Compare subsystem by subsystem against the reference implementations: speech chain vs `wotr-access/src/Speech/`, input vs `src/Input/` plus the category model, screens vs `src/Screens/ScreenManager.cs`, graph/announcer vs `src/UI/Graph/`, dev driver vs Tangledeep's `Tanglebeep/Dev/` and CLAUDE.md contract (endpoint by endpoint, plus the threading model and launcher discipline) and WotR's `src/Dev/`.
- Write the result into `docs/parity-audit.md`: per subsystem, what we match, what we deliberately diverge on (with the GML/GameMaker reason), what is missing and whether it matters yet (per-part user announcement settings, type-ahead search, and the `/loadsave` equivalent are post-foundation features, not gaps).
- Fix anything found that violates a standing constraint; fold new lessons into this doc and `game-and-tooling.md`.
- Turn the outcome into a recurring check: write our own `.claude/commands/audit.md` in the WotR style, encoding this project's invariants (the standing conventions above plus whatever the parity audit sharpened) as the periodic architectural-health command for all future sessions.

Exit criteria: `parity-audit.md` exists and every divergence is either fixed or documented as deliberate; our audit command exists; the next-phase backlog (in-run screens, combat, encounters, scanner equivalent, background-run if still unsolved) is drafted at the bottom of that doc.

Status: not started.

## After the foundation

Not planned in detail yet, deliberately: in-run menus (crew, cargo, shop, upgrade, armament, maps), the ship/combat screen (sonification-grade feedback, the hardest design problem), text encounters (the `oEncounter` family), meta screens (ship/commander select, archives), the `/loadsave` equivalent (jump into a run in one call), and background-run if the session 2 attempt failed. These get planned in `parity-audit.md`'s backlog once the foundation is proven.

One lead to carry forward from the references: Tanglebeep's biggest early gameplay win was piping the game's centralized event log to speech. Void War has a persistent `oShipLog` global object; investigate it early in the in-run phase as the likely analog.
