// scrVwaTestWalk - Void War Access screen walker, DEV BUILDS ONLY (one of
// the three test scripts; the assertion collector, the selftest, and the
// derive-expectations-live design rule live in scrVwaTest).
//
// vwa_dev_walk_start(screenKey) + vwa_dev_walk_status: an end-to-end
// contract check of the FOCUSED screen, both invoked through the dev
// driver's `call` command. A frame-driven state machine (ticked from the
// dev pump append via vwa_dev_walk_tick) visits every node of the
// screen's render through the real focus path (navState.nextMove ->
// reconcile -> observe) and verifies, per node: focus lands, exactly one
// utterance is spoken, its text equals a fresh live resolve of the same
// node (vwa_ann_compose rendered through vwa_speak_render), and the
// alt-arrow line review steps every line down and back up with the
// boundary words at the ends. Two probes follow: the screen's first
// adjustable control gets a net-zero adjust whose feedback utterances
// must equal exactly the live parts that changed, and one type-ahead
// character taken from a real label must land with a spoken
// announcement. Speech is observed through global.vwaSpeakTap (the
// chokepoint's sanctioned observation point; never speaks).
// scripts/smoke.ps1 is the dumb runner that opens screens, starts walks,
// polls status, and prints failures - no expectations live in PowerShell.

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
// that changed, in part order; when none changed, every non-empty live part
// (the adjust heartbeat) - mirrors vwa_nav_state_feedback's adjust-path
// rule.
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
    if (array_length(diffs) == 0)
    {
        for (var i = 0; i < array_length(sigTo); i++)
        {
            if (sigTo[i] != "")
            {
                array_push(diffs, sigTo[i]);
            }
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
// one step back, each press's feedback checked against the rule above.
// Movement is detected by the live signature, never by silence (a step
// between identically-rendered values speaks the heartbeat, and a press
// against the range top speaks it too). After right then left the
// signature normally sits back at its start - whether the right press
// moved (left undid it) or hit the top (both pressed into the same end).
// A signature still off its start means the right press sat on the top
// and the left press moved down: one restoring right closes the loop.
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
    vwa_dev_walk_adjust_feedback(w, "adjust right", sigBefore, sigAfter);
    w.tap = [];
    vwa_nav_move("left");
    var sigLeft = vwa_dev_walk_sig(w);
    if (sigLeft == undefined)
    {
        vwa_test_ok(w.tc, "walk: adjust node survived adjusting", false,
            "node lost after left");
        return;
    }
    vwa_dev_walk_adjust_feedback(w, "adjust left", sigAfter, sigLeft);
    if (vwa_test_join(sigLeft) != vwa_test_join(sigBefore))
    {
        w.tap = [];
        vwa_nav_move("right");
        vwa_dev_walk_adjust_feedback(w, "adjust restore", sigLeft,
            vwa_dev_walk_sig(w));
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
