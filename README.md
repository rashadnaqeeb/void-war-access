# Void War Access

A screen-reader accessibility mod for [Void War](https://store.steampowered.com/app/2853590/) (Steam, Windows). Speech is the primary interface: menus are navigated by keyboard and every control is announced through your screen reader (JAWS, NVDA, or Windows SAPI voices, via Prism).

The mod never modifies the game's own files. It builds a patched copy of the game data and launches it through Steam; removing the mod is deleting a folder.

## Status

Early development. What works today:

- Boot to the main menu and hear it announced.
- Navigate the main menu with the arrow keys (wrapping top to bottom), hear each entry as "label, button, n of m", and activate entries with Enter.
- The announcements popup (patch notes): entries are listed by title, Enter reads an announcement's body, Escape dismisses it (the game's own key). Quirk inherited from the game: the very first dismissal on a profile makes the popup reappear once - press Escape again.
- The full settings menu: checkboxes ("label, toggle, checked/not checked" - Enter flips them and the new state is announced), the volume sliders (left/right arrows adjust in 1-point steps, Ctrl with left/right in 10-point steps, the new value is announced), the window size and language dropdowns (Enter opens the list as its own screen landing on the current choice, Enter commits, Escape closes just the list), Configure Keybinds, and Back. A control's tooltip is read as part of its announcement. Side-by-side controls (the fullscreen/borderless/windowed trio) form a group: it counts as one item in the vertical list, arriving on it announces "group" and its list position, and left/right move within it ("1 of 3").
- The confirmation dialogue (for example when choosing a beta language): the message is read, arrows reach Confirm and Cancel.
- The in-game pause menu (Resume, Hangar, Restart, Settings, Main Menu).
- Submenus (used by upcoming mod screens such as the mod's own settings): a collapsible section presented as an element in the list, announced as "label, submenu, k items, n of m". Right arrow or Enter enters it, landing on its first item; left arrow returns to its header (on controls that don't use left/right themselves, like sliders or row members); up from the first item also lands on the header; down from the header skips the whole section; walking down past its last item continues into whatever follows, entering the next submenu directly with its title announced. Submenus nest.
- Speech hotkeys, available everywhere - including while typing in a game text field: Ctrl stops speech, Shift+F11 resets the speech stack if it ever goes quiet.

In-run gameplay (combat, encounters, ship management) is not yet accessible.

## Requirements

- Windows, 64-bit.
- Void War installed through Steam.
- A running screen reader (JAWS or NVDA), or Windows SAPI voices - Prism picks the best available.
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

- Arrow keys: move through a menu (up/down wrap at the ends; left/right adjust sliders and move within horizontal rows). On a submenu header, Right enters; inside a submenu, Left returns to the header when the focused control doesn't claim left/right itself.
- Ctrl with Left/Right: adjust sliders in large steps.
- Enter: activate the focused control (buttons click, checkboxes flip, dropdowns open, a dropdown entry commits, a submenu opens).
- Tab and Shift+Tab: cycle between control groups on screens that have them.
- Home and End: jump to the first or last control of the current group.
- Escape: close popups and menus (the game's own handling). With a dropdown list open, Escape closes just the list and stays in the menu.
- Ctrl: stop speech.
- Shift+F11: reset the speech stack and announce the active backend.

A control's tooltip, when the game gives it one, is read as part of the
control's announcement; there is no separate tooltip key.

## For developers

`CLAUDE.md` holds the project invariants, verified game facts, and the build/run/verify workflow; `docs/backlog.md` lists future work. The mod is developed agent-first: an in-process dev driver (dev builds only, loopback HTTP on port 8772) exposes speech capture, UI dumps, and input injection so the whole loop runs unattended.
