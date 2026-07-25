# drive-smoke.ps1 - end-to-end regression check for the dev driver.
#
# Exercises the whole session-2 surface against a live game: /health, the
# eval-lite interpreter (ping/room/get/set/dump/instances/call), /gui/raw,
# and /screenshot. Assumes a launcher (run-game.ps1) is already up and the
# game is at (or heading to) the main menu; the smoke settles that
# precondition itself, because boot can pass through transition rooms
# where the menu object does not exist yet. No check asserts state a
# harmless change can alter (room names, exact instance counts,
# save-dependent list content) - anchors derive from the live game and
# checks assert plumbing consistency. Drives over HTTP only, so it needs
# no terminal focus. Exits nonzero on the first failed check.
#
# Usage: powershell -NoProfile -File scripts\drive-smoke.ps1

param(
    [int]$Port = $(if ($env:VWACCESS_DEV_PORT) { [int]$env:VWACCESS_DEV_PORT } else { 8772 })
)

$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$checks = 0
$fails = 0

function Cmd([string]$body) {
    return Invoke-RestMethod -Uri "$base/cmd" -Method Post -Body $body -TimeoutSec 8
}

function Check([string]$name, [bool]$ok, $detail) {
    $script:checks++
    if ($ok) {
        Write-Host "  ok   $name"
    } else {
        $script:fails++
        Write-Host "  FAIL $name -> $detail" -ForegroundColor Red
    }
}

Write-Host "drive-smoke: against $base"

# --- health ---
$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status
Check 'health pumping' ($h.pumpAgeMs -ge 0 -and $h.pumpAgeMs -lt 5000) $h.pumpAgeMs

# --- interpreter basics ---
Check 'ping' ((Cmd 'ping') -eq 'pong') 'no pong'
$room = Cmd 'room'
Check 'room command answers a room name' ($room.room -is [string] -and
    $room.room.Length -gt 0) ($room | ConvertTo-Json -Compress)

# --- get/set round trip on a scratch global ---
Cmd 'set global.vwaSmokeProbe 123.5' | Out-Null
$g = Cmd 'get global.vwaSmokeProbe'
Check 'set/get global' ($g -eq 123.5) $g

# --- compound literals: set a nested array/struct, read it back ---
Cmd 'set global.vwaSmokeProbe [1, "two words", {a: 3, b: [true]}]' | Out-Null
$cl = Cmd 'dump global.vwaSmokeProbe 4'
Check 'compound set round trip' ($cl.Count -eq 3 -and $cl[1] -eq 'two words' -and
    $cl[2].a -eq 3 -and $cl[2].b[0] -eq $true) ($cl | ConvertTo-Json -Compress)

# --- compound literal as a call argument ---
$ccall = Cmd 'call vwa_array_index_of ["alpha", "beta", "gamma"] beta'
Check 'compound call arg' ($ccall.result -eq 1) ($ccall | ConvertTo-Json -Compress)

# --- discovery: globals and scripts ---
$gl = Cmd 'globals vwaSmokeProbe'
Check 'globals finds the probe' ($gl.count -ge 1 -and
    $gl.globals[0].name -eq 'vwaSmokeProbe' -and $gl.globals[0].type -eq 'array') `
    ($gl | ConvertTo-Json -Compress)
$sc = Cmd 'scripts vwa_dev_dispatch'
Check 'scripts finds the dispatcher' ($sc.count -ge 1 -and
    ($sc.scripts | ForEach-Object { $_.name }) -contains 'vwa_dev_dispatch') `
    ($sc | ConvertTo-Json -Compress)

# --- /log tails ---
$logShim = Invoke-RestMethod "$base/log?which=shim&lines=10" -TimeoutSec 5
Check 'log tail shim' ($logShim -is [string] -and $logShim.Length -gt 0) $logShim
$logMod = Invoke-RestMethod "$base/log?which=mod&lines=10" -TimeoutSec 5
Check 'log tail mod' ($logMod -is [string] -and $logMod.Length -gt 0) $logMod

# --- settle the main-menu precondition: boot can pass through transition
#     rooms where oMainMenuControls does not exist yet; the object checks
#     below need it live, so wait for it rather than assume it ---
$inst = $null
$settled = $false
for ($i = 0; $i -lt 30; $i++) {
    $inst = Cmd 'instances oMainMenuControls'
    if ($inst.count -ge 1) { $settled = $true; break }
    Start-Sleep -Seconds 1
}
Check 'main menu controls settled' $settled $inst.count

# --- dump the main menu buttonList: the reverse-engineering path. The
#     list's content is save-dependent (Continue comes and goes), so the
#     checks are shape and cross-path consistency, never membership ---
$buttons = Cmd 'dump oMainMenuControls.buttonList 3'
$labels = @($buttons | ForEach-Object { $_.buttonStr })
$named = @($labels | Where-Object { $_ -is [string] -and $_.Length -gt 0 })
Check 'buttonList dump yields labeled buttons' ($labels.Count -ge 1 -and
    $named.Count -eq $labels.Count) ($labels -join ',')

# --- indexed member read, cross-checked against the dump ---
$oneLabel = Cmd 'get oMainMenuControls.buttonList[0].buttonStr'
Check 'indexed member read' ($oneLabel -is [string] -and $oneLabel.Length -gt 0) $oneLabel
Check 'indexed read agrees with the dump' ($labels.Count -ge 1 -and
    $labels[0] -eq $oneLabel) "$($labels -join ',') vs $oneLabel"

# --- instances enumeration (count is state; presence was settled above) ---
Check 'instances lists the menu controls' ($inst.count -ge 1) $inst.count
Check 'instance has id' ($inst.instances[0].id -gt 0) $inst.instances[0].id

# --- call a harmless script and get its return ---
$call = Cmd 'call scoreData_hasAnyEntry'
Check 'call returns a bool' ($call.result -is [bool]) $call.result
$loc = Cmd 'call vwa_t vwa--boot'
Check 'call vwa_t localized' ($loc.result -is [string] -and $loc.result.Length -gt 0) $loc.result

# --- call a bound method by path (regression: script_execute_ext coerces a
#     method to a wrong script index, so the dispatcher invokes methods
#     directly - session 5; getLocalizedText idempotently refreshes labels) ---
$mcall = Cmd 'call oMainMenuControls.getLocalizedText'
Check 'method-path call runs and returns null' ($null -eq $mcall.result) ($mcall | ConvertTo-Json -Compress)

# --- error handling: a bad command must not crash the pump ---
$err = Cmd 'get global.doesNotExistXyz'
Check 'missing global errors cleanly' ($err -like 'ERROR:*') $err
$ping2 = Cmd 'ping'
Check 'pump alive after error' ($ping2 -eq 'pong') $ping2

# --- /gui/raw: the room agrees with the interpreter's answer (two
#     independent driver paths), never a hardcoded room name ---
$roomNow = (Cmd 'room').room
$gui = Invoke-RestMethod "$base/gui/raw" -TimeoutSec 10
Check 'gui/raw room agrees with the interpreter' ($gui.room -eq $roomNow) `
    "$($gui.room) vs $roomNow"
Check 'gui/raw lists main menu' ($null -ne $gui.families.oMainMenuControls) 'missing family'

# --- agent-drive quiet window: a POST arms it; GETs alone let it expire ---
Cmd 'ping' | Out-Null
$hq = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'quiet window armed by a POST' ($hq.quietMsLeft -gt 0) $hq.quietMsLeft
Start-Sleep -Milliseconds ([int]$hq.quietMsLeft + 500)
$hq = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'quiet window expired with only GETs' ($hq.quietMsLeft -eq 0) $hq.quietMsLeft

# --- /screenshot: file exists and is a PNG ---
$shot = Invoke-RestMethod "$base/screenshot" -TimeoutSec 8
$png = $shot.path
$isPng = $false
if (Test-Path $png) {
    $bytes = [System.IO.File]::ReadAllBytes($png)
    $isPng = $bytes.Length -gt 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and
             $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47
}
Check 'screenshot is a PNG' $isPng $png

Write-Host ""
if ($fails -gt 0) {
    Write-Host "drive-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "drive-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
