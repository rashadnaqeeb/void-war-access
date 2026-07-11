# mainmenu-smoke.ps1 - end-to-end regression check for session 5: the real
# main-menu screen and the announcements (patch notes) popup screen.
#
# Profile-agnostic by design: the main menu's entries are conditional
# (Continue, Tutorial, Archives, Credits appear with save/progress state),
# so expected speech lines are derived live from /gui/mod (whose per-node
# parts are exactly what the announcer speaks) rather than hard-coded.
# Asserts: boot transcript reached the main menu, /gui/mod vs /gui/raw
# agreement on the button list, sibling moves with "n of m", arrow wrap
# within the menu's own Tab stop, the social button bar as a second Tab
# stop (labels from the live oSocialButton tooltips, Tab announces the
# group), opening Settings (name-only placeholder screen this session) and
# closing it via the game's own stored closeMenu callback with focus
# restore, opening the announcements popup, reading a body on demand, and
# dismissal with focus restore. Assumes a launcher (run-game.ps1) is already up at
# the main menu; drives over HTTP only. Exits nonzero on any failed check.
#
# Usage: powershell -NoProfile -File scripts\mainmenu-smoke.ps1

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

# A /cmd `get` of a string replies with a bare JSON string (text/plain on
# the wire, but Invoke-RestMethod still JSON-decodes plain text when it
# parses - PS 5.1 behavior), so the quoted reply arrives already decoded.
function CmdStr([string]$body) {
    $r = Cmd $body
    if ($r -is [string] -and $r.Length -ge 2 -and $r[0] -eq '"') {
        return ("[" + $r + "]" | ConvertFrom-Json)[0]  # in case a PS version leaves it raw
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
    Start-Sleep -Milliseconds 250  # a frame for the pump + the tick's observe
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

# The spoken line for landing on a /gui/mod node (vwa_speak joins parts
# with ", "; the node's parts array is already resolved and empty-free).
function NodeLine($node) {
    return ($node.parts -join ', ')
}

Write-Host "mainmenu-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

$mainMenuName = CmdStr 'get global.label_mainMenu'
$settingsName = CmdStr 'get global.label_settings'
$annName = CmdStr 'get global.label_announcements'

# --- if the popup opened at boot (fresh announcements), clear it first ---
$m = GuiMod
for ($i = 0; $i -lt 3 -and $m.focused -eq 'announcements'; $i++) {
    Write-Host '  (dismissing the boot announcements popup)'
    Cmd 'call vwa_dev_dismiss_start_popup' | Out-Null
    Start-Sleep -Milliseconds 300
    $m = GuiMod
}

# --- the main menu screen is up and interpreted ---
# Two Tab stops: the menu proper (the first node's stop) and the social
# button bar. Partitioned by the stop key; all counts derived live.
Check 'main-menu focused' ($m.focused -eq 'main-menu') $m.focused
$menuStop = $m.nodes[0].stop
$menuNodes = @($m.nodes | Where-Object { $_.stop -eq $menuStop })
$socialNodes = @($m.nodes | Where-Object { $_.stop -eq 'social' })
$n = $menuNodes.Count
Check 'at least the 5 unconditional entries' ($n -ge 5) $n
Check 'no nodes outside the two known stops' (
    ($menuNodes.Count + $socialNodes.Count) -eq $m.nodes.Count) (
    ($m.nodes | ForEach-Object { $_.stop } | Sort-Object -Unique) -join ',')
$types = @($m.nodes | ForEach-Object { $_.type } | Sort-Object -Unique)
Check 'every entry is a button' (($types -join ',') -eq 'button') ($types -join ',')
$posOk = $true
for ($i = 0; $i -lt $n; $i++) {
    if ($menuNodes[$i].pos[0] -ne ($i + 1) -or $menuNodes[$i].pos[1] -ne $n) { $posOk = $false }
}
for ($i = 0; $i -lt $socialNodes.Count; $i++) {
    if ($socialNodes[$i].pos[0] -ne ($i + 1) -or $socialNodes[$i].pos[1] -ne $socialNodes.Count) { $posOk = $false }
}
Check '"n of m" stamped per stop in list order' $posOk (($m.nodes | ForEach-Object { $_.pos -join '/' }) -join ' ')

# --- boot transcript: the boot announcement is followed IMMEDIATELY by a
#     screen name (main menu, or the announcements popup when it auto-opens)
#     - any stray line in between means a phantom screen spoke during boot ---
$bootLines = @((Invoke-RestMethod "$base/speech?since=0" -TimeoutSec 5).lines)
Check 'transcript has the main menu announcement' ($bootLines -contains $mainMenuName) ("$($bootLines.Count) lines")
$bootMsg = (Cmd 'call vwa_t vwa--boot').result
$bootIdx = [array]::IndexOf($bootLines, $bootMsg)
Check 'boot announcement present' ($bootIdx -ge 0) ($bootLines | Select-Object -First 3)
$afterBoot = if ($bootIdx -ge 0 -and $bootIdx + 1 -lt $bootLines.Count) { $bootLines[$bootIdx + 1] } else { '' }
Check 'no stray speech between boot and the first screen' (
    $afterBoot -eq $mainMenuName -or $afterBoot -eq $annName) $afterBoot

# --- /gui/raw vs /gui/mod: nothing lost from the real button list ---
$raw = Cmd 'gui.raw'
$rawButtons = @($raw.families.oMainMenuControls[0].buttonList)
Check 'raw and mod agree on entry count' ($rawButtons.Count -eq $n) "$($rawButtons.Count) raw vs $n mod"
$rawLabels = @($rawButtons | ForEach-Object { $_.buttonStr }) -join '|'
$modLabels = @($menuNodes | ForEach-Object { $_.parts[0] }) -join '|'
Check 'raw and mod agree on labels in order' ($rawLabels -eq $modLabels) "raw '$rawLabels' vs mod '$modLabels'"

# --- the social bar vs its live instances: labels are the game's own
#     tooltips, order is visual (x ascending) ---
$rawSocial = @((Cmd 'instances oSocialButton').instances | Sort-Object x)
Check 'raw and mod agree on social button count' (
    $rawSocial.Count -eq $socialNodes.Count) "$($rawSocial.Count) raw vs $($socialNodes.Count) mod"
$rawSocialLabels = @($rawSocial | ForEach-Object { CmdStr "get $($_.id).tooltipStr" }) -join '|'
$modSocialLabels = @($socialNodes | ForEach-Object { $_.parts[0] }) -join '|'
Check 'raw and mod agree on social labels in order' (
    $rawSocialLabels -eq $modSocialLabels) "raw '$rawSocialLabels' vs mod '$modSocialLabels'"

# --- park focus on the first entry (no speech assertion: it may already
#     be there; a same-node nextMove is silent by design) ---
$screens = Cmd 'get global.vwaScreens'
$mmIndex = -1
for ($i = 0; $i -lt $screens.Count; $i++) {
    if ($screens[$i].key -eq 'main-menu') { $mmIndex = $i }
}
Check 'main-menu found in the registry' ($mmIndex -ge 0) 'not registered'
function FocusMainMenu([string]$skey) {
    Cmd "set global.vwaScreens[$mmIndex].navState.nextMove $skey" | Out-Null
    Start-Sleep -Milliseconds 300
}
FocusMainMenu $menuNodes[0].skey
Check 'focus parked on the first entry' ((GuiMod).focusKey -eq $menuNodes[0].skey) (GuiMod).focusKey

# --- arrow wrap: up from the top lands on the bottom, down wraps back -
#     within the menu's own stop (arrows never reach the social bar) ---
CheckSpeech 'up from the first entry wraps to the last' { Fire 'nav-up' } @(NodeLine $menuNodes[$n - 1])
CheckSpeech 'down from the last entry wraps to the first' { Fire 'nav-down' } @(NodeLine $menuNodes[0])

# --- the social bar: Tab enters it announcing the group word, left/right
#     walk its buttons, Shift+Tab returns to the remembered menu entry ---
if ($socialNodes.Count -gt 0) {
    $groupWord = (Cmd 'call vwa_t vwa--group-social').result
    CheckSpeech 'Tab reaches the social group, announced with its group word' {
        Fire 'nav-next-stop'
    } @("$groupWord, $(NodeLine $socialNodes[0])")
    for ($i = 1; $i -lt $socialNodes.Count; $i++) {
        CheckSpeech "right to social button $($i + 1)" { Fire 'nav-right' } @(NodeLine $socialNodes[$i])
    }
    CheckSpeech 'right at the last social button is a dead edge' { Fire 'nav-right' } @()
    CheckSpeech 'Shift+Tab returns to the remembered menu entry' {
        Fire 'nav-prev-stop'
    } @(NodeLine $menuNodes[0])
} else {
    Write-Host '  (no social buttons live; skipping social bar checks)'
}

# --- walk down to Settings, hearing each entry exactly once ---
$settingsIdx = -1
$annIdx = -1
for ($i = 0; $i -lt $n; $i++) {
    if ($menuNodes[$i].skey -eq 'mm:label_settings') { $settingsIdx = $i }
    if ($menuNodes[$i].skey -eq 'mm:label_announcements') { $annIdx = $i }
}
Check 'Settings entry present' ($settingsIdx -ge 0) ($menuNodes | ForEach-Object { $_.skey })
Check 'Announcements entry present' ($annIdx -ge 0) ($menuNodes | ForEach-Object { $_.skey })
for ($i = 1; $i -le $settingsIdx; $i++) {
    CheckSpeech "down to entry $($i + 1) of $n" { Fire 'nav-down' } @(NodeLine $menuNodes[$i])
}

# --- Enter on Settings: the real settings screen opens (session 6): it
#     announces its name, then the landing control ---
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$sm = GuiMod
Check 'settings screen focused' ($sm.focused -eq 'menu-settings') $sm.focused
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$expected = @($settingsName, (NodeLine $sm.nodes[0]))
Check 'activating Settings announces name then landing' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"
$s = Invoke-RestMethod "$base/state" -TimeoutSec 8
$stackNames = @($s.stack | ForEach-Object { $_.name })
Check 'settings screen stacked over main-menu' (
    $stackNames -contains 'main-menu' -and $stackNames -contains 'menu-settings') ($stackNames -join ',')
Check 'settings keeps ui live (real screen now)' (
    ($s.liveCategories -contains 'ui') -and ($s.liveCategories -contains 'global')) ($s.liveCategories -join ',')

# --- close via the game's own stored callback: focus restores, spoken once ---
CheckSpeech 'closing settings re-announces menu and restores focus' {
    Cmd 'call oMenuSettings.closeMenu'
} @($mainMenuName, (NodeLine $menuNodes[$settingsIdx]))

# --- Enter on Announcements: the popup screen, derived expectations ---
CheckSpeech 'jump to the Announcements entry' {
    FocusMainMenu $menuNodes[$annIdx].skey
} @(NodeLine $menuNodes[$annIdx])
$cur = SpeechNext
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$a = GuiMod
Check 'announcements screen focused' ($a.focused -eq 'announcements') $a.focused
Check 'announcements screen is exclusive on the stack' (
    @($a.stack | Where-Object { $_.key -eq 'announcements' -and $_.exclusive }).Count -eq 1) ($a.stack | ConvertTo-Json -Compress)
$got = @((Invoke-RestMethod "$base/speech?since=$cur" -TimeoutSec 5).lines)
$expected = @($annName, (NodeLine $a.nodes[0]))
Check 'popup announced: screen name then first title' (
    ($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

if ($a.nodes.Count -ge 2) {
    CheckSpeech 'down to the second announcement title' { Fire 'nav-down' } @(NodeLine $a.nodes[1])
    $body = CmdStr 'get global.gameStartMessages[1].messageBody'
    CheckSpeech 'Enter reads the announcement body on demand' { Fire 'nav-activate' } @($body)
} else {
    Write-Host '  (single announcement; skipping body-read checks)'
}

# --- dismissal (the game's own path is Escape; dev-only helper mirrors it,
#     honoring the saved once-per-profile double-spawn quirk) ---
$cur = SpeechNext
$d = Cmd 'call vwa_dev_dismiss_start_popup'
if ($d.result.respawned) {
    # The respawn replaces the instance in the same frame, so the screen
    # never pops and nothing speaks until the second dismissal.
    Write-Host '  (first-ever dismissal respawned the popup; dismissing again)'
    Start-Sleep -Milliseconds 300
    $d = Cmd 'call vwa_dev_dismiss_start_popup'
}
Check 'popup dismissed' ($d.result.dismissed -eq $true) ($d | ConvertTo-Json -Compress)
$got = @(SpeechFrom $cur)
$m2 = GuiMod
Check 'main menu focus restored to Announcements' (
    $m2.focused -eq 'main-menu' -and $m2.focusKey -eq $menuNodes[$annIdx].skey) "$($m2.focused)/$($m2.focusKey)"
$expected = @($mainMenuName, (NodeLine $menuNodes[$annIdx]))
Check 'uncover re-announced menu and landing' (($got -join '|') -eq ($expected -join '|')) "expected '$($expected -join '|')', got '$($got -join '|')'"

Check 'pump alive at end' ((Cmd 'ping') -eq 'pong') 'no pong'

Write-Host ""
if ($fails -gt 0) {
    Write-Host "mainmenu-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "mainmenu-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
