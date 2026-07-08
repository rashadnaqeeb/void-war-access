# input-smoke.ps1 - end-to-end regression check for the input layer (session 3).
#
# Exercises /state, POST /input, category liveness, shadowing resolution,
# game-key suppression through the patched input_check, and the tick
# watchdog, against a live game at the main menu. Assumes a launcher
# (run-game.ps1) is already up; drives over HTTP only. Exits nonzero on the
# first failed check's summary.
#
# Usage: powershell -NoProfile -File scripts\input-smoke.ps1

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

function Fire([string]$actionKey) {
    # POST /input; ERROR replies come back as plain 200 text.
    return Invoke-RestMethod -Uri "$base/input" -Method Post -Body $actionKey -TimeoutSec 8
}

function GetState {
    return Invoke-RestMethod "$base/state" -TimeoutSec 8
}

function SpeechNext {
    return (Invoke-RestMethod "$base/speech?since=0" -TimeoutSec 5).next
}

function SpeechFrom([uint64]$cursor) {
    return (Invoke-RestMethod "$base/speech?since=$cursor" -TimeoutSec 5).lines
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

Write-Host "input-smoke: against $base"

# --- health and tick liveness ---
$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status
$s1 = GetState
Start-Sleep -Milliseconds 250
$s2 = GetState
Check 'input tick runs every frame' ($s2.ticks -gt $s1.ticks) "$($s1.ticks) -> $($s2.ticks)"
Check 'typematic delay sane' ($s2.keyDelayMs -ge 150 -and $s2.keyDelayMs -le 2000) $s2.keyDelayMs
Check 'typematic rate sane' ($s2.keyRateMs -ge 10 -and $s2.keyRateMs -le 500) $s2.keyRateMs

# --- baseline live set at the main menu: the real main-menu screen
#     (session 5) keeps ui live, plus the always-on global ---
Check 'live categories = ui,global' (($s2.liveCategories -join ',') -eq 'ui,global') ($s2.liveCategories -join ',')
$actionKeys = @($s2.actions | ForEach-Object { $_.key })
Check 'starter actions registered' (
    $actionKeys -contains 'speech-stop' -and
    $actionKeys -contains 'panic-reset') ($actionKeys -join ',')

# --- starter actions fire through /input and land in /speech ---
$r = Fire 'speech-stop'
Check '/input speech-stop fired' ($r -eq 'fired speech-stop') $r

$cur = SpeechNext
$r = Fire 'panic-reset'
Check '/input panic-reset fired' ($r -eq 'fired panic-reset') $r
$lines = @(SpeechFrom $cur)
Check 'panic spoke a reset confirmation' (($lines -join '|') -match 'reset') ($lines -join '|')
$h2 = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health ok after panic reset' ($h2.status -eq 'ok') $h2.status
Check 'pump alive after panic reset' ((Cmd 'ping') -eq 'pong') 'no pong'

# --- refusals ---
$r = Fire 'no-such-action'
Check 'unknown action errors' ($r -like 'ERROR:*') $r

# --- test actions, liveness, shadowing flip ---
# ui is live at the main menu (the real main-menu screen), so the "ui dead"
# side of the flip comes from covering it with an EXCLUSIVE dev test screen
# whose category set is combat only.
Cmd 'call vwa_dev_register_test_actions' | Out-Null
$s = GetState
$f8 = @($s.conflicts | Where-Object { $_.chord -eq '119' })
Check 'F8 chord conflict detected' ($f8.Count -eq 1) ($s.conflicts | ConvertTo-Json -Compress)
Check 'ui shadows global on F8' ($f8[0].winner -eq 'dev-shout-ui' -and $f8[0].shadowed -contains 'dev-shout-global') ($f8 | ConvertTo-Json -Compress)

$cur = SpeechNext
$r = Fire 'dev-shout-ui'
Check 'ui action fires while live' ($r -eq 'fired dev-shout-ui') $r
$lines = @(SpeechFrom $cur)
Check 'ui action spoke' (($lines -join '|') -match 'test shout ui') ($lines -join '|')

Cmd 'call vwa_dev_test_screen combat!' | Out-Null
$s = GetState
$stackNames = @($s.stack | ForEach-Object { $_.name })
Check 'exclusive test screen on stack' ($stackNames -contains 'vwa-test-screen') ($stackNames -join ',')
Check 'exclusive modal kills ui below it' (($s.liveCategories -join ',') -eq 'combat,global') ($s.liveCategories -join ',')
$conflictChords = @($s.conflicts | ForEach-Object { $_.chord })
Check 'no F8 conflict while ui dead' (-not ($conflictChords -contains '119')) ($s.conflicts | ConvertTo-Json -Compress)
$r = Fire 'dev-shout-ui'
Check 'ui action refused while ui not live' ($r -like 'ERROR:*') $r
$r = Fire 'dev-shout-global'
Check 'global action fires under the modal' ($r -eq 'fired dev-shout-global') $r

Cmd 'call vwa_dev_test_screen none' | Out-Null
$s = GetState
Check 'uncovering restores ui' (($s.liveCategories -join ',') -eq 'ui,global') ($s.liveCategories -join ',')
$r = Fire 'dev-shout-ui'
Check 'ui action fires again' ($r -eq 'fired dev-shout-ui') $r

# --- suppression: the game's own input_check goes quiet, then comes back ---
# One-frame probe: rebinds open_doors to vk_nokey (held whenever no key is
# down) and reads the game's input_check with the flag on, then off; every
# touched state is restored. The probe self-heals stale runner key state
# (io_clear when keyboard_check_direct disagrees), so a lasting live=false
# with kbDirect=true means a human is really holding a key - worth
# outwaiting.
$r = Cmd 'call vwa_dev_suppression_probe open_doors'
Check 'game key suppressed' ($r.result.suppressed -eq $false) ($r | ConvertTo-Json -Compress)
foreach ($attempt in 1..12) {
    if ($r.result.live -eq $true) { break }
    Write-Host "  ...  live=false, kbKey $($r.result.kbKey) direct=$($r.result.kbDirect) (someone holding a key?); retrying"
    Start-Sleep -Seconds 5
    $r = Cmd 'call vwa_dev_suppression_probe open_doors'
}
Check 'game key live again' ($r.result.live -eq $true) ($r | ConvertTo-Json -Compress)

# --- watchdog: a tick fault must clear suppression, not kill the keyboard ---
Cmd 'set global.vwaSuppressGameKeys true' | Out-Null
Cmd 'call vwa_dev_arm_input_fault' | Out-Null
Start-Sleep -Milliseconds 100  # give the tick a frame to trip
$g = Cmd 'get global.vwaSuppressGameKeys'
Check 'watchdog cleared suppression' ($g -eq $false) $g
$s = GetState
Check 'watchdog trip reported' ($s.watchdogTripped -eq $true) $s.watchdogTripped
Cmd 'set global.vwaInputWatchdogTripped false' | Out-Null
$s = GetState
Check 'ticks still running after watchdog' ($s.ticks -gt $s2.ticks) "$($s2.ticks) -> $($s.ticks)"
Check 'pump alive at end' ((Cmd 'ping') -eq 'pong') 'no pong'

Write-Host ""
if ($fails -gt 0) {
    Write-Host "input-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "input-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
