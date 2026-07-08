# typeahead-smoke.ps1 - regression check for type-ahead search: the tiered
# matcher (scrVwaSearch, exercised with literal fixtures through the dev
# driver) and the navigator glue (dev-typed characters land focus on the
# main menu and in settings, arrows step results, Escape clears, a
# matchless buffer reports itself).
#
# Profile-agnostic: end-to-end expectations derive live from /gui/mod and
# the game's own label globals. All state is restored: searches are
# cleared, settings is closed through its own Back button.
# Assumes a launcher (run-game.ps1) is already up at the main menu; drives
# over HTTP only. Exits nonzero on any failed check.
#
# Usage: powershell -NoProfile -File scripts\typeahead-smoke.ps1

param(
    [int]$Port = $(if ($env:VWACCESS_DEV_PORT) { [int]$env:VWACCESS_DEV_PORT } else { 8772 })
)

$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$checks = 0
$fails = 0

function Cmd([string]$body) {
    # Explicit UTF-8: this smoke SENDS non-ASCII text (the fold fixtures),
    # and PS 5.1 otherwise encodes string bodies as Latin-1.
    return Invoke-RestMethod -Uri "$base/cmd" -Method Post -Body $body `
        -ContentType 'text/plain; charset=utf-8' -TimeoutSec 8
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

function TypeAhead([string]$text) {
    return (Cmd ('call vwa_dev_typeahead "' + $text + '"')).result
}

function SearchState {
    return (Cmd 'call vwa_dev_search_state').result
}

function ClearSearch {
    Cmd 'call vwa_nav_search_clear false' | Out-Null
}

Write-Host "typeahead-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

# --- matcher fixtures: one per tier, plus folding and the comma rules ---
function CheckTier([string]$name, [string]$prefix, [int]$tier, [int]$pos) {
    $r = (Cmd ('call vwa_search_match_tier "' + $name + '" "' + $prefix + '"')).result
    Check "tier('$name','$prefix') = $tier@$pos" (
        $r.tier -eq $tier -and ($tier -lt 0 -or $r.matchPos -eq $pos)) "$($r.tier)@$($r.matchPos)"
}

CheckTier 'load game' 'load' 0 1     # start-of-string whole word
CheckTier 'load game' 'l' 1 1        # start-of-string prefix
CheckTier 'load game' 'game' 2 6     # mid-string whole word
CheckTier 'load game' 'ga' 3 6       # mid-string word prefix
CheckTier 'load game' 'oad' 4 2      # substring anywhere
CheckTier 'gas pipe' 'ga pi' 5 1     # word-prefix abbreviation
CheckTier 'load game' 'x' -1 0       # no match
CheckTier 'Load Game' 'LOAD' 0 1     # case-insensitive
CheckTier 'Séance' 'sean' 1 1        # diacritics fold
CheckTier 'name, meta' 'meta' 2 7    # comma is a word boundary
CheckTier 'resume, paused' 'pau' 3 9 # word prefix inside metadata
CheckTier 'gas, pipe' 'ga pi' -1 0   # abbreviation never crosses a comma

$folded = (Cmd 'call vwa_search_fold "Œuvre Éclair"').result
Check 'fold expands ligatures and strips accents' ($folded -eq 'oeuvre eclair') $folded

# --- end-to-end on the main menu ---
$m = GuiMod
for ($i = 0; $i -lt 3 -and $m.focused -eq 'announcements'; $i++) {
    Write-Host '  (dismissing the boot announcements popup)'
    Cmd 'call vwa_dev_dismiss_start_popup' | Out-Null
    Start-Sleep -Milliseconds 300
    $m = GuiMod
}
Check 'main-menu focused' ($m.focused -eq 'main-menu') $m.focused

ClearSearch
$settingsLabel = CmdStr 'get global.label_settings'
$settingsNode = NodeByKey $m 'mm:label_settings'

# Typing a full label lands on its entry; each keystroke re-announces the
# current best match, so the LAST spoken line is the landing's readout.
$cur = SpeechNext
$st = TypeAhead $settingsLabel
Check 'full label: search active' ($st.active -eq $true) $st.active
Check 'full label: focus landed on the Settings entry' (
    $st.focusSkey -eq 'mm:label_settings') $st.focusSkey
Check 'full label: best result is the Settings entry' (
    @($st.resultSkeys)[0] -eq 'mm:label_settings') (@($st.resultSkeys) -join ',')
$got = @(SpeechFrom $cur)
Check 'full label: landing spoken (interrupting, once per keystroke)' (
    $got.Count -gt 0 -and $got[-1] -eq (NodeLine $settingsNode)) ($got -join '|')
$g = GuiMod
Check 'full label: graph focus agrees' ($g.focusKey -eq 'mm:label_settings') $g.focusKey

# Escape clears the search (spoken), focus stays where the search left it.
$cur = SpeechNext
Fire 'nav-back' | Out-Null
$got = @(SpeechFrom $cur)
$clearedText = (Cmd 'call vwa_t vwa--search-cleared').result
Check 'escape clears with announcement' (($got -join '|') -eq $clearedText) ($got -join '|')
$st = SearchState
Check 'search state cleared' ($st.active -eq $false -and $st.buffer -eq '') ($st | ConvertTo-Json -Compress)
$g = GuiMod
Check 'clearing did not close the screen' ($g.focused -eq 'main-menu') $g.focused
Check 'clearing did not move focus' ($g.focusKey -eq 'mm:label_settings') $g.focusKey

# Same-letter cycling: the first letter's matches cycle in result order.
$first = $settingsLabel.Substring(0, 1).ToLower()
$st1 = TypeAhead $first
$n = @($st1.resultSkeys).Count
Check "single letter '$first' has results" ($n -ge 1) $n
$st2 = TypeAhead $first
$expCursor = 1 % $n
Check 'repeat letter collapses the buffer and cycles' (
    $st2.buffer -eq $first -and $st2.cursor -eq $expCursor) "buffer=$($st2.buffer) cursor=$($st2.cursor)"
Check 'repeat letter keeps the same results' (
    (@($st2.resultSkeys) -join ',') -eq (@($st1.resultSkeys) -join ',')) (@($st2.resultSkeys) -join ',')

# Down steps the results through the real action path; Home jumps back.
$exp = @($st2.resultSkeys)[(($st2.cursor + 1) % $n)]
Fire 'nav-down' | Out-Null
Start-Sleep -Milliseconds 250
$st3 = SearchState
Check 'nav-down steps to the next result' ($st3.focusSkey -eq $exp) $st3.focusSkey
Fire 'nav-home' | Out-Null
Start-Sleep -Milliseconds 250
$st4 = SearchState
Check 'nav-home jumps to the first result' (
    $st4.cursor -eq 0 -and $st4.focusSkey -eq @($st2.resultSkeys)[0]) $st4.focusSkey
Fire 'nav-back' | Out-Null
Start-Sleep -Milliseconds 250

# A matchless buffer speaks itself with the no-match wording.
$cur = SpeechNext
$st = TypeAhead 'qxj'
Check 'no-match: no results' (@($st.resultSkeys).Count -eq 0) (@($st.resultSkeys) -join ',')
$noMatchTpl = (Cmd 'call vwa_t vwa--search-no-match').result
$expLine = $noMatchTpl.Replace('{text}', 'qxj')
$got = @(SpeechFrom $cur)
Check 'no-match spoken with the buffer text' (
    $got.Count -gt 0 -and $got[-1] -eq $expLine) ($got -join '|')
Fire 'nav-back' | Out-Null
Start-Sleep -Milliseconds 250

# --- settings: type-ahead over the widget adapter's labels ---
FocusNode 'main-menu' 'mm:label_settings'
Fire 'nav-activate' | Out-Null
Start-Sleep -Milliseconds 400
$s = GuiMod
Check 'settings screen focused' ($s.focused -eq 'menu-settings') $s.focused

$musicLabel = CmdStr 'get oSettings_volume_music.leftLabel'
$st = TypeAhead $musicLabel
Check 'settings: typing the music label lands on the slider' (
    $st.focusSkey -eq 'oSettings_volume_music') $st.focusSkey
Fire 'nav-back' | Out-Null
Start-Sleep -Milliseconds 250
$g = GuiMod
Check 'settings survived the search clear' ($g.focused -eq 'menu-settings') $g.focused

FocusNode 'menu-settings' 'bm:label_back'
$r = Fire 'nav-activate'
Check 'Back activation fired cleanly' (-not ($r -like 'ERROR:*')) $r
Start-Sleep -Milliseconds 500
$g = GuiMod
Check 'settings closed via Back' ($g.focused -eq 'main-menu') $g.focused

Check 'input watchdog never tripped' ((Cmd 'get global.vwaInputWatchdogTripped') -eq $false) 'tripped'
Check 'pump alive at end' ((Cmd 'ping') -eq 'pong') 'no pong'

Write-Host ""
if ($fails -gt 0) {
    Write-Host "typeahead-smoke: $fails of $checks checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "typeahead-smoke: all $checks checks passed" -ForegroundColor Green
exit 0
