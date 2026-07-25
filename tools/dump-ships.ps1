# dump-ships.ps1 - regenerate decompiled\ships.json (structured ship-room
# dump with per-instance rotation and creation-code names; see
# dump-ships.csx). Reads the pristine data.win, never writes game data.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$gameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Void War'
$utmt = "$repo\tools\utmt-cli\UndertaleModCli.exe"

& $utmt load "$gameDir\data.win" -s "$repo\tools\dump-ships.csx"
if ($LASTEXITCODE -ne 0) { throw "UTMT dump-ships failed (exit $LASTEXITCODE)" }
Write-Host 'dump-ships: OK'
