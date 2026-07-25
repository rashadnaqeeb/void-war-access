// scrVwaEarcon - Void War Access earcon layer (piece 5, cursor events):
// named audio events through the mod's ONE audio chokepoint,
// vwa_earcon(name). Feature code never calls audio_* directly - it names
// an event; the event-to-sound mapping (the game's own sound assets,
// chosen by Rashad in play) lives here in vwa_earcon_sounds. Wired so
// far: the ship cursor's movement channel (scrVwaShipLayer) -
// wall-block, the airlock-block pair (airlock-open-block /
// airlock-closed-block: the airlock's live door-state sound layered
// with a hiss that marks it as an airlock; the layering is provisional,
// judged by ear in play), and the door-cross events door-open /
// door-closed / door-battered. The scanner events (wrap, direction
// tones) join when the scanner half of piece 5 builds; selection events
// join with piece 6.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// Playback is native GameMaker audio (the piece-5 audio-path decision,
// proven live by vwa_dev_earcon_probe), deliberately OUTSIDE the game's
// sfx_start/oSoundMgr path: earcons are navigation audio, so they must
// not be silenced by the game's SFX master toggle or volume slider,
// must not hit its per-step duplicate suppression, and must sound while
// the game is paused - command mode is the ship layer's core rhythm,
// and oSoundMgr's pausable registry would mute them exactly when they
// matter. audio_play_sound at priority 100 (gameplay sfx run at 1, so
// an earcon is never the voice stolen under load), per-instance gain
// from global.vwaEarconVolume applied at time 0, pitch untouched.
//
// One event = one or more sound assets started together (the airlock
// layering). A new event STOPS the previous event's still-playing
// instances - the audio analog of the speech interrupt on direct
// user-caused movement, keeping fast arrowing crisp; only instances
// this module itself started are ever touched.
//
// Failure contract (never silent, never strand): a sound that fails to
// start logs ERROR; vwa_earcon returns whether EVERY sound of the event
// started, and each caller whose information exists nowhere else speaks
// its old localized token as the fallback when it returns false. An
// unknown event name throws - a mod bug, surfaced by the input
// watchdog.
//
// global.vwaEarconTap(name, ok), when set (dev builds: the test
// walkers), observes every event after its play attempt - the
// sanctioned observation hook on this chokepoint, mirroring
// global.vwaSpeakTap. It observes, never plays. Live audition through
// the dev driver: `call vwa_earcon <name>`.
//
// Settings-forward state (a future settings screen binds it; the
// default holds until then): global.vwaEarconVolume (0..1, default 0.8,
// the probe's by-ear level) - the earcon layer's own volume, NEVER
// multiplied by global.volumeMax_SFX (the game's SFX slider must not be
// able to silence navigation audio).

function vwa_earcon_init()
{
    global.vwaEarconVolume = 0.8;
    global.vwaEarconLive = [];
    vwa_log("earcon: layer initialized");
}

// PURE (given the asset table): event name -> array of sound assets
// started together, or undefined for an unknown name (the chokepoint
// throws on it). The mapping is the sound-choice record; new events are
// new cases here.
function vwa_earcon_sounds(name)
{
    switch (name)
    {
        case "wall-block":
            return [vs_ui_click2];
        case "airlock-open-block":
            return [sfxDoorOpen_crop,
                clickHiss03b_filtered_EXOSKELETONBluezone_SmartSoundFXPOND5];
        case "airlock-closed-block":
            return [sfxDoorClose_crop,
                clickHiss03b_filtered_EXOSKELETONBluezone_SmartSoundFXPOND5];
        case "door-open":
            return [sfxDoorOpen_crop];
        case "door-closed":
            return [sfxDoorClose_crop];
        case "door-battered":
            return [Metlimpt_Ji_B_03_soundbits];
    }
    return undefined;
}

// THE audio chokepoint (see header). Returns whether every sound of the
// event started; the caller speaks its fallback token on false when the
// event's information exists nowhere else.
function vwa_earcon(name)
{
    var sounds = vwa_earcon_sounds(name);
    if (sounds == undefined)
    {
        throw ("earcon: unknown event " + string(name));
    }
    for (var i = 0; i < array_length(global.vwaEarconLive); i++)
    {
        if (audio_is_playing(global.vwaEarconLive[i]))
        {
            audio_stop_sound(global.vwaEarconLive[i]);
        }
    }
    global.vwaEarconLive = [];
    var ok = true;
    for (var i = 0; i < array_length(sounds); i++)
    {
        var inst = audio_play_sound(sounds[i], 100, false);
        if (inst < 0)
        {
            ok = false;
            vwa_log("ERROR: earcon: " + name + " sound "
                + audio_get_name(sounds[i]) + " failed to play");
            continue;
        }
        audio_sound_gain(inst, global.vwaEarconVolume, 0);
        array_push(global.vwaEarconLive, inst);
    }
    if (variable_global_exists("vwaEarconTap") && global.vwaEarconTap != undefined)
    {
        var tapFn = global.vwaEarconTap;
        tapFn(name, ok);
    }
    return ok;
}
