// scrVwaScreens - Void War Access screen layer: the screen registry, the
// per-frame poll-and-diff stack resolve, focus sync, and the navigator (the
// UI-category actions that move the graph cursor, the type-ahead glue, plus
// the once-per-frame observe that speaks focus changes). Built on the graph
// engine in scrVwaGraph, the composer in scrVwaAnnounce, and the matcher in
// scrVwaSearch.
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
//   postDispatch (optional) fn(), run for the FOCUSED screen after the
//              action dispatch, still in Begin Step - the one slot where a
//              screen can consume raw game keys its own chords share
//              (consuming earlier would eat the mod's own dispatch; the
//              game's raw Step reads still see the cleared key). First
//              consumer: ship-select's arrow consume against the hull
//              cycler's raw arrowKeysToCycle.
//
// Speech rules implemented here (the invariants): the tick is the ONE place
// framework speech happens, once per observed change; screen-name
// announcements never interrupt; a focus move within a screen interrupts
// (genuine focus movement, so key repeat reads the landing item); the
// initial landing after a screen change does not interrupt (it queues
// behind the screen name); live-part changes do not interrupt. Keystroke
// feedback (search landings, state feedback, alt+up/down line review)
// speaks immediately from the handler, interrupting. State feedback speaks
// the changed live parts; an ADJUST that changed no live text re-speaks
// every non-empty live part instead (the heartbeat - identically-rendered
// neighbors and range ends still answer the key), while an activation
// with no visible change stays silent, mirroring the game.
//
// Announcements are line-structured (session 10): the control summary is
// one line, each tooltip-kind part its own line (vwa_ann_leaf), and
// vwa_speak renders lines as newlines. Alt+up/down step the focused
// control's lines one per press (vwa_nav_line_step), re-resolved live at
// every press; past the ends speaks a boundary word.

function vwa_screens_init()
{
    global.vwaScreens = [];          // registration order
    global.vwaScreenStack = [];      // active, bottom -> top (input layer reads this)
    global.vwaFocusedScreen = undefined;
    // Last-announced focus; node is the actual node struct from the render
    // it was spoken from (its parent chain feeds the next path diff).
    global.vwaNavSpoken = { screenKey: undefined, skey: undefined, node: undefined };
    global.vwaNavLiveCache = [];     // resolved texts of the focused node's live parts
    // Alt+up/down line review: a cursor over the focused node's announcement
    // lines. Keyed to the focus it belongs to; every focus announcement
    // resets it to line 0 (the summary line, the one just heard). The lines
    // themselves are re-resolved from the live node at every press - the
    // cursor is the only state (never cache game state).
    global.vwaLineCursor = { screenKey: undefined, skey: undefined, idx: 0 };
    // Type-ahead: the pure matcher state (scrVwaSearch) plus the glue that
    // ties results back to graph nodes. scopeSkeys/scopeNames are the
    // focused Tab stop's nodes as captured at the last keystroke (results
    // index into them); focusSkey is where the last result landed - focus
    // moving off it means the results are stale.
    global.vwaSearch = vwa_search_new();
    global.vwaSearchNav = { scopeSkeys: [], scopeNames: [],
                            focusSkey: undefined, screenKey: undefined,
                            fieldMode: false };

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
            return vwa_t("vwa--group-generic");
        },
        submenuItemsText: function(k)
        {
            if (k == 1)
            {
                return vwa_t("vwa--submenu-item-one");
            }
            return string_replace(vwa_t("vwa--submenu-items"), "{k}", string(k));
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
        option: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-option"); }, false)] },
        submenu: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-submenu"); }, false)] },
        // Editable text box: activation enters the game's text-field mode
        // via vwa_text_begin (scrVwaText); the screen supplies the adapter.
        textfield: { order: stdOrder, common: [
            vwa_part_fn("role", function() { return vwa_t("vwa--role-edit"); }, false)] },
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
    // A screen that just gained focus waits one tick before its landing
    // announcement: our tick runs in Begin Step, and on a screen's first
    // frame the game's freshly created instances have not had their first
    // Step yet - announcing now reads half-initialized state (bit us: the
    // commander rows spoke the oCrew parent's default maxHP and an empty
    // ability list). The screen name above still speaks on the change tick;
    // the landing follows one frame later, settled.
    if (focKey != prevKey)
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

// The focused screen's postDispatch hook (see the header). Called from
// vwa_input_tick after the action dispatch; errors land in the tick's own
// watchdog (which fails the game-key gate open and logs loudly).
function vwa_screens_post_dispatch()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined || !variable_struct_exists(scr, "postDispatch")
        || scr.postDispatch == undefined)
    {
        return;
    }
    var fn = scr.postDispatch;
    fn();
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
        global.vwaLineCursor = { screenKey: scr.key, skey: nd.nid.skey, idx: 0 };
        return;
    }

    // Same node: live-part watch. Compare by list position; a build returns
    // parts in a stable order, so index identity holds across frames. When
    // the live-part COUNT changes (the node's part set reshaped under
    // focus), index identity is void: rebaseline silently instead of
    // speaking a positionally-wrong part.
    var liveParts = vwa_ann_live_parts(nd, global.vwaControlTypes);
    var sameShape = (array_length(liveParts)
        == array_length(global.vwaNavLiveCache));
    var fresh = [];
    for (var i = 0; i < array_length(liveParts); i++)
    {
        var t = vwa_part_resolve(liveParts[i]);
        array_push(fresh, t);
        if (sameShape && t != global.vwaNavLiveCache[i] && t != "")
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
    // Ctrl+left/right: large adjust steps on the focused control
    // (vwa_widget_slider_adjust). No-op on a control with no onAdjust.
    vwa_action_register("nav-left-large", "vwa--action-nav-left-large", "ui",
        vwa_bind(vk_left, false, true, false), true, function()
        {
            vwa_nav_adjust_large(-1);
        });
    vwa_action_register("nav-right-large", "vwa--action-nav-right-large", "ui",
        vwa_bind(vk_right, false, true, false), true, function()
        {
            vwa_nav_adjust_large(1);
        });
    // Ctrl+up/down: submenu jumps, riding the graph's jump pseudo-edges
    // (grid screens will reuse the chord for region jumps). Both land
    // exactly where the plain arrow at the enclosing submenu's boundary
    // lands; see the submenu block in scrVwaGraph's header.
    vwa_action_register("nav-jump-up", "vwa--action-nav-jump-up", "ui",
        vwa_bind(vk_up, false, true, false), true, function()
        {
            vwa_nav_move("jump-up");
        });
    vwa_action_register("nav-jump-down", "vwa--action-nav-jump-down", "ui",
        vwa_bind(vk_down, false, true, false), true, function()
        {
            vwa_nav_move("jump-down");
        });
    vwa_action_register("nav-activate", "vwa--action-nav-activate", "ui",
        vwa_bind(vk_enter, false, false, false), false, function()
        {
            vwa_nav_activate();
        });
    vwa_action_register("nav-next-stop", "vwa--action-nav-next-stop", "ui",
        vwa_bind(vk_tab, false, false, false), true, function()
        {
            vwa_nav_stop_cycle(1);
        });
    vwa_action_register("nav-prev-stop", "vwa--action-nav-prev-stop", "ui",
        vwa_bind(vk_tab, true, false, false), true, function()
        {
            vwa_nav_stop_cycle(-1);
        });
    // Home/End jump to the focused Tab stop's first/last control (arrows
    // never cross a stop, so neither do these).
    vwa_action_register("nav-home", "vwa--action-nav-home", "ui",
        vwa_bind(vk_home, false, false, false), false, function()
        {
            vwa_nav_move_ends(-1);
        });
    vwa_action_register("nav-end", "vwa--action-nav-end", "ui",
        vwa_bind(vk_end, false, false, false), false, function()
        {
            vwa_nav_move_ends(1);
        });
    // Alt+up/down: line review over the focused control's announcement.
    // Landing speaks the whole thing; these step back through it one line
    // per press (the summary line, then each tooltip/sheet line). Lines are
    // re-resolved live at every press.
    vwa_action_register("nav-line-prev", "vwa--action-line-prev", "ui",
        vwa_bind(vk_up, false, false, true), true, function()
        {
            vwa_nav_line_step(-1);
        });
    vwa_action_register("nav-line-next", "vwa--action-line-next", "ui",
        vwa_bind(vk_down, false, false, true), true, function()
        {
            vwa_nav_line_step(1);
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
}

// One alt-arrow press: move the line cursor and speak the landed line
// (interrupting - direct user-caused feedback). The lines come fresh from
// vwa_ann_leaf on the focused node, so a live value change since the
// landing reads current, not as-spoken. Past either end speaks the
// localized boundary word and stays. Focus having moved since the last
// announcement resets to the top implicitly (the cursor is re-keyed by the
// announce points).
function vwa_nav_line_step(dirNum)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (!vwa_graph_rerender(scr.graph))
    {
        return;
    }
    var nd = vwa_graph_node(scr.graph);
    if (nd == undefined)
    {
        return;
    }
    var lines = vwa_ann_leaf(nd, global.vwaControlTypes, global.vwaAnnHooks);
    if (array_length(lines) == 0)
    {
        return;
    }
    var cur = global.vwaLineCursor;
    if (cur.screenKey != scr.key || cur.skey != nd.nid.skey)
    {
        // The cursor belonged to another focus (or nothing): rebase here.
        global.vwaLineCursor = { screenKey: scr.key, skey: nd.nid.skey, idx: 0 };
        cur = global.vwaLineCursor;
    }
    // The line set can reshape between presses (live game state); clamp
    // before stepping so the step is relative to a real line.
    cur.idx = clamp(cur.idx, 0, array_length(lines) - 1);
    var next = cur.idx + dirNum;
    if (next < 0)
    {
        vwa_speak([vwa_t("vwa--line-top")], true);
        return;
    }
    if (next >= array_length(lines))
    {
        vwa_speak([vwa_t("vwa--line-bottom")], true);
        return;
    }
    cur.idx = next;
    vwa_speak([lines[next]], true);
}

function vwa_nav_back()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (vwa_nav_search_action("back"))
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

function vwa_nav_move(dir)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    var kind = (dir == "up" || dir == "down") ? dir : "other";
    if (vwa_nav_search_action(kind))
    {
        return;
    }
    if (dir == "left" || dir == "right")
    {
        if (vwa_graph_adjust(scr.graph, (dir == "right") ? 1 : -1, false))
        {
            vwa_nav_state_feedback(scr, true);
            return;
        }
    }
    vwa_graph_move(scr.graph, dir);
}

function vwa_nav_adjust_large(sign)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (vwa_nav_search_action("other"))
    {
        return;
    }
    if (vwa_graph_adjust(scr.graph, sign, true))
    {
        vwa_nav_state_feedback(scr, true);
    }
}

function vwa_nav_activate()
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    // Enter is not a search key: it clears the search silently and then
    // activates whatever result the search focused.
    vwa_nav_search_action("other");
    // Enter on a submenu header enters it, same as right arrow (a header's
    // action IS entering; an empty one is a silent edge, like any list
    // end - its "0 items" already told the player why).
    if (vwa_graph_rerender(scr.graph))
    {
        var nd = vwa_graph_node(scr.graph);
        if (nd != undefined && vwa_opt(nd, "isSubmenu", false))
        {
            vwa_graph_move(scr.graph, "right");
            return;
        }
    }
    if (!vwa_graph_activate(scr.graph))
    {
        vwa_speak([vwa_t("vwa--no-action")], false);
        return;
    }
    vwa_nav_state_feedback(scr, false);
}

// Speak a user-caused value change NOW, interrupting, instead of waiting
// for the next tick's non-interrupting live-part watch: under typematic
// key repeat on a slider the queued values would read behind the actual
// position. heartbeat is true on the adjust paths only: when a successful
// adjust changed no live text - a step between two states that render
// identically (consecutive hidden hulls on the ship cycler both read
// Unknown Vessel) or a press against a range end - every non-empty live
// part is re-spoken, so the key always answers; silence there reads as a
// dead control. Activation keeps changed-only semantics (its feedback is
// the callback's own visible effect; when the game shows nothing, silence
// mirrors that). Rebaselines the live cache so the watch does not re-speak
// the change. Rerenders first: an activation that destroyed its
// own control (Cancel closing a dialogue) must not resolve parts through a
// dead instance - after the rebuild, focus having moved means skip.
function vwa_nav_state_feedback(scr, heartbeat)
{
    var fnAct = scr.isActive;
    if (!fnAct())
    {
        return; // the activation closed this screen; the tick pops it next
    }
    if (!vwa_graph_rerender(scr.graph))
    {
        return;
    }
    var nd = vwa_graph_node(scr.graph);
    var spoken = global.vwaNavSpoken;
    if (nd == undefined || spoken.screenKey != scr.key
        || spoken.skey != nd.nid.skey)
    {
        return; // focus moved; the tick's observe announces the landing
    }
    var liveParts = vwa_ann_live_parts(nd, global.vwaControlTypes);
    var fresh = [];
    var spoke = false;
    for (var i = 0; i < array_length(liveParts); i++)
    {
        var t = vwa_part_resolve(liveParts[i]);
        array_push(fresh, t);
        if (i < array_length(global.vwaNavLiveCache)
            && t != global.vwaNavLiveCache[i] && t != "")
        {
            vwa_speak([t], true);
            spoke = true;
        }
    }
    if (heartbeat && !spoke)
    {
        for (var i = 0; i < array_length(fresh); i++)
        {
            if (fresh[i] != "")
            {
                vwa_speak([fresh[i]], true);
            }
        }
    }
    global.vwaNavLiveCache = fresh;
    spoken.node = nd;
}

function vwa_nav_move_ends(dirNum)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (vwa_nav_search_action((dirNum < 0) ? "home" : "end"))
    {
        return;
    }
    vwa_graph_move_ends(scr.graph, dirNum);
}

function vwa_nav_stop_cycle(dirNum)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    if (vwa_nav_search_action("other"))
    {
        return;
    }
    vwa_graph_move_stop(scr.graph, dirNum);
}

// ---- type-ahead ----
// Letters (and, once a buffer exists, space) type into a search over the
// focused Tab stop; the best match focuses and speaks immediately (direct
// user-caused feedback, so it interrupts). While a search is active, up and
// down step the results, Home/End jump to the first/last result, Escape
// clears (consumed, so the game's own Escape handlers stay quiet), and any
// other navigation key clears silently and then does its normal job. The
// matcher itself lives in scrVwaSearch.

// Once per frame from vwa_input_tick, after vwa_screens_tick (so the
// focused screen and its render are current). Screens can opt out with
// allowsTypeahead: false (for future screens whose letters are hotkeys);
// the game's text-field mode always wins.
function vwa_nav_typeahead_tick()
{
    var nav = global.vwaSearchNav;
    if (global.textFieldInputEnabled)
    {
        // The game's text field owns the keyboard (and keyboard_string).
        nav.fieldMode = true;
        vwa_nav_search_clear(false);
        return;
    }
    if (nav.fieldMode)
    {
        // First tick after the field mode ended: discard the buffer
        // instead of searching it. Anything in there was typed while the
        // field owned the keyboard (residue the field's own consume gate
        // missed, or dev injection) and belongs to the field, not to a
        // search.
        nav.fieldMode = false;
        vwa_input_take_typed();
        return;
    }

    var typed = vwa_input_take_typed();

    var scr = global.vwaFocusedScreen;
    var nd = (scr != undefined && vwa_opt(scr, "allowsTypeahead", true))
        ? vwa_graph_node(scr.graph) : undefined;
    if (nd == undefined)
    {
        vwa_nav_search_clear(false);
        nav.screenKey = (scr != undefined) ? scr.key : undefined;
        return;
    }
    if (nav.screenKey != scr.key)
    {
        // Focus changed screens: drop any search along with this frame's
        // typed characters (they were aimed at the old screen).
        nav.screenKey = scr.key;
        vwa_nav_search_clear(false);
        return;
    }
    // Focus moved off the last result (Tab, a rebuild, an activation):
    // the results are stale.
    if (global.vwaSearch.active && nav.focusSkey != undefined
        && nav.focusSkey != nd.nid.skey)
    {
        vwa_nav_search_clear(false);
    }

    for (var i = 1; i <= string_length(typed); i++)
    {
        var o = string_ord_at(typed, i);
        if (vwa_search_char_is_letter(o))
        {
            vwa_nav_typeahead_char(chr(o));
        }
        else if (o == 32 && global.vwaSearch.buffer != "")
        {
            vwa_nav_typeahead_char(" ");
        }
    }
}

// One typed character: recapture the search scope fresh from the current
// render (never cache game state), append, search.
function vwa_nav_typeahead_char(ch)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined)
    {
        return;
    }
    var nd = vwa_graph_node(scr.graph);
    if (nd == undefined || scr.navState.curRender == undefined)
    {
        return;
    }
    var nav = global.vwaSearchNav;
    var order = scr.navState.curRender.order;
    var scope = [];
    var names = [];
    for (var i = 0; i < array_length(order); i++)
    {
        var cand = order[i];
        if (cand.stopKey != nd.stopKey)
        {
            continue;
        }
        array_push(scope, cand.nid.skey);
        array_push(names, vwa_nav_search_text(cand));
    }
    if (array_length(scope) == 0)
    {
        return;
    }
    nav.scopeSkeys = scope;
    nav.scopeNames = names;
    vwa_search_add_char(global.vwaSearch, ch);
    vwa_search_run(global.vwaSearch, array_length(scope),
        function(i) { return global.vwaSearchNav.scopeNames[i]; },
        function(i) { vwa_nav_search_land(i); },
        function(txt) { vwa_nav_search_no_match(txt); });
}

// A node's searchable text: its first part's resolved label (game text is
// markup-free, so the label is match-ready as-is).
function vwa_nav_search_text(nd)
{
    return vwa_ann_first_label(nd);
}

// Focus a specific control by structural key and speak the landing NOW,
// interrupting (like vwa_nav_state_feedback, keystroke feedback cannot wait
// a frame - and a repeated keystroke re-reads the unchanged landing, which
// a silent observe would swallow). Rebaselines the announce memory so the
// tick's observe does not re-speak the move. False = the key is not in the
// current render (focus unchanged). Callers: the type-ahead landing below,
// the encounter screen's number-key choice jump (scrVwaMenuEncounter).
function vwa_nav_focus_speak(scr, skey)
{
    if (!vwa_graph_focus(scr.graph, skey))
    {
        return false;
    }
    var nd = vwa_graph_node(scr.graph);
    var spoken = global.vwaNavSpoken;
    var fromNd = (spoken.screenKey == scr.key) ? spoken.node : undefined;
    var parts = vwa_ann_compose(fromNd, nd, global.vwaControlTypes,
        global.vwaAnnHooks, undefined);
    if (array_length(parts) > 0)
    {
        vwa_speak(parts, true);
    }
    global.vwaNavSpoken = { screenKey: scr.key, skey: nd.nid.skey, node: nd };
    global.vwaNavLiveCache = vwa_nav_live_resolve(nd);
    global.vwaLineCursor = { screenKey: scr.key, skey: nd.nid.skey, idx: 0 };
    return true;
}

// Land on a search result via vwa_nav_focus_speak.
function vwa_nav_search_land(idx)
{
    var scr = global.vwaFocusedScreen;
    var nav = global.vwaSearchNav;
    if (scr == undefined || idx < 0 || idx >= array_length(nav.scopeSkeys))
    {
        vwa_log("ERROR: search landing with no screen or bad index "
            + string(idx));
        return;
    }
    var skey = nav.scopeSkeys[idx];
    if (!vwa_nav_focus_speak(scr, skey))
    {
        // The control vanished between keystroke and step; the next tick's
        // staleness check clears the results.
        vwa_log("search: result " + string(skey) + " no longer in the render");
        return;
    }
    nav.focusSkey = global.vwaNavSpoken.skey;
}

function vwa_nav_search_no_match(txt)
{
    vwa_speak([string_replace(vwa_t("vwa--search-no-match"), "{text}", txt)],
        true);
}

function vwa_nav_search_clear(announce)
{
    var st = global.vwaSearch;
    var nav = global.vwaSearchNav;
    var had = st.active || st.buffer != "";
    vwa_search_reset(st);
    nav.scopeSkeys = [];
    nav.scopeNames = [];
    nav.focusSkey = undefined;
    if (announce && had)
    {
        vwa_speak([vwa_t("vwa--search-cleared")], true);
    }
}

// The navigator handlers call this first. kind: "up" / "down" / "home" /
// "end" / "back" / "other". Returns true when the active search consumed
// the action. Up/down are reserved while a search is active even with no
// results (they must not move focus out from under a mid-typing search);
// Home/End join in only when there are results to jump within; Escape
// always clears; everything else clears silently and proceeds.
function vwa_nav_search_action(kind)
{
    var st = global.vwaSearch;
    if (!st.active && st.buffer == "")
    {
        return false;
    }
    var scr = global.vwaFocusedScreen;
    var nav = global.vwaSearchNav;
    if (scr != undefined)
    {
        var nd = vwa_graph_node(scr.graph);
        if (nd != undefined && nav.focusSkey != undefined
            && nav.focusSkey != nd.nid.skey)
        {
            vwa_nav_search_clear(false);
            return false;
        }
    }
    if (kind == "up" || kind == "down")
    {
        if (array_length(st.results) > 0)
        {
            vwa_search_navigate(st, (kind == "down") ? 1 : -1,
                function(i) { vwa_nav_search_land(i); });
        }
        return true;
    }
    if ((kind == "home" || kind == "end") && array_length(st.results) > 0)
    {
        vwa_search_jump(st, kind == "end",
            function(i) { vwa_nav_search_land(i); });
        return true;
    }
    if (kind == "back")
    {
        vwa_nav_search_clear(true);
        vwa_input_consume_escape();
        return true;
    }
    vwa_nav_search_clear(false);
    return false;
}
