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

// Game-key gate, registry axis: the game's three keyboard input_check*
// wrappers consult the mod's default-deny allowlist (scrVwaInput's
// vwa_game_bind_allowed, which fails open before mod init and under the
// tick watchdog) alongside the game's own textFieldInputEnabled gate. The
// search string appears exactly three times in scrKeybinds, once per
// keyboard wrapper (the mouse wrappers don't carry the textField gate).
group.QueueFindReplace("gml_GlobalScript_scrKeybinds",
    "global.textFieldInputEnabled ||",
    "global.textFieldInputEnabled || !vwa_game_bind_allowed(arg0) ||");

// Game-key gate, raw axis: the verified player-facing raw keyboard reads
// in game code - the sites that can act on a key press alone, outside the
// input_check* registry - are routed through scrVwaInput's gated wrappers
// (vwa_game_kcp / vwa_game_kc). Derived from a full decompile sweep
// (session 13); re-derive after a game update. Left alone by design:
// text-field objects (typing must always work), the keybind-capture
// object (oKeybindSetter), reads behind enableDebugKeys / enableDevMode /
// drawDebugF*, modifier-only reads (their main key is already gated), and
// oPopupGroup's number-key reads (the commit shortcut's caller is removed
// by the Step replacement below; the held-number highlight only acts with
// the mouse). Entries needing several replacements get ONE queued replace
// built here (stacked QueueFindReplace on one entry is unverified); each
// site must match exactly once pre-import, and every patched entry is
// re-decompiled post-import to prove the gate survived the recompile.
var rawGates = new (string Entry, string Find, string Replace)[]
{
    // The Escape family: menu/screen close-or-back, popup cancel, and the
    // in-run pause menu (oPopupManager). Escape sits on the gate's base
    // allowance, so behavior is unchanged until a context revokes it.
    ("gml_Object_oCredits_Create_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oGameStartMessage_Draw_64", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMainMenuControls_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuButtonBack_Create_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuCommander_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuConfigureKeybinds_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuLanguage_Draw_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuLanguage_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuPause_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oMenuSettings_Draw_64", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oPopupManager_Create_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oShipListMenu_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oShipMenu_shipSelector_Step_1", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oTxtItemSlotToUnequip_Create_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oTxtSpellForget_Create_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oUICommanderList_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oUIMenu_Step_2", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    ("gml_Object_oWMGalaxyGen_Step_0", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    // The confirmation dialogue reads Escape as a held check.
    ("gml_Object_oUIConfirmationDialogue_Step_0", "keyboard_check(vk_escape)", "vwa_game_kc(vk_escape)"),
    // The upgrade menu's Escape-undo.
    ("gml_GlobalScript_scrMenu", "keyboard_check_pressed(vk_escape)", "vwa_game_kcp(vk_escape)"),
    // Start-message keyboard scroll (mouse wheel scroll stays).
    ("gml_Object_oGameStartMessage_Draw_64", "keyboard_check(vk_down)", "vwa_game_kc(vk_down)"),
    ("gml_Object_oGameStartMessage_Draw_64", "keyboard_check(vk_up)", "vwa_game_kc(vk_up)"),
    // Music mute (right Shift+M; the Shift read is a modifier and stays raw).
    ("gml_Object_oMusicControls_Draw_0", "keyboard_check_pressed(ord(\"M\"))", "vwa_game_kcp(ord(\"M\"))"),
    // Ship-select hull cycling arrows (the mod's ship-select screen owns
    // the arrows; its postDispatch consume becomes belt-and-braces).
    ("gml_Object_oShipMenu_shipSelector_Create_0", "keyboard_check_pressed(vk_left)", "vwa_game_kcp(vk_left)"),
    ("gml_Object_oShipMenu_shipSelector_Create_0", "keyboard_check_pressed(vk_right)", "vwa_game_kcp(vk_right)"),
};

string DecompileEntry(string entryName)
{
    var entryCode = Data.Code.ByName(entryName);
    if (entryCode == null)
        throw new Exception(entryName + " not found");
    return new Underanalyzer.Decompiler.DecompileContext(
        new GlobalDecompileContext(Data), entryCode, Data.ToolInfo.DecompilerSettings).DecompileToString();
}

int CountOccurrences(string text, string needle)
{
    int n = 0;
    for (int at = text.IndexOf(needle); at >= 0; at = text.IndexOf(needle, at + 1))
        n++;
    return n;
}

foreach (var siteGroup in rawGates.GroupBy(g => g.Entry))
{
    string entryText = DecompileEntry(siteGroup.Key);
    foreach (var site in siteGroup)
    {
        int hits = CountOccurrences(entryText, site.Find);
        if (hits != 1)
            throw new Exception($"{siteGroup.Key}: expected exactly 1 occurrence of '{site.Find}', found {hits} - game update reshaped the entry?");
        entryText = entryText.Replace(site.Find, site.Replace);
    }
    group.QueueReplace(siteGroup.Key, entryText);
}

// Dialogue popups: replace oPopupGroup's Begin Step to drop the game's raw
// number-key shortcut, which EXECUTES a choice - silent to a blind player.
// The mod's number keys move the cursor to the choice instead
// (scrVwaMenuEncounter). Asserted below: the shortcut call must be gone and
// the mouse click path must survive.
group.QueueReplace("gml_Object_oPopupGroup_Step_1",
    File.ReadAllText(Path.Combine(gmlDir, "oPopupGroup_Step_1.replace.gml")));

group.Import();

// The registry-axis FindReplace must actually have landed: QueueFindReplace
// no-ops silently on no match (e.g. after a game update reshapes
// scrKeybinds), which would ship an input_check that ignores the gate.
string kbText = DecompileEntry("gml_GlobalScript_scrKeybinds");
int kbHits = CountOccurrences(kbText, "vwa_game_bind_allowed");
if (kbHits != 3)
    throw new Exception($"scrKeybinds gate patch: expected 3 occurrences of vwa_game_bind_allowed, found {kbHits}");

// Every raw-axis gate must have survived the recompile. The re-decompile
// renders vk constants numerically inside calls to the mod's wrappers
// (vk_escape becomes 27 - the decompiler only names constants for
// functions it knows), so assert on the wrapper-call count plus the
// absence of the original ungated read, not on the exact replace text.
foreach (var siteGroup in rawGates.GroupBy(g => g.Entry))
{
    string entryText = DecompileEntry(siteGroup.Key);
    int gateCalls = CountOccurrences(entryText, "vwa_game_k");
    if (gateCalls != siteGroup.Count())
        throw new Exception($"{siteGroup.Key}: expected {siteGroup.Count()} gated raw reads after import, found {gateCalls}");
    foreach (var site in siteGroup)
    {
        if (entryText.Contains(site.Find))
            throw new Exception($"{siteGroup.Key}: ungated read '{site.Find}' still present after import");
    }
}

// The popup Step replacement must have landed on the real entry (a game
// update renaming or reshaping it would silently leave the number-commit
// shortcut alive): the shortcut call must be gone, the click path present.
var pgCode = Data.Code.ByName("gml_Object_oPopupGroup_Step_1");
if (pgCode == null)
    throw new Exception("gml_Object_oPopupGroup_Step_1 not found");
string pgText = new Underanalyzer.Decompiler.DecompileContext(
    new GlobalDecompileContext(Data), pgCode, Data.ToolInfo.DecompilerSettings).DecompileToString();
if (pgText.Contains("keyboardShortcut_choiceExecute"))
    throw new Exception("oPopupGroup Step_1: number-commit shortcut still present after replace");
if (!pgText.Contains("detect_choice_click_and_execute"))
    throw new Exception("oPopupGroup Step_1: click path missing after replace - wrong entry replaced?");

// The import must actually have produced every script's code entry.
foreach (var path in scriptFiles)
{
    var name = Path.GetFileNameWithoutExtension(path);
    if (Data.Code.ByName("gml_GlobalScript_" + name) == null)
        throw new Exception("gml_GlobalScript_" + name + " was not created by the import");
}

ScriptMessage("vw-access GML import OK (" + scriptFiles.Count + " scripts)");
