// Non-interactive export of all embedded sounds from Void War's data.win.
// Writes .wav/.ogg files plus a manifest listing name, kind, and file size.
using System.Text;
using System;
using System.IO;
using System.Linq;
using UndertaleModLib.Models;

EnsureDataLoaded();

string outRoot = @"C:\Users\rasha\Documents\void-war\audio";
Directory.CreateDirectory(outRoot);

var manifest = new StringBuilder();
int ok = 0, skipped = 0;

foreach (UndertaleSound sound in Data.Sounds)
{
    string name = sound.Name?.Content ?? "unnamed";
    byte[] data = sound.AudioFile?.Data;
    if (data is null || data.Length == 0)
    {
        manifest.AppendLine($"{name}\tEXTERNAL/EMPTY\tfile={sound.File?.Content}");
        skipped++;
        continue;
    }
    string ext = ".bin";
    if (data.Length > 4)
    {
        if (data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F') ext = ".wav";
        else if (data[0] == 'O' && data[1] == 'g' && data[2] == 'g') ext = ".ogg";
    }
    string path = Path.Combine(outRoot, name + ext);
    File.WriteAllBytes(path, data);
    manifest.AppendLine($"{name}{ext}\t{data.Length} bytes");
    ok++;
}

File.WriteAllText(Path.Combine(outRoot, "_manifest.txt"), manifest.ToString());
ScriptMessage($"Exported {ok} sounds, skipped {skipped}. Output: {outRoot}");
