# screens-smoke.ps1 - end-to-end regression check for the framework core
# (session 4): screen stack, control graph, navigator, announcer.
#
# Drives the synthetic dev test menu (vwa_dev_test_menu) through POST /input
# and asserts the EXACT /speech transcript: screen-name announcement, path
# entry (contexts outermost first), sibling moves, auto "n of m", live-part
# re-speak (toggle/slider), Tab-stop cycling with remembered positions,
# no-action feedback, focus recovery (survivor fallback and tier-1
# reference follow), and silence where nothing should speak. Also checks
# /gui/mod. Assumes a launcher (run-game.ps1) is already up at the main
# menu; drives over HTTP only. Exits nonzero on any failed check.
#
# Usage: powershell -NoProfile -File scripts\screens-smoke.ps1

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
    return Invoke-RestMethod -Uri "$base/input" -Method Post -Body $actionKey -TimeoutSec 8
}

function SpeechNext {
    return (Invoke-RestMethod "$base/speech?since=0" -TimeoutSec 5).next
}

function SpeechFrom([uint64]$cursor) {
    Start-Sleep -Milliseconds 250  # give the pump a frame to dispatch + the tick to observe
    return @((Invoke-RestMethod "$base/speech?since=$cursor" -TimeoutSec 5).lines)
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

# Fire an action (or run a command), then assert the exact new speech lines.
function CheckSpeech([string]$name, [scriptblock]$act, [string[]]$expected) {
    $cur = SpeechNext
    & $act | Out-Null
    $got = @(SpeechFrom $cur)
    $gotJ = $got -join '|'
    $expJ = $expected -join '|'
    Check $name ($gotJ -eq $expJ) "expected '$expJ', got '$gotJ'"
}

Write-Host "screens-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

# --- clean slate, then open the test menu: screen name + initial landing ---
Cmd 'call vwa_dev_test_menu off' | Out-Null
Start-Sleep -Milliseconds 200
CheckSpeech 'menu opens: screen name, then full first-focus path' {
    $r = Cmd 'call vwa_dev_test_menu on'
    Check 'test menu on reply' ($r.result -eq 'test menu on') ($r | ConvertTo-Json -Compress)
} @('Test menu', 'Alpha, button, 1 of 5')

$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'ui category live with menu open' (($s.liveCategories -join ',') -eq 'ui,global') ($s.liveCategories -join ',')
$stackNames = @($s.stack | ForEach-Object { $_.name })
Check 'test menu on the stack' ($stackNames -contains 'vwa-test-menu') ($stackNames -join ',')
$actionKeys = @($s.actions | ForEach-Object { $_.key })
Check 'nav actions registered' (
    $actionKeys -contains 'nav-up' -and $actionKeys -contains 'nav-down' -and
    $actionKeys -contains 'nav-activate' -and $actionKeys -contains 'nav-next-stop') ($actionKeys -join ',')

# --- /gui/mod: the interpreted view ---
$m = Invoke-RestMethod "$base/gui/mod" -TimeoutSec 8
Check 'gui.mod focused screen' ($m.focused -eq 'vwa-test-menu') $m.focused
Check 'gui.mod focus key' ($m.focusKey -eq 'item:Alpha') $m.focusKey
Check 'gui.mod node count' ($m.nodes.Count -eq 10) $m.nodes.Count
$alpha = $m.nodes | Where-Object { $_.skey -eq 'item:Alpha' }
Check 'gui.mod alpha wired down to beta' ($alpha.edges.down -eq 'item:Beta') ($alpha.edges | ConvertTo-Json -Compress)
Check 'gui.mod alpha has backing ref' ($alpha.hasRef -eq $true) $alpha.hasRef
$ok = $m.nodes | Where-Object { $_.skey -eq 'ok' }
Check 'gui.mod row position stamped' ($ok.pos[0] -eq 1 -and $ok.pos[1] -eq 2) ($ok.pos -join '/')
$one = $m.nodes | Where-Object { $_.skey -eq 'one' }
Check 'gui.mod context on parent chain' (($one.parents -join ',') -eq 'ctx:/Extras') ($one.parents -join ',')
Check 'gui.mod stops' ($one.stop -eq 'extras' -and $alpha.stop -eq 'main') "$($alpha.stop)/$($one.stop)"

# --- arrows: sibling moves, one announcement each ---
CheckSpeech 'down to Beta' { Fire 'nav-down' } @('Beta, button, 2 of 5')
CheckSpeech 'down to Gamma' { Fire 'nav-down' } @('Gamma, button, 3 of 5')
CheckSpeech 'down to Sound toggle' { Fire 'nav-down' } @('Sound, toggle, off, 4 of 5')

# --- live part: toggle flips speak just the changed value ---
CheckSpeech 'toggle on speaks just the value' { Fire 'nav-activate' } @('on')
CheckSpeech 'toggle off speaks just the value' { Fire 'nav-activate' } @('off')

# --- slider: left/right adjust instead of navigating ---
CheckSpeech 'down to Volume slider' { Fire 'nav-down' } @('Volume, slider, 5, 5 of 5')
CheckSpeech 'right adjusts up' { Fire 'nav-right' } @('6')
CheckSpeech 'left adjusts down' { Fire 'nav-left' } @('5')

# --- a two-item row: horizontal moves, in-row positions, edge silence ---
CheckSpeech 'down to OK' { Fire 'nav-down' } @('OK, button, 1 of 2')
CheckSpeech 'right to Cancel' { Fire 'nav-right' } @('Cancel, button, 2 of 2')
CheckSpeech 'right at the row edge stays silent' { Fire 'nav-right' } @()
CheckSpeech 'activate Cancel' { Fire 'nav-activate' } @('Cancel pressed')

# --- Tab stops: entering a context reads it outermost-first; memory ---
CheckSpeech 'Tab enters Extras stop' { Fire 'nav-next-stop' } @('Extras, One, button, 1 of 3')
CheckSpeech 'down to Two' { Fire 'nav-down' } @('Two, button, 2 of 3')
CheckSpeech 'down to Status label' { Fire 'nav-down' } @('Status, 3 of 3')
CheckSpeech 'activate on a label says no action' { Fire 'nav-activate' } @('No action')
CheckSpeech 'Tab wraps to main stop, remembered Cancel' { Fire 'nav-next-stop' } @('Cancel, button, 2 of 2')
CheckSpeech 'Shift+Tab back to Extras, remembered Status' { Fire 'nav-prev-stop' } @('Extras, Status, 3 of 3')

# --- focus recovery: survivor fallback when the focused node vanishes ---
CheckSpeech 'dev focus jump to Beta' { Cmd 'call vwa_dev_menu_focus item:Beta' } @('Beta, button, 2 of 5')
CheckSpeech 'hiding Beta falls back to nearest survivor' {
    Cmd 'set global.vwaDevMenu.hideBeta true'
} @('Alpha, button, 1 of 4')
CheckSpeech 'Beta returning does not steal focus or speak' {
    Cmd 'set global.vwaDevMenu.hideBeta false'
} @()

# --- focus recovery: tier-1 reference follow across a structural rename ---
CheckSpeech 'dev focus jump to Gamma' { Cmd 'call vwa_dev_menu_focus item:Gamma' } @('Gamma, button, 3 of 5')
CheckSpeech 'rename: focus follows the backing ref, announces new label' {
    Cmd 'call vwa_dev_menu_rename Gamma GammaX'
} @('GammaX, button, 3 of 5')

# --- exclusive screens: a covering hard modal blocks lower categories ---
CheckSpeech 'covering test screen pushes silently' { Cmd 'call vwa_dev_test_screen combat' } @()
$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'covered menu still contributes ui' (($s.liveCategories -join ',') -eq 'combat,ui,global') ($s.liveCategories -join ',')
Cmd 'call vwa_dev_test_screen combat!' | Out-Null
Start-Sleep -Milliseconds 200
$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'exclusive modal blocks ui below it' (($s.liveCategories -join ',') -eq 'combat,global') ($s.liveCategories -join ',')
CheckSpeech 'uncovering re-announces the menu and restores focus' {
    Cmd 'call vwa_dev_test_screen none'
} @('Test menu', 'GammaX, button, 3 of 5')

# --- close: focus falls to the real main-menu screen underneath (session
#     5), which re-announces and keeps ui live. Its remembered landing
#     varies with profile and prior smokes, so match shape, not text. ---
$cur = SpeechNext
Cmd 'call vwa_dev_test_menu off' | Out-Null
$got = @(SpeechFrom $cur)
Check 'menu off uncovers the main menu' (
    $got.Count -eq 2 -and $got[1] -match ', button, \d+ of \d+$') ($got -join '|')
$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'ui stays live via the main menu' (($s.liveCategories -join ',') -eq 'ui,global') ($s.liveCategories -join ',')
$m = Invoke-RestMethod "$base/gui/mod" -TimeoutSec 8
Check 'gui.mod focus back on the main menu' ($m.focused -eq 'main-menu' -and $m.nodes.Count -ge 5) ($m.focused)
Check 'pump alive at end' ((Cmd 'ping') -eq 'pong') 'no pong'

Write-Host ""
if ($fails -gt 0) {
    Write-Host "screens-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "screens-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
