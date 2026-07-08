# Void War Access

A screen-reader accessibility mod for [Void War](https://store.steampowered.com/app/2853590/) (Steam, Windows). Speech is the primary interface: menus are navigated by keyboard and every control is announced through your screen reader (JAWS and NVDA via Prism, with SAPI as fallback).

The mod never modifies the game's own files. It builds a patched copy of the game data and launches it through Steam; removing the mod is deleting a folder.

## Status

Early development. What works today:

- Boot to the main menu and hear it announced.
- Navigate the main menu with the arrow keys (wrapping top to bottom), hear each entry as "label, button, n of m", and activate entries with Enter.
- The announcements popup (patch notes): entries are listed by title, Enter reads an announcement's body, Escape dismisses it (the game's own key). Quirk inherited from the game: the very first dismissal on a profile makes the popup reappear once - press Escape again.
- The full settings menu: checkboxes ("label, toggle, checked/not checked" - Enter flips them and the new state is announced), the volume sliders (left/right arrows adjust in 5-point steps, the new value is announced), the window size and language dropdowns (Enter opens the list as its own screen landing on the current choice, Enter commits, Escape closes just the list), Configure Keybinds, and Back. F9 reads the focused control's tooltip.
- The confirmation dialogue (for example when choosing a beta language): the message is read, arrows reach Confirm and Cancel.
- The in-game pause menu (Resume, Hangar, Restart, Settings, Main Menu).
- Speech hotkeys, available everywhere: F11 repeats the last spoken line, Ctrl stops speech, Shift+F11 resets the speech stack if it ever goes quiet.

In-run gameplay (combat, encounters, ship management) is not yet accessible.

## Requirements

- Windows, 64-bit.
- Void War installed through Steam.
- A running screen reader (JAWS or NVDA), or Windows SAPI voices as fallback.
- To build from source: clang (LLVM) and .NET 8.

## Build and run

From the repository root, in PowerShell:

```
powershell -NoProfile -File tools\build-mod.ps1
powershell -NoProfile -File tools\run-game.ps1 -Speech
```

The first command builds the speech DLL and the patched game data into `build\` (about a minute). The second launches the game through Steam with speech on. Steam must be running and logged in.

Without `-Speech`, the mod runs in capture-only mode: nothing is voiced, but every line that would have been spoken is written to `vwa-speech.log` in `%AppData%\Roaming\Void_War\` (used for automated testing).

## Keys

- Arrow keys: move through a menu (up/down wrap at the ends; left/right adjust sliders and move within horizontal rows).
- Enter: activate the focused control (buttons click, checkboxes flip, dropdowns open, a dropdown entry commits).
- Tab and Shift+Tab: cycle between control groups on screens that have them.
- Escape: close popups and menus (the game's own handling). With a dropdown list open, Escape closes just the list and stays in the menu.
- F9: read the focused control's tooltip.
- F11: repeat the last spoken line.
- Ctrl: stop speech.
- Shift+F11: reset the speech stack and announce the active backend.

## For developers

`docs/build-plan.md` is the session-by-session roadmap; `docs/game-and-tooling.md` records verified game facts and toolchain notes; `CLAUDE.md` holds the project invariants. The mod is developed agent-first: an in-process dev driver (dev builds only, loopback HTTP on port 8772) exposes speech capture, UI dumps, and input injection so the whole loop runs unattended.
