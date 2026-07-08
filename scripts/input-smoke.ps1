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

# --- baseline live set: empty stack = global only ---
Check 'live categories = global' (($s2.liveCategories -join ',') -eq 'global') ($s2.liveCategories -join ',')
$actionKeys = @($s2.actions | ForEach-Object { $_.key })
Check 'starter actions registered' (
    $actionKeys -contains 'repeat-last' -and
    $actionKeys -contains 'speech-stop' -and
    $actionKeys -contains 'panic-reset') ($actionKeys -join ',')

# --- starter actions fire through /input and land in /speech ---
$cur = SpeechNext
$r = Fire 'repeat-last'
Check '/input repeat-last fired' ($r -eq 'fired repeat-last') $r
$lines = @(SpeechFrom $cur)
Check 'repeat-last spoke' ($lines.Count -ge 1) ($lines -join '|')

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
Cmd 'call vwa_dev_register_test_actions' | Out-Null
$r = Fire 'dev-shout-ui'
Check 'ui action refused while ui not live' ($r -like 'ERROR:*') $r
$s = GetState
$conflictChords = @($s.conflicts | ForEach-Object { $_.chord })
Check 'no F10 conflict while only global live' (-not ($conflictChords -contains '121')) ($s.conflicts | ConvertTo-Json -Compress)

Cmd 'call vwa_dev_test_screen ui' | Out-Null
$s = GetState
Check 'test screen on stack' ($s.stack.Count -eq 1 -and $s.stack[0].name -eq 'vwa-test-screen') ($s.stack | ConvertTo-Json -Compress)
Check 'live categories = ui,global' (($s.liveCategories -join ',') -eq 'ui,global') ($s.liveCategories -join ',')
$f10 = @($s.conflicts | Where-Object { $_.chord -eq '121' })
Check 'F10 chord conflict detected' ($f10.Count -eq 1) ($s.conflicts | ConvertTo-Json -Compress)
Check 'ui shadows global on F10' ($f10[0].winner -eq 'dev-shout-ui' -and $f10[0].shadowed -contains 'dev-shout-global') ($f10 | ConvertTo-Json -Compress)

$cur = SpeechNext
$r = Fire 'dev-shout-ui'
Check 'ui action fires while live' ($r -eq 'fired dev-shout-ui') $r
$lines = @(SpeechFrom $cur)
Check 'ui action spoke' (($lines -join '|') -match 'test shout ui') ($lines -join '|')

Cmd 'call vwa_dev_test_screen none' | Out-Null
$s = GetState
Check 'stack cleared flips winner back' (($s.liveCategories -join ',') -eq 'global') ($s.liveCategories -join ',')
$r = Fire 'dev-shout-ui'
Check 'ui action refused again' ($r -like 'ERROR:*') $r
$r = Fire 'dev-shout-global'
Check 'global action fires with empty stack' ($r -eq 'fired dev-shout-global') $r

# --- suppression: the game's own input_check goes quiet, then comes back ---
# One-frame probe: rebinds open_doors to vk_nokey (held whenever no key is
# down) and reads the game's input_check with the flag on, then off; every
# touched state is restored. live=false has two known benign causes, both
# worth outwaiting: the runner's key bookkeeping reads "something held" for
# the first minute or so after boot (kbKey 0), and a human typing anywhere
# on the machine (the keepalive keeps key state updating while backgrounded).
$r = Cmd 'call vwa_dev_suppression_probe open_doors'
Check 'game key suppressed' ($r.result.suppressed -eq $false) ($r | ConvertTo-Json -Compress)
foreach ($attempt in 1..12) {
    if ($r.result.live -eq $true) { break }
    Write-Host "  ...  live=false, kbKey $($r.result.kbKey) (boot warm-up or someone typing?); retrying"
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
