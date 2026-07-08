# drive-smoke.ps1 - end-to-end regression check for the dev driver.
#
# Exercises the whole session-2 surface against a live game: /health, the
# eval-lite interpreter (ping/room/get/set/dump/instances/call), /gui/raw,
# and /screenshot. Assumes a launcher (run-game.ps1) is already up and the
# game sits at the main menu; it drives over HTTP only, so it needs no
# terminal focus. Exits nonzero on the first failed check.
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
Check 'room is main menu' ($room.room -eq 'rmMainMenu') $room.room

# --- get/set round trip on a scratch global ---
Cmd 'set global.vwaSmokeProbe 123.5' | Out-Null
$g = Cmd 'get global.vwaSmokeProbe'
Check 'set/get global' ($g -eq 123.5) $g

# --- dump the main menu buttonList: the reverse-engineering path ---
$buttons = Cmd 'dump oMainMenuControls.buttonList 3'
$labels = @($buttons | ForEach-Object { $_.buttonStr })
Check 'buttonList has New Game' ($labels -contains 'New Game') ($labels -join ',')
Check 'buttonList has Settings' ($labels -contains 'Settings') ($labels -join ',')
Check 'buttonList has Exit' ($labels -contains 'Exit') ($labels -join ',')

# --- indexed member read ---
$oneLabel = Cmd 'get oMainMenuControls.buttonList[0].buttonStr'
Check 'indexed member read' ($oneLabel -is [string] -and $oneLabel.Length -gt 0) $oneLabel

# --- instances enumeration ---
$inst = Cmd 'instances oMainMenuControls'
Check 'instances count 1' ($inst.count -eq 1) $inst.count
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

# --- /gui/raw ---
$gui = Invoke-RestMethod "$base/gui/raw" -TimeoutSec 10
Check 'gui/raw room' ($gui.room -eq 'rmMainMenu') $gui.room
Check 'gui/raw lists main menu' ($null -ne $gui.families.oMainMenuControls) 'missing family'

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
