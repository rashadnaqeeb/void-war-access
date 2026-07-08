// Non-interactive full dump of Void War's data.win for the accessibility mod project.
// Exports decompiled GML, strings, and a structural manifest (objects, rooms, extensions).
using System.Text;
using System;
using System.IO;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Linq;
using UndertaleModLib.Util;

EnsureDataLoaded();

string outRoot = @"C:\Users\rasha\Documents\void-war\decompiled";
string codeFolder = Path.Combine(outRoot, "code");
Directory.CreateDirectory(codeFolder);

// --- General info ---
var gen8 = Data.GeneralInfo;
var info = new StringBuilder();
info.AppendLine($"Name: {gen8.Name?.Content}");
info.AppendLine($"FileName: {gen8.FileName?.Content}");
info.AppendLine($"DisplayName: {gen8.DisplayName?.Content}");
info.AppendLine($"GameMaker version: {gen8.Major}.{gen8.Minor}.{gen8.Release}.{gen8.Build}");
info.AppendLine($"Bytecode: {gen8.BytecodeVersion}");
info.AppendLine($"Counts: code={Data.Code.Count} scripts={Data.Scripts.Count} objects={Data.GameObjects.Count} rooms={Data.Rooms.Count} sprites={Data.Sprites.Count} sounds={Data.Sounds.Count} fonts={Data.Fonts.Count} shaders={Data.Shaders.Count} extensions={Data.Extensions.Count}");
File.WriteAllText(Path.Combine(outRoot, "info.txt"), info.ToString());

// --- Extensions (we need to learn how the game declares its one extension) ---
var ext = new StringBuilder();
foreach (var e in Data.Extensions)
{
    ext.AppendLine($"Extension: {e.Name?.Content}  FolderName: {e.FolderName?.Content}  ClassName: {e.ClassName?.Content}");
    foreach (var f in e.Files)
    {
        ext.AppendLine($"  File: {f.Filename?.Content}  Kind: {f.Kind}  InitScript: {f.InitScript?.Content}  CleanupScript: {f.CleanupScript?.Content}");
        foreach (var fn in f.Functions)
        {
            var args = string.Join(", ", fn.Arguments.Select(a => a.Type.ToString()));
            ext.AppendLine($"    Func: {fn.Name?.Content}  ExtName: {fn.ExtName?.Content}  Ret: {fn.RetType}  Kind: {fn.Kind}  Args: ({args})");
        }
    }
}
File.WriteAllText(Path.Combine(outRoot, "extensions.txt"), ext.ToString());

// --- Game objects: name, parent, sprite, which events exist ---
var objs = new StringBuilder();
foreach (var o in Data.GameObjects)
{
    string parent = o.ParentId?.Name?.Content ?? "";
    string sprite = o.Sprite?.Name?.Content ?? "";
    var evs = new List<string>();
    for (int i = 0; i < o.Events.Count; i++)
    {
        foreach (var e in o.Events[i])
        {
            foreach (var a in e.Actions)
            {
                string code = a.CodeId?.Name?.Content ?? "";
                if (code != "") evs.Add(code);
            }
        }
    }
    objs.AppendLine($"{o.Name?.Content}\tparent={parent}\tsprite={sprite}\tevents={string.Join(",", evs)}");
}
File.WriteAllText(Path.Combine(outRoot, "objects.txt"), objs.ToString());

// --- Rooms: layers and instances (object counts per room) ---
var rooms = new StringBuilder();
foreach (var r in Data.Rooms)
{
    rooms.AppendLine($"ROOM {r.Name?.Content}  size={r.Width}x{r.Height}  persistent={r.Persistent}");
    if (r.Layers is not null)
    {
        foreach (var l in r.Layers)
        {
            rooms.AppendLine($"  layer {l.LayerName?.Content}  type={l.LayerType}  depth={l.LayerDepth}");
            if (l.InstancesData is not null)
            {
                var counts = l.InstancesData.Instances
                    .GroupBy(inst => inst.ObjectDefinition?.Name?.Content ?? "?")
                    .OrderByDescending(g => g.Count());
                foreach (var g in counts)
                    rooms.AppendLine($"    {g.Key} x{g.Count()}");
            }
        }
    }
    foreach (var inst in r.GameObjects)
        rooms.AppendLine($"  legacy-instance {inst.ObjectDefinition?.Name?.Content} at {inst.X},{inst.Y}");
}
File.WriteAllText(Path.Combine(outRoot, "rooms.txt"), rooms.ToString());

// --- Strings ---
using (var sw = new StreamWriter(Path.Combine(outRoot, "strings.txt")))
{
    foreach (var s in Data.Strings)
        sw.WriteLine(s.Content.Replace("\r", "\\r").Replace("\n", "\\n"));
}

// --- All code, decompiled ---
GlobalDecompileContext globalDecompileContext = new(Data);
Underanalyzer.Decompiler.IDecompileSettings decompilerSettings = Data.ToolInfo.DecompilerSettings;
List<UndertaleCode> toDump = Data.Code.Where(c => c.ParentEntry is null).ToList();
int done = 0, failed = 0;

await Task.Run(() => Parallel.ForEach(toDump, code =>
{
    string path = Paths.JoinVerifyWithinDirectory(codeFolder, code.Name.Content + ".gml");
    try
    {
        File.WriteAllText(path, new Underanalyzer.Decompiler.DecompileContext(globalDecompileContext, code, decompilerSettings).DecompileToString());
        System.Threading.Interlocked.Increment(ref done);
    }
    catch (Exception e)
    {
        File.WriteAllText(path, "/*\nDECOMPILER FAILED!\n\n" + e.ToString() + "\n*/");
        System.Threading.Interlocked.Increment(ref failed);
    }
}));

ScriptMessage($"Dump complete. code entries ok={done} failed={failed}");
