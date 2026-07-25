// Structured dump of every ship-layout room (any room containing oCell
// instances) for the accessibility mod's ship-shape audit. Unlike
// dump-all.csx's rooms.txt, this emits per-instance rotation and the
// creation-code entry name (both needed to resolve cell-side overrides).
// Output: decompiled\ships.json.
using System.Text;
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;

EnsureDataLoaded();

string outRoot = @"C:\Users\rasha\Documents\void-war\decompiled";
Directory.CreateDirectory(outRoot);

string J(string s) => s is null ? "null" : "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

var sb = new StringBuilder();
sb.AppendLine("[");
bool firstRoom = true;

foreach (var r in Data.Rooms)
{
    var insts = r.GameObjects;
    if (insts is null || !insts.Any(i => (i.ObjectDefinition?.Name?.Content ?? "").StartsWith("oCell")))
        continue;

    if (!firstRoom) sb.AppendLine(",");
    firstRoom = false;
    sb.AppendLine("{" + $"\"room\": {J(r.Name?.Content)}, \"instances\": [");
    bool firstInst = true;
    foreach (var inst in insts)
    {
        string obj = inst.ObjectDefinition?.Name?.Content ?? "?";
        string cc = inst.CreationCode?.Name?.Content;
        if (!firstInst) sb.AppendLine(",");
        firstInst = false;
        sb.Append($"  {{\"obj\": {J(obj)}, \"x\": {inst.X}, \"y\": {inst.Y}, \"rot\": {inst.Rotation}, \"cc\": {J(cc)}}}");
    }
    sb.AppendLine();
    sb.Append("]}");
}
sb.AppendLine();
sb.AppendLine("]");
File.WriteAllText(Path.Combine(outRoot, "ships.json"), sb.ToString());
ScriptMessage("ships.json written");
