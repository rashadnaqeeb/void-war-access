// build-mod.csx - import the mod's GML into data.win.
// Run via: tools\utmt-cli\UndertaleModCli.exe load <original data.win>
//              -s tools\build-mod.csx -o build\data-test.win
// Invoked from the repo root by tools/build-mod.ps1 (relative paths below
// resolve against the process working directory).
//
// UTMT 0.9.x notes (bit us in session 0): ImportGMLString does not exist in
// CLI scripts - CodeImportGroup is the supported path.

using System;
using System.IO;
using UndertaleModLib.Compiler;

EnsureDataLoaded();

string gmlDir = Path.Combine(Environment.CurrentDirectory, "src", "gml");

var group = new CodeImportGroup(Data);

// New global script: logging, localization, the speech chokepoint.
group.QueueReplace("gml_GlobalScript_scrVwaCore",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaCore.gml")));

// New global script: the input layer (actions, categories, suppression).
group.QueueReplace("gml_GlobalScript_scrVwaInput",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaInput.gml")));

// New global scripts: the framework core (session 4) - control graph,
// announcement composition, type-ahead matcher, screen layer + navigator.
group.QueueReplace("gml_GlobalScript_scrVwaGraph",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaGraph.gml")));
group.QueueReplace("gml_GlobalScript_scrVwaAnnounce",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaAnnounce.gml")));
group.QueueReplace("gml_GlobalScript_scrVwaSearch",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaSearch.gml")));
group.QueueReplace("gml_GlobalScript_scrVwaScreens",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaScreens.gml")));

// New global script: the text edit layer (session 9) - edit-mode tracker,
// review cursor, keyboard exit for the game's text fields.
group.QueueReplace("gml_GlobalScript_scrVwaText",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaText.gml")));

// New global script: the crew sheet composer (session 10) - categorized
// spoken lines for a crew instance; the commander select screen consumes it.
group.QueueReplace("gml_GlobalScript_scrVwaSheet",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaSheet.gml")));

// New global script: the real game screens (session 5) - main menu,
// announcements popup, game-menu placeholders.
group.QueueReplace("gml_GlobalScript_scrVwaMenus",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaMenus.gml")));

// Dev-driver eval-lite interpreter (dev builds only; the release build
// script will omit this file and the dev pump append).
group.QueueReplace("gml_GlobalScript_scrVwaDev",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaDev.gml")));

// In-game test module (session 11): pure-module selftest + the screen
// walker. Dev builds only, like scrVwaDev.
group.QueueReplace("gml_GlobalScript_scrVwaTest",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaTest.gml")));

// Boot patch: shim load, input-layer init, boot announcement, at the end of
// oInitGlobals Create.
group.QueueAppend("gml_Object_oInitGlobals_Create_0",
    File.ReadAllText(Path.Combine(gmlDir, "oInitGlobals_Create_0.append.gml")));

// Input tick (ships) then dev pump (dev builds only), both appended to the
// persistent input manager's Begin Step. Two QueueAppends on one entry apply
// in order; input-smoke.ps1 verifies both blocks live (ticks grow AND the
// pump answers).
group.QueueAppend("gml_Object_oInputManager_Step_1",
    File.ReadAllText(Path.Combine(gmlDir, "oInputManager_Step_1.append.gml")));
group.QueueAppend("gml_Object_oInputManager_Step_1",
    File.ReadAllText(Path.Combine(gmlDir, "oInputManager_Step_1.dev.append.gml")));

// Orderly shim teardown on the game's Game End event (oGlobal also
// autosaves there): restore the window's WndProc and stop the dev server
// before the runner unloads the DLL.
group.QueueAppend("gml_Object_oGlobal_Other_3",
    File.ReadAllText(Path.Combine(gmlDir, "oGlobal_Other_3.append.gml")));

// Suppression lever: the game's three keyboard input_check* wrappers gain
// our flag alongside the game's own textFieldInputEnabled gate. The search
// string appears exactly three times in scrKeybinds, once per keyboard
// wrapper (the mouse wrappers don't carry the textField gate).
group.QueueFindReplace("gml_GlobalScript_scrKeybinds",
    "global.textFieldInputEnabled ||",
    "global.textFieldInputEnabled || global.vwaSuppressGameKeys ||");

group.Import();

// The suppression FindReplace must actually have landed: QueueFindReplace
// no-ops silently on no match (e.g. after a game update reshapes
// scrKeybinds), which would ship an input_check that ignores the flag.
var kbCode = Data.Code.ByName("gml_GlobalScript_scrKeybinds");
if (kbCode == null)
    throw new Exception("gml_GlobalScript_scrKeybinds not found");
string kbText = new Underanalyzer.Decompiler.DecompileContext(
    new GlobalDecompileContext(Data), kbCode, Data.ToolInfo.DecompilerSettings).DecompileToString();
int kbHits = 0;
for (int at = kbText.IndexOf("global.vwaSuppressGameKeys"); at >= 0;
     at = kbText.IndexOf("global.vwaSuppressGameKeys", at + 1))
    kbHits++;
if (kbHits != 3)
    throw new Exception($"scrKeybinds suppression patch: expected 3 occurrences of the flag, found {kbHits}");

// The import must actually have produced the new scripts' code entries.
if (Data.Code.ByName("gml_GlobalScript_scrVwaCore") == null)
    throw new Exception("gml_GlobalScript_scrVwaCore was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaInput") == null)
    throw new Exception("gml_GlobalScript_scrVwaInput was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaGraph") == null)
    throw new Exception("gml_GlobalScript_scrVwaGraph was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaAnnounce") == null)
    throw new Exception("gml_GlobalScript_scrVwaAnnounce was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaSearch") == null)
    throw new Exception("gml_GlobalScript_scrVwaSearch was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaScreens") == null)
    throw new Exception("gml_GlobalScript_scrVwaScreens was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaText") == null)
    throw new Exception("gml_GlobalScript_scrVwaText was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaSheet") == null)
    throw new Exception("gml_GlobalScript_scrVwaSheet was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaMenus") == null)
    throw new Exception("gml_GlobalScript_scrVwaMenus was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaDev") == null)
    throw new Exception("gml_GlobalScript_scrVwaDev was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaTest") == null)
    throw new Exception("gml_GlobalScript_scrVwaTest was not created by the import");

ScriptMessage("vw-access GML import OK");
