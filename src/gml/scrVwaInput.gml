// scrVwaInput - Void War Access input layer: action registry, category
// live-set resolution with focus-first shadowing, typematic key repeat, and
// the game-key gate: every keyboard read the GAME makes is denied by
// default and passes only by explicit mod allowance (session 13 flip; the
// old on-demand suppression flag is gone).
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The game-key gate model:
// - Two allowlists, independent axes. global.vwaGameAllowBinds holds game
//   keybind NAMES: build-mod patches scrKeybinds' three keyboard
//   input_check* wrappers to consult vwa_game_bind_allowed(bindName), so
//   the game's whole rebindable vocabulary is deny-by-default.
//   global.vwaGameAllowVks holds raw vk codes: build-mod routes the
//   verified player-facing raw keyboard_check* sites in game code (the
//   reads that can act on a key press alone - the Escape family, the ship
//   selector arrows, the start-message scroll, the music mute) through
//   vwa_game_kc / vwa_game_kcp, which consult vwa_game_vk_allowed(vk).
//   The site list and per-site asserts live in build-mod.csx; re-derive
//   the list from the decompile after any game update.
// - Feature code grants and revokes through vwa_game_allow_bind /
//   vwa_game_allow_vk; every toggle logs. Base allowance, seeded at init:
//   vk_escape only - the game's own Escape handling is the sanctioned
//   fallback wherever the mod does not act (mod screens consume Escape
//   when they do act). Everything else waits for an explicit allowance
//   from the context that wants it.
// - Fail open, never closed: before vwa_input_init the predicates answer
//   true (a failed boot patch must leave the game playable), and the tick
//   watchdog sets global.vwaGameKeysOpen on a crash, overriding both
//   lists until cleared by hand (sticky: a flapping fault must not
//   flicker the keyboard; /state reports it). A mod bug can never leave
//   the game's keyboard dead.
// - Raw sites left ungated, by design: text-field objects (typing must
//   always work; scrVwaText manages them), the keybind-capture object
//   (oKeybindSetter), reads behind enableDebugKeys / enableDevMode /
//   drawDebugF*, and modifier-only reads (Shift/Ctrl/Alt flavoring an
//   action whose main key is already gated).
//
// This script is the ONE sanctioned home of raw keyboard_check* calls in mod
// code: feature code registers actions and never reads keys itself.
// (vwa_game_kc / vwa_game_kcp are called from patched GAME code, not from
// mod feature code.)
//
// Categories are plain strings ("global", "ui", "ship", "targeting",
// "dev"); enums are avoided because the UTMT importer compiles each code
// entry separately and cross-entry enum visibility is not guaranteed.
// Priority comes from vwa_live_categories(): screens on the stack contribute
// their categories focused-first, then active MODES, then "global", always
// live, last. "targeting" is reserved; "dev" is only live while a dev/test
// screen declares it.
//
// Modes (vwa_mode_register): input context that is not a screen - the ship
// layer (scrVwaShipLayer) is spatial and never enters the stack. A mode is
// { key, category, isActive }; its category joins the live list only while
// isActive() answers true AND the screen stack is empty - any stacked
// screen (a menu, an encounter popup screen, a dev synthetic screen)
// suspends every mode, so the open thing's own handler takes over and the
// mode resumes when the stack clears.

function vwa_input_init()
{
    global.vwaActions = {};      // actionKey -> action struct
    global.vwaActionOrder = [];  // registration order: stable dumps, shadow tie-breaks
    global.vwaScreenStack = [];  // owned by scrVwaScreens once vwa_screens_init runs
    global.vwaModes = [];        // mode providers (see header): {key, category, isActive}
    global.vwaChordState = {};   // string(vk) -> {vk, actionKey, downAt, lastFire} for edge + repeat
    global.vwaGameAllowBinds = {};  // game keybind names allowed through input_check*
    global.vwaGameAllowVks = {};    // raw vk codes (string keys) allowed through the patched raw sites
    global.vwaGameKeysOpen = false; // watchdog fail-open: overrides both allowlists
    global.vwaInputFault = false;           // armed by the dev driver to test the watchdog
    global.vwaInputWatchdogTripped = false; // sticky until cleared; /state reports it
    global.vwaInputTicks = 0;

    // OS typematic settings via the shim; defaults when the shim is absent.
    global.vwaKeyDelayMs = 500;
    global.vwaKeyRateMs = 50;
    if (global.vwaShim != undefined)
    {
        global.vwaKeyDelayMs = external_call(global.vwaShim.keyDelay);
        global.vwaKeyRateMs = external_call(global.vwaShim.keyRate);
    }

    // Base gate allowance: the game's Escape handling is the sanctioned
    // fallback wherever the mod does not act (see header).
    vwa_game_allow_vk(vk_escape, true);

    vwa_register_global_actions();
    vwa_log("input: layer initialized (repeat delay " + string(global.vwaKeyDelayMs)
        + "ms, rate " + string(global.vwaKeyRateMs) + "ms)");
}

// binding: struct from vwa_bind(), or an array of them - any listed chord
// fires the action (stored as a list so a second key can be added without
// reshaping the registry).
// repeats: typematic repeat while held.
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
    variable_struct_set(a, "bindings", is_array(binding) ? binding : [binding]);
    variable_struct_set(a, "repeats", repeats);
    variable_struct_set(a, "handler", handler);
    // textSafe: still dispatches while the game's text-field input is
    // active. Only for chords that cannot type a character into the field
    // (set after registration; see vwa_register_global_actions).
    variable_struct_set(a, "textSafe", false);
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
// screen's categories in declared order, then active mode categories (only
// while the stack is empty - see the mode paragraph in the header), then
// "global". An exclusive screen (a hard modal) blocks the categories of
// every screen below it.
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
    if (array_length(stack) == 0)
    {
        for (var i = 0; i < array_length(global.vwaModes); i++)
        {
            var m = global.vwaModes[i];
            if (m.isActive() && vwa_array_index_of(cats, m.category) < 0)
            {
                array_push(cats, m.category);
            }
        }
    }
    if (vwa_array_index_of(cats, "global") < 0)
    {
        array_push(cats, "global");
    }
    return cats;
}

// Register a mode provider (see header). Modes never unregister; liveness
// is entirely the isActive predicate.
function vwa_mode_register(m)
{
    array_push(global.vwaModes, m);
    vwa_log("input: mode registered: " + m.key + " (category " + m.category + ")");
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
    var a = variable_struct_get(global.vwaActions, actionKey);
    if (global.textFieldInputEnabled && !a.textSafe)
    {
        throw "text field input active; actions suppressed";
    }
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
// fails the game-key gate open and logs loudly.
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
        vwa_input_unstick_keys();
        // Screen layer first (resolve/diff the stack, sync focus, announce),
        // so the live category set is current when chords dispatch below.
        // Type-ahead runs between the two: it sees the fresh stack, and a
        // landing it makes is current when the actions dispatch.
        if (variable_global_exists("vwaScreens"))
        {
            vwa_screens_tick();
            vwa_nav_typeahead_tick();
        }
        // Text edit layer next (scrVwaText): announces edit-mode edges and
        // backspace feedback, so the dispatch below sees the same flag
        // state the tick observed.
        if (variable_global_exists("vwaText"))
        {
            vwa_text_tick();
        }
        // While the game's text-field input is active, only text-safe
        // actions dispatch: the speech controls must never go dead while
        // the player is typing (never strand the user).
        vwa_input_dispatch(global.textFieldInputEnabled);
        // The focused screen's post-dispatch hook (raw-key consumes that
        // must land AFTER the mod's own chords resolved but BEFORE the
        // game's Step-event reads; see scrVwaScreens' header).
        if (variable_global_exists("vwaScreens"))
        {
            vwa_screens_post_dispatch();
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
        global.vwaGameKeysOpen = true;
        global.vwaInputWatchdogTripped = true;
        vwa_log("ERROR: input tick crashed; game-key gate failed open, every game key live: "
            + string(err));
    }
}

// ---- game-key gate (see header for the model) ----

// Called from the patched input_check* wrappers in scrKeybinds, so it runs
// on every game key poll: fail open before init and under the watchdog,
// otherwise allow only listed bind names.
function vwa_game_bind_allowed(bindName)
{
    if (!variable_global_exists("vwaGameAllowBinds") || global.vwaGameKeysOpen)
    {
        return true;
    }
    return variable_struct_exists(global.vwaGameAllowBinds, bindName);
}

function vwa_game_vk_allowed(vk)
{
    if (!variable_global_exists("vwaGameAllowVks") || global.vwaGameKeysOpen)
    {
        return true;
    }
    return variable_struct_exists(global.vwaGameAllowVks, string(vk));
}

// The patched raw sites in game code call these in place of
// keyboard_check / keyboard_check_pressed (site list in build-mod.csx).
function vwa_game_kc(vk)
{
    return vwa_game_vk_allowed(vk) && keyboard_check(vk);
}

function vwa_game_kcp(vk)
{
    return vwa_game_vk_allowed(vk) && keyboard_check_pressed(vk);
}

function vwa_game_allow_bind(bindName, on)
{
    if (on)
    {
        variable_struct_set(global.vwaGameAllowBinds, bindName, true);
    }
    else
    {
        variable_struct_remove(global.vwaGameAllowBinds, bindName);
    }
    vwa_log("input: game bind " + string(bindName) + (on ? " allowed" : " denied"));
}

function vwa_game_allow_vk(vk, on)
{
    if (on)
    {
        variable_struct_set(global.vwaGameAllowVks, string(vk), true);
    }
    else
    {
        variable_struct_remove(global.vwaGameAllowVks, string(vk));
    }
    vwa_log("input: game key vk " + string(vk) + (on ? " allowed" : " denied"));
}

// The background keepalive (the shim's WndProc subclass) swallows the
// focus-loss messages that normally make the runner clear its key state, so
// a key pressed while switching windows reads "held" forever - its release
// went to another window. A stale modifier silently breaks exact-modifier
// chord matching (a pinned Alt; bit us session 4); a stale non-modifier is
// worse: a repeating action (arrows) fires forever (session-7 review).
// Detect the lie with keyboard_check_direct (real OS state, ignoring window
// focus) and reset the runner's bookkeeping. This io_clear only fires when
// the runner claims a key the OS reports up, so no real input can be
// discarded; it logs every time.
function vwa_input_unstick_keys()
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
    // keyboard_key is the runner's current held key (0 = none, and 0 during
    // the freshly-booted "phantom hold" quirk, so > 0 skips both). The
    // generic modifier codes are excluded: keyboard_check_direct is only
    // verified against their left/right variants, which the checks above
    // use.
    if (!stale && keyboard_key > 0
        && keyboard_key != vk_shift && keyboard_key != vk_control
        && keyboard_key != vk_alt
        && !keyboard_check_direct(keyboard_key))
    {
        stale = true;
    }
    if (stale)
    {
        io_clear();
        vwa_log("input: cleared stale key state (runner held a key the OS reports up)");
    }
}

// Drain the runner's typed-character buffer for the type-ahead layer.
// Lives here: this script is the one sanctioned home of raw keyboard reads.
// keyboard_string is drained every eligible frame so stale characters can
// never flush into a later search; it is never touched while the game's
// text-field mode owns it (oTextField reads and clears it itself), and the
// type-ahead tick discards the first drain after that mode ends (leftover
// characters belonged to the field). Returns "" while Ctrl or Alt is held -
// chords are not typing.
function vwa_input_take_typed()
{
    if (global.textFieldInputEnabled)
    {
        return "";
    }
    var typed = keyboard_string;
    keyboard_string = "";
    if (keyboard_check(vk_control) || keyboard_check(vk_alt))
    {
        return "";
    }
    return typed;
}

// Consume a key press a mod handler just acted on, so the game's own raw
// keyboard_check(_pressed) reads do not also act on it this frame (settings
// closes on Escape, the ship selector cycles hulls on the arrows - raw and
// ungated, even mid-text-edit). Our tick runs in Begin Step, before every
// game Step/Draw read, and keyboard_clear is the game's own consume
// mechanism (oUIConfirmationDialogue Step_0 does exactly this). A held key
// re-asserts through OS auto-repeat, so consuming does not wedge it. Lives
// here because this script is the one sanctioned home of raw keyboard
// functions.
function vwa_input_consume_key(vk)
{
    keyboard_clear(vk);
}

function vwa_input_consume_escape()
{
    vwa_input_consume_key(vk_escape);
}

// Append characters to the runner's typed buffer as if the player had
// typed them; keyboard_string is what the game's oTextField consumes. Only
// the dev driver calls this (vwa_dev_type) - real typing needs no help.
function vwa_input_inject_typed(txt)
{
    keyboard_string = keyboard_string + string(txt);
}

function vwa_input_dispatch(textOnly)
{
    var live = vwa_live_categories();

    // Resolve shadowing first: per chord, the action whose category sits
    // earliest in the live list wins this frame (registration order breaks
    // ties). Only then look at edge/repeat state, which is per main key.
    var winners = {};
    for (var i = 0; i < array_length(global.vwaActionOrder); i++)
    {
        var a = variable_struct_get(global.vwaActions, global.vwaActionOrder[i]);
        if (textOnly && !a.textSafe)
        {
            continue;
        }
        var prio = vwa_array_index_of(live, a.category);
        if (prio < 0)
        {
            continue;
        }
        for (var bi = 0; bi < array_length(a.bindings); bi++)
        {
            var bnd = a.bindings[bi];
            if (!vwa_chord_down(bnd))
            {
                continue;
            }
            var cid = vwa_chord_id(bnd);
            var w = variable_struct_get(winners, cid);
            if (w == undefined || prio < w.prio)
            {
                variable_struct_set(winners, cid, { a: a, prio: prio, bnd: bnd });
            }
        }
    }

    var now = current_time;
    var cids = variable_struct_get_names(winners);
    for (var i = 0; i < array_length(cids); i++)
    {
        var w = variable_struct_get(winners, cids[i]);
        var a = w.a;
        // Edge/repeat state is keyed by the MAIN key alone, not the full
        // chord id: releasing a fired chord's modifier while the main key
        // is still held must not mint a fresh edge for the modifier-less
        // chord (Shift+Tab with Shift released first fired nav-next
        // straight back; session-7 review). A different action landing on
        // an already-held main key waits for a fresh press.
        var skey = string(w.bnd.vk);
        var st = variable_struct_get(global.vwaChordState, skey);
        if (st == undefined)
        {
            // Fresh press of the main key: fire once.
            variable_struct_set(global.vwaChordState, skey,
                { vk: w.bnd.vk, actionKey: a.actionKey, downAt: now, lastFire: now });
            vwa_action_invoke(a);
        }
        else if (st.actionKey == a.actionKey
            && a.repeats && now - st.downAt >= global.vwaKeyDelayMs
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
    // The speech controls survive text entry (never strand the user while
    // typing): neither chord can type a character into a field.
    variable_struct_get(global.vwaActions, "speech-stop").textSafe = true;
    variable_struct_get(global.vwaActions, "panic-reset").textSafe = true;
}
