# build-mod.ps1 - full mod build: shim, lang CSV merge, patched data.win.
# The original data.win is never modified; everything lands in build\.
# -SkipShim: skip the shim/test build (GML-only iteration).
# -SkipData: skip the data.win rebuild (~1 min; shim-only iteration).

param(
    [switch]$SkipShim,
    [switch]$SkipData
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$gameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Void War'
$utmt = "$repo\tools\utmt-cli\UndertaleModCli.exe"

if (-not $SkipShim) {
    & "$repo\tools\build-shim.ps1"
}

# Lang CSVs: start from the game's pristine files each build (so game updates
# propagate and vwa rows never duplicate), then append our vwa-- rows.
Write-Host 'build-mod: merging lang CSVs...'
New-Item -ItemType Directory -Force -Path "$repo\build\lang" | Out-Null
foreach ($lang in 'en', 'de', 'es', 'fr') {
    foreach ($fam in 'UIText', 'encounterText', 'functionText') {
        Copy-Item "$gameDir\lang\${fam}_$lang" "$repo\build\lang\${fam}_$lang" -Force
    }
    $src = "$repo\src\lang\vwa-$lang.csv"
    $dst = "$repo\build\lang\UIText_$lang"
    # Skip the vwa file's header row; game files end with a newline already.
    $rows = (Get-Content $src -Encoding UTF8) | Select-Object -Skip 1 | Where-Object { $_ -ne '' }
    $existing = [System.IO.File]::ReadAllText($dst)
    if (-not $existing.EndsWith("`n")) { $rows = @('') + $rows }
    [System.IO.File]::AppendAllText($dst, ($rows -join "`r`n") + "`r`n")
}

# Support files the runner expects next to the data file.
Copy-Item "$gameDir\options.ini" "$repo\build\options.ini" -Force
Copy-Item "$gameDir\bl" "$repo\build\bl" -Force

if (-not $SkipData) {
    Write-Host 'build-mod: patching data.win (takes about a minute)...'
    Push-Location $repo
    try {
        & $utmt load "$gameDir\data.win" -s "$repo\tools\build-mod.csx" -o "$repo\build\data-test.win"
        if ($LASTEXITCODE -ne 0) { throw "UTMT import failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
}

Write-Host 'build-mod: OK'
