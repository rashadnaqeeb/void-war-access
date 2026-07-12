# screens-smoke.ps1 - end-to-end regression check for the framework core
# (session 4): screen stack, control graph, navigator, announcer.
#
# Drives the synthetic dev test menu (vwa_dev_test_menu) through POST /input
# and asserts the EXACT /speech transcript: screen-name announcement, path
# entry (contexts outermost first), sibling moves, auto "n of m", live-part
# re-speak (toggle/slider), Tab-stop cycling with remembered positions,
# no-action feedback, focus recovery (survivor fallback and tier-1
# reference follow), silence where nothing should speak, and the submenu
# model (vwa_dev_test_submenu): header discovery with item counts, enter by
# right arrow and Enter, a focused slider keeping left/right for itself,
# boundary dive, left/up exits, header subtree skip, nested bottom-exit
# recursion, and the Ctrl+up/down jumps (boundary-arrow equivalents).
# Also checks /gui/mod. Assumes a launcher (run-game.ps1) is already up at
# the main menu; drives over HTTP only. Exits nonzero on any failed check.
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
} @('Test menu', 'Alpha, button, 1 of 6')

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

# --- arrows: sibling moves, one announcement each. The vertical count (6)
#     includes the OK/Cancel row as ONE entry: a multi-item row is a group
#     that lands once in the vertical list. ---
CheckSpeech 'down to Beta' { Fire 'nav-down' } @('Beta, button, 2 of 6')
CheckSpeech 'down to Gamma' { Fire 'nav-down' } @('Gamma, button, 3 of 6')
CheckSpeech 'down to Sound toggle' { Fire 'nav-down' } @('Sound, toggle, off, 4 of 6')

# --- live part: toggle flips speak just the changed value ---
CheckSpeech 'toggle on speaks just the value' { Fire 'nav-activate' } @('on')
CheckSpeech 'toggle off speaks just the value' { Fire 'nav-activate' } @('off')

# --- slider: left/right adjust instead of navigating ---
CheckSpeech 'down to Volume slider' { Fire 'nav-down' } @('Volume, slider, 5, 5 of 6')
CheckSpeech 'right adjusts up' { Fire 'nav-right' } @('6')
CheckSpeech 'left adjusts down' { Fire 'nav-left' } @('5')

# --- a two-item row: entering announces the group (label + vertical
#     position), then the member with its in-row position; moves within the
#     row stay group-silent; edges are silent ---
CheckSpeech 'down to OK' { Fire 'nav-down' } @("Actions, 6 of 6`nOK, button, 1 of 2")
CheckSpeech 'right to Cancel' { Fire 'nav-right' } @('Cancel, button, 2 of 2')
CheckSpeech 'right at the row edge stays silent' { Fire 'nav-right' } @()
CheckSpeech 'activate Cancel' { Fire 'nav-activate' } @('Cancel pressed')

# --- Tab stops: entering a context reads it outermost-first; memory ---
CheckSpeech 'Tab enters Extras stop' { Fire 'nav-next-stop' } @("Extras`nOne, button, 1 of 3")
CheckSpeech 'down to Two' { Fire 'nav-down' } @('Two, button, 2 of 3')
CheckSpeech 'down to Status label' { Fire 'nav-down' } @('Status, 3 of 3')
CheckSpeech 'activate on a label says no action' { Fire 'nav-activate' } @('No action')
CheckSpeech 'Tab wraps to main stop, remembered Cancel' { Fire 'nav-next-stop' } @("Actions, 6 of 6`nCancel, button, 2 of 2")
CheckSpeech 'Shift+Tab back to Extras, remembered Status' { Fire 'nav-prev-stop' } @("Extras`nStatus, 3 of 3")

# --- focus recovery: survivor fallback when the focused node vanishes ---
CheckSpeech 'dev focus jump to Beta' { Cmd 'call vwa_dev_menu_focus item:Beta' } @('Beta, button, 2 of 6')
CheckSpeech 'hiding Beta falls back to nearest survivor' {
    Cmd 'set global.vwaDevMenu.hideBeta true'
} @('Alpha, button, 1 of 5')
CheckSpeech 'Beta returning does not steal focus or speak' {
    Cmd 'set global.vwaDevMenu.hideBeta false'
} @()

# --- focus recovery: tier-1 reference follow across a structural rename ---
CheckSpeech 'dev focus jump to Gamma' { Cmd 'call vwa_dev_menu_focus item:Gamma' } @('Gamma, button, 3 of 6')
CheckSpeech 'rename: focus follows the backing ref, announces new label' {
    Cmd 'call vwa_dev_menu_rename Gamma GammaX'
} @('GammaX, button, 3 of 6')

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
} @('Test menu', 'GammaX, button, 3 of 6')

# --- submenus (session 8): the synthetic submenu screen covers the test
#     menu. Level 0 is Intro / Audio / Video / Outro (4 vertical entries);
#     Audio holds Master (slider) + Music, Video holds Fullscreen + the
#     nested Advanced (Gamma + Delta) as its LAST child. ---
CheckSpeech 'submenu screen opens' {
    $r = Cmd 'call vwa_dev_test_submenu on'
    Check 'submenu test on reply' ($r.result -eq 'submenu test screen on') ($r | ConvertTo-Json -Compress)
} @('Submenu test', 'Intro, button, 1 of 4')
CheckSpeech 'down discovers the Audio header with its count' { Fire 'nav-down' } @('Audio, submenu, 2 items, 2 of 4')
CheckSpeech 'right enters, landing on the first child' { Fire 'nav-right' } @('Master, slider, 5, 1 of 2')
CheckSpeech 'left on a slider adjusts instead of exiting' { Fire 'nav-left' } @('4')
CheckSpeech 'down to Music' { Fire 'nav-down' } @('Music, button, 2 of 2')
CheckSpeech 'down off the bottom dives into the next submenu' { Fire 'nav-down' } @("Video, submenu, 2 items, 3 of 4`nFullscreen, toggle, off, 1 of 2")
CheckSpeech 'left exits to the enclosing header' { Fire 'nav-left' } @('Video, submenu, 2 items, 3 of 4')
CheckSpeech 'Enter on a header enters like right arrow' { Fire 'nav-activate' } @('Fullscreen, toggle, off, 1 of 2')
CheckSpeech 'up from the first child lands on the header' { Fire 'nav-up' } @('Video, submenu, 2 items, 3 of 4')
CheckSpeech 'up at header level shows the sibling header' { Fire 'nav-up' } @('Audio, submenu, 2 items, 2 of 4')
CheckSpeech 'down from a header skips its subtree' { Fire 'nav-down' } @('Video, submenu, 2 items, 3 of 4')
CheckSpeech 'left on a top-level header stays silent' { Fire 'nav-left' } @()
CheckSpeech 're-enter Video' { Fire 'nav-right' } @('Fullscreen, toggle, off, 1 of 2')
CheckSpeech 'down discovers the nested Advanced header' { Fire 'nav-down' } @('Advanced, submenu, 2 items, 2 of 2')
CheckSpeech 'right enters the nested submenu' { Fire 'nav-right' } @('Gamma, button, 1 of 2')
CheckSpeech 'down to Delta' { Fire 'nav-down' } @('Delta, button, 2 of 2')
CheckSpeech 'bottom exit recurses through both levels to Outro' { Fire 'nav-down' } @('Outro, button, 4 of 4')
CheckSpeech 'up from a plain sibling shows the Video header' { Fire 'nav-up' } @('Video, submenu, 2 items, 3 of 4')

# --- Ctrl+up/down submenu jumps: both land exactly where the plain arrow
#     at the enclosing submenu's boundary lands. ---
CheckSpeech 'Ctrl+Up on a top-level header acts like plain up' { Fire 'nav-jump-up' } @('Audio, submenu, 2 items, 2 of 4')
CheckSpeech 're-enter Audio for the jump checks' { Fire 'nav-right' } @('Master, slider, 4, 1 of 2')
CheckSpeech 'Ctrl+Down exits like bottom flow, diving into Video' { Fire 'nav-jump-down' } @("Video, submenu, 2 items, 3 of 4`nFullscreen, toggle, off, 1 of 2")
CheckSpeech 'down to the nested header for the climb' { Fire 'nav-down' } @('Advanced, submenu, 2 items, 2 of 2')
CheckSpeech 'enter the nested submenu for the climb' { Fire 'nav-right' } @('Gamma, button, 1 of 2')
CheckSpeech 'Ctrl+Up jumps to the nested header' { Fire 'nav-jump-up' } @('Advanced, submenu, 2 items, 2 of 2')
CheckSpeech 'Ctrl+Up from a nested header climbs one level out' { Fire 'nav-jump-up' } @('Video, submenu, 2 items, 3 of 4')
CheckSpeech 'back inside Video' { Fire 'nav-right' } @('Fullscreen, toggle, off, 1 of 2')
CheckSpeech 'down to the nested header for the escape' { Fire 'nav-down' } @('Advanced, submenu, 2 items, 2 of 2')
CheckSpeech 'Ctrl+Down from a nested header escapes the enclosing submenu' { Fire 'nav-jump-down' } @('Outro, button, 4 of 4')
CheckSpeech 'Ctrl+Down on a plain top-level element is silent' { Fire 'nav-jump-down' } @()
CheckSpeech 'Ctrl+Up on a plain top-level element is silent' { Fire 'nav-jump-up' } @()

$m = Invoke-RestMethod "$base/gui/mod" -TimeoutSec 8
Check 'gui.mod submenu screen focused' ($m.focused -eq 'vwa-test-submenu') $m.focused
Check 'gui.mod submenu node count' ($m.nodes.Count -eq 10) $m.nodes.Count
$audio = $m.nodes | Where-Object { $_.skey -eq 'sm:audio' }
Check 'gui.mod header typed submenu' ($audio.type -eq 'submenu') $audio.type
Check 'gui.mod header right enters first child' ($audio.edges.right -eq 'master') ($audio.edges | ConvertTo-Json -Compress)
$master = $m.nodes | Where-Object { $_.skey -eq 'master' }
Check 'gui.mod first child up and left go to the header' (
    $master.edges.up -eq 'sm:audio' -and $master.edges.left -eq 'sm:audio') ($master.edges | ConvertTo-Json -Compress)
$music = $m.nodes | Where-Object { $_.skey -eq 'music' }
Check 'gui.mod last child dives into the sibling submenu' ($music.edges.down -eq 'fullscreen') ($music.edges | ConvertTo-Json -Compress)
$delta = $m.nodes | Where-Object { $_.skey -eq 'delta' }
Check 'gui.mod nested bottom exit recurses to Outro' ($delta.edges.down -eq 'outro') ($delta.edges | ConvertTo-Json -Compress)
$gamma = $m.nodes | Where-Object { $_.skey -eq 'gamma' }
Check 'gui.mod nested parent chain' (($gamma.parents -join ',') -eq 'sm:video,sm:adv') ($gamma.parents -join ',')
Check 'gui.mod jump edges: header up, enclosing exit down' (
    $gamma.edges.'jump-up' -eq 'sm:adv' -and $gamma.edges.'jump-down' -eq 'outro') ($gamma.edges | ConvertTo-Json -Compress)

CheckSpeech 'submenu screen off restores the test menu' {
    Cmd 'call vwa_dev_test_submenu off'
} @('Test menu', 'GammaX, button, 3 of 6')

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
