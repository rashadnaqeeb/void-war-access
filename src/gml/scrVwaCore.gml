// scrVwaCore - Void War Access core: logging, localization wrapper, the
// speech chokepoint, and shim binding. The dev-driver command dispatcher
// lives in scrVwaDev (dev builds only).
// Imported by tools/build-mod.csx as a new global script.

function vwa_pad2(n)
{
    var s = string(n);
    if (string_length(s) < 2)
    {
        s = "0" + s;
    }
    return s;
}

function vwa_timestamp()
{
    return vwa_pad2(current_hour) + ":" + vwa_pad2(current_minute) + ":" + vwa_pad2(current_second);
}

// Mod log, in the save dir (%AppData%\Roaming\Void_War\vwa-mod.log).
// Every guarded failure path in the mod reports here - no silent failures.
function vwa_log(msg)
{
    var f = file_text_open_append("vwa-mod.log");
    file_text_write_string(f, vwa_timestamp() + " " + string(msg));
    file_text_writeln(f);
    file_text_close(f);
}

// Localized mod string. Mod strings ship as vwa-- rows merged into the
// game's own lang CSVs, so they route through the same localization the
// game uses. Falls back to the key itself (logged) rather than silence.
function vwa_t(key)
{
    var s = localizedUIText_get(key);
    if (s == undefined)
    {
        vwa_log("ERROR: missing localized string for key " + key);
        return key;
    }
    return s;
}

// Resolve the directory holding the patched data.win (and therefore the
// shim DLL) from the -game command-line argument.
function vwa_shim_dll_path()
{
    for (var i = 0; i <= parameter_count(); i++)
    {
        if (parameter_string(i) == "-game" && i + 1 <= parameter_count())
        {
            var p = parameter_string(i + 1);
            for (var j = string_length(p); j >= 1; j--)
            {
                var c = string_char_at(p, j);
                if (c == "\\" || c == "/")
                {
                    return string_copy(p, 1, j) + "vw_speech.dll";
                }
            }
        }
    }
    return "vw_speech.dll";
}

// Bind the shim's exports. Returns true when the DLL is loaded and
// initialized; on any failure the mod still runs, capture-to-file only.
function vwa_shim_init()
{
    global.vwaShim = undefined;
    var dllPath = vwa_shim_dll_path();
    try
    {
        var shim = {
            init: external_define(dllPath, "vw_init", dll_cdecl, ty_real, 0),
            speak: external_define(dllPath, "vw_speak", dll_cdecl, ty_real, 2, ty_string, ty_real),
            stopSpeech: external_define(dllPath, "vw_stop", dll_cdecl, ty_real, 0),
            backendName: external_define(dllPath, "vw_backend_name", dll_cdecl, ty_string, 0),
            poll: external_define(dllPath, "vw_poll", dll_cdecl, ty_string, 0),
            reply: external_define(dllPath, "vw_reply", dll_cdecl, ty_real, 1, ty_string),
            keyDelay: external_define(dllPath, "vw_key_delay", dll_cdecl, ty_real, 0),
            keyRate: external_define(dllPath, "vw_key_rate", dll_cdecl, ty_real, 0),
            resetSpeech: external_define(dllPath, "vw_reset_speech", dll_cdecl, ty_real, 0),
            shutdownShim: external_define(dllPath, "vw_shutdown", dll_cdecl, ty_real, 0)
        };
        var tier = external_call(shim.init);
        global.vwaShim = shim;
        vwa_log("shim loaded from " + dllPath + ", tier " + string(tier)
            + ", backend " + string(external_call(shim.backendName)));
        return true;
    }
    catch (err)
    {
        vwa_log("ERROR: shim load failed from " + dllPath + ": " + string(err));
        return false;
    }
}

// The chokepoint's pure join, factored out so the in-game walker
// (scrVwaTest, dev builds) can render the expected text of a parts array
// through the exact code the chokepoint uses. Two shapes (Rashad's line
// model, session 10):
// - flat: every element a string (or struct with .text) - ONE spoken line,
//   parts joined with ", " (the classic announcement).
// - line-structured: ANY element being an array makes every element a LINE
//   (a flat element is a one-part line); parts join with ", " within a
//   line, lines join with "\n". Newlines are what the alt+up/down line
//   review steps through, and screen readers pause at them.
function vwa_speak_render(parts)
{
    var text = "";
    var lined = false;
    for (var i = 0; i < array_length(parts); i++)
    {
        if (is_array(parts[i]))
        {
            lined = true;
            break;
        }
    }
    for (var i = 0; i < array_length(parts); i++)
    {
        var line = is_array(parts[i]) ? parts[i] : [parts[i]];
        var lineText = "";
        for (var j = 0; j < array_length(line); j++)
        {
            var part = line[j];
            var s = is_struct(part) ? string(part.text) : string(part);
            if (s == "")
            {
                continue;
            }
            if (lineText != "")
            {
                lineText += ", ";
            }
            lineText += s;
        }
        if (lineText == "")
        {
            continue;
        }
        if (text != "")
        {
            text += lined ? "\n" : ", ";
        }
        text += lineText;
    }
    return text;
}

// THE speech chokepoint. Every spoken string in the mod flows through here:
// feature code hands over an array of parts; joining happens only in
// vwa_speak_render above.
// Each utterance is appended to vwa-speech.log in the save dir before the
// shim is involved, so speech is diagnosable even with no DLL at all
// (a multi-line utterance is one log entry per line, indented after the
// first, so the log stays one-utterance-per-entry greppable).
// global.vwaSpeakTap, when set (dev builds: the scrVwaTest walker), receives
// every utterance's final text - the sanctioned observation point for
// in-game speech verification. It must never speak.
function vwa_speak(parts, interrupt)
{
    var text = "";
    if (is_array(parts))
    {
        text = vwa_speak_render(parts);
    }
    else
    {
        // Composition discipline violation - speak anyway (never strand),
        // but make the offending call site findable.
        vwa_log("WARNING: vwa_speak called with non-array parts: " + string(parts));
        text = string(parts);
    }
    if (text == "")
    {
        return;
    }

    if (variable_global_exists("vwaSpeakTap") && global.vwaSpeakTap != undefined)
    {
        var tapFn = global.vwaSpeakTap;
        tapFn(text, interrupt);
    }

    var f = file_text_open_append("vwa-speech.log");
    file_text_write_string(f, string_replace_all(text, "\n", "\n  "));
    file_text_writeln(f);
    file_text_close(f);

    if (global.vwaShim != undefined)
    {
        var rc = external_call(global.vwaShim.speak, text, interrupt ? 1 : 0);
        if (rc < 0)
        {
            vwa_log("ERROR: vw_speak returned " + string(rc) + " for: " + text);
        }
    }
}

// Speech-stack controls live here so feature code never touches the shim
// directly (the same rule as the vwa_speak chokepoint).

function vwa_stop_speech()
{
    if (global.vwaShim == undefined)
    {
        vwa_log("stop: no shim loaded; nothing to stop");
        return;
    }
    var rc = external_call(global.vwaShim.stopSpeech);
    if (rc < 0)
    {
        vwa_log("ERROR: vw_stop returned " + string(rc));
    }
}

// The panic action: never strand the user. If the shim never loaded, retry
// the full load; otherwise tear down and re-create the speech backends.
// Always speaks (and therefore logs) a confirmation so the user knows the
// panic key did something even when only the file capture is left.
function vwa_speech_panic()
{
    vwa_log("panic: speech stack reset requested");
    if (global.vwaShim == undefined)
    {
        if (vwa_shim_init())
        {
            global.vwaShimReady = true;
        }
    }
    else
    {
        var tier = external_call(global.vwaShim.resetSpeech);
        vwa_log("panic: shim reset, tier " + string(tier));
    }
    var backend = (global.vwaShim != undefined)
        ? string(external_call(global.vwaShim.backendName))
        : "no shim (file capture only)";
    vwa_speak([vwa_t("vwa--speech-reset"), backend], true);
}

// Orderly shim teardown, called from oGlobal's Game End event (appended by
// build-mod; fires on quit and on window close, at the menu and in-run).
// Without it vw_shutdown is never called in a real run: the subclassed
// WndProc and the server thread persist to process kill, and a teardown
// path that unloads the DLL before the window dies would leave the window
// dispatching into unmapped code (session-7 review).
function vwa_shim_shutdown()
{
    if (global.vwaShim == undefined)
    {
        vwa_log("shutdown: no shim loaded; nothing to tear down");
        return;
    }
    vwa_log("shutdown: game end, tearing down shim");
    external_call(global.vwaShim.shutdownShim);
    global.vwaShimReady = false;
    global.vwaShim = undefined;
}
