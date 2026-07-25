// scrVwaEarcon - Void War Access earcon layer (piece 5, cursor events):
// named audio events through the mod's ONE audio chokepoint - the named
// events via vwa_earcon(name), the scanner direction tone via
// vwa_earcon_dir. Feature code never calls audio_* directly - it names
// an event; the event-to-sound mapping (the game's own sound assets,
// chosen by Rashad in play) lives here in vwa_earcon_sounds. Wired: the
// ship cursor's movement channel (scrVwaShipLayer) - wall-block, the
// airlock-block pair (airlock-open-block / airlock-closed-block: the
// airlock's live door-state sound layered with a hiss that marks it as
// an airlock; the layering is provisional, judged by ear in play), the
// door-cross events door-open / door-closed / door-battered - and the
// scanner channel (scrVwaShipScan) - scan-wrap plus the direction tone
// below. Selection events join with piece 6.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The scanner direction tone (vwa_earcon_dir(up, rt, withWrap)): a
// SPATIAL pointer to the announced entry, synthesized at play time -
// the straight-line tile offset from the cursor, cursor-relative
// up/right positive matching the spoken coordinate convention, NEVER
// the walking path the announcement speaks (the tone says where it IS,
// the spoken legs say how to walk there). ONE 55ms tone (5ms fades)
// carrying the whole vector - revised in play with Rashad from
// oni-access's vertical-then-horizontal two-segment sequence, keeping
// its three anchor frequencies:
// - PITCH is the vertical angle: the offset's angle fraction toward
//   vertical (arctan of |up|/|right|, 0 flat to 1 straight up or
//   down) blends from the 457Hz horizontal anchor toward 709Hz for up
//   or 297Hz for down, in LOG space so the blend is perceptually even
//   ("1 up 1 right" sounds halfway between middle and highest).
// - PAN is the horizontal fraction: constant-power toward the
//   offset's side, scaled by the remaining angle fraction - full pan
//   (1) due east or west, 0.5 at 45 degrees, center at pure vertical
//   (Rashad's calibration; oni-access's 0.79 cap dropped with the
//   two-segment shape).
// - LOUDNESS is straight-line (Euclidean) distance: baked base
//   amplitude 0.25 of full scale (sine RMS about -15 dBFS, calibrated
//   with ffmpeg against the game assets this layer already plays -
//   vs_ui_click2 mean -17 dB, sfxDoorOpen_crop mean -18 dB), falling
//   1 dB per tile and flooring at -20 dB (ratio 0.1) from 20 tiles
//   out - hulls run at most about 20 tiles across, so the whole
//   audible range maps onto real ship distances (oni-access reaches
//   the same floor over its hundreds-of-tiles maps; per-tile dB steps
//   stay perceptually even where a linear ramp would compress the
//   short distances that matter most).
// A zero-zero offset ("here") is the horizontal anchor at center, full
// loudness. withWrap layers the scan-wrap click into the same event
// (one user action, one interrupt). The tone AUGMENTS speech and its
// information lives in the spoken legs, so a failed tone logs but
// needs no spoken fallback.
//
// Settings-forward state (a future settings screen binds it; the
// default holds until then): global.vwaEarconDirTones (default true) -
// the direction-tone toggle; off suppresses only the tone, never the
// wrap click or the spoken announcement.
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
// applied at time 0, pitch untouched.
//
// Volume (decided in play with Rashad, replacing the earlier mod-side
// volume variable): per-play gain is 1.5 * global.volumeMax_SFX, read
// live - earcons ride 50 percent above the game's own sfx so they
// always overpower them, and the game's SFX slider stays the player's
// one volume control. Consequence, accepted: the slider at zero
// silences earcons too, with no spoken fallback (vwa_earcon's false
// means failed-to-start, never merely quiet). global.vwaEarconMute
// (dev builds: the test sweeps) zeroes the gain without touching
// playback - events still start and the tap still observes, so a
// dev-driven sweep does not bombard whoever is at the machine.
//
// One event = one or more sounds started together (the airlock
// layering; the wrap click plus direction tone of one scanner
// announcement). A new event STOPS the previous event's still-playing
// instances and frees the previous tone's buffer - the audio analog of
// the speech interrupt on direct user-caused movement, keeping fast
// arrowing and fast browsing crisp; only instances this module itself
// started are ever touched.
//
// Failure contract (never silent, never strand): a sound that fails to
// start logs ERROR; vwa_earcon returns whether EVERY sound of the event
// started, and each caller whose information exists nowhere else speaks
// its old localized token as the fallback when it returns false. An
// unknown event name throws - a mod bug, surfaced by the input
// watchdog.
//
// global.vwaEarconTap(name, ok, info), when set (dev builds: the test
// walkers), observes every event after its play attempt - the
// sanctioned observation hook on this chokepoint, mirroring
// global.vwaSpeakTap. info is undefined for named events and {up, rt}
// for the direction tone. It observes, never plays. Live audition
// through the dev driver: `call vwa_earcon <name>` or
// `call vwa_earcon_dir <up> <rt> <withWrap>`.

function vwa_earcon_init()
{
    global.vwaEarconMute = false;
    global.vwaEarconDirTones = true;
    global.vwaEarconLive = [];
    global.vwaEarconTone = undefined;
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
        case "scan-wrap":
            return [buttonSmall_doubleClick1_SmartSoundFXPOND5];
    }
    return undefined;
}

// The per-play gain (see the volume note in the header).
function vwa_earcon_gain()
{
    return global.vwaEarconMute ? 0 : (1.5 * global.volumeMax_SFX);
}

// Stop every still-playing instance this module started and free the
// previous direction tone's buffer sound (its instance was just
// stopped; the stop-then-free order is the probe-verified path). The
// start of every new event.
function vwa_earcon_stop_prev()
{
    for (var i = 0; i < array_length(global.vwaEarconLive); i++)
    {
        if (audio_is_playing(global.vwaEarconLive[i]))
        {
            audio_stop_sound(global.vwaEarconLive[i]);
        }
    }
    global.vwaEarconLive = [];
    if (global.vwaEarconTone != undefined)
    {
        audio_free_buffer_sound(global.vwaEarconTone.snd);
        buffer_delete(global.vwaEarconTone.buf);
        global.vwaEarconTone = undefined;
    }
}

// The observation hook's one call site shape (see header).
function vwa_earcon_tap_call(name, ok, info)
{
    if (variable_global_exists("vwaEarconTap") && global.vwaEarconTap != undefined)
    {
        var tapFn = global.vwaEarconTap;
        tapFn(name, ok, info);
    }
}

// Start every sound of a named event; logs each failure. Returns
// whether all started.
function vwa_earcon_play_assets(name, sounds)
{
    var gain = vwa_earcon_gain();
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
        audio_sound_gain(inst, gain, 0);
        array_push(global.vwaEarconLive, inst);
    }
    return ok;
}

// THE audio chokepoint for named events (see header). Returns whether
// every sound of the event started; the caller speaks its fallback
// token on false when the event's information exists nowhere else.
function vwa_earcon(name)
{
    var sounds = vwa_earcon_sounds(name);
    if (sounds == undefined)
    {
        throw ("earcon: unknown event " + string(name));
    }
    vwa_earcon_stop_prev();
    var ok = vwa_earcon_play_assets(name, sounds);
    vwa_earcon_tap_call(name, ok, undefined);
    return ok;
}

// PURE: one distance component's loudness ratio - 1 dB per tile,
// floored at -20 dB (ratio 0.1) from 20 tiles out (see header).
function vwa_earcon_dir_ratio(d)
{
    return power(10, -min(abs(d), 20) / 20);
}

// PURE: the direction tone's segment list for a straight-line tile
// offset (up positive up, rt positive right - the spoken coordinate
// convention). Always exactly ONE segment (see header): pitch blends
// the vertical angle across the 297/457/709 anchors in log space, pan
// scales toward the offset's side by the horizontal fraction, ratio is
// the Euclidean-distance falloff. A zero-zero offset is the horizontal
// anchor at center, full ratio - the "here" blip. Kept as a list: the
// synthesis loop stays segment-generic.
function vwa_earcon_dir_segments(up, rt)
{
    if (up == 0 && rt == 0)
    {
        return [{ freq: 457, pan: 0, ratio: 1 }];
    }
    var t = arctan2(abs(up), abs(rt)) / (pi / 2);
    var freq = 457;
    if (up > 0)
    {
        freq = 457 * power(709 / 457, t);
    }
    else if (up < 0)
    {
        freq = 457 * power(297 / 457, t);
    }
    return [{ freq: freq, pan: sign(rt) * (1 - t),
              ratio: vwa_earcon_dir_ratio(sqrt((up * up) + (rt * rt))) }];
}

// THE audio chokepoint for the scanner direction tone (see header).
// One event: withWrap layers the scan-wrap click in before the tone.
// The toggle suppresses only the tone. Synthesis: 48kHz stereo s16,
// 55ms segments (5ms fades), constant-power pan and the distance ratio
// baked per segment on the 0.25 base amplitude (the loop stays
// multi-segment-capable with a 10ms gap, though the current tone is a
// single segment); the buffer sound is freed by the NEXT event's stop
// (one outstanding tone at most). Failures log; the tone augments
// speech, so there is no spoken fallback (the walking legs carry the
// information).
function vwa_earcon_dir(up, rt, withWrap)
{
    vwa_earcon_stop_prev();
    var okAll = true;
    if (withWrap)
    {
        okAll = vwa_earcon_play_assets("scan-wrap", vwa_earcon_sounds("scan-wrap"));
        vwa_earcon_tap_call("scan-wrap", okAll, undefined);
    }
    if (!global.vwaEarconDirTones)
    {
        return okAll;
    }
    var segs = vwa_earcon_dir_segments(up, rt);
    var rate = 48000;
    var segN = 2640;   // 55ms
    var fadeN = 240;   // 5ms
    var gapN = 480;    // 10ms
    var total = (array_length(segs) * segN)
        + ((array_length(segs) - 1) * gapN);
    var buf = buffer_create(total * 4, buffer_fixed, 2);
    buffer_seek(buf, buffer_seek_start, 0);
    for (var s = 0; s < array_length(segs); s++)
    {
        if (s > 0)
        {
            for (var i = 0; i < gapN; i++)
            {
                buffer_write(buf, buffer_s16, 0);
                buffer_write(buf, buffer_s16, 0);
            }
        }
        var sg = segs[s];
        var ang = (sg.pan + 1) * pi / 4;
        var ampL = cos(ang);
        var ampR = sin(ang);
        var amp = 0.25 * 32767 * sg.ratio;
        for (var i = 0; i < segN; i++)
        {
            var env = 1;
            if (i < fadeN)
            {
                env = i / fadeN;
            }
            else if (i >= segN - fadeN)
            {
                env = (segN - i) / fadeN;
            }
            var v = sin(2 * pi * sg.freq * i / rate) * env * amp;
            buffer_write(buf, buffer_s16, round(v * ampL));
            buffer_write(buf, buffer_s16, round(v * ampR));
        }
    }
    var ok = true;
    var snd = audio_create_buffer_sound(buf, buffer_s16, rate, 0,
        total * 4, audio_stereo);
    if (snd < 0)
    {
        buffer_delete(buf);
        ok = false;
        vwa_log("ERROR: earcon: direction tone buffer sound failed ("
            + string(snd) + ")");
    }
    else
    {
        var inst = audio_play_sound(snd, 100, false);
        if (inst < 0)
        {
            audio_free_buffer_sound(snd);
            buffer_delete(buf);
            ok = false;
            vwa_log("ERROR: earcon: direction tone failed to play ("
                + string(inst) + ")");
        }
        else
        {
            audio_sound_gain(inst, vwa_earcon_gain(), 0);
            array_push(global.vwaEarconLive, inst);
            global.vwaEarconTone = { buf: buf, snd: snd };
        }
    }
    vwa_earcon_tap_call("scan-dir", ok, { up: up, rt: rt });
    return okAll && ok;
}
