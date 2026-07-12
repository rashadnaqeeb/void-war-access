// build-mod.csx - import the mod's GML into data.win.
// Run via: tools\utmt-cli\UndertaleModCli.exe load <original data.win>
//              -s tools\build-mod.csx -o build\data-test.win
// Invoked from the repo root by tools/build-mod.ps1 (relative paths below
// resolve against the process working directory).
//
// UTMT 0.9.x notes (bit us in session 0): ImportGMLString does not exist in
// CLI scripts - CodeImportGroup is the supported path.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UndertaleModLib.Compiler;

EnsureDataLoaded();

string gmlDir = Path.Combine(Environment.CurrentDirectory, "src", "gml");

var group = new CodeImportGroup(Data);

// Every src/gml/scr*.gml file becomes one new global script,
// gml_GlobalScript_<basename>. Adding a script is dropping a file in
// src/gml - no build-code change. Dev-only scripts are listed here so a
// future release build can skip them; the dev build imports everything.
var devOnlyScripts = new HashSet<string> { "scrVwaDev", "scrVwaDevScreens", "scrVwaTest" };
var scriptFiles = Directory.GetFiles(gmlDir, "scr*.gml")
    .OrderBy(p => Path.GetFileName(p), StringComparer.Ordinal)
    .ToList();
if (scriptFiles.Count == 0)
    throw new Exception("no src/gml/scr*.gml files found - wrong working directory?");
foreach (var path in scriptFiles)
{
    var name = Path.GetFileNameWithoutExtension(path);
    group.QueueReplace("gml_GlobalScript_" + name, File.ReadAllText(path));
}

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

// The import must actually have produced every script's code entry.
foreach (var path in scriptFiles)
{
    var name = Path.GetFileNameWithoutExtension(path);
    if (Data.Code.ByName("gml_GlobalScript_" + name) == null)
        throw new Exception("gml_GlobalScript_" + name + " was not created by the import");
}

ScriptMessage("vw-access GML import OK (" + scriptFiles.Count + " scripts)");
