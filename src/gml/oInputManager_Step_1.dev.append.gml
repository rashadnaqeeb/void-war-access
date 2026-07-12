// --- Void War Access dev pump (appended by build-mod, DEV BUILDS ONLY) ---
// One poll/reply round per step. oInputManager is persistent and created at
// boot, so this runs every frame in every room. The watchdog exists to
// protect the game, and it logs loudly - the one sanctioned swallow.
if (variable_global_exists("vwaShimReady") && global.vwaShimReady)
{
    try
    {
        var __vwaCmd = external_call(global.vwaShim.poll);
        if (__vwaCmd != "")
        {
            var __vwaReply = "";
            try
            {
                __vwaReply = vwa_dev_dispatch(__vwaCmd);
            }
            catch (__vwaErr)
            {
                __vwaReply = "ERROR: " + string(__vwaErr);
                vwa_log("ERROR: dev dispatch failed for '" + __vwaCmd + "': " + string(__vwaErr));
            }
            external_call(global.vwaShim.reply, __vwaReply);
        }
    }
    catch (__vwaPumpErr)
    {
        // Watchdog: the pump must never take the game down.
        global.vwaShimReady = false;
        vwa_log("ERROR: dev pump crashed, pump disabled for this run: " + string(__vwaPumpErr));
    }
}

// The screen walker's frame tick (scrVwaTest): advances a running walk one
// step per frame, after the input tick's rerender and observe. Catches its
// own errors into the walk's failure list.
vwa_dev_walk_tick();
