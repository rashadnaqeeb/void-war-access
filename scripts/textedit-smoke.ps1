# textedit-smoke.ps1 - regression check for the text edit layer
# (scrVwaText): enter the game's text-field mode, watch the mode
# announcements (including the pending path), drive the review cursor,
# verify deletion feedback from the text diff, prove the type-ahead drain
# keeps off keyboard_string mid-edit and discards the leftover after the
# mode ends, and exit from the keyboard.
#
# Runs entirely at the main menu against the game's REAL text machinery:
# text_field_input (the same script every field's Step calls) creates the
# oTextField singleton, and the flag plus that instance ARE the game's
# whole edit-mode state - no field object required, no room change, no
# profile requirements. End-to-end typing cannot be automated (the runner
# ignores synthetic key presses, and oTextField only consumes
# keyboard_string while a physical key is held), so "characters I type land
# in the field" stays a manual check; everything the MOD owns around it is
# covered here.
#
# All state is restored: edit mode is closed (oTextField destroys itself)
# and focus is left on the main menu.
# Assumes a launcher (run-game.ps1) is already up at the main menu; drives
# over HTTP only. Exits nonzero on any failed check.
#
# Usage: powershell -NoProfile -File scripts\textedit-smoke.ps1

param(
    [int]$Port = $(if ($env:VWACCESS_DEV_PORT) { [int]$env:VWACCESS_DEV_PORT } else { 8772 })
)

$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$checks = 0
$fails = 0

function Cmd([string]$body) {
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

function TextState {
    return (Cmd 'call vwa_dev_text_state').result
}

function LocStr([string]$key) {
    return (Cmd ('call vwa_t "' + $key + '"')).result
}

# Poll until $cond returns truthy (about 10s), else $null.
function WaitFor([scriptblock]$cond, [string]$what) {
    for ($i = 0; $i -lt 40; $i++) {
        $v = & $cond
        if ($v) { return $v }
        Start-Sleep -Milliseconds 250
    }
    Write-Host "  (timed out waiting for $what)"
    return $null
}

# Fire a review action and return the new speech lines it produced.
function ReviewSays([string]$actionKey) {
    $cur = SpeechNext
    Fire $actionKey | Out-Null
    return @(SpeechFrom $cur)
}

Write-Host "textedit-smoke: against $base"

$h = Invoke-RestMethod "$base/health" -TimeoutSec 5
Check 'health status ok' ($h.status -eq 'ok') $h.status

$m = GuiMod
for ($i = 0; $i -lt 3 -and $m.focused -eq 'announcements'; $i++) {
    Write-Host '  (dismissing the boot announcements popup)'
    Cmd 'call vwa_dev_dismiss_start_popup' | Out-Null
    Start-Sleep -Milliseconds 300
    $m = GuiMod
}
Check 'main-menu focused' ($m.focused -eq 'main-menu') $m.focused

$st = TextState
Check 'text mode idle at start' (-not $st.flag -and -not $st.active) ($st | ConvertTo-Json -Compress)

# --- enter edit mode: begin first (pending, no field), then the game's own
# field-creation script supplies oTextField with a known seed text ---
$cur = SpeechNext
Cmd 'call vwa_text_begin' | Out-Null
Start-Sleep -Milliseconds 300
$st = TextState
Check 'pending until a field exists' ($st.flag -and $st.pending -and -not $st.active) ($st | ConvertTo-Json -Compress)

Cmd 'call text_field_input "alpha beta"' | Out-Null
$active = WaitFor { (TextState).active } 'edit mode active'
Check 'edit mode active once the field exists' ([bool]$active) (TextState | ConvertTo-Json -Compress)
$editing = LocStr 'vwa--text-editing'
$lines = SpeechFrom $cur
Check 'entry announced with the text' ((@($lines) -join ' ') -match ([regex]::Escape($editing) + '.*alpha beta')) ($lines -join ' | ')
$st = TextState
Check 'cursor parked at the end (10)' ($st.cursor -eq 10 -and $st.fieldText -eq 'alpha beta') ($st | ConvertTo-Json -Compress)

# --- review cursor ---
$lines = ReviewSays 'text-review-left'
Check "left speaks 't'" (@($lines)[-1] -eq 't') ($lines -join ' | ')
$lines = ReviewSays 'text-review-word-left'
Check "word-left speaks 'beta'" (@($lines)[-1] -eq 'beta') ($lines -join ' | ')
$lines = ReviewSays 'text-review-word-left'
Check "word-left again speaks 'alpha'" (@($lines)[-1] -eq 'alpha') ($lines -join ' | ')
$lines = ReviewSays 'text-review-word-right'
Check "word-right speaks 'beta'" (@($lines)[-1] -eq 'beta') ($lines -join ' | ')
$lines = ReviewSays 'text-review-home'
Check "home speaks 'a'" (@($lines)[-1] -eq 'a') ($lines -join ' | ')
$lines = ReviewSays 'text-review-end'
Check "end speaks 'a'" (@($lines)[-1] -eq 'a') ($lines -join ' | ')
$lines = ReviewSays 'text-read'
Check 'read-all speaks the text' (@($lines)[-1] -eq 'alpha beta') ($lines -join ' | ')

# --- deletion feedback from the text diff ---
$cur = SpeechNext
Cmd 'call text_field_replace "alpha bet"' | Out-Null
$lines = SpeechFrom $cur
Check "single end-deletion speaks 'a'" (@($lines)[-1] -eq 'a') ($lines -join ' | ')
$cur = SpeechNext
Cmd 'call text_field_replace "alpha "' | Out-Null
$lines = SpeechFrom $cur
Check "multi end-deletion speaks 't, e, b'" (@($lines)[-1] -eq 't, e, b') ($lines -join ' | ')
$space = LocStr 'vwa--char-space'
$lines = ReviewSays 'text-review-end'
Check 'end on a space speaks the space word' (@($lines)[-1] -eq $space) ($lines -join ' | ')

# --- the type-ahead drain keeps off keyboard_string mid-edit ---
Cmd 'call vwa_dev_type "xy"' | Out-Null
Start-Sleep -Milliseconds 400
$st = TextState
Check 'injected buffer persists mid-edit' ($st.kbString -like '*xy') ($st | ConvertTo-Json -Compress)

# --- keyboard exit; the leftover buffer is discarded, never searched ---
$cur = SpeechNext
Fire 'text-exit' | Out-Null
$idle = WaitFor { $s = TextState; -not $s.active -and -not $s.flag } 'edit mode closed'
Check 'edit mode closed by text-exit' ([bool]$idle) (TextState | ConvertTo-Json -Compress)
$closed = LocStr 'vwa--text-edit-closed'
$lines = SpeechFrom $cur
$joined = @($lines) -join ' | '
Check 'exit announced with final text' ($joined -match ([regex]::Escape($closed) + '.*alpha')) $joined
Check 'no stale search speech from the leftover buffer' (-not ($joined -match 'xy')) $joined
Start-Sleep -Milliseconds 400
$st = TextState
Check 'field gone and buffer drained after exit' (-not $st.fieldExists -and $st.kbString -eq '') ($st | ConvertTo-Json -Compress)
$search = (Cmd 'call vwa_dev_search_state').result
Check 'type-ahead buffer empty' ($search.buffer -eq '') ($search | ConvertTo-Json -Compress)

# --- ui navigation is back after the edit ---
$cur = SpeechNext
Fire 'nav-down' | Out-Null
$lines = SpeechFrom $cur
Check 'ui navigation live again (nav-down speaks)' (@($lines).Count -ge 1 -and @($lines)[-1] -ne '') ($lines -join ' | ')
Check 'main-menu still focused' ((GuiMod).focused -eq 'main-menu') (GuiMod).focused

$wd = CmdStr 'get global.vwaInputWatchdogTripped'
Check 'input watchdog never tripped' (-not [bool]$wd) $wd

Write-Host "textedit-smoke: $checks checks, $fails failed"
exit $(if ($fails -gt 0) { 1 } else { 0 })
