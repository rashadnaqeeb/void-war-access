# settings-smoke.ps1 - end-to-end regression check for session 6: the
# generic widget adapter and the settings family (settings menu, dropdown
# child screens, confirmation dialogue, pause/escape menu).
#
# Profile-agnostic: expected speech lines derive live from /gui/mod (whose
# per-node parts are exactly what the announcer speaks). All state this
# script touches is restored: the toggled checkbox is toggled back, the
# volume slider is stepped back, the window-size dropdown re-commits the
# CURRENT entry, the beta-language confirmation is cancelled, the
# dev-spawned pause menu is closed through its own Resume button.
# Assumes a launcher (run-game.ps1) is already up at the main menu; drives
# over HTTP only. Exits nonzero on any failed check.
#
# Usage: powershell -NoProfile -File scripts\settings-smoke.ps1

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

function CmdStr([string]$body) {
    $r = Cmd $body
    if ($r -is [string] -and $r.Length -ge 2 -and $r[0] -eq '"') {
        return ("[" + $r + "]" | ConvertFrom-Json)[0]
    }
    return $r
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

function NodeLine($node) {
    return ($node.parts -join ', ')
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

Write-Host "settings-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

$settingsName = CmdStr 'get global.label_settings'
$mainMenuName = CmdStr 'get global.label_mainMenu'

# --- clear the boot popup if it is up, land on the main menu ---
$m = GuiMod
for ($i = 0; $i -lt 3 -and $m.focused -eq 'announcements'; $i++) {
    Write-Host '  (dismissing the boot announcements popup)'
    Cmd 'call vwa_dev_dismiss_start_popup' | Out-Null
    Start-Sleep -Milliseconds 300
    $m = GuiMod
}
Check 'main-menu focused' ($m.focused -eq 'main-menu') $m.focused

# --- open settings through the real mod path ---
FocusNode 'main-menu' 'mm:label_settings'
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$s = GuiMod
Check 'settings screen focused' ($s.focused -eq 'menu-settings') $s.focused
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$expected = @($settingsName, (NodeLine $s.nodes[0]))
Check 'settings announced: name then first control' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

# --- raw-vs-mod diff: every live settings widget has a node ---
$cbs = (Cmd 'instances oSettings_checkbox').instances
Check '10 checkboxes live' ($cbs.Count -eq 10) $cbs.Count
$missing = @()
foreach ($cb in $cbs) {
    if (-not (NodeByKey $s $cb.object)) { $missing += $cb.object }
}
Check 'every checkbox has a mod node' ($missing.Count -eq 0) ($missing -join ',')
foreach ($k in @('oSettings_windowSize', 'oSettings_volume_music',
                 'oSettings_volume_sound', 'oSettings_language',
                 'oButton_configureKeybinds', 'bm:label_back')) {
    Check "node present: $k" ($null -ne (NodeByKey $s $k)) 'missing'
}
Check 'node count matches widget count (16)' ($s.nodes.Count -eq 16) $s.nodes.Count

# --- types resolved by the vtable ---
Check 'windowSize is a combo' ((NodeByKey $s 'oSettings_windowSize').type -eq 'combo') ((NodeByKey $s 'oSettings_windowSize').type)
Check 'music volume is a slider' ((NodeByKey $s 'oSettings_volume_music').type -eq 'slider') ((NodeByKey $s 'oSettings_volume_music').type)
Check 'fullscreen is a toggle' ((NodeByKey $s 'oSettings_checkbox_fullscreen').type -eq 'toggle') ((NodeByKey $s 'oSettings_checkbox_fullscreen').type)
Check 'back is a button' ((NodeByKey $s 'bm:label_back').type -eq 'button') ((NodeByKey $s 'bm:label_back').type)

# --- the three window-mode checkboxes form one horizontal row ---
$fs = NodeByKey $s 'oSettings_checkbox_fullscreen'
Check 'fullscreen row: 1 of 3' (($fs.pos -join '/') -eq '1/3') ($fs.pos -join '/')
Check 'fullscreen has a right edge' ($null -ne $fs.edges.right) ($fs.edges | ConvertTo-Json -Compress)

# --- toggle a checkbox: state part speaks alone, real state flips ---
$svKey = 'oSettings_checkbox_showVersionInfo'
$sv = NodeByKey $s $svKey
CheckSpeech 'focus the version-info checkbox' { FocusNode 'menu-settings' $svKey } @(NodeLine $sv)
$beforeToggled = (Cmd 'get oSettings_checkbox_showVersionInfo.toggled')
$stateChecked = (Cmd 'call vwa_t vwa--state-checked').result
$stateUnchecked = (Cmd 'call vwa_t vwa--state-unchecked').result
$expectFirst = if ($beforeToggled -eq $true) { $stateUnchecked } else { $stateChecked }
$expectSecond = if ($beforeToggled -eq $true) { $stateChecked } else { $stateUnchecked }
CheckSpeech 'toggle speaks the new state alone' { Fire 'nav-activate' } @($expectFirst)
CheckSpeech 'toggle back speaks the restored state' { Fire 'nav-activate' } @($expectSecond)
$after = Cmd 'get oSettings_checkbox_showVersionInfo.toggled'
Check 'checkbox state restored' ($after -eq $beforeToggled) "$beforeToggled -> $after"

# --- slider: right adjusts up, left restores; value speaks alone ---
$volBefore = Cmd 'get global.currVolume_BGM'
$labelBefore = CmdStr 'get oSettings_volume_music.rightLabel'
CheckSpeech 'focus the music slider' { FocusNode 'menu-settings' 'oSettings_volume_music' } @(NodeLine (NodeByKey $s 'oSettings_volume_music'))
$cur = SpeechNext
Fire 'nav-right' | Out-Null
Start-Sleep -Milliseconds 350
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$labelUp = CmdStr 'get oSettings_volume_music.rightLabel'
Check 'slider stepped up' ([int]$labelUp -gt [int]$labelBefore) "$labelBefore -> $labelUp"
Check 'new value spoke alone' (($got -join '|') -eq $labelUp) "expected '$labelUp', got '$($got -join '|')'"
CheckSpeech 'left restores the value, speaking it' { Fire 'nav-left' } @($labelBefore)
$volAfter = Cmd 'get global.currVolume_BGM'
Check 'volume global restored' ([math]::Abs($volAfter - $volBefore) -lt 0.001) "$volBefore -> $volAfter"

# --- dropdown: open as child screen, land on selection, escape closes ---
$ws = NodeByKey $s 'oSettings_windowSize'
CheckSpeech 'focus the window-size combo' { FocusNode 'menu-settings' 'oSettings_windowSize' } @(NodeLine $ws)
$ddIdxBefore = Cmd 'get oSettings_windowSize.dropdown_currSelectedIndex'
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$d = GuiMod
Check 'dropdown child screen focused' ($d.focused -eq 'vwa-dropdown') $d.focused
$entryCount = (Cmd 'dump oSettings_windowSize.dropdownEntries 1').Count
Check 'one node per entry' ($d.nodes.Count -eq $entryCount) "$($d.nodes.Count) vs $entryCount"
Check 'landed on the selected entry' ($d.focusKey -eq "opt:$ddIdxBefore") "$($d.focusKey) vs opt:$ddIdxBefore"
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$wsLabel = CmdStr 'get oSettings_windowSize.leftLabel'
$landNode = NodeByKey $d "opt:$ddIdxBefore"
$expected = @($wsLabel, (NodeLine $landNode))
Check 'dropdown announced: label then selected entry' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

$second = NodeByKey $d 'opt:1'
CheckSpeech 'down to the second entry' { Fire 'nav-down' } @(NodeLine $second)

# Escape closes just the list; settings survives underneath.
$cur = SpeechNext
Fire 'nav-back' | Out-Null
Start-Sleep -Milliseconds 400
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$m2 = GuiMod
Check 'escape closed the dropdown only' ($m2.focused -eq 'menu-settings') $m2.focused
Check 'menuToggle still settings' ((Cmd 'get global.menuToggle') -eq 9) (Cmd 'get global.menuToggle')
$expected = @($settingsName, (NodeLine $ws))
Check 'settings re-announced with combo focus restored' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

# --- choose from the dropdown: re-commit the CURRENT entry (no real
#     change) through the game's own select_dropdownEntry ---
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$cur = SpeechNext
$r = Fire 'nav-activate'
Check 'choose activation fired cleanly' (-not ($r -like 'ERROR:*')) $r
Start-Sleep -Milliseconds 500
$m2 = GuiMod
Check 'choosing closed the dropdown' ($m2.focused -eq 'menu-settings') $m2.focused
$ddIdxAfter = Cmd 'get oSettings_windowSize.dropdown_currSelectedIndex'
Check 'selection index unchanged' ($ddIdxAfter -eq $ddIdxBefore) "$ddIdxBefore -> $ddIdxAfter"
Check 'toggleDropdown cleared' ((Cmd 'get oSettings_windowSize.toggleDropdown') -eq $false) 'still open'

# --- tooltips read inline as a part of the control announcement (no
#     tooltip key; a control without a tooltip appends nothing). Focusing
#     into the window-mode trio crosses into its row group: the entry
#     announces the localized generic group word plus the group's vertical
#     position (row 2 of the 14 vertical entries), then the member with its
#     in-row "1 of 3" - and its tooltip text, since /gui/mod parts and the
#     announcer share vwa_ann_leaf. ---
$grpWord = (Cmd 'call vwa_t vwa--group-generic').result
$fsTip = CmdStr 'get oSettings_checkbox_fullscreen.tooltipStr'
CheckSpeech 'focus the fullscreen checkbox' { FocusNode 'menu-settings' 'oSettings_checkbox_fullscreen' } @("$grpWord, 2 of 14, $(NodeLine $fs)")
Check 'checkbox announcement carries its tooltip inline' (
    (NodeLine $fs) -like "*$fsTip*") (NodeLine $fs)
CheckSpeech 'focus the back button (no tooltip, none appended)' { FocusNode 'menu-settings' 'bm:label_back' } @(NodeLine (NodeByKey $s 'bm:label_back'))
Check 'no-tooltip button appends nothing' (
    @((NodeByKey $s 'bm:label_back').parts).Count -eq 3) ((NodeByKey $s 'bm:label_back').parts -join ' / ')

# --- confirmation dialogue via the beta-language flow, then cancel ---
$langBefore = Cmd 'get global.currLanguage'
CheckSpeech 'focus the language combo' { FocusNode 'menu-settings' 'oSettings_language' } @(NodeLine (NodeByKey $s 'oSettings_language'))
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$d = GuiMod
Check 'language dropdown open' ($d.focused -eq 'vwa-dropdown') $d.focused
Fire 'nav-down' | Out-Null
Start-Sleep -Milliseconds 300
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 500
$c = GuiMod
Check 'confirmation dialogue screen focused' ($c.focused -eq 'confirm') $c.focused
Check 'menuToggle is confirmDialogue' ((Cmd 'get global.menuToggle') -eq 14) (Cmd 'get global.menuToggle')
Check 'dialogue has message plus two buttons' ($c.nodes.Count -eq 3) $c.nodes.Count
$confirmName = (Cmd 'call vwa_t vwa--screen-confirm').result
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$expected = @($confirmName, (NodeLine $c.nodes[0]))
Check 'dialogue announced: name then message' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

# Confirm/Cancel form a row group: entering announces the generic group
# word and the group's vertical position (entry 2 after the message label).
CheckSpeech 'down lands on Confirm' { Fire 'nav-down' } @("$grpWord, 2 of 2, $(NodeLine $c.nodes[1])")
CheckSpeech 'right lands on Cancel' { Fire 'nav-right' } @(NodeLine $c.nodes[2])
$cur = SpeechNext
$r = Fire 'nav-activate'
Check 'cancel activation fired cleanly' (-not ($r -like 'ERROR:*')) $r
Start-Sleep -Milliseconds 500
$m2 = GuiMod
Check 'cancel returned to settings' ($m2.focused -eq 'menu-settings') $m2.focused
Check 'language unchanged' ((Cmd 'get global.currLanguage') -eq $langBefore) (Cmd 'get global.currLanguage')

# --- Back closes settings; focus restores to the main menu entry ---
FocusNode 'menu-settings' 'bm:label_back'
Start-Sleep -Milliseconds 200
$cur = SpeechNext
$r = Fire 'nav-activate'
Check 'Back activation fired cleanly' (-not ($r -like 'ERROR:*')) $r
Start-Sleep -Milliseconds 500
$m2 = GuiMod
Check 'settings closed via Back' ($m2.focused -eq 'main-menu') $m2.focused
Check 'menuToggle cleared' ((Cmd 'get global.menuToggle') -eq 0) (Cmd 'get global.menuToggle')
Check 'focus restored to the Settings entry' ($m2.focusKey -eq 'mm:label_settings') $m2.focusKey

# --- pause/escape menu (dev-spawned; safe at the main menu: pause_game
#     no-ops with no run live, Resume reverts cleanly) ---
$cur = SpeechNext
Cmd 'call vwa_dev_spawn oMenuPause' | Out-Null
Start-Sleep -Milliseconds 500
$p = GuiMod
Check 'escape menu screen focused' ($p.focused -eq 'menu-escape') $p.focused
Check 'escape menu has the five buttons' ($p.nodes.Count -eq 5) $p.nodes.Count
$pauseName = (Cmd 'call vwa_t vwa--screen-pause').result
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$expected = @($pauseName, (NodeLine $p.nodes[0]))
Check 'escape menu announced: name then Resume' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"
$resumeLabel = CmdStr 'get global.label_resume'
Check 'first button is Resume' ($p.nodes[0].parts[0] -eq $resumeLabel) $p.nodes[0].parts[0]

CheckSpeech 'down to the second pause button' { Fire 'nav-down' } @(NodeLine $p.nodes[1])
FocusNode 'menu-escape' $p.nodes[0].skey
Start-Sleep -Milliseconds 200
$r = Fire 'nav-activate'
Check 'Resume activation fired cleanly' (-not ($r -like 'ERROR:*')) $r
Start-Sleep -Milliseconds 500
$m2 = GuiMod
Check 'Resume closed the escape menu' ($m2.focused -eq 'main-menu') $m2.focused
Check 'menuToggle cleared after Resume' ((Cmd 'get global.menuToggle') -eq 0) (Cmd 'get global.menuToggle')
Check 'pause menu instance gone' ((Cmd 'instances oMenuPause').count -eq 0) 'still alive'

Check 'pump alive at end' ((Cmd 'ping') -eq 'pong') 'no pong'

Write-Host ""
if ($fails -gt 0) {
    Write-Host "settings-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "settings-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
