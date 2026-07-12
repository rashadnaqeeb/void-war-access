# run-game.ps1 - build, launch, and babysit the modded game.
#
# Run this as a BACKGROUND task: it blocks until the game exits, so a crash
# wakes the agent. Never start a second launcher while one is alive; the lock
# below refuses it.
#
# Stopping a run (bit us): the game is Steam's child, not ours, and a hard
# task-cancel kills this script without running its finally - so cancelling
# ORPHANS the game and leaves a stale lock. Both are self-healing: the next
# launcher run clears the stale lock and kills the orphan (verified). To stop
# without relaunching, taskkill "Void War.exe" - the launcher then wakes,
# reports the exit, and releases the lock cleanly.
#
# -NoBuild   launch whatever is already in build\ (re-test the exact binary)
# -NoBg      disable the shim's focus-pause keepalive (diagnostic / to test a
#            release-parity launch)
# -WaitMainMenu  after /health, keep waiting until /gui/mod shows the
#            main-menu screen on the stack (the game has finished booting
#            into rmMainMenu and the mod sees it)
#
# The game boot-freezes until its window gains focus once (runner-level,
# verified), but Steam's -applaunch focuses it automatically, so /health
# normally answers with no human touch. If it stalls, focus the window once.
# The shim also subclasses the window's WndProc to swallow later deactivation
# (see -NoBg); the autonomous loop runs unattended.

param(
    [switch]$NoBuild,
    [switch]$NoBg,      # disable the focus-pause keepalive (diagnostic / release-parity)
    [switch]$WaitMainMenu,
    [int]$HealthTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = if ($env:VWACCESS_DEV_PORT) { [int]$env:VWACCESS_DEV_PORT } else { 8772 }
$lockPath = Join-Path $env:TEMP 'vwaccess-run-game.lock'
$steam = 'C:\Program Files (x86)\Steam\steam.exe'
$gameProcName = 'Void War'

# --- single-instance lock (holds the launcher PID) ---
if (Test-Path $lockPath) {
    $oldPid = Get-Content $lockPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Error "another run-game.ps1 (PID $oldPid) is alive - cancel that task first"
        exit 3
    }
    Write-Host 'run-game: clearing stale lock (holder is dead)'
    Remove-Item $lockPath -Force
}
Set-Content $lockPath $PID

$game = $null
try {
    # --- kill orphaned game processes; wait for exit AND the port to free ---
    Get-Process $gameProcName -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "run-game: killing orphaned game (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force
        $_.WaitForExit(10000) | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and
           (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
        throw "port $port is still in use after 15s - something else owns it"
    }

    # --- build; a failure aborts the launch so a stale build never runs ---
    if (-not $NoBuild) {
        & "$repo\tools\build-mod.ps1"
    }

    # --- shim config (Steam does not forward this shell's env to the game) ---
    $bgVal = if ($NoBg) { 0 } else { 1 }
    Set-Content "$repo\build\vw_speech.cfg" @("port=$port", 'nodev=0', "bg=$bgVal")

    # --- launch through Steam (direct exe launch fails the Steamworks check) ---
    Write-Host "run-game: launching (port=$port)..."
    & $steam -applaunch 2853590 -game "$repo\build\data-test.win" -debugoutput "$repo\build\debug-out.txt"

    $deadline = (Get-Date).AddSeconds(60)
    while (-not $game -and (Get-Date) -lt $deadline) {
        $game = Get-Process $gameProcName -ErrorAction SilentlyContinue | Select-Object -First 1
        Start-Sleep -Milliseconds 500
    }
    if (-not $game) {
        throw 'game process did not appear within 60s (is Steam running and logged in?)'
    }
    Write-Host "run-game: game PID $($game.Id); waiting for /health." `
        'FOCUS THE GAME WINDOW ONCE if this stalls - the runner is frozen until then.'

    # --- poll /health until the shim answers ---
    $deadline = (Get-Date).AddSeconds($HealthTimeoutSec)
    $health = $null
    while ((Get-Date) -lt $deadline) {
        if ($game.HasExited) {
            throw "game exited during boot (code $($game.ExitCode)) - check build\debug-out.txt and build\vw_speech.log"
        }
        try {
            $health = Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 2
            if ($health.status -eq 'ok') { break }
        }
        catch { $health = $null }
        Start-Sleep -Seconds 1
    }
    if (-not $health) {
        throw "no /health answer within ${HealthTimeoutSec}s (window never focused? shim failed? see build\vw_speech.log)"
    }
    Write-Host "run-game: HEALTHY backend=$($health.backend) spoken=$($health.spoken)"

    # --- optionally wait for the main menu screen (boot reaches rmMainMenu) ---
    if ($WaitMainMenu) {
        Write-Host 'run-game: waiting for the main-menu screen...'
        $deadline = (Get-Date).AddSeconds(180)
        $onStack = $false
        while ((Get-Date) -lt $deadline) {
            if ($game.HasExited) {
                throw "game exited while waiting for the main menu (code $($game.ExitCode))"
            }
            try {
                $mod = Invoke-RestMethod "http://127.0.0.1:$port/gui/mod" -TimeoutSec 4
                if (@($mod.stack | ForEach-Object { $_.key }) -contains 'main-menu') {
                    $onStack = $true
                    break
                }
            }
            catch { }
            Start-Sleep -Milliseconds 500
        }
        if (-not $onStack) {
            throw 'main-menu screen never appeared on the stack within 180s (see the mod log)'
        }
        Write-Host "run-game: main menu active (focused screen: $($mod.focused))"
    }

    # --- block until the game exits; the exit code is the task's result ---
    $game.WaitForExit()
    # ExitCode is unreadable for processes we didn't spawn (Steam spawned it)
    # unless the handle allows it; treat unreadable as 0-with-a-note.
    $code = $null
    try { $code = $game.ExitCode } catch { }
    if ($null -eq $code) {
        Write-Host 'run-game: game exited (exit code unreadable - not our child process)'
        exit 0
    }
    Write-Host "run-game: game exited with code $code"
    exit $code
}
finally {
    if ($game -and -not $game.HasExited) {
        Stop-Process -Id $game.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
}
