// Round-trip test: append a file-write marker to oInitGlobals' Create event.
// The marker lands in the game's save dir (%AppData%\Roaming\Void_War), proving
// injected GML executes. show_debug_message is not captured by -debugoutput in
// this build, so files are the reliable side channel.
using System;
using UndertaleModLib.Compiler;

EnsureDataLoaded();

var group = new CodeImportGroup(Data);
group.QueueAppend("gml_Object_oInitGlobals_Create_0", @"
var __vwf = file_text_open_write(""vw-access-test.txt"");
file_text_write_string(__vwf, ""VW-ACCESS injection works. boot timestamp "" + string(current_year) + ""-"" + string(current_month) + ""-"" + string(current_day) + "" "" + string(current_hour) + "":"" + string(current_minute));
file_text_close(__vwf);
");
group.Import();

ScriptMessage("Injection compile OK");
