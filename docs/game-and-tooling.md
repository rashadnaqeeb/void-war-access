# Void War: Game Facts and Modding Toolchain

Reference for the Void War accessibility mod (screen-reader support for blind players). Everything here was verified directly against the game and toolchain unless marked otherwise. Sibling projects and primary pattern sources: `../factorio-access` and `../wotr-access`, both mature accessibility mods with extensive agent-directed documentation.

## The game

- Void War, Steam app id 2853590, installed at `C:\Program Files (x86)\Steam\steamapps\common\Void War`.
- Version at time of writing: 1.4.0c (June 24, 2026). Version history is embedded in `announcements_init()` in `scrAnnouncementsText`.
- Engine: GameMaker Studio 2023.8 (runner reports v2023.8(2)[r152]), VM bytecode (bytecode 17), NOT YYC. `data.win` is 326 MB and fully decompilable.
- 64-bit process. Speech integration must therefore use Prism, not Tolk (Tolk is only suitable for 32-bit processes).
- Genre: FTL-like. Real-time-with-pause tactical ship combat plus menu-driven management and text encounters. Mixed tempo: combat needs sonification-grade feedback, menus need navigation-and-speech.
- Game folder contents: `Void War.exe` (the GameMaker runner), `data.win` (all game assets and code), `lang\` (external localization files), `options.ini`, `bl` (credits/backer list), `Steamworks_x64.dll`, `steam_api64.dll`.

### Localization system

- Game text is externalized in `lang\` as CSV files (`key,text`): `UIText_<lang>`, `encounterText_<lang>`, `functionText_<lang>` for en, de, es, fr.
- Keys are derived from object names, e.g. `oWPPhotonCannon1--name`, `oItemTeleportRoomRandomTarget--description`. Lookup functions in `scrLocalization`: `localizedUIText_get`, `localizedFunctionText_get`, `localizedEncounterText_get`.
- This means mod speech can route through the game's own localized strings, and mod-authored strings could ship as additional CSV rows following the same mechanism.
- `oInitGlobals` respects `global.disableLocalization` and calls `language_set(global.currLanguage)` at boot.

### Code structure (from the decompile)

- Counts: 17,754 code entries (11,060 top-level after filtering child entries), 7,005 scripts, 5,708 objects, 281 rooms, 7,428 sprites, 155 sounds, 58 fonts, 16 shaders, 1 extension (Steamworks).
- Naming is clean and descriptive: global scripts are `scrThing` (e.g. `scrLocalization`, `scrTooltipFunctions`, `scrMenu`, `scrDrawNode`, `scrCrewAI`, `scrSaveGame`), objects are `oThing`.
- Deep parent hierarchies: 3,270 objects parent to `oEncounter`; other big families are `oKeyword`, `oCrew`, `oWeapon`, `oHull`, `oModule`, `oItem*`, `oAbility*`. UI families: `oButton`, `obj_gm_button`, `oMenuElement`, `oTxtPlaceholder`. GameMaker events inherit, so patching a parent object's event covers all children - the analog of WotR Access patching a base ViewModel class.
- Boot sequence: first room `rmPreload` contains only `oInitGlobals`, whose Create event initializes all globals, keybinds (`keybinds_init_default`), settings, meta progression, achievements, localization, and calls `scrCreateGlobalObjs()` before `room_goto_next()`. Then `rmLoading` (`oAssetLoader`), then `rmMainMenu`.
- Persistent global objects created at boot (in `objList_global()`): `oGameData`, `oShipLog`, `oMusicMgr`, `oSoundMgr`, `oPlayerInfo`, `oUICursor`, `oUISpriteMgr`, `oSpaceGen`, `oShipMover`, `oScreenShaker`, `oCrewAIManager`, `oCrewDraw`, `oSpaceDustParticles`, `oInputManager`, `oAutoTester`.
- The game has a debug wrapper family `sdm()` through `sdm5()` in `scrMiscScripts`; only `sdm5` actually prints, the rest are empty stubs. `global.enableDevMode` gates `sdmTog`.
- Save data lives in `%AppData%\Roaming\Void_War\` (`profile.sav`, autosaves, `score.sav`). GML relative file paths resolve here.

### The patch notes screen

- `oGameStartMessage` shows patch notes at boot, created from `oGlobal`'s Create event in `rmMainMenu`. It is mouse-first and completely inaccessible; it blocked a blind player from ever reaching the main menu.
- Dismissal: any left click or Escape. Quirk: dismissing the first instance spawns one more instance (gated by `global.gameStartPopupSpawned`), so Escape must be pressed twice. Arrow keys and mouse wheel scroll it.
- Good early mod target: read it aloud, or suppress it.

## Decompiled reference

- Location: `decompiled\` in this project. Produced by `tools\dump-all.csx`, rerunnable after game updates.
- `decompiled\code\` - 11,060 .gml files, one per top-level code entry, zero decompiler failures. Naming: `gml_Object_<name>_<Event>_<subtype>.gml`, `gml_GlobalScript_<name>.gml`.
- `decompiled\objects.txt` - every object with parent, sprite, and event list (tab-separated).
- `decompiled\rooms.txt` - rooms with layers and instance counts.
- `decompiled\strings.txt` - all 62,766 strings.
- `decompiled\extensions.txt` - the Steamworks extension's full function table. This is the template for how GameMaker declares native-DLL functions: every function takes and returns only Double or String.
- `decompiled\info.txt` - engine version and asset counts.
- UTMT event-name suffixes: `Step_0` is Step, `Step_1` is Begin Step, `Step_2` is End Step, `Draw_64` is Draw GUI, `Draw_0` is Draw.

## Toolchain

### UndertaleModTool CLI

- `tools\utmt-cli\UndertaleModCli.exe`, release 0.9.1.1, runs on the installed .NET 8. Loads and saves this data.win without issues.
- Key commands: `info <data.win>`, `dump <data.win>`, `load <data.win> -s <script.csx> -o <output.win>`.
- Scripts are C# (.csx) against UndertaleModLib. Gotchas hit in practice: the old `ImportGMLString` helper does not exist in 0.9.x CLI scripts - use `UndertaleModLib.Compiler.CodeImportGroup` with `QueueReplace`/`QueueAppend` then `Import()`. The extension function property is `ExtName`, not `ExternalName`. `Data.ToolInfo` has no `Version`.
- Full rebuild of the 326 MB data.win takes on the order of a minute. `CodeImportGroup.QueueAppend` on a decompiled event compiles cleanly.

### Build and launch workflow

- `build\` holds the patched `data-test.win` plus mirrored support files. The GameMaker runner sets its working directory to the data file's directory, so the build folder must contain copies of `options.ini` and `lang\` (already copied there).
- Launch: `"C:\Program Files (x86)\Steam\steam.exe" -applaunch 2853590 -game <path-to-patched.win> -debugoutput <log path>`. Launching `Void War.exe` directly does not work: the Steamworks extension runs `RestartAppIfNecessary`, refuses to continue, and deletes any `steam_appid.txt` placed next to the exe. Launching through Steam passes the check and forwards the extra arguments.
- The original `data.win` is never modified; the mod loads via `-game`.
- Achievements: unknown whether the `-game` flag affects them; Steam integration initializes normally and stats load.

### Runtime observations that shape the dev loop

- The game pauses completely when its window loses focus, including during boot. A game launched from a terminal sits frozen before running any game code until the window is focused once. Windows prevents background processes from forcing focus, so during development a human needs to focus the window (or we eventually patch the focus-pause out).
- `show_debug_message` output does NOT appear in the `-debugoutput` log. That log only carries runner internals (chunk loading, swap chain, pause events). Verified: a session that demonstrably executed GML produced no GML print lines in the log.
- Therefore the reliable side channel from injected GML is file writes. Relative paths land in `%AppData%\Roaming\Void_War\`. Verified end to end: an appended write in `oInitGlobals` Create produced the marker file about 30 seconds after launch.
- This file channel is the planned equivalent of WotR Access's dev server `/speech` endpoint: the mod will append every spoken line to a log file so an agent can verify speech output without hearing TTS.

### Injection is proven

The full pipeline was verified this session: decompile, edit GML (`CodeImportGroup.QueueAppend` on `gml_Object_oInitGlobals_Create_0`), recompile with UTMT CLI, launch through Steam with `-game`, injected code executed and wrote its marker file.

## Speech output plan

- Screen reader bridge: Prism (github.com/ethindp/prism), a native C library abstracting NVDA, JAWS, SAPI, and other backends. A known-good x64 `prism.dll` (about 1 MB) is vendored in `..\wotr-access\vendor\prism.dll`, with working usage patterns in `..\wotr-access\src\Speech\PrismNative.cs` and `PrismHandler.cs`.
- Prism's API is context-and-pointer based: `prism_init` returns a context pointer, `prism_registry_create_best` returns a backend pointer, `prism_backend_speak(backend, utf8_text, interrupt_bool)` speaks. Errors are an int enum; feature flags are a u64 bitmask.
- GameMaker's native-call mechanism (`external_define`/`external_call`, and the extension table in data.win) supports ONLY doubles and null-terminated strings as arguments and return values. Prism's pointer-based API does not fit directly.
- Plan: a small C shim DLL (working name `vw_speech.dll`) built with clang (installed at `C:\Program Files\LLVM\bin\clang.exe`; Visual Studio 18 is also present). The shim owns the Prism context and backend internally and exports GameMaker-shaped functions, e.g. `double vw_init()`, `double vw_speak(char* text, double interrupt)`, `double vw_stop()`, `char* vw_backend_name()`. Injected GML loads it with `external_define` at boot.
- The Steamworks extension in `decompiled\extensions.txt` documents the exact function-declaration shape GameMaker uses for native calls (Kind 11, Double/String signatures).

## Session 1 findings: shim and dev driver (verified 2026-07-08)

The speech shim and dev-driver transport are built and verified end to end in the live game (boot announcement in `/speech`, `ping`/`say` round-trips through the GML pump, speech log file matches the ring buffer). Facts learned:

- Prism is vendored at `vendor/prism/` as v0.16.6 from the Tangledeep mod's copy (DLL + header + license, a matched pair proven with NVDA on this machine). The WotR `vendor/prism.dll` is a different build; the `PrismError` enum ordering in the v0.16.6 header differs from WotR's C# binding, so always code against the vendored header. ABI notes in `vendor/prism/README.md`.
- clang on MSVC targets: ISO C functions (`fopen`, `strncpy`) trip `-Wdeprecated-declarations` under `-Werror`; the standard fix is `-D_CRT_SECURE_NO_WARNINGS` (a documented MSVC define, not warning suppression).
- `CodeImportGroup.QueueReplace` on a nonexistent `gml_GlobalScript_*` name CREATES the script asset, and its functions are registered and callable at runtime (verified: `vwa_shim_init`/`vwa_speak` defined in the new script ran from `oInitGlobals` Create).
- The game's lang CSVs have NO trailing newline; blindly appending rows glues them onto the last line (bit us; `build-mod.ps1` guards it). The files are extensionless UTF-8 CSVs with a `key,text` header, CRLF endings.
- `localizedUIText_get` returns `undefined` (not a placeholder string) on a missing key; `vwa_t` logs and falls back to the key itself.
- Merged `vwa--` rows load through the game's own CSV mechanism: the boot announcement came out of `vwa_t("vwa--boot")` localized.
- `external_define` works with the DLL's absolute path derived from the `-game` command-line argument (`parameter_string` loop); handles stored in a `global.vwaShim` struct and invoked via `external_call` work fine.
- Steam does NOT forward the launching shell's env vars to the game. The shim reads `build\vw_speech.cfg` (written by the launcher) and lets env vars override when present.
- Focus-pause update: in this session's launch (Steam `-applaunch` while no other window stole focus), the game reached GML and answered `/health` about 2 seconds after the process appeared, with zero human interaction - Steam appears to give the game window focus itself. The freeze-until-focused behavior remains real (observed in session 0) but a normal Steam launch may not need a human. Keep the "focus the window if /health stalls" hint.
- Prism's create_best selects JAWS on this machine (`prism:JAWS`); voiced output confirmed by ear by Rashad (2026-07-08).
- Shim exports and tier codes: `vw_init` returns 2 prism / 1 sapi / 0 capture-only. Speech gate off means Prism/SAPI are never initialized at all (unattended runs touch no screen reader). `/health` reports `backend`, `speechOn`, `spoken` count, and `pumpAgeMs` (ms since the last `vw_poll`; -1 = GML never pumped, i.e. game frozen or patch failed).

## Session 2 findings: dev driver and background-run (verified 2026-07-08)

The eval-lite interpreter, `/gui/raw`, `/screenshot`, and the WndProc
background-run keepalive are built and verified live at the main menu. Facts
learned:

- `var depth` (and any `var <builtin>`) is a hard compile error in the UTMT
  0.9.x importer ("Declaring local variable over builtin 'depth'"). GML
  builtins like `depth`, `x`, `y`, `visible` cannot be shadowed by a local.
  Bit us; renamed to `dumpDepth`. Watch for this in every new script.
- `json_stringify` is not usable for the dev dump: it cannot represent methods
  or live instances, and it has no depth/cycle guard. We hand-roll a recursive
  dumper (`vwa_dump_json`) that summarizes methods as `"<method>"`, instances as
  `{__object,__id,x,y,depth,visible,...}`, and caps recursion by depth plus a
  global node budget (`global.vwaDumpBudget`) so a cyclic or huge graph cannot
  wedge the frame. `string(<real>)` truncates to 2 decimals, so numbers get their
  own formatter (`vwa_json_num`).
- Reflection primitives that work as documented in this build: `variable_global_get/set`,
  `variable_instance_get/set`, `variable_instance_get_names`, `variable_struct_get_names`,
  `instance_find`/`instance_number`, `asset_get_index`/`asset_get_type`,
  `object_get_name`, `script_execute_ext(fn, argArray)`. `typeof(v) == "ref"`
  identifies an instance reference; instance ids read back as reals >= 100000
  (main menu controls instance was id 100005).
- Reading a built-in instance var (`x`, `sprite_index`) via `variable_instance_get`
  works, but `variable_instance_exists` returns false for built-ins - so the path
  resolver probes the value and only errors when it is `undefined` AND the name
  doesn't exist.
- `instance_create_depth` returns the new id immediately and runs Create
  synchronously. CORRECTED in session 5: the session-2 observation that "a menu
  created by calling its button's onClick out of the normal flow does not survive
  to the next frame" was WRONG - the onClick never ran at all. `script_execute_ext`
  on a METHOD value does not call the method: it silently coerces it to a number
  and executes an unrelated script index (the incrementing 2257/2258 "ids" were
  that script allocating ds handles). The dev driver's `call` now invokes bound
  methods directly (`fn(args...)`, arity-capped); menus opened or closed through
  stored callbacks behave exactly as in normal flow and survive fine.
- The main menu at boot: `global.menuToggle == 0`, room `rmMainMenu`,
  `oMainMenuControls` buttonList = New Game, Achievements, Settings, Exit,
  Announcements (Continue/Tutorial/Archives/Credits are conditional on save and
  progress state, absent on a fresh profile). `oButton` children present are
  `oUIStationsSave`, `oUIStationsReturn`, `oSocialButton` x2; the button collision
  boxes are `o1x1Pixel` instances parented to `oMainMenuControls`.
- Screenshots: `screen_save(relativeName)` writes a valid PNG to the save dir;
  `game_save_id` is that dir's absolute path (used to return the full path).
- WndProc background-run: `SetWindowLongPtrW(GWLP_WNDPROC)` on the game window
  succeeds from the game's main thread (which owns the window). The window class
  is `YYGameMakerYY`, title "Void War". The window does NOT exist yet when
  `vw_init` runs (oInitGlobals Create, preload room), so installation must retry -
  it is driven from `vw_poll` once per frame and succeeds on the first pump
  (attempt 1). We swallow `WM_ACTIVATE(WA_INACTIVE)`, `WM_ACTIVATEAPP(0)`, and
  `WM_KILLFOCUS`. `/health` reports `bgKeepalive`; the subclass is removed on
  `vw_shutdown`.
- Background-run outcome: the autonomous loop runs unattended today. This whole
  session drove the game over HTTP while it was backgrounded (a File Explorer
  window held the foreground) and the pump never stalled (`pumpAgeMs` stayed
  0-16ms). The documented "pauses on focus loss" is really a BOOT freeze - the
  runner is frozen until the window is focused once - and Steam's `-applaunch`
  focuses it automatically, so no human touch is needed. A steady-state
  focus-loss freeze could NOT be reproduced: Windows' foreground lock blocks a
  programmatic `SetForegroundWindow` from a background process (the same lock that
  stops anything from stealing the game's focus mid-run), and a global
  `FindWindowW("YYGameMakerYY")` returns 0 (the class is process-local), so I
  could not force a minimize either. Net: the WndProc subclass is an installed,
  harmless safeguard whose strict necessity is unproven; the loop works with it on
  (default) or off (`-NoBg`).
- `POST /cmd` replies are content-typed by shape: a reply starting with `{` or `[`
  is served as `application/json`, else `text/plain` (errors and ping/say are
  plain text). `/gui/raw` and `/screenshot` are GET sugar that submit
  `gui.raw`/`screenshot` through the same one-command-per-frame pump.

## Session 3 findings: input layer (verified 2026-07-08)

The input layer (`scrVwaInput`), the scrKeybinds suppression patch, `/state`,
`POST /input`, and the `vw_reset_speech` shim export are built and verified
live (31-check input-smoke plus the 18-check drive-smoke both pass from a
cold boot). Facts learned:

- `CodeImportGroup.QueueFindReplace(entry, search, replace)` exists in UTMT
  0.9.1.1 and works for surgical patches (used to add
  `global.vwaSuppressGameKeys` to the three keyboard `input_check*` guards).
  It NO-OPS SILENTLY when the search text does not match, so build-mod.csx
  decompiles the entry after `Import()` and asserts the patch text is
  present. Decompiling inside a CLI csx works exactly as in dump-all.csx:
  `new Underanalyzer.Decompiler.DecompileContext(new GlobalDecompileContext(Data),
  code, Data.ToolInfo.DecompilerSettings).DecompileToString()`.
- Two `QueueAppend` calls on the same code entry apply in queue order
  (verified live: the input tick and the dev pump both appended to
  `gml_Object_oInputManager_Step_1` and both run).
- Anonymous `function() {...}` expressions compile fine through the UTMT
  importer (action handlers use them), as do struct literals holding them.
- `keyboard_key_press`/`keyboard_key_release` DO NOT WORK in this runner:
  the simulated key never appears in `keyboard_check`, not even in the same
  frame (bit us; the suppression probe uses a different signal). Verify any
  input-simulation idea against the live game before building on it.
- `keyboard_check(vk_nokey)` (keycode 0) is true while no key is held, and a
  game keybind set to 0 passes `input_check`'s guard - that is the
  suppression probe's key-down signal: rebind `open_doors` to 0, read
  `input_check` with the flag on and off, restore, all in one frame
  (`vwa_dev_suppression_probe`).
- Freshly-booted runner io reports "a key is held" with no key named
  (vk_nokey false, vk_anykey false, keyboard_key 0) for roughly the first
  minute after launch, then settles on its own. `io_clear()` does NOT fix
  it. input-smoke outwaits it (12 x 5s retries on the probe); anything else
  that needs real key state right after boot must do the same.
- The keepalive trade-off is real in practice: with the game backgrounded,
  key state keeps updating, so a human typing anywhere on the machine can
  make "no key held" false during unattended runs (the probe reports
  `kbKey` to tell that apart from a real break).
- `variable_struct_remove`, `string(array)` (for error text), and
  `current_time`-based repeat timing all compile and behave as documented.
- Shim: `vw_reset_speech` tears down and re-creates the speech backends
  (Prism module unloaded and reloaded) without touching the ring, server, or
  command slot; it holds the state lock because `/health` reads the backend
  string from the HTTP thread. `/state` and `POST /input <actionKey>` are
  shim-side sugar submitting `state` / `input <key>` through the pump.

## Session 4 findings: screens, graph, announcer (verified 2026-07-08)

The framework core (`scrVwaGraph`, `scrVwaAnnounce`, `scrVwaScreens`), the
`/gui/mod` endpoint, and the synthetic test menu are built and verified live
(46-check screens-smoke plus the other two smokes all pass from a cold
boot). Facts learned:

- GML `==` on two struct references is reference equality, and it works as
  the graph's tier-1 node identity: the smoke's rename test (structural key
  changes, backing struct ref stays) follows focus correctly. Comparing a
  struct to a real with `==` returns false without erroring (vwa_ref_eq
  still guards the type mix explicitly).
- `method({...}, function() { ... self.x ... })` closures compile under the
  UTMT importer and behave as documented - the standard way to give per-item
  handlers/label functions their data (GML anonymous functions do NOT
  capture locals; they capture only self).
- `array_sort` with an anonymous comparator, `string_replace`, `clamp`, and
  struct-member function calls via a local (`var f = st.fn; f()`) all
  compile and work under the importer.
- **The bg keepalive makes runner key state lie** (bit us): the WndProc
  subclass swallows the focus-loss messages that normally make the runner
  clear its keyboard bookkeeping, so a key pressed before a window switch
  whose RELEASE went to the other window reads "held" forever. Observed
  live: a stale left Alt (keyboard_key 164) pinned for over a minute and
  broke exact-modifier chord matching and the suppression probe.
  `keyboard_check_direct` (real OS state, ignores focus; accepts
  vk_lalt/vk_ralt/vk_lshift/vk_rshift/vk_lcontrol/vk_rcontrol) exposes the
  lie. Fixes shipped: `vwa_input_unstick_modifiers` (every input tick:
  io_clear + loud log when the runner holds a modifier the OS reports up)
  and the suppression probe self-heals on any runner-held key the OS denies.
  The unstick's fix path cannot be provoked on demand (this runner ignores
  keyboard_key_press), so it is code-reviewed + trigger-observed; watch the
  mod log for its line in real sessions.
- Speech ordering that the framework guarantees, for future screens: screen
  name first (no interrupt), then the landing control's full path (no
  interrupt, so it queues behind the name); moves within a screen interrupt;
  live-part changes and activation feedback do not. All speech flows as
  parts arrays into vwa_speak; the announcer returns arrays, never joined
  strings.
- The navigator announces from the per-frame tick (observe), one frame after
  the action that moved focus - multiple moves in one frame speak once, on
  the final landing. The dev pump processes one command per frame, so any
  HTTP round-trip after a POST /input observes the settled state.

## Session 5 findings: main menu and announcements (verified 2026-07-08)

The first real screens (`scrVwaMenus`: main menu, announcements popup,
name-only placeholders for open game menus), `-WaitMainMenu`, and
`scripts/mainmenu-smoke.ps1` are built and verified live (all four smokes
pass from a cold boot). Facts learned:

- **`script_execute_ext` on a METHOD value does not call the method** (bit
  us, and silently): the method coerces to a number and an unrelated script
  index executes instead. Observed as `call oMenuSettings.closeMenu`
  returning fresh incrementing ds-handle-like numbers (2257, 2258, ...) with
  none of closeMenu's side effects. This also invalidated session 2's
  "menus created via onClick don't survive a frame" observation - the
  onClick never ran. The dev driver's `call` now invokes bound methods
  directly (`fn(args...)`, arity-capped at 4), which also preserves the
  method's bound self. Direct invocation through a local
  (`var f = nd.onActivate; f();`) was never affected - only the
  script_execute_ext path.
- `global.menuToggle` is NONZERO during the whole boot loading phase; the
  asset loader clears it (`gameMenu_setFlag(0)`) only when loading finishes.
  Any screen keyed on menuToggle must also gate on
  `!global.gameIsLoading` (set at the top of oInitGlobals Create, cleared
  by oAssetLoader, reused by oGameLoader for save loads) or it will
  announce over the loading screen (bit us: a stray "Menu" opened every
  boot transcript).
- Boot room order is rmPreload -> rmLoading -> rmSettingsPlacement (a
  brief settings-measuring room holding an oMenuSettings instance whose
  Create skips menu init there) -> rmMainMenu (oMenuSettings Step forwards
  out of rmSettingsPlacement).
- `localization_functionText_add(key, text)` does `variable_global_set`, so
  `global.label_mainMenu`, `label_settings`, `label_language`,
  `label_announcements` etc. hold the current language's text - the game's
  own strings, reused as our screen names (no vwa-- row needed).
- menuToggle values (gameMenu_to_str): 0 none, 1 crew, 2 cargo, 3 shop,
  4 upgrade, 5 localMap, 6 sectorMap, 7 armament, 8 escape, 9 settings,
  10 language, 11 shipListMenu, 12 shipSelect, 13 commanderSelect,
  14 confirmDialogue, 15 configureKeybinds.
- The game's menu keyboard handling is all raw `keyboard_check*`, so it is
  unaffected by the scrKeybinds suppression lever: Escape at the bare main
  menu OPENS settings (oMainMenuControls Step), Escape in settings closes
  it (oMenuSettings Draw_64), Escape/click dismisses the announcements
  popup (oGameStartMessage Draw_64). Arrows/mouse wheel scroll the popup
  visually. The main menu itself has no keyboard support at all.
- The announcements double-spawn quirk is once per PROFILE, not per boot:
  `global.gameStartPopupSpawned` is saved (scrSaveGame) and the popup
  auto-opens only while `gameStartMessages_lastDisplayedAnnouncementIndex`
  (also saved) trails the newest announcement.
- `oMainMenuControls.buttonList` structs are created once per room entry
  (spawn_buttons in Room Start) and are stable across frames - good tier-1
  refs. `buttonStr` re-localizes in place via getLocalizedText;
  `localizedLabelName` ("label_newGame") is the stable identity key.
  Activation guard mirrored from the draw handler: block when oCredits or
  oGameStartMessage exists or gameMenu_is(9, 15, 14), click sound
  `sfx_start(global.sfx_click2, 0, 1, 0, 0)`, then the stored onClick.
- PowerShell 5.1 `Invoke-RestMethod` JSON-decodes a text/plain body when it
  happens to parse as JSON, so a `/cmd get` of a string arrives already
  unquoted in smoke scripts (CmdStr in mainmenu-smoke handles both).

## Reference mods (pattern sources)

- `..\factorio-access` - Lua mod, speech via stdout protocol to an external launcher. Patterns: MessageBuilder speech composition (crashes on hand-added spaces), scanner as streaming entity database, graph-based keyboard UI rebuilt per keypress, vary-early message wording, minimal punctuation, let-it-crash over defensive guards, tick-based offline test framework.
- `..\wotr-access` - C# Harmony mod for Unity. Patterns: Prism handler chain with never-strand-the-user fallbacks (Prism, SAPI, clipboard) and a panic reset hotkey, screen/element/proxy layering that reads live game state at announce time (never cached), declarative announcement ordering, review cursor plus movement cursor exploration model, localization of every mod string, DEBUG-only dev server driven by an agent for verification.
- Both repos contain extensive agent-directed docs (CLAUDE.md, devdocs, audit checklists) explaining why these decisions were made. Read them before designing the corresponding subsystem here.
