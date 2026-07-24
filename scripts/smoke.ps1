# smoke.ps1 - THE screen smoke (session 11 redesign). All assertions run
# inside the game: `call vwa_dev_selftest` unit-tests the pure modules and
# `call vwa_dev_walk_start <screen>` sweeps every node of the focused
# screen, verifying real speech against a fresh live resolve (scrVwaTest).
# This script is deliberately dumb: it opens screens, starts walks, polls
# status, runs a few flow checks whose expectations are read live from the
# game, and diffs the mod log for new ERROR lines. It never composes an
# expected speech string - that rule is what keeps intentional wording
# changes from breaking the smoke (the session-10 lesson).
#
# Needs a live dev build at the main menu (run-game.ps1 -WaitMainMenu).
# Companions: drive-smoke.ps1 (dev driver plumbing), input-smoke.ps1
# (input layer + suppression).
#
# Usage: powershell -NoProfile -File scripts\smoke.ps1

param(
    [int]$Port = $(if ($env:VWACCESS_DEV_PORT) { [int]$env:VWACCESS_DEV_PORT } else { 8772 })
)

$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$checks = 0
$fails = 0
$gameChecks = 0

function Cmd([string]$body) {
    return Invoke-RestMethod -Uri "$base/cmd" -Method Post -Body $body -TimeoutSec 8
}

function Fire([string]$actionKey) {
    return Invoke-RestMethod -Uri "$base/input" -Method Post -Body $actionKey -TimeoutSec 8
}

function GuiMod {
    return Invoke-RestMethod "$base/gui/mod" -TimeoutSec 8
}

function SpeechNext {
    return (Invoke-RestMethod "$base/speech?since=0" -TimeoutSec 5).next
}

function SpeechFrom([uint64]$cursor) {
    Start-Sleep -Milliseconds 300
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

# Park focus on a node of the FOCUSED screen via the graph's nextMove.
function FocusNode([string]$screenKey, [string]$skey) {
    $screens = Cmd 'get global.vwaScreens'
    $idx = -1
    for ($i = 0; $i -lt $screens.Count; $i++) {
        if ($screens[$i].key -eq $screenKey) { $idx = $i }
    }
    if ($idx -lt 0) { throw "screen $screenKey not registered" }
    Cmd "set global.vwaScreens[$idx].navState.nextMove $skey" | Out-Null
    Start-Sleep -Milliseconds 300
}

# Wait until a screen is focused with a settled render (focusKey non-null,
# so the one-tick landing defer has passed).
function WaitFocused([string]$key, [int]$tries = 40) {
    for ($i = 0; $i -lt $tries; $i++) {
        $m = GuiMod
        if ($m.focused -eq $key -and $m.focusKey) { return $m }
        Start-Sleep -Milliseconds 250
    }
    throw "screen $key never became focused (last: $($m.focused))"
}

# Start an in-game walk of the focused screen and poll it to completion.
# Every check inside the walk was computed in GML; this just reports.
function Walk([string]$screenKey) {
    $r = Cmd "call vwa_dev_walk_start $screenKey"
    $s = $null
    for ($i = 0; $i -lt 480; $i++) {
        Start-Sleep -Milliseconds 250
        $s = (Cmd 'call vwa_dev_walk_status').result
        if ($s.done) { break }
    }
    Check "walk ${screenKey}: completed" ([bool]$s.done) "stuck in phase $($s.phase), $($s.nodesDone)/$($s.nodes) nodes"
    $f = @($s.failures | Where-Object { $_ })
    Check "walk ${screenKey}: $($s.checks) in-game checks over $($s.nodes) nodes" ($f.Count -eq 0) "$($f.Count) failures"
    foreach ($line in $f) {
        Write-Host "       $line" -ForegroundColor Red
    }
    $script:gameChecks += $s.checks
    return $s
}

function ModLogErrorCount {
    # 'injected test fault' marks ERROR lines a test wrote ON PURPOSE to
    # prove a sanctioned logging path fires (the input watchdog fault, the
    # selftest's section quarantine). Real failures never carry the marker.
    $t = Invoke-RestMethod "$base/log?which=mod&lines=6000" -TimeoutSec 8
    return @(($t -split "`n") | Where-Object {
        $_ -match 'ERROR' -and $_ -notmatch 'injected test fault'
    }).Count
}

Write-Host "smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

$errBase = ModLogErrorCount

# --- in-game selftest: the pure modules on constructed fixtures ---
$st = (Cmd 'call vwa_dev_selftest').result
$sf = @($st.failures | Where-Object { $_ })
# $st.checks -gt 0 guards the ERROR-reply case: a crashed selftest returns
# text, .result is null, and an empty failure list would pass silently.
Check "selftest: $($st.checks) checks" ($st.checks -gt 0 -and $sf.Count -eq 0) "$($sf.Count) failures (checks: $($st.checks))"
foreach ($line in $sf) {
    Write-Host "       $line" -ForegroundColor Red
}
$gameChecks += $st.checks

# --- announcements popup: the walker's biggest real line-review surface
# (one control per boot announcement, body lines as tooltip parts). Spawn
# it when the boot one is already gone so this coverage is deterministic,
# then dismiss through the real path.
$m = GuiMod
if ($m.focused -ne 'announcements') {
    Cmd 'call vwa_dev_spawn oGameStartMessage' | Out-Null
}
WaitFocused 'announcements' | Out-Null
Walk 'announcements' | Out-Null
for ($i = 0; $i -lt 3 -and (GuiMod).focused -eq 'announcements'; $i++) {
    Cmd 'call vwa_dev_dismiss_start_popup' | Out-Null
    Start-Sleep -Milliseconds 500
}
$m = WaitFocused 'main-menu'

# --- the main menu ---
Walk 'main-menu' | Out-Null

# --- the synthetic test screens: rich known topologies end to end ---
Cmd 'call vwa_dev_test_menu on' | Out-Null
WaitFocused 'vwa-test-menu' | Out-Null
Walk 'vwa-test-menu' | Out-Null
Cmd 'call vwa_dev_test_menu off' | Out-Null
WaitFocused 'main-menu' | Out-Null

Cmd 'call vwa_dev_test_submenu on' | Out-Null
WaitFocused 'vwa-test-submenu' | Out-Null
Walk 'vwa-test-submenu' | Out-Null
Cmd 'call vwa_dev_test_submenu off' | Out-Null
WaitFocused 'main-menu' | Out-Null

# --- settings, opened through the real mod path ---
FocusNode 'main-menu' 'mm:label_settings'
Fire 'nav-activate' | Out-Null
WaitFocused 'menu-settings' | Out-Null
Walk 'menu-settings' | Out-Null
FocusNode 'menu-settings' 'bm:label_back'
Fire 'nav-activate' | Out-Null
$m = WaitFocused 'main-menu'
Check 'settings closed, focus restored to the Settings entry' ($m.focusKey -eq 'mm:label_settings') $m.focusKey

# --- commander select: New Game, walk, flows, leave ---
FocusNode 'main-menu' 'mm:label_newGame'
Fire 'nav-activate' | Out-Null
$m = WaitFocused 'commander-select'
Check 'commander select opens on a commander row' ($m.focusKey -like 'cmdr:*') $m.focusKey
Walk 'commander-select' | Out-Null

# Text edit handoff (state checks; the edit layer's speech needs physical
# keys, which no script can press).
FocusNode 'commander-select' 'cmdr-name'
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 300
$ts = (Cmd 'call vwa_dev_text_state').result
Check 'Enter enters text edit mode' ([bool]$ts.active -and [bool]$ts.flag) ($ts | ConvertTo-Json -Compress)
Cmd 'call vwa_dev_type abc' | Out-Null
$ts = (Cmd 'call vwa_dev_text_state').result
Check 'typed buffer survives mid-edit (type-ahead drain stays off)' ($ts.kbString -like '*abc') $ts.kbString
Fire 'text-commit' | Out-Null
Start-Sleep -Milliseconds 300
$ts = (Cmd 'call vwa_dev_text_state').result
Check 'text-commit leaves edit mode' (-not [bool]$ts.active) ($ts | ConvertTo-Json -Compress)
$m = GuiMod
Check 'screen survived the edit exit' ($m.focused -eq 'commander-select') $m.focused

# Randomize speaks the fresh name (expectation read back from the game).
FocusNode 'commander-select' 'cmdr-randomize'
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 300
$newName = (Cmd 'get oCommanderNameBox.text')
$got = @(SpeechFrom $cur)
Check 'randomize speaks the fresh name' ($got.Count -ge 1 -and $got[-1] -eq $newName) ($got -join '|')

# Auto-paging (session 12): the FULL commander list is in the graph with
# no pager nodes; focusing an off-page row flips the game's own page
# (ensure-visible). Expectations read live: the row set from the render,
# the page count from the game's own page controls.
$m = GuiMod
$rows = @($m.nodes | Where-Object { $_.skey -like 'cmdr:*' })
$pages = Cmd 'get oUICommanderList.pageControls.maxPage'
$pagers = @($m.nodes | Where-Object { $_.skey -like 'cmdr-page-*' })
Check 'no pager nodes in the graph' ($pagers.Count -eq 0) ($pagers.skey -join '|')
# Full-set coverage is proven by the flip below: the LAST graph row lives
# on the game's LAST page, so rows necessarily span every page (counting
# the game-side array here trips the PS 5.1 nested-value collapse).
FocusNode 'commander-select' $rows[-1].skey
$pg = Cmd 'get oUICommanderList.currPageIndex'
Check 'focusing the last commander flips the game to the last page' ($pg -eq ($pages - 1)) "page index $pg of $pages pages"
FocusNode 'commander-select' $rows[0].skey
$pg = Cmd 'get oUICommanderList.currPageIndex'
Check 'focusing the first commander flips back to page one' ($pg -eq 0) "page index $pg"

# --- ship select: confirm the commander, walk, cycle a hull, the list ---
FocusNode 'commander-select' 'cmdr-confirm'
Fire 'nav-activate' | Out-Null
$m = WaitFocused 'ship-select'
Check 'ship select opens on the hull cycler' ($m.focusKey -eq 'ship-cycler') $m.focusKey
Walk 'ship-select' | Out-Null

# The ship name's commit/cancel split (session 12): Enter runs the field's
# own set_name, Escape discards. Expectations read back from the game; the
# injected value is state, not a speech expectation.
FocusNode 'ship-select' 'ship-name'
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
Cmd 'set oTextField.text "VWA Smoke"' | Out-Null
Fire 'text-commit' | Out-Null
Start-Sleep -Milliseconds 300
$nm = Cmd 'get oHull.customHullName'
Check 'ship name commit writes the custom hull name' ($nm -eq 'VWA Smoke') $nm
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
Cmd 'set oTextField.text "Discarded"' | Out-Null
Fire 'text-cancel' | Out-Null
Start-Sleep -Milliseconds 300
$nm = Cmd 'get oHull.customHullName'
Check 'ship name cancel leaves the custom hull name untouched' ($nm -eq 'VWA Smoke') $nm
$ts = (Cmd 'call vwa_dev_text_state').result
Check 'text-cancel leaves edit mode' (-not [bool]$ts.active) ($ts | ConvertTo-Json -Compress)
Cmd 'call oShipMenu_shipName.reset_name' | Out-Null

# One hull cycle: exactly one utterance (the identity of the new hull; the
# raw-arrow consume means no double step), then a second walk on the OTHER
# hull proves the cross-room rebuild + focus reconcile.
FocusNode 'ship-select' 'ship-cycler'
$cur = SpeechNext
Fire 'nav-right' | Out-Null
Start-Sleep -Milliseconds 1200
$got = @(SpeechFrom $cur)
Check 'hull cycle speaks exactly one identity line' ($got.Count -eq 1) ($got -join '|')
$m = GuiMod
Check 'focus stays on the cycler across the room switch' ($m.focusKey -eq 'ship-cycler') $m.focusKey
Walk 'ship-select' | Out-Null

# The ship list overlay: open through the real button, walk, activate a
# hull; the overlay closes itself and ship select regains focus.
FocusNode 'ship-select' 'ship-view-list'
Fire 'nav-activate' | Out-Null
WaitFocused 'ship-list' | Out-Null
Walk 'ship-list' | Out-Null
FocusNode 'ship-list' 'hull:0'
Fire 'nav-activate' | Out-Null
$m = WaitFocused 'ship-select'
Check 'hull activation returns focus to ship select' ($m.focused -eq 'ship-select') $m.focused

# Leave through the real Main Menu button.
FocusNode 'ship-select' 'ship-main-menu'
Fire 'nav-activate' | Out-Null
WaitFocused 'main-menu' | Out-Null

# --- the framework survived all of it ---
$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'input watchdog never tripped' (-not $s.watchdogTripped) $s.watchdogTripped
$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'pump alive at end' ($h.status -eq 'ok') $h.status
$errNow = ModLogErrorCount
Check 'no new ERROR lines in the mod log' ($errNow -le $errBase) "$errBase before, $errNow after"

Write-Host ''
if ($fails -gt 0) {
    Write-Host "smoke: $fails of $checks runner checks FAILED ($gameChecks in-game checks)" -ForegroundColor Red
    exit 1
}
Write-Host "smoke: all $checks runner checks passed ($gameChecks in-game checks)" -ForegroundColor Green
exit 0
