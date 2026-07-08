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

// New global script: all vwa_* functions.
group.QueueReplace("gml_GlobalScript_scrVwaCore",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaCore.gml")));

// Dev-driver eval-lite interpreter (dev builds only; the release build
// script will omit this file and the pump append).
group.QueueReplace("gml_GlobalScript_scrVwaDev",
    File.ReadAllText(Path.Combine(gmlDir, "scrVwaDev.gml")));

// Boot patch: shim load + boot announcement, at the end of oInitGlobals Create.
group.QueueAppend("gml_Object_oInitGlobals_Create_0",
    File.ReadAllText(Path.Combine(gmlDir, "oInitGlobals_Create_0.append.gml")));

// Dev pump: one poll/reply round per step in the persistent input manager.
group.QueueAppend("gml_Object_oInputManager_Step_1",
    File.ReadAllText(Path.Combine(gmlDir, "oInputManager_Step_1.append.gml")));

group.Import();

// The import must actually have produced the new scripts' code entries.
if (Data.Code.ByName("gml_GlobalScript_scrVwaCore") == null)
    throw new Exception("gml_GlobalScript_scrVwaCore was not created by the import");
if (Data.Code.ByName("gml_GlobalScript_scrVwaDev") == null)
    throw new Exception("gml_GlobalScript_scrVwaDev was not created by the import");

ScriptMessage("vw-access GML import OK");
