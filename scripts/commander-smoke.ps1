# commander-smoke.ps1 - end-to-end regression check for the commander
# select screen (session 10): the New Game entry, the settled landing (the
# one-tick defer after a screen gains focus), the crew sheet lines, the
# alt-arrow line review with boundary words, the name textfield handoff to
# the text edit layer, the randomize button's live feedback, page flipping
# with live page readout, and the Resonance node. Profile-agnostic:
# expected speech derives from /gui/mod lines (the resolver runs on the
# live game) and from the game's own label globals; nothing assumes which
# commanders are unlocked. Leaves the game back at the main menu via
# vwa_dev_close_commander_select (the Escape branch mirror - synthetic
# Escape cannot be pressed).
#
# Usage: powershell -NoProfile -File scripts\commander-smoke.ps1

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
    Start-Sleep -Milliseconds 250
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

function CheckSpeech([string]$name, [scriptblock]$act, [string[]]$expected) {
    $cur = SpeechNext
    & $act | Out-Null
    $got = @(SpeechFrom $cur)
    $gotJ = $got -join '|'
    $expJ = $expected -join '|'
    Check $name ($gotJ -eq $expJ) "expected '$expJ', got '$gotJ'"
}

# The spoken text for landing on a /gui/mod node (vwa_speak joins parts
# with ", " within a line and lines with newlines).
function NodeLine($node) {
    $ls = @($node.lines | ForEach-Object { @($_) -join ', ' })
    return ($ls -join "`n")
}

function GuiMod {
    return Invoke-RestMethod "$base/gui/mod" -TimeoutSec 8
}

function NodeByKey($m, [string]$skey) {
    return ($m.nodes | Where-Object { $_.skey -eq $skey } | Select-Object -First 1)
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

Write-Host "commander-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

$m = GuiMod
if ($m.focused -ne 'main-menu') {
    throw "commander-smoke needs the game at the main menu (focused: $($m.focused))"
}

# --- enter: New Game -> commander select ---
$selectLabel = (Cmd 'get global.label_selectCommander')
$cur = SpeechNext
FocusNode 'main-menu' 'mm:label_newGame'
$cur = SpeechNext   # discard the focus-move announcement
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 1500   # room change + one-tick landing defer + settle

$m = GuiMod
Check 'commander select focused' ($m.focused -eq 'commander-select') $m.focused
Check 'focus starts on a commander row' ($m.focusKey -like 'cmdr:*') $m.focusKey

# The landing must equal the SETTLED row lines (catches the defer
# regression: announcing on the screen's first tick reads the oCrew
# parent's defaults before the crew's first Step).
$row = NodeByKey $m $m.focusKey
$got = @(SpeechFrom $cur)
Check 'entry speech: screen name then settled landing' (
    $got.Count -eq 2 -and $got[0] -eq $selectLabel -and $got[1] -eq (NodeLine $row)) ($got -join '|')

# --- structure: rows mirror the game's page ---
$ct = Cmd 'get oUICommanderList.commanderCt'
$rowNodes = @($m.nodes | Where-Object { $_.skey -like 'cmdr:*' })
Check 'one row per page entry' ($rowNodes.Count -eq $ct) "$($rowNodes.Count) vs commanderCt $ct"
foreach ($rn in $rowNodes) {
    $hiddenLabel = (Cmd 'call vwa_t vwa--commander-hidden').result
    if ($rn.lines[0][0] -eq $hiddenLabel) {
        Check "hidden row $($rn.skey) has no sheet" ($rn.lines.Count -eq 1) $rn.lines.Count
    } else {
        Check "row $($rn.skey) carries sheet lines" ($rn.lines.Count -gt 1) $rn.lines.Count
    }
}
$pageNodes = @('cmdr-page-prev', 'cmdr-page-next', 'cmdr-resonance') |
    ForEach-Object { NodeByKey $m $_ }
Check 'page and resonance nodes present' (@($pageNodes | Where-Object { $_ }).Count -eq 3) 'missing'

# --- alt-arrow line review over the focused row ---
$rowLines = @($row.lines | ForEach-Object { @($_) -join ', ' })
if ($rowLines.Count -ge 2) {
    CheckSpeech 'alt-down speaks line 2' { Fire 'nav-line-next' } @($rowLines[1])
    CheckSpeech 'alt-up back to line 1' { Fire 'nav-line-prev' } @($rowLines[0])
    $topWord = (Cmd 'call vwa_t vwa--line-top').result
    CheckSpeech 'alt-up past the top says the boundary word' { Fire 'nav-line-prev' } @($topWord)
    $lastIdx = $rowLines.Count - 1
    CheckSpeech 'End of review: step to the last line' {
        for ($i = 0; $i -lt $lastIdx; $i++) { Fire 'nav-line-next' | Out-Null; Start-Sleep -Milliseconds 120 }
    } @($rowLines[1..$lastIdx])
    $bottomWord = (Cmd 'call vwa_t vwa--line-bottom').result
    CheckSpeech 'alt-down past the bottom says the boundary word' { Fire 'nav-line-next' } @($bottomWord)
} else {
    Check 'focused row has sheet lines to review' $false ($rowLines -join '|')
}

# --- name stop: textfield handoff and randomize feedback ---
$m = GuiMod
$nameNode = NodeByKey $m 'cmdr-name'
CheckSpeech 'Tab lands on the name field' { Fire 'nav-next-stop' } @((NodeLine $nameNode))
$editing = (Cmd 'call vwa_t vwa--text-editing').result
$boxText = (Cmd 'get oCommanderNameBox.text')
CheckSpeech 'Enter starts editing' { Fire 'nav-activate' } @("$editing, $boxText")
$closed = (Cmd 'call vwa_t vwa--text-edit-closed').result
CheckSpeech 'text-exit closes the edit' { Fire 'text-exit' } @("$closed, $boxText")
$m = GuiMod
Check 'screen survived the edit exit' ($m.focused -eq 'commander-select') $m.focused

$cur = SpeechNext
Fire 'nav-down' | Out-Null
Start-Sleep -Milliseconds 300
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$newName = (Cmd 'get oCommanderNameBox.text')
$got = @(SpeechFrom $cur)
Check 'randomize speaks the fresh name' (
    $got.Count -eq 2 -and $got[1] -eq $newName) ($got -join '|')

# --- page flip: live page readout as activation feedback ---
# (page count from the counter's own scalar: returning nested arrays like
# pageData through a PowerShell function collapses them)
$pages = Cmd 'get oUICommanderList.pageControls.maxPage'
$pageOf = (Cmd 'call vwa_t vwa--page-of').result
$page2 = $pageOf -replace '\{n\}', '2' -replace '\{m\}', "$pages"
$page1 = $pageOf -replace '\{n\}', '1' -replace '\{m\}', "$pages"
FocusNode 'commander-select' 'cmdr-page-next'
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
$got = @(SpeechFrom $cur)
Check 'page next speaks the new page' ($got.Count -ge 1 -and $got[0] -eq $page2) ($got -join '|')
FocusNode 'commander-select' 'cmdr-page-prev'
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
$got = @(SpeechFrom $cur)
Check 'page prev speaks page one' ($got.Count -ge 1 -and $got[0] -eq $page1) ($got -join '|')

# --- resonance node ---
$m = GuiMod
$res = NodeByKey $m 'cmdr-resonance'
$bal = (Cmd 'get global.currMetaCurrency')
Check 'resonance value is the live balance' ($res.lines[0] -contains "$bal") ($res.lines[0] -join ',')
CheckSpeech 'focus the resonance readout' {
    FocusNode 'commander-select' 'cmdr-resonance'
} @((NodeLine $res))

# --- leave: the Escape-branch mirror puts us back at the main menu ---
$cur = SpeechNext
$r = Cmd 'call vwa_dev_close_commander_select'
Check 'close helper replied' ($r.result.closed -eq $true) ($r | ConvertTo-Json -Compress)
Start-Sleep -Milliseconds 1500
$m = GuiMod
Check 'back at the main menu' ($m.focused -eq 'main-menu') $m.focused

$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
Check 'input watchdog never tripped' (-not $s.watchdogTripped) $s.watchdogTripped
$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'pump alive at end' ($h.status -eq 'ok') $h.status

Write-Host ''
if ($fails -gt 0) {
    Write-Host "commander-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "commander-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
