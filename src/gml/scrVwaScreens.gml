// scrVwaScreens - Void War Access screen layer: the screen registry, the
// per-frame poll-and-diff stack resolve, focus sync, and the navigator (the
// UI-category actions that move the graph cursor, plus the once-per-frame
// observe that speaks focus changes). Ported from WotR Access's
// Screens/ScreenManager + Screen and UI/Navigator, on the GML graph engine
// in scrVwaGraph and the composer in scrVwaAnnounce.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// A screen is a struct registered once at boot (or lazily by dev tooling):
//   key        stable string identity (stack diffing, /gui/mod)
//   layerNum   stack order: higher sits on top; the top screen is focused
//   isActive   fn() -> bool, polled every frame (poll-and-diff: the game
//              owns whether a screen is showing; we never track open/close)
//   name       fn() -> spoken screen name ("" = silent), or undefined
//   build      fn(builder) declaring the control graph fresh from live game
//              state (immediate mode), or undefined for a graph-less screen
//   categories input categories this screen keeps live while stacked
//   exclusive  true = a hard modal: screens below it contribute no input
//              categories (vwa_live_categories in scrVwaInput honors this)
//
// Speech rules implemented here (the invariants): the tick is the ONE place
// framework speech happens, once per observed change; screen-name
// announcements never interrupt; a focus move within a screen interrupts
// (genuine focus movement, so key repeat reads the landing item); the
// initial landing after a screen change does not interrupt (it queues
// behind the screen name); live-part changes do not interrupt.

function vwa_screens_init()
{
    global.vwaScreens = [];          // registration order
    global.vwaScreenStack = [];      // active, bottom -> top (input layer reads this)
    global.vwaFocusedScreen = undefined;
    // Last-announced focus; node is the actual node struct from the render
    // it was spoken from (its parent chain feeds the next path diff).
    global.vwaNavSpoken = { screenKey: undefined, skey: undefined, node: undefined };
    global.vwaNavLiveCache = [];     // resolved texts of the focused node's live parts

    vwa_control_types_init();
    global.vwaAnnHooks = {
        posText: function(i, n)
        {
            var s = vwa_t("vwa--pos-of");
            s = string_replace(s, "{n}", string(i));
            return string_replace(s, "{m}", string(n));
        },
        groupText: function()
        {
            return vwa_t("vwa--group-radio");
        }
    };
    vwa_register_nav_actions();
    vwa_log("screens: layer initialized");
}

// Control types as data (scrVwaAnnounce): speak order of part kinds plus the
// common role-word part. Role words resolve through vwa_t at speak time.
function vwa_control_types_init()
{
    var stdOrder = ["label", "role", "value", "selected", "enabled", "tooltip", "position"];
    global.vwaControlTypes = {
        button: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-button"); }, false)] },
        toggle: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-toggle"); }, false)] },
        slider: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-slider"); }, false)] },
        combo: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-combo"); }, false)] },
        label: { order: stdOrder, common: [] }
    };
}

function vwa_screen_find(key)
{
    for (var i = 0; i < array_length(global.vwaScreens); i++)
    {
        if (global.vwaScreens[i].key == key)
        {
            return global.vwaScreens[i];
        }
    }
    return undefined;
}

// Register a screen (see the struct contract in the header). Optional
// fields get defaults; the graph engine handle and nav state are attached
// here. Re-registering a key is a mod bug: throw.
function vwa_screen_register(scr)
{
    if (vwa_screen_find(scr.key) != undefined)
    {
        throw ("screens: duplicate screen key " + scr.key);
    }
    if (!variable_struct_exists(scr, "name"))
    {
        scr.name = undefined;
    }
    if (!variable_struct_exists(scr, "build"))
    {
        scr.build = undefined;
    }
    if (!variable_struct_exists(scr, "exclusive"))
    {
        scr.exclusive = false;
    }
    scr.regIndex = array_length(global.vwaScreens);
    scr.navState = vwa_nav_state_new();
    scr.graph = { build: scr.build, state: scr.navState };
    scr.faultLogged = false; // one loud log per activation, not per frame
    array_push(global.vwaScreens, scr);
    vwa_log("screens: registered " + scr.key + " (layer "
        + string(scr.layerNum) + ")");
}

function vwa_screens_stack_has(stack, scr)
{
    for (var i = 0; i < array_length(stack); i++)
    {
        if (stack[i] == scr)
        {
            return true;
        }
    }
    return false;
}

// Once per frame from vwa_input_tick, BEFORE action dispatch so the stack
// (and therefore the live category set) is current when chords resolve.
// Screen callbacks are guarded per screen: a broken isActive/name/build is
// logged once and the screen is treated as inactive/silent/empty - loud in
// the log, harmless to the game (the input watchdog still backstops the
// framework itself).
function vwa_screens_tick()
{
    // Resolve: which registered screens are showing, bottom -> top.
    var desired = [];
    for (var i = 0; i < array_length(global.vwaScreens); i++)
    {
        var scr = global.vwaScreens[i];
        var act = false;
        try
        {
            var fnAct = scr.isActive;
            act = fnAct();
        }
        catch (err)
        {
            if (!scr.faultLogged)
            {
                scr.faultLogged = true;
                vwa_log("ERROR: screen " + scr.key + " isActive threw: " + string(err));
            }
        }
        if (act)
        {
            array_push(desired, scr);
        }
    }
    array_sort(desired, function(a, b)
    {
        if (a.layerNum != b.layerNum)
        {
            return (a.layerNum < b.layerNum) ? -1 : 1;
        }
        return (a.regIndex < b.regIndex) ? -1 : 1;
    });

    // Diff against the previous stack: pops clear nav state (reopening
    // starts fresh), pushes just log; focus handling is separate below.
    for (var i = 0; i < array_length(global.vwaScreenStack); i++)
    {
        var scr = global.vwaScreenStack[i];
        if (!vwa_screens_stack_has(desired, scr))
        {
            vwa_nav_state_reset(scr.navState);
            scr.faultLogged = false;
            vwa_log("screens: popped " + scr.key);
        }
    }
    for (var i = 0; i < array_length(desired); i++)
    {
        if (!vwa_screens_stack_has(global.vwaScreenStack, desired[i]))
        {
            vwa_log("screens: pushed " + desired[i].key);
        }
    }
    global.vwaScreenStack = desired;

    // Focus sync: the top screen is focused. On change, announce the screen
    // name (never interrupt) and reset the navigator's announce memory so
    // the initial landing reads its full path without interrupting.
    var focused = undefined;
    if (array_length(desired) > 0)
    {
        focused = desired[array_length(desired) - 1];
    }
    var prevKey = (global.vwaFocusedScreen != undefined)
        ? global.vwaFocusedScreen.key : undefined;
    var focKey = (focused != undefined) ? focused.key : undefined;
    if (focKey != prevKey)
    {
        global.vwaNavSpoken = { screenKey: undefined, skey: undefined, node: undefined };
        global.vwaNavLiveCache = [];
        if (focused != undefined && focused.name != undefined)
        {
            try
            {
                var fnName = focused.name;
                var nm = fnName();
                if (nm != "" && nm != undefined)
                {
                    vwa_speak([nm], false);
                }
            }
            catch (err)
            {
                if (!focused.faultLogged)
                {
                    focused.faultLogged = true;
                    vwa_log("ERROR: screen " + focused.key + " name threw: " + string(err));
                }
            }
        }
    }
    global.vwaFocusedScreen = focused;

    if (focused == undefined)
    {
        return;
    }

    // Rebuild the focused screen's graph from live state and reconcile
    // focus into it (immediate mode - every frame, so controls appearing,
    // vanishing, or relabeling are followed without any event wiring).
    var hasGraph = false;
    try
    {
        hasGraph = vwa_graph_rerender(focused.graph);
    }
    catch (err)
    {
        if (!focused.faultLogged)
        {
            focused.faultLogged = true;
            vwa_log("ERROR: screen " + focused.key + " build threw: " + string(err));
        }
        return;
    }
    if (hasGraph)
    {
        vwa_nav_observe(focused);
    }
}

// Speak once per observed focus change; while focus rests, watch the
// focused node's live parts and speak just what changed (state feedback
// without re-reading the control).
function vwa_nav_observe(scr)
{
    var nd = vwa_graph_node(scr.graph);
    if (nd == undefined)
    {
        return;
    }
    var spoken = global.vwaNavSpoken;
    if (spoken.screenKey != scr.key || spoken.skey != nd.nid.skey)
    {
        var fromNd = (spoken.screenKey == scr.key) ? spoken.node : undefined;
        var parts = vwa_ann_compose(fromNd, nd, global.vwaControlTypes,
            global.vwaAnnHooks, undefined);
        if (array_length(parts) > 0)
        {
            // Interrupt only on movement within the screen; the first
            // landing queues behind the screen-name announcement.
            vwa_speak(parts, fromNd != undefined);
        }
        global.vwaNavSpoken = { screenKey: scr.key, skey: nd.nid.skey, node: nd };
        global.vwaNavLiveCache = vwa_nav_live_resolve(nd);
        return;
    }

    // Same node: live-part watch. Compare by list position; a build returns
    // parts in a stable order, so index identity holds across frames.
    var liveParts = vwa_ann_live_parts(nd, global.vwaControlTypes);
    var fresh = [];
    for (var i = 0; i < array_length(liveParts); i++)
    {
        var t = vwa_part_resolve(liveParts[i]);
        array_push(fresh, t);
        if (i < array_length(global.vwaNavLiveCache)
            && t != global.vwaNavLiveCache[i] && t != "")
        {
            vwa_speak([t], false);
        }
    }
    global.vwaNavLiveCache = fresh;
    spoken.node = nd; // keep the parent chain current for the next path diff
}

function vwa_nav_live_resolve(nd)
{
    var liveParts = vwa_ann_live_parts(nd, global.vwaControlTypes);
    var out = [];
    for (var i = 0; i < array_length(liveParts); i++)
    {
        array_push(out, vwa_part_resolve(liveParts[i]));
    }
    return out;
}

// ---- the navigator's UI-category actions ----
// Arrows move (left/right adjust first when the focused control supports
// it), Enter activates, Tab / Shift+Tab cycle Tab stops. Handlers only
// mutate cursor state; the tick's observe speaks the outcome next frame -
// exactly once, no matter how many moves landed in one frame.

function vwa_register_nav_actions()
{
    vwa_action_register("nav-up", "vwa--action-nav-up", "ui",
        vwa_bind(vk_up, false, false, false), true, function()
        {
            vwa_nav_move("up");
        });
    vwa_action_register("nav-down", "vwa--action-nav-down", "ui",
        vwa_bind(vk_down, false, false, false), true, function()
        {
            vwa_nav_move("down");
        });
    vwa_action_register("nav-left", "vwa--action-nav-left", "ui",
        vwa_bind(vk_left, false, false, false), true, function()
        {
            vwa_nav_move("left");
        });
    vwa_action_register("nav-right", "vwa--action-nav-right", "ui",
        vwa_bind(vk_right, false, false, false), true, function()
        {
            vwa_nav_move("right");
        });
    vwa_action_register("nav-activate", "vwa--action-nav-activate", "ui",
        vwa_bind(vk_enter, false, false, false), false, function()
        {
            vwa_nav_activate();
        });
    vwa_action_register("nav-next-stop", "vwa--action-nav-next-stop", "ui",
        vwa_bind(vk_tab, false, false, false), false, function()
        {
            vwa_nav_stop_cycle(1);
        });
    vwa_action_register("nav-prev-stop", "vwa--action-nav-prev-stop", "ui",
        vwa_bind(vk_tab, true, false, false), false, function()
        {
            vwa_nav_stop_cycle(-1);
        });
    // Back is opt-in per screen: a screen declaring onBack (fn() -> bool)
    // gets first claim on Escape; returning true consumes the press so the
    // game's own raw Escape handlers underneath do not also fire (a dropdown
    // must close without the whole settings menu closing behind it). With no
    // onBack the game sees Escape untouched - dismissing the popup, closing
    // settings, opening settings from the bare main menu all stay the game's
    // own behavior.
    vwa_action_register("nav-back", "vwa--action-nav-back", "ui",
        vwa_bind(vk_escape, false, false, false), false, function()
        {
            vwa_nav_back();
        });
    // Tooltip on demand: F9 reads the focused control's tooltip. F-keys
    // avoid every key the game binds (see vwa_register_global_actions).
    vwa_action_register("nav-tooltip", "vwa--action-nav-tooltip", "ui",
        vwa_bind(vk_f9, false, false, false), false, function()
        {
            vwa_nav_tooltip();
        });
}

function vwa_nav_back()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (!variable_struct_exists(scr, "onBack") || scr.onBack == undefined)
    {
        return;
    }
    var fn = scr.onBack;
    if (fn())
    {
        vwa_input_consume_escape();
    }
}

function vwa_nav_tooltip()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (!vwa_graph_tooltip(scr.graph))
    {
        vwa_speak([vwa_t("vwa--no-tooltip")], false);
    }
}

function vwa_nav_move(dir)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (dir == "left" || dir == "right")
    {
        if (vwa_graph_adjust(scr.graph, (dir == "right") ? 1 : -1, false))
        {
            return; // adjusted; the live-part watch speaks the new value
        }
    }
    vwa_graph_move(scr.graph, dir);
}

function vwa_nav_activate()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (!vwa_graph_activate(scr.graph))
    {
        vwa_speak([vwa_t("vwa--no-action")], false);
    }
}

function vwa_nav_stop_cycle(dirNum)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    vwa_graph_move_stop(scr.graph, dirNum);
}
