// scrVwaTest - Void War Access in-game test module, DEV BUILDS ONLY (like
// scrVwaDev; the release build omits both). Two entry points, both invoked
// through the dev driver's `call` command:
//
// - vwa_dev_selftest: unit tests for the pure modules (the vwa_speak join,
//   the graph engine, announcement composition, the type-ahead matcher)
//   against constructed fixtures, in one frame, inside the real GML runtime
//   - so it also proves the UTMT import compiled what we think it did.
//   Returns {checks, failures}.
//
// - vwa_dev_walk_start(screenKey) + vwa_dev_walk_status: the screen walker,
//   an end-to-end contract check of the FOCUSED screen. A frame-driven
//   state machine (ticked from the dev pump append) visits every node of
//   the screen's render through the real focus path (navState.nextMove ->
//   reconcile -> observe) and verifies, per node: focus lands, exactly one
//   utterance is spoken, its text equals a fresh live resolve of the same
//   node (vwa_ann_compose rendered through vwa_speak_render), and the
//   alt-arrow line review steps every line down and back up with the
//   boundary words at the ends. Two probes follow: the screen's first
//   adjustable control gets a net-zero adjust whose feedback utterances
//   must equal exactly the live parts that changed, and one type-ahead
//   character taken from a real label must land with a spoken
//   announcement. Speech is observed through global.vwaSpeakTap (the
//   chokepoint's sanctioned observation point; never speaks).
//
// DESIGN RULE (the reason this module exists - session 11): expected
// values are always derived live, in-game, from the same state the player
// hears - never hardcoded composed strings. An intentional wording change
// can therefore never break the walker; what breaks it is speech not
// happening, happening twice, mismatching live state, or a screen
// crashing. scripts/smoke.ps1 is a dumb runner: it opens screens, starts
// walks, polls status, and prints failures - no expectations live in
// PowerShell.

// ---- assertion collector ----

function vwa_test_ctx()
{
    return { checks: 0, failures: [] };
}

function vwa_test_ok(tc, name, cond, detail)
{
    tc.checks += 1;
    if (cond)
    {
        return;
    }
    if (array_length(tc.failures) < 25)
    {
        array_push(tc.failures, name + ": " + string(detail));
    }
    else if (array_length(tc.failures) == 25)
    {
        array_push(tc.failures, "(further failures suppressed)");
    }
}

function vwa_test_eq(tc, name, got, want)
{
    vwa_test_ok(tc, name, got == want,
        "expected [" + string(want) + "] got [" + string(got) + "]");
}

function vwa_test_join(arr)
{
    var s = "";
    for (var i = 0; i < array_length(arr); i++)
    {
        if (i > 0)
        {
            s += " | ";
        }
        s += string(arr[i]);
    }
    return s;
}

// ---- selftest ----

function vwa_dev_selftest()
{
    var tc = vwa_test_ctx();
    vwa_test_speak_render(tc);
    vwa_test_graph(tc);
    vwa_test_announce(tc);
    vwa_test_search(tc);
    return { checks: tc.checks, failures: tc.failures };
}

// The chokepoint's pure join (both shapes, empties vanishing).
function vwa_test_speak_render(tc)
{
    vwa_test_eq(tc, "render: flat join",
        vwa_speak_render(["a", "", "b"]), "a, b");
    vwa_test_eq(tc, "render: struct part text",
        vwa_speak_render([{ text: "x" }, "y"]), "x, y");
    vwa_test_eq(tc, "render: line mode",
        vwa_speak_render([["a", "b"], ["c"]]), "a, b\nc");
    vwa_test_eq(tc, "render: mixed flat element becomes a line",
        vwa_speak_render(["x", ["y", "z"]]), "x\ny, z");
    vwa_test_eq(tc, "render: empty line vanishes",
        vwa_speak_render([["a"], [""], ["b"]]), "a\nb");
    vwa_test_eq(tc, "render: all empty",
        vwa_speak_render([["", ""]]), "");
}

function vwa_test_gkey(gr)
{
    var nd = vwa_graph_node(gr);
    return (nd == undefined) ? "none" : nd.nid.skey;
}

function vwa_test_gmove(tc, gr, dir, wantKey)
{
    vwa_graph_move(gr, dir);
    vwa_test_eq(tc, "graph: " + dir + " to " + wantKey,
        vwa_test_gkey(gr), wantKey);
}

// The navigation engine on a fixture: rows, a submenu (skip / enter / flow
// out / jump edges), two Tab stops, focus reconciliation across rebuilds
// (ref follow on rename, nearest survivor on deletion), builder validation.
function vwa_test_graph(tc)
{
    var fx = { beta: { tag: "beta" }, betaName: "Beta", hideGamma: false };
    var gr = {
        build: method({ fx: fx }, function(b)
        {
            vwa_gb_begin_stop(b, "main");
            vwa_gb_add(b, vwa_id("alpha"), {
                typeKey: "button", parts: [vwa_part("label", "Alpha")] });
            vwa_gb_add(b, vwa_id_ref(self.fx.beta, "item:" + self.fx.betaName), {
                typeKey: "button",
                parts: [vwa_part("label", self.fx.betaName)] });
            if (!self.fx.hideGamma)
            {
                vwa_gb_add(b, vwa_id("gamma"), {
                    typeKey: "button", parts: [vwa_part("label", "Gamma")] });
            }
            vwa_gb_begin_submenu(b, vwa_id("sub"), {
                parts: [vwa_part("label", "Sub")] });
            vwa_gb_add(b, vwa_id("c1"), {
                typeKey: "button", parts: [vwa_part("label", "Child one")] });
            vwa_gb_add(b, vwa_id("c2"), {
                typeKey: "button", parts: [vwa_part("label", "Child two")] });
            vwa_gb_end_submenu(b);
            vwa_gb_add(b, vwa_id("delta"), {
                typeKey: "button", parts: [vwa_part("label", "Delta")] });
            vwa_gb_begin_stop(b, "second");
            vwa_gb_start_row(b, undefined, "Pair");
            vwa_gb_add(b, vwa_id("x"), {
                typeKey: "button", parts: [vwa_part("label", "Ex")] });
            vwa_gb_add(b, vwa_id("y"), {
                typeKey: "button", parts: [vwa_part("label", "Why")] });
            vwa_gb_end_row(b);
        }),
        state: vwa_nav_state_new()
    };

    vwa_test_ok(tc, "graph: fixture renders", vwa_graph_rerender(gr), "rerender false");
    vwa_test_eq(tc, "graph: initial focus", vwa_test_gkey(gr), "alpha");

    vwa_test_gmove(tc, gr, "down", "item:Beta");
    vwa_test_gmove(tc, gr, "down", "gamma");
    vwa_test_gmove(tc, gr, "down", "sub");
    vwa_test_gmove(tc, gr, "down", "delta");   // header skips its subtree
    vwa_test_gmove(tc, gr, "up", "sub");
    vwa_test_gmove(tc, gr, "right", "c1");     // enter the submenu
    vwa_test_gmove(tc, gr, "down", "c2");
    vwa_test_gmove(tc, gr, "down", "delta");   // flow out at the bottom
    vwa_graph_focus(gr, "c1");
    vwa_test_gmove(tc, gr, "up", "sub");       // first child up to the header
    vwa_graph_focus(gr, "c1");
    vwa_test_gmove(tc, gr, "left", "sub");     // left exits to the header
    vwa_graph_focus(gr, "c1");
    vwa_test_gmove(tc, gr, "jump-up", "sub");
    vwa_graph_focus(gr, "c1");
    vwa_test_gmove(tc, gr, "jump-down", "delta");

    // Tab stops: cycle to the pair, arrow within the row, wrap back to the
    // remembered position.
    vwa_graph_move_stop(gr, 1);
    vwa_test_eq(tc, "graph: stop cycle lands the second stop",
        vwa_test_gkey(gr), "x");
    vwa_test_gmove(tc, gr, "right", "y");
    vwa_graph_move_stop(gr, 1);
    vwa_test_eq(tc, "graph: stop cycle wraps to the remembered position",
        vwa_test_gkey(gr), "delta");
    vwa_graph_move_ends(gr, -1);
    vwa_test_eq(tc, "graph: Home to the stop's first control",
        vwa_test_gkey(gr), "alpha");
    vwa_graph_move_ends(gr, 1);
    vwa_test_eq(tc, "graph: End to the stop's last control",
        vwa_test_gkey(gr), "delta");

    // Reconciliation tier 1: the skey changes with a rename, the backing
    // ref does not - focus follows the ref.
    vwa_graph_focus(gr, "item:Beta");
    fx.betaName = "Beta2";
    vwa_graph_rerender(gr);
    vwa_test_eq(tc, "graph: focus follows the ref across a rename",
        vwa_test_gkey(gr), "item:Beta2");

    // Nearest survivor: the focused node vanishes, focus walks backward.
    vwa_graph_focus(gr, "gamma");
    fx.hideGamma = true;
    vwa_graph_rerender(gr);
    vwa_test_eq(tc, "graph: nearest survivor after a deletion",
        vwa_test_gkey(gr), "item:Beta2");

    // Builder validation throws (caught here; a real screen's build throw
    // is the screens layer's quarantine).
    var threw = false;
    try
    {
        var bd = vwa_gb_new();
        vwa_gb_add(bd, vwa_id("dup"), {
            typeKey: "button", parts: [vwa_part("label", "One")] });
        vwa_gb_add(bd, vwa_id("dup"), {
            typeKey: "button", parts: [vwa_part("label", "Two")] });
    }
    catch (err)
    {
        threw = true;
    }
    vwa_test_ok(tc, "graph: duplicate key throws", threw, "no throw");
    threw = false;
    try
    {
        var be = vwa_gb_new();
        vwa_gb_add(be, vwa_id("noparts"), { typeKey: "button" });
    }
    catch (err)
    {
        threw = true;
    }
    vwa_test_ok(tc, "graph: missing parts throws", threw, "no throw");
}

// Composition against a custom types/hooks pair, so every expected string
// is deterministic fixture text (the live localized hooks are the walker's
// job).
function vwa_test_announce(tc)
{
    var types = {
        button: {
            order: ["label", "role", "value", "selected", "enabled",
                    "tooltip", "position"],
            common: [vwa_part("role", "Button")]
        }
    };
    var hooks = {
        posText: function(i, n)
        {
            return "pos " + string(i) + " of " + string(n);
        },
        groupText: function()
        {
            return "Group";
        },
        submenuItemsText: function(k)
        {
            return string(k) + " items";
        }
    };

    // A labeled context wrapping two buttons, the first carrying two
    // tooltip parts (so its leaf is three lines).
    var b = vwa_gb_new();
    vwa_gb_push_context(b, "Panel");
    vwa_gb_add(b, vwa_id("a1"), {
        typeKey: "button",
        parts: [vwa_part("label", "First"),
                vwa_part("tooltip", "Tip one"),
                vwa_part("tooltip", "Tip two")] });
    vwa_gb_add(b, vwa_id("a2"), {
        typeKey: "button", parts: [vwa_part("label", "Second")] });
    vwa_gb_pop_context(b);
    var rndr = vwa_gb_build(b);
    var a1 = variable_struct_get(rndr.byKey, "a1");
    var a2 = variable_struct_get(rndr.byKey, "a2");

    vwa_test_eq(tc, "announce: leaf lines (summary + one line per tooltip)",
        vwa_speak_render(vwa_ann_leaf(a1, types, hooks)),
        "First, Button, pos 1 of 2\nTip one\nTip two");
    vwa_test_eq(tc, "announce: compose from nothing reads the path",
        vwa_speak_render(vwa_ann_compose(undefined, a1, types, hooks, undefined)),
        "Panel\nFirst, Button, pos 1 of 2\nTip one\nTip two");
    vwa_test_eq(tc, "announce: sibling move reads just the control",
        vwa_speak_render(vwa_ann_compose(a1, a2, types, hooks, undefined)),
        "Second, Button, pos 2 of 2");

    // A submenu header: child count in the summary; entering reads the
    // header level then the landing child; ascending reads just the header.
    var b2 = vwa_gb_new();
    vwa_gb_begin_submenu(b2, vwa_id("sm"), {
        parts: [vwa_part("label", "Tools")] });
    vwa_gb_add(b2, vwa_id("t1"), {
        typeKey: "button", parts: [vwa_part("label", "Hammer")] });
    vwa_gb_add(b2, vwa_id("t2"), {
        typeKey: "button", parts: [vwa_part("label", "Saw")] });
    vwa_gb_end_submenu(b2);
    var rndr2 = vwa_gb_build(b2);
    var hdr = variable_struct_get(rndr2.byKey, "sm");
    var t1 = variable_struct_get(rndr2.byKey, "t1");
    var t2 = variable_struct_get(rndr2.byKey, "t2");

    vwa_test_eq(tc, "announce: header leaf carries the child count",
        vwa_speak_render(vwa_ann_leaf(hdr, types, hooks)), "Tools, 2 items");
    vwa_test_eq(tc, "announce: entering reads header then child",
        vwa_speak_render(vwa_ann_compose(undefined, t1, types, hooks, undefined)),
        "Tools, 2 items\nHammer, Button, pos 1 of 2");
    vwa_test_eq(tc, "announce: ascending reads just the header",
        vwa_speak_render(vwa_ann_compose(t2, hdr, types, hooks, undefined)),
        "Tools, 2 items");

    // Level dedupe: a context whose label repeats the control below it.
    var b3 = vwa_gb_new();
    vwa_gb_push_context(b3, "Audio");
    vwa_gb_add(b3, vwa_id("au"), {
        typeKey: "button", parts: [vwa_part("label", "Audio")] });
    vwa_gb_pop_context(b3);
    var rndr3 = vwa_gb_build(b3);
    var au = variable_struct_get(rndr3.byKey, "au");
    vwa_test_eq(tc, "announce: duplicate level label dedupes",
        vwa_speak_render(vwa_ann_compose(undefined, au, types, hooks, undefined)),
        "Audio, Button");
}

function vwa_test_search_type(st, cap, names, txt)
{
    for (var i = 1; i <= string_length(txt); i++)
    {
        vwa_search_add_char(st, string_char_at(txt, i));
        vwa_search_run(st, array_length(names),
            method({ names: names }, function(ii)
            {
                return self.names[ii];
            }),
            method({ cap: cap }, function(ii)
            {
                self.cap.landed = ii;
            }),
            method({ cap: cap }, function(t)
            {
                self.cap.noMatch = t;
            }));
    }
}

// The tiered matcher on literal strings: best-tier landing, repeat-letter
// cycling, name-before-metadata, the abbreviation tier, no-match reporting.
function vwa_test_search(tc)
{
    var names = ["Load Game", "New Game", "Settings", "Gas Pipe, tool"];
    var st = vwa_search_new();
    var cap = { landed: -1, noMatch: undefined };

    vwa_test_search_type(st, cap, names, "l");
    vwa_test_eq(tc, "search: prefix beats a metadata substring", cap.landed, 0);
    vwa_test_search_type(st, cap, names, "l");
    vwa_test_eq(tc, "search: repeat letter cycles to the next match", cap.landed, 3);
    vwa_test_search_type(st, cap, names, "l");
    vwa_test_eq(tc, "search: repeat letter wraps", cap.landed, 0);

    vwa_search_reset(st);
    vwa_test_search_type(st, cap, names, "new");
    vwa_test_eq(tc, "search: growing buffer stays on the match", cap.landed, 1);

    vwa_search_reset(st);
    vwa_test_search_type(st, cap, names, "ga pi");
    vwa_test_eq(tc, "search: word-prefix abbreviation", cap.landed, 3);

    vwa_search_reset(st);
    cap.noMatch = undefined;
    vwa_test_search_type(st, cap, names, "zz");
    vwa_test_eq(tc, "search: no match reports the buffer", cap.noMatch, "zz");
    vwa_test_eq(tc, "search: no match leaves no results",
        array_length(st.results), 0);
    vwa_test_ok(tc, "search: stays active on no match", st.active, "inactive");
}

// ---- the screen walker ----

function vwa_dev_walk_start(screenKey)
{
    if (variable_global_exists("vwaDevWalk") && global.vwaDevWalk != undefined
        && !global.vwaDevWalk.done)
    {
        throw "walk: another walk is still running";
    }
    var scr = global.vwaFocusedScreen;
    if (scr == undefined || scr.key != screenKey)
    {
        throw ("walk: screen " + string(screenKey) + " is not focused (focused: "
            + ((scr == undefined) ? "none" : scr.key) + ")");
    }
    if (scr.navState.curRender == undefined || scr.navState.curId == undefined)
    {
        throw "walk: the screen has no settled render yet";
    }
    var order = scr.navState.curRender.order;
    if (array_length(order) == 0)
    {
        throw "walk: the screen renders no nodes";
    }
    var skeys = [];
    var adjustSkey = undefined;
    for (var i = 0; i < array_length(order); i++)
    {
        array_push(skeys, order[i].nid.skey);
        if (adjustSkey == undefined && order[i].onAdjust != undefined)
        {
            adjustSkey = order[i].nid.skey;
        }
    }
    global.vwaDevWalk = {
        scr: scr, screenKey: screenKey,
        skeys: skeys, idx: 0, pending: undefined, expectMove: false,
        prevNode: vwa_graph_node(scr.graph),
        adjustSkey: adjustSkey,
        tap: [], tc: vwa_test_ctx(), nodesDone: 0,
        phase: "sweep", done: false
    };
    global.vwaSpeakTap = method({ }, function(text, intr)
    {
        array_push(global.vwaDevWalk.tap, text);
    });
    vwa_log("walk: started on " + screenKey + " ("
        + string(array_length(skeys)) + " nodes)");
    return { started: screenKey, nodes: array_length(skeys) };
}

function vwa_dev_walk_status()
{
    if (!variable_global_exists("vwaDevWalk") || global.vwaDevWalk == undefined)
    {
        throw "walk: nothing started this run";
    }
    var w = global.vwaDevWalk;
    return { screen: w.screenKey, phase: w.phase, done: w.done,
             nodes: array_length(w.skeys), nodesDone: w.nodesDone,
             checks: w.tc.checks, failures: w.tc.failures };
}

function vwa_dev_walk_finish(w)
{
    w.done = true;
    w.phase = "done";
    global.vwaSpeakTap = undefined;
    vwa_log("walk: " + w.screenKey + " finished, " + string(w.tc.checks)
        + " checks, " + string(array_length(w.tc.failures)) + " failures");
}

// Ticked once per frame from the dev pump append (after the input tick, so
// the frame's rerender and observe have already run). A crash in the walker
// itself becomes a reported failure, never a wedged game.
function vwa_dev_walk_tick()
{
    if (!variable_global_exists("vwaDevWalk") || global.vwaDevWalk == undefined
        || global.vwaDevWalk.done)
    {
        return;
    }
    var w = global.vwaDevWalk;
    try
    {
        vwa_dev_walk_step(w);
    }
    catch (err)
    {
        vwa_test_ok(w.tc, "walk: step crashed", false, string(err));
        vwa_dev_walk_finish(w);
    }
}

function vwa_dev_walk_step(w)
{
    if (global.vwaFocusedScreen != w.scr)
    {
        vwa_test_ok(w.tc, "walk: screen stayed focused", false,
            "focus moved to " + ((global.vwaFocusedScreen == undefined)
                ? "none" : global.vwaFocusedScreen.key));
        vwa_dev_walk_finish(w);
        return;
    }
    if (w.phase == "sweep")
    {
        if (w.pending == undefined)
        {
            if (w.idx >= array_length(w.skeys))
            {
                w.phase = (w.adjustSkey != undefined) ? "adjust-focus" : "typeahead";
                return;
            }
            w.tap = [];
            w.expectMove = (global.vwaNavSpoken.skey != w.skeys[w.idx]
                || global.vwaNavSpoken.screenKey != w.scr.key);
            w.scr.navState.nextMove = w.skeys[w.idx];
            w.pending = w.skeys[w.idx];
            return;
        }
        vwa_dev_walk_verify_node(w);
        w.pending = undefined;
        w.idx += 1;
        return;
    }
    if (w.phase == "adjust-focus")
    {
        w.scr.navState.nextMove = w.adjustSkey;
        w.phase = "adjust-run";
        return;
    }
    if (w.phase == "adjust-run")
    {
        vwa_dev_walk_adjust(w);
        w.phase = "typeahead";
        return;
    }
    if (w.phase == "typeahead")
    {
        vwa_dev_walk_typeahead(w);
        vwa_dev_walk_finish(w);
        return;
    }
    vwa_test_ok(w.tc, "walk: known phase", false, w.phase);
    vwa_dev_walk_finish(w);
}

// One swept node, the frame after its nextMove: focus landed, the observe
// spoke it exactly once with the text a fresh live resolve produces, and
// the alt-arrow line review walks its lines down and back up with the
// boundary words at the ends.
function vwa_dev_walk_verify_node(w)
{
    var st = w.scr.navState;
    var nd = (st.curRender != undefined)
        ? variable_struct_get(st.curRender.byKey, w.pending) : undefined;
    if (nd == undefined)
    {
        vwa_test_ok(w.tc, "walk: node " + w.pending + " still in the render",
            false, "vanished mid-walk");
        return;
    }
    vwa_test_ok(w.tc, "walk: focus landed on " + w.pending,
        st.curId != undefined && st.curId.skey == w.pending,
        (st.curId == undefined) ? "no focus" : st.curId.skey);
    if (st.curId == undefined || st.curId.skey != w.pending)
    {
        return; // the line review below would test the wrong node
    }

    if (w.expectMove)
    {
        var expected = vwa_speak_render(vwa_ann_compose(w.prevNode, nd,
            global.vwaControlTypes, global.vwaAnnHooks, undefined));
        vwa_test_ok(w.tc, "walk: one utterance landing on " + w.pending,
            array_length(w.tap) == 1, vwa_test_join(w.tap));
        if (array_length(w.tap) >= 1)
        {
            vwa_test_eq(w.tc, "walk: landing text for " + w.pending,
                w.tap[0], expected);
        }
    }
    else
    {
        vwa_test_ok(w.tc, "walk: no re-announce for " + w.pending,
            array_length(w.tap) == 0, vwa_test_join(w.tap));
    }

    var lines = vwa_ann_leaf(nd, global.vwaControlTypes, global.vwaAnnHooks);
    var n = array_length(lines);
    if (n > 0)
    {
        var expectedSeq = [];
        for (var i = 1; i < n; i++)
        {
            array_push(expectedSeq, vwa_speak_render([lines[i]]));
        }
        array_push(expectedSeq, vwa_t("vwa--line-bottom"));
        for (var i = n - 2; i >= 0; i--)
        {
            array_push(expectedSeq, vwa_speak_render([lines[i]]));
        }
        array_push(expectedSeq, vwa_t("vwa--line-top"));

        w.tap = [];
        for (var i = 1; i < n; i++)
        {
            vwa_nav_line_step(1);
        }
        vwa_nav_line_step(1);
        for (var i = n - 2; i >= 0; i--)
        {
            vwa_nav_line_step(-1);
        }
        vwa_nav_line_step(-1);

        var okSeq = (array_length(w.tap) == array_length(expectedSeq));
        if (okSeq)
        {
            for (var i = 0; i < array_length(expectedSeq); i++)
            {
                if (w.tap[i] != expectedSeq[i])
                {
                    okSeq = false;
                    break;
                }
            }
        }
        vwa_test_ok(w.tc, "walk: line review on " + w.pending, okSeq,
            "expected [" + vwa_test_join(expectedSeq) + "] got ["
            + vwa_test_join(w.tap) + "]");
    }

    w.prevNode = nd;
    w.nodesDone += 1;
}

// The adjust node's live parts, freshly resolved.
function vwa_dev_walk_sig(w)
{
    var st = w.scr.navState;
    var nd = (st.curRender != undefined)
        ? variable_struct_get(st.curRender.byKey, w.adjustSkey) : undefined;
    return (nd == undefined) ? undefined : vwa_nav_live_resolve(nd);
}

// The immediate feedback of one adjust press must be exactly the live parts
// that changed, in part order (mirrors vwa_nav_state_feedback's own rule).
function vwa_dev_walk_adjust_feedback(w, name, sigFrom, sigTo)
{
    var diffs = [];
    var n = min(array_length(sigFrom), array_length(sigTo));
    for (var i = 0; i < n; i++)
    {
        if (sigTo[i] != sigFrom[i] && sigTo[i] != "")
        {
            array_push(diffs, sigTo[i]);
        }
    }
    var okSeq = (array_length(w.tap) == array_length(diffs));
    if (okSeq)
    {
        for (var i = 0; i < array_length(diffs); i++)
        {
            if (w.tap[i] != diffs[i])
            {
                okSeq = false;
                break;
            }
        }
    }
    vwa_test_ok(w.tc, "walk: " + name + " feedback", okSeq,
        "expected [" + vwa_test_join(diffs) + "] got ["
        + vwa_test_join(w.tap) + "]");
}

// Net-zero adjust on the screen's first adjustable control: one step out,
// one step back, value restored, each press's feedback spoken immediately.
// At the range's top the directions swap; a degenerate range just checks
// nothing moved.
function vwa_dev_walk_adjust(w)
{
    var st = w.scr.navState;
    if (st.curId == undefined || st.curId.skey != w.adjustSkey)
    {
        vwa_test_ok(w.tc, "walk: adjust probe focused " + w.adjustSkey, false,
            (st.curId == undefined) ? "no focus" : st.curId.skey);
        return;
    }
    var sigBefore = vwa_dev_walk_sig(w);
    if (sigBefore == undefined)
    {
        vwa_test_ok(w.tc, "walk: adjust node resolves", false, "node lost");
        return;
    }
    w.tap = [];
    vwa_nav_move("right");
    var sigAfter = vwa_dev_walk_sig(w);
    if (sigAfter == undefined)
    {
        vwa_test_ok(w.tc, "walk: adjust node survived adjusting", false,
            "node lost after right");
        return;
    }
    if (array_length(w.tap) > 0)
    {
        vwa_dev_walk_adjust_feedback(w, "adjust right", sigBefore, sigAfter);
        w.tap = [];
        vwa_nav_move("left");
        vwa_dev_walk_adjust_feedback(w, "adjust left", sigAfter,
            vwa_dev_walk_sig(w));
    }
    else
    {
        // No movement right: at the top of the range, go the other way.
        vwa_nav_move("left");
        var sigLeft = vwa_dev_walk_sig(w);
        if (array_length(w.tap) == 0)
        {
            vwa_test_ok(w.tc, "walk: degenerate adjust range left the value alone",
                vwa_test_join(sigLeft) == vwa_test_join(sigBefore),
                vwa_test_join(sigLeft));
            return;
        }
        vwa_dev_walk_adjust_feedback(w, "adjust left", sigBefore, sigLeft);
        w.tap = [];
        vwa_nav_move("right");
    }
    vwa_test_ok(w.tc, "walk: adjust restored " + w.adjustSkey,
        vwa_test_join(vwa_dev_walk_sig(w)) == vwa_test_join(sigBefore),
        "expected [" + vwa_test_join(sigBefore) + "] got ["
        + vwa_test_join(vwa_dev_walk_sig(w)) + "]");
}

// One type-ahead character taken from a real label in the focused Tab stop
// must produce a landing (results, focus, one spoken announcement matching
// a fresh resolve of the landed node). Cleared silently afterwards.
function vwa_dev_walk_typeahead(w)
{
    if (!vwa_opt(w.scr, "allowsTypeahead", true))
    {
        return;
    }
    var st = w.scr.navState;
    if (st.curRender == undefined || st.curId == undefined)
    {
        vwa_test_ok(w.tc, "walk: typeahead probe has a render", false, "none");
        return;
    }
    var nd = variable_struct_get(st.curRender.byKey, st.curId.skey);
    if (nd == undefined)
    {
        vwa_test_ok(w.tc, "walk: typeahead probe has a focused node", false,
            st.curId.skey);
        return;
    }
    var order = st.curRender.order;
    var ch = "";
    for (var i = 0; i < array_length(order); i++)
    {
        if (order[i].stopKey != nd.stopKey)
        {
            continue;
        }
        var lbl = vwa_ann_first_label(order[i]);
        for (var j = 1; j <= string_length(lbl); j++)
        {
            var o = string_ord_at(lbl, j);
            if (vwa_search_char_is_letter(o))
            {
                ch = chr(o);
                break;
            }
        }
        if (ch != "")
        {
            break;
        }
    }
    if (ch == "")
    {
        return; // no letters anywhere in this stop's labels
    }
    var fromNd = (global.vwaNavSpoken.screenKey == w.scr.key)
        ? global.vwaNavSpoken.node : undefined;
    w.tap = [];
    vwa_nav_typeahead_char(ch);
    var landedOk = global.vwaSearch.active
        && array_length(global.vwaSearch.results) > 0;
    vwa_test_ok(w.tc, "walk: typeahead '" + ch + "' found a match", landedOk,
        "buffer [" + global.vwaSearch.buffer + "], results "
        + string(array_length(global.vwaSearch.results)));
    if (landedOk)
    {
        var landedNd = vwa_graph_node(w.scr.graph);
        var expected = vwa_speak_render(vwa_ann_compose(fromNd, landedNd,
            global.vwaControlTypes, global.vwaAnnHooks, undefined));
        vwa_test_ok(w.tc, "walk: typeahead landing spoke once",
            array_length(w.tap) == 1, vwa_test_join(w.tap));
        if (array_length(w.tap) >= 1)
        {
            vwa_test_eq(w.tc, "walk: typeahead landing text", w.tap[0], expected);
        }
    }
    vwa_nav_search_clear(false);
}
