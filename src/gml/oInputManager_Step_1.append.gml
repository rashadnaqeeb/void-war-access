// --- Void War Access input tick (appended by build-mod; ships in release) ---
// One vwa_input_tick per frame, in Begin Step so mod actions dispatch (and
// the suppression flag settles) before the game's own Step-event key reads.
// The exists-guard only protects against a failed boot patch; the tick has
// its own watchdog inside.
if (variable_global_exists("vwaInputTicks"))
{
    vwa_input_tick();
}
