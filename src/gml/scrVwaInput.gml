// scrVwaInput - Void War Access input layer: action registry, category
// live-set resolution with focus-first shadowing, typematic key repeat, and
// the suppression flag the game's own key reads honor (build-mod patches
// scrKeybinds' input_check* to return false while
// global.vwaSuppressGameKeys is true).
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// This script is the ONE sanctioned home of raw keyboard_check* calls in mod
// code: feature code registers actions and never reads keys itself.
//
// Categories are plain strings ("global", "ui", "combat", "targeting",
// "dev"); enums are avoided because the UTMT importer compiles each code
// entry separately and cross-entry enum visibility is not guaranteed.
// Priority comes from vwa_live_categories(): screens on the stack contribute
// their categories focused-first, and "global" is always live, last.
// "targeting" is reserved; "dev" is only live while a dev/test screen
// declares it.

function vwa_input_init()
{
    global.vwaActions = {};      // actionKey -> action struct
    global.vwaActionOrder = [];  // registration order: stable dumps, shadow tie-breaks
    global.vwaScreenStack = [];  // owned by scrVwaScreens once vwa_screens_init runs
    global.vwaChordState = {};   // chordId -> {vk, downAt, lastFire} for edge + repeat
    global.vwaSuppressGameKeys = false;
    global.vwaInputFault = false;           // armed by the dev driver to test the watchdog
    global.vwaInputWatchdogTripped = false; // sticky until cleared; /state reports it
    global.vwaInputTicks = 0;
    if (!variable_global_exists("vwaLastSpoken"))
    {
        global.vwaLastSpoken = "";
    }

    // OS typematic settings via the shim; defaults when the shim is absent.
    global.vwaKeyDelayMs = 500;
    global.vwaKeyRateMs = 50;
    if (global.vwaShim != undefined)
    {
        global.vwaKeyDelayMs = external_call(global.vwaShim.keyDelay);
        global.vwaKeyRateMs = external_call(global.vwaShim.keyRate);
    }

    vwa_register_global_actions();
    vwa_log("input: layer initialized (repeat delay " + string(global.vwaKeyDelayMs)
        + "ms, rate " + string(global.vwaKeyRateMs) + "ms)");
}

// binding: struct from vwa_bind(). repeats: typematic repeat while held.
// handler: a zero-argument function; handlers speak via vwa_speak only.
function vwa_action_register(actionKey, labelKey, category, binding, repeats, handler)
{
    if (variable_struct_exists(global.vwaActions, actionKey))
    {
        vwa_log("input: re-registering action " + actionKey);
    }
    else
    {
        array_push(global.vwaActionOrder, actionKey);
    }
    var a = {};
    variable_struct_set(a, "actionKey", actionKey);
    variable_struct_set(a, "labelKey", labelKey);
    variable_struct_set(a, "category", category);
    variable_struct_set(a, "binding", binding);
    variable_struct_set(a, "repeats", repeats);
    variable_struct_set(a, "handler", handler);
    variable_struct_set(global.vwaActions, actionKey, a);
}

function vwa_bind(vkCode, needShift, needCtrl, needAlt)
{
    return { vk: vkCode, shift: needShift, ctrl: needCtrl, alt: needAlt };
}

function vwa_array_index_of(arr, v)
{
    for (var i = 0; i < array_length(arr); i++)
    {
        if (arr[i] == v)
        {
            return i;
        }
    }
    return -1;
}

// Identical chords in two live categories shadow by this id.
function vwa_chord_id(binding)
{
    return string(binding.vk)
        + (binding.shift ? "s" : "")
        + (binding.ctrl ? "c" : "")
        + (binding.alt ? "a" : "");
}

// Exact modifier match, except a modifier that IS the main key is exempt
// (so plain Ctrl can be a binding: classic screen-reader speech stop).
function vwa_chord_down(binding)
{
    if (!keyboard_check(binding.vk))
    {
        return false;
    }
    if (binding.vk != vk_shift && keyboard_check(vk_shift) != binding.shift)
    {
        return false;
    }
    if (binding.vk != vk_control && keyboard_check(vk_control) != binding.ctrl)
    {
        return false;
    }
    if (binding.vk != vk_alt && keyboard_check(vk_alt) != binding.alt)
    {
        return false;
    }
    return true;
}

// Priority-ordered live category list: stack top (focused) first, each
// screen's categories in declared order, then "global". An exclusive screen
// (a hard modal) blocks the categories of every screen below it.
function vwa_live_categories()
{
    var cats = [];
    var stack = global.vwaScreenStack;
    for (var i = array_length(stack) - 1; i >= 0; i--)
    {
        var scats = stack[i].categories;
        for (var j = 0; j < array_length(scats); j++)
        {
            if (vwa_array_index_of(cats, scats[j]) < 0)
            {
                array_push(cats, scats[j]);
            }
        }
        if (variable_struct_exists(stack[i], "exclusive") && stack[i].exclusive)
        {
            break;
        }
    }
    if (vwa_array_index_of(cats, "global") < 0)
    {
        array_push(cats, "global");
    }
    return cats;
}

function vwa_action_invoke(a)
{
    var h = variable_struct_get(a, "handler");
    h();
}

// Fire an action by key through the same liveness rules as a physical press
// (the dev driver's POST /input lands here). Throws plain strings on
// refusal; the dev pump surfaces them as ERROR replies.
function vwa_input_fire(actionKey)
{
    if (!variable_struct_exists(global.vwaActions, actionKey))
    {
        throw ("no such action: " + actionKey);
    }
    if (global.textFieldInputEnabled)
    {
        throw "text field input active; actions suppressed";
    }
    var a = variable_struct_get(global.vwaActions, actionKey);
    var live = vwa_live_categories();
    if (vwa_array_index_of(live, a.category) < 0)
    {
        throw ("action " + actionKey + " not live (category " + a.category
            + "; live: " + string(live) + ")");
    }
    vwa_action_invoke(a);
    return "fired " + actionKey;
}

// Once per frame from oInputManager Begin Step, before the game's own
// Step-event key reads. The watchdog is a sanctioned swallow-and-log spot:
// a mod bug must never leave the game's keyboard dead, so any error here
// clears the suppression flag and logs loudly.
function vwa_input_tick()
{
    global.vwaInputTicks += 1;
    try
    {
        if (global.vwaInputFault)
        {
            global.vwaInputFault = false;
            throw "injected test fault (vwa_dev_arm_input_fault)";
        }
        vwa_input_unstick_modifiers();
        // Screen layer first (resolve/diff the stack, sync focus, announce),
        // so the live category set is current when chords dispatch below.
        if (variable_global_exists("vwaScreens"))
        {
            vwa_screens_tick();
        }
        if (!global.textFieldInputEnabled)
        {
            vwa_input_dispatch();
        }
        // Release chord state once the main key is up, so the next press is
        // a fresh edge. (Kept while a chord is merely broken by a modifier
        // change: re-completing a held non-repeat chord must not re-fire.)
        var ids = variable_struct_get_names(global.vwaChordState);
        for (var i = 0; i < array_length(ids); i++)
        {
            var st = variable_struct_get(global.vwaChordState, ids[i]);
            if (!keyboard_check(st.vk))
            {
                variable_struct_remove(global.vwaChordState, ids[i]);
            }
        }
    }
    catch (err)
    {
        global.vwaSuppressGameKeys = false;
        global.vwaInputWatchdogTripped = true;
        vwa_log("ERROR: input tick crashed; suppression cleared, game keys live again: "
            + string(err));
    }
}

// The background keepalive (the shim's WndProc subclass) swallows the
// focus-loss messages that normally make the runner clear its key state, so
// a modifier pressed while switching windows reads "held" forever - its
// release went to another window. That silently breaks exact-modifier chord
// matching (a stale Alt pinned keyboard_check(vk_alt) for minutes; bit us
// session 4). Detect the lie with keyboard_check_direct (real OS state,
// ignoring window focus) and reset the runner's bookkeeping. This io_clear
// only fires when the runner claims a modifier the OS reports up, so no
// real input can be discarded; it logs every time.
function vwa_input_unstick_modifiers()
{
    var stale = false;
    if (keyboard_check(vk_shift) && !keyboard_check_direct(vk_lshift)
        && !keyboard_check_direct(vk_rshift))
    {
        stale = true;
    }
    if (keyboard_check(vk_control) && !keyboard_check_direct(vk_lcontrol)
        && !keyboard_check_direct(vk_rcontrol))
    {
        stale = true;
    }
    if (keyboard_check(vk_alt) && !keyboard_check_direct(vk_lalt)
        && !keyboard_check_direct(vk_ralt))
    {
        stale = true;
    }
    if (stale)
    {
        io_clear();
        vwa_log("input: cleared stale modifier state (runner held a modifier the OS reports up)");
    }
}

// Consume an Escape press a mod screen just handled, so the game's own raw
// keyboard_check(_pressed)(vk_escape) menu handlers (settings closes on
// Escape, the popup dismisses on Escape) do not also act on it this frame.
// Our tick runs in Begin Step, before every game Step/Draw read, and
// keyboard_clear is the game's own consume mechanism
// (oUIConfirmationDialogue Step_0 does exactly this). Lives here because
// this script is the one sanctioned home of raw keyboard functions.
function vwa_input_consume_escape()
{
    keyboard_clear(vk_escape);
}

function vwa_input_dispatch()
{
    var live = vwa_live_categories();

    // Resolve shadowing first: per chord, the action whose category sits
    // earliest in the live list wins this frame (registration order breaks
    // ties). Only then look at edge/repeat state, which is chord-level.
    var winners = {};
    for (var i = 0; i < array_length(global.vwaActionOrder); i++)
    {
        var a = variable_struct_get(global.vwaActions, global.vwaActionOrder[i]);
        var prio = vwa_array_index_of(live, a.category);
        if (prio < 0)
        {
            continue;
        }
        if (!vwa_chord_down(a.binding))
        {
            continue;
        }
        var cid = vwa_chord_id(a.binding);
        var w = variable_struct_get(winners, cid);
        if (w == undefined || prio < w.prio)
        {
            variable_struct_set(winners, cid, { a: a, prio: prio });
        }
    }

    var now = current_time;
    var cids = variable_struct_get_names(winners);
    for (var i = 0; i < array_length(cids); i++)
    {
        var a = variable_struct_get(winners, cids[i]).a;
        var st = variable_struct_get(global.vwaChordState, cids[i]);
        if (st == undefined)
        {
            // Fresh chord (or one completed late by a modifier): fire once.
            variable_struct_set(global.vwaChordState, cids[i],
                { vk: a.binding.vk, downAt: now, lastFire: now });
            vwa_action_invoke(a);
        }
        else if (a.repeats && now - st.downAt >= global.vwaKeyDelayMs
            && now - st.lastFire >= global.vwaKeyRateMs)
        {
            st.lastFire = now;
            vwa_action_invoke(a);
        }
    }
}

// The always-live starter actions. Bindings avoid every key the game binds
// (letters, digits, space/tab/enter/backslash/minus/equals, F1): Ctrl and
// the high F-keys are free. Rebinding UI arrives with the settings work.
function vwa_register_global_actions()
{
    vwa_action_register("repeat-last", "vwa--action-repeat-last", "global",
        vwa_bind(vk_f11, false, false, false), false, function()
        {
            if (global.vwaLastSpoken == "")
            {
                vwa_speak([vwa_t("vwa--nothing-to-repeat")], true);
            }
            else
            {
                vwa_speak([global.vwaLastSpoken], true);
            }
        });
    vwa_action_register("speech-stop", "vwa--action-stop-speech", "global",
        vwa_bind(vk_control, false, false, false), false, function()
        {
            vwa_stop_speech();
        });
    vwa_action_register("panic-reset", "vwa--action-panic-reset", "global",
        vwa_bind(vk_f11, true, false, false), false, function()
        {
            vwa_speech_panic();
        });
}
