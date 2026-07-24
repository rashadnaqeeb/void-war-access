// --- Void War Access boot (appended by build-mod) ---
// Runs at the very end of oInitGlobals' Create, after the game's globals,
// localization, and the persistent global objects all exist.
global.vwaShim = undefined;
global.vwaShimReady = false;
if (vwa_shim_init())
{
    global.vwaShimReady = true;
}
vwa_input_init();
vwa_screens_init();
vwa_text_init();
vwa_menus_init();
vwa_ship_layer_init();
if (global.vwaShimReady)
{
    vwa_speak([vwa_t("vwa--boot")], false);
}
