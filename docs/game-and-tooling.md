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

## Reference mods (pattern sources)

- `..\factorio-access` - Lua mod, speech via stdout protocol to an external launcher. Patterns: MessageBuilder speech composition (crashes on hand-added spaces), scanner as streaming entity database, graph-based keyboard UI rebuilt per keypress, vary-early message wording, minimal punctuation, let-it-crash over defensive guards, tick-based offline test framework.
- `..\wotr-access` - C# Harmony mod for Unity. Patterns: Prism handler chain with never-strand-the-user fallbacks (Prism, SAPI, clipboard) and a panic reset hotkey, screen/element/proxy layering that reads live game state at announce time (never cached), declarative announcement ordering, review cursor plus movement cursor exploration model, localization of every mod string, DEBUG-only dev server driven by an agent for verification.
- Both repos contain extensive agent-directed docs (CLAUDE.md, devdocs, audit checklists) explaining why these decisions were made. Read them before designing the corresponding subsystem here.
