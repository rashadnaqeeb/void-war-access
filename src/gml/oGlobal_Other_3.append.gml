// Void War Access: orderly shim teardown on the game's own Game End event
// (the one that autosaves and shuts Steam down - it runs on quit and on
// window close, at the menu and in-run). Restores the game window's
// WndProc and stops the dev server thread before the process unloads the
// DLL. Appended by build-mod.csx; ships in release.
vwa_shim_shutdown();
