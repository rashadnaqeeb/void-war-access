// scrVwaGraph - Void War Access control graph: two-tier node identity,
// immediate-mode graph builder (menu mode + raw mode), and the navigation
// engine (down-right total order, focus reconciliation across rebuilds, Tab
// stops with remembered positions). Ported from WotR Access's UI/Graph
// (GraphBuilder/KeyGraph/ControlId), itself from Tanglebeep and Factorio
// Access's key-graph.lua.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// PURE MODULE: no instance or global references, no speech - the engine
// returns what happened and the screens layer (scrVwaScreens) announces it.
// Announcement-part helpers and composition live in scrVwaAnnounce.
//
// Known divergences from the WotR reference, deliberate for now:
// - No expandable tree groups (BeginGroup) and no regions; nothing in the
//   Void War foundation screens needs them yet.
// - No menu/raw mode-boundary stitching: a Tab stop that mixes menu rows
//   with raw nodes leaves the seam unwired. Revisit if a real screen mixes
//   modes (WotR GraphBuilder.StitchModeBoundaries is the recipe).
//
// Directions are the strings "up" / "down" / "left" / "right" (enums are
// avoided; cross-entry enum visibility is not guaranteed under the UTMT
// importer). Structural keys and stop keys are strings.

// ---- node identity ----
// Two tiers so focus can follow a control across rebuilds: skey (structural,
// always present, value-equatable string) and ref (optional backing object -
// an instance id or a struct, matched by identity: == on two struct
// references is reference equality, and vwa_ref_eq never compares a struct
// against a real).

function vwa_id(skey)
{
    return { ref: undefined, skey: skey };
}

function vwa_id_ref(ref, skey)
{
    return { ref: ref, skey: skey };
}

function vwa_ref_eq(a, b)
{
    if (is_undefined(a) || is_undefined(b))
    {
        return false;
    }
    if (is_struct(a) != is_struct(b))
    {
        return false;
    }
    return a == b;
}

function vwa_opt(st, fieldName, defVal)
{
    if (is_struct(st) && variable_struct_exists(st, fieldName))
    {
        return variable_struct_get(st, fieldName);
    }
    return defVal;
}

// ---- builder ----
// Immediate mode: screens declare their controls fresh from live game state
// on every build; nothing is retained between builds except the nav state
// (focus, stop memory) in scrVwaScreens.
//
// Menu mode: vwa_gb_add inside vwa_gb_start_row/vwa_gb_end_row makes a
// horizontal row; vwa_gb_add outside a row makes a single-item row (a plain
// vertical menu). Consecutive rows in the same Tab stop chain vertically;
// rows sharing a non-undefined rowKey get column-preserving vertical moves.
// Raw mode: vwa_gb_add_raw + vwa_gb_connect for arbitrary topologies.
// vwa_gb_begin_stop groups nodes into Tab stops (arrows never cross a stop);
// vwa_gb_push_context/vwa_gb_pop_context push non-focusable labeled levels
// onto the parent chain (announced by path diff when focus enters them).

function vwa_gb_new()
{
    return {
        rows: [],          // menu mode: {items:[node], rowKey, stopKey}
        curRow: undefined,
        rawEdges: [],      // {from, dir, to, label}
        declared: [],      // every focusable node in declaration order
        ids: {},           // skey -> true (duplicate detection)
        startKey: undefined,
        stopKey: "stop#0",
        stopAuto: 1,
        parents: []        // context node stack (non-focusable)
    };
}

// def fields: parts (required, non-empty array from scrVwaAnnounce helpers),
// typeKey (control type name, optional), onActivate / onAdjust / onTooltip
// (optional bound methods; onAdjust takes (sign, large)).
function vwa_gb_make_node(b, nodeId, def)
{
    var parts = vwa_opt(def, "parts", undefined);
    if (!is_array(parts) || array_length(parts) == 0)
    {
        throw ("graph: node " + string(nodeId.skey) + " needs a non-empty parts array");
    }
    if (variable_struct_exists(b.ids, nodeId.skey))
    {
        throw ("graph: duplicate node key " + string(nodeId.skey));
    }
    variable_struct_set(b.ids, nodeId.skey, true);
    var parentCnt = array_length(b.parents);
    var nd = {
        nid: nodeId,
        parts: parts,
        typeKey: vwa_opt(def, "typeKey", undefined),
        onActivate: vwa_opt(def, "onActivate", undefined),
        onAdjust: vwa_opt(def, "onAdjust", undefined),
        onTooltip: vwa_opt(def, "onTooltip", undefined),
        parent: (parentCnt > 0) ? b.parents[parentCnt - 1] : undefined,
        focusable: true,
        stopKey: b.stopKey,
        posIndex: 0,
        posCount: 0,
        trans: {}         // dir -> {to: skey, label: string|undefined}
    };
    array_push(b.declared, nd);
    return nd;
}

// Start a new Tab stop. stopName must be stable across rebuilds (it keys the
// stop's remembered focus position); "" auto-assigns by index, stable when
// the screen declares its stops in a fixed order.
function vwa_gb_begin_stop(b, stopName)
{
    if (b.curRow != undefined)
    {
        throw "graph: cannot begin a stop inside an open row";
    }
    b.stopKey = (stopName == "") ? ("stop#" + string(b.stopAuto)) : stopName;
    b.stopAuto += 1;
}

// Push one non-focusable level of presentation hierarchy (a labeled panel).
// It exists only on parent chains for path-diff announcements. label is a
// resolved string (builds rerun every frame, so it stays live).
function vwa_gb_push_context(b, label)
{
    var parentCnt = array_length(b.parents);
    var parentKey = (parentCnt > 0) ? b.parents[parentCnt - 1].nid.skey : "";
    var nd = {
        nid: vwa_id("ctx:" + parentKey + "/" + label),
        parts: [vwa_part("label", label)],
        typeKey: undefined,
        onActivate: undefined,
        onAdjust: undefined,
        onTooltip: undefined,
        parent: (parentCnt > 0) ? b.parents[parentCnt - 1] : undefined,
        focusable: false,
        stopKey: b.stopKey,
        posIndex: 0,
        posCount: 0,
        trans: {}
    };
    array_push(b.parents, nd);
}

function vwa_gb_pop_context(b)
{
    if (array_length(b.parents) == 0)
    {
        throw "graph: no context to pop";
    }
    array_pop(b.parents);
}

// Open a horizontal row. Rows sharing a non-undefined rowKey with the row
// above/below keep the column on vertical moves. groupLabel names the group
// a multi-item row forms ("" = unnamed: the announcer substitutes its
// caller-localized generic group word, hooks.groupText).
function vwa_gb_start_row(b, rowKey, groupLabel)
{
    if (b.curRow != undefined)
    {
        throw "graph: cannot start a row while another is open";
    }
    b.curRow = { items: [], rowKey: rowKey, stopKey: b.stopKey,
                 groupLabel: groupLabel };
}

function vwa_gb_end_row(b)
{
    if (b.curRow == undefined)
    {
        throw "graph: no row to end";
    }
    if (array_length(b.curRow.items) == 0)
    {
        throw "graph: row cannot be empty";
    }
    array_push(b.rows, b.curRow);
    b.curRow = undefined;
}

// Add a control: into the open row, or as its own single-item row.
function vwa_gb_add(b, nodeId, def)
{
    var nd = vwa_gb_make_node(b, nodeId, def);
    if (b.curRow != undefined)
    {
        nd.inRow = true;
        array_push(b.curRow.items, nd);
    }
    else
    {
        array_push(b.rows, { items: [nd], rowKey: undefined, stopKey: b.stopKey });
    }
}

// Add a node with no automatic wiring (raw mode; wire with vwa_gb_connect).
// Raw nodes are never in a row, so they get no auto position stamp.
function vwa_gb_add_raw(b, nodeId, def)
{
    vwa_gb_make_node(b, nodeId, def);
}

// Directed edge fromKey -> toKey with an optional spoken transition label
// ("" = silent edge). Edges naming undeclared nodes are dropped at build.
function vwa_gb_connect(b, fromKey, dir, toKey, label)
{
    array_push(b.rawEdges, { from: fromKey, dir: dir, to: toKey, label: label });
}

// Focus starts here when the graph has no prior position (default: the
// first declared node).
function vwa_gb_set_start(b, skey)
{
    b.startKey = skey;
}

// Finalize into a render {byKey, order, startKey}, or undefined when nothing
// was declared (the screens layer treats that as "no graph yet").
function vwa_gb_build(b)
{
    if (b.curRow != undefined)
    {
        throw "graph: unclosed row - call vwa_gb_end_row";
    }
    if (array_length(b.declared) == 0)
    {
        return undefined;
    }
    var rndr = { byKey: {}, order: b.declared, startKey: undefined };
    for (var i = 0; i < array_length(b.declared); i++)
    {
        var nd = b.declared[i];
        variable_struct_set(rndr.byKey, nd.nid.skey, nd);
    }

    vwa_gb_synth_groups(b);
    vwa_gb_wire_rows(b);

    for (var i = 0; i < array_length(b.rawEdges); i++)
    {
        var e = b.rawEdges[i];
        var fromNd = variable_struct_get(rndr.byKey, e.from);
        if (fromNd == undefined || variable_struct_get(rndr.byKey, e.to) == undefined)
        {
            continue;
        }
        variable_struct_set(fromNd.trans, e.dir,
            { to: e.to, label: (e.label == "") ? undefined : e.label });
    }

    if (b.startKey != undefined && variable_struct_get(rndr.byKey, b.startKey) != undefined)
    {
        rndr.startKey = b.startKey;
    }
    else
    {
        rndr.startKey = b.declared[0].nid.skey;
    }

    vwa_gb_stamp_positions(b);
    return rndr;
}

// Left/right within a row; up/down between consecutive rows of the same Tab
// stop (arrows never cross a stop). Shared non-undefined row keys preserve
// the column; otherwise vertical moves land on the first item.
function vwa_gb_wire_rows(b)
{
    // Group rows by stop key, keeping first-appearance order.
    var stopKeys = [];
    var byStop = {};
    for (var i = 0; i < array_length(b.rows); i++)
    {
        var row = b.rows[i];
        var lst = variable_struct_get(byStop, row.stopKey);
        if (lst == undefined)
        {
            lst = [];
            variable_struct_set(byStop, row.stopKey, lst);
            array_push(stopKeys, row.stopKey);
        }
        array_push(lst, row);
    }

    for (var s = 0; s < array_length(stopKeys); s++)
    {
        var rows = variable_struct_get(byStop, stopKeys[s]);
        for (var r = 0; r < array_length(rows); r++)
        {
            var row = rows[r];
            for (var p = 0; p < array_length(row.items); p++)
            {
                var nd = row.items[p];
                if (r > 0)
                {
                    variable_struct_set(nd.trans, "up",
                        { to: vwa_gb_vertical_target(row, rows[r - 1], p), label: undefined });
                }
                if (r < array_length(rows) - 1)
                {
                    variable_struct_set(nd.trans, "down",
                        { to: vwa_gb_vertical_target(row, rows[r + 1], p), label: undefined });
                }
                if (p > 0)
                {
                    variable_struct_set(nd.trans, "left",
                        { to: row.items[p - 1].nid.skey, label: undefined });
                }
                if (p < array_length(row.items) - 1)
                {
                    variable_struct_set(nd.trans, "right",
                        { to: row.items[p + 1].nid.skey, label: undefined });
                }
            }
        }
    }
}

function vwa_gb_vertical_target(fromRow, toRow, pos)
{
    if (fromRow.rowKey != undefined && toRow.rowKey != undefined
        && fromRow.rowKey == toRow.rowKey && pos < array_length(toRow.items))
    {
        return toRow.items[pos].nid.skey;
    }
    return toRow.items[0].nid.skey;
}

// A multi-item row IS a group: synthesize a non-focusable context node that
// carries the row's label (or, when empty, the announcer's generic group
// word via hooks.groupText) and the row's position among the stop's
// vertical entries, and reparent the members under it. Arriving in the row
// then announces the group level first (path diff), while the members keep
// their own "x of k" within the row - the two numbering axes never blur
// (session-7 user report: landing on the window-mode trio spoke a bare
// "1 of 3" that read as a vertical position).
function vwa_gb_synth_groups(b)
{
    for (var i = 0; i < array_length(b.rows); i++)
    {
        var row = b.rows[i];
        if (array_length(row.items) <= 1)
        {
            continue;
        }
        var first = row.items[0];
        var gnd = {
            nid: vwa_id("grp:" + first.nid.skey),
            parts: [vwa_part("label", vwa_opt(row, "groupLabel", ""))],
            typeKey: undefined,
            onActivate: undefined,
            onAdjust: undefined,
            onTooltip: undefined,
            parent: first.parent,
            focusable: false,
            isGroup: true,
            stopKey: row.stopKey,
            posIndex: 0,
            posCount: 0,
            trans: {}
        };
        row.groupNode = gnd;
        for (var p = 0; p < array_length(row.items); p++)
        {
            row.items[p].parent = gnd;
        }
    }
}

// Auto-stamp "n of m" sibling positions on two axes: a multi-item row's
// members within their row, and one vertical entry per ROW - the node
// itself for a single-item row, the synthesized group node for a multi-item
// row - among the rows sharing a (parent, stop). The vertical count
// therefore includes groups as single landing points. Raw nodes get none.
// Spoken only when m > 1 (scrVwaAnnounce).
function vwa_gb_stamp_positions(b)
{
    var groupKeys = [];
    var groups = {};
    for (var i = 0; i < array_length(b.rows); i++)
    {
        var row = b.rows[i];
        var entry = row.items[0];
        if (array_length(row.items) > 1)
        {
            vwa_gb_stamp(row.items);
            entry = row.groupNode;
        }
        var parentKey = (entry.parent != undefined) ? entry.parent.nid.skey : "";
        var gk = parentKey + "|" + entry.stopKey;
        var lst = variable_struct_get(groups, gk);
        if (lst == undefined)
        {
            lst = [];
            variable_struct_set(groups, gk, lst);
            array_push(groupKeys, gk);
        }
        array_push(lst, entry);
    }
    for (var i = 0; i < array_length(groupKeys); i++)
    {
        vwa_gb_stamp(variable_struct_get(groups, groupKeys[i]));
    }
}

function vwa_gb_stamp(siblings)
{
    var cnt = array_length(siblings);
    if (cnt < 2)
    {
        return;
    }
    for (var i = 0; i < cnt; i++)
    {
        siblings[i].posIndex = i + 1;
        siblings[i].posCount = cnt;
    }
}

// ---- traversal order and focus reconciliation ----

// The down-right total order: from the start node, go right until stuck
// (recording each node), queue every down for a later pass, repeat; then
// append anything unreached (later Tab stops have no cross-stop edges) in
// declaration order, so the order is total. Used for nearest-survivor focus
// recovery.
function vwa_graph_compute_order(rndr)
{
    var order = [];
    var seen = {};
    var fringe = [rndr.startKey];
    var i = 0;
    while (i < array_length(fringe))
    {
        var k = fringe[i];
        while (variable_struct_get(seen, k) == undefined)
        {
            variable_struct_set(seen, k, true);
            array_push(order, k);
            var nd = variable_struct_get(rndr.byKey, k);
            if (nd == undefined)
            {
                break;
            }
            var d = variable_struct_get(nd.trans, "down");
            if (d != undefined)
            {
                array_push(fringe, d.to);
            }
            var r = variable_struct_get(nd.trans, "right");
            if (r == undefined)
            {
                break;
            }
            k = r.to;
        }
        i++;
    }
    for (var j = 0; j < array_length(rndr.order); j++)
    {
        var sk = rndr.order[j].nid.skey;
        if (variable_struct_get(seen, sk) == undefined)
        {
            variable_struct_set(seen, sk, true);
            array_push(order, sk);
        }
    }
    return order;
}

// The first node in a stop that reads as selected (carries a non-empty
// "selected"-kind part) - where entering a stop lands with no memory, so a
// radio/tab group opens on its checked member, not the top of the list.
function vwa_graph_selected_in_stop(rndr, stopKey)
{
    for (var i = 0; i < array_length(rndr.order); i++)
    {
        var nd = rndr.order[i];
        if (nd.stopKey != stopKey)
        {
            continue;
        }
        for (var p = 0; p < array_length(nd.parts); p++)
        {
            if (nd.parts[p].kind == "selected" && vwa_part_resolve(nd.parts[p]) != "")
            {
                return nd;
            }
        }
    }
    return undefined;
}

// Where focus lands when entering a stop: the remembered position, else the
// selected member, else the stop's first node.
function vwa_graph_stop_landing(rndr, st, stopKey)
{
    var remembered = variable_struct_get(st.stopMemory, stopKey);
    if (remembered != undefined)
    {
        var nd = variable_struct_get(rndr.byKey, remembered);
        if (nd != undefined && nd.stopKey == stopKey)
        {
            return nd;
        }
    }
    var sel = vwa_graph_selected_in_stop(rndr, stopKey);
    if (sel != undefined)
    {
        return sel;
    }
    for (var i = 0; i < array_length(rndr.order); i++)
    {
        if (rndr.order[i].stopKey == stopKey)
        {
            return rndr.order[i];
        }
    }
    return undefined;
}

function vwa_graph_remember_stop(st, nd)
{
    variable_struct_set(st.stopMemory, nd.stopKey, nd.nid.skey);
}

function vwa_graph_set_current(st, nd)
{
    st.curId = { ref: nd.nid.ref, skey: nd.nid.skey };
    vwa_graph_remember_stop(st, nd);
}

// Move focus from st.curId to a valid control in rndr, then recompute the
// traversal order. Recovery tiers: 1) the same backing object even if its
// structural key changed (it moved); 2) the same structural key even if the
// backing object was rebuilt; 3) nearest survivor walking the previous
// order backward; else the start node (preferring its stop's selected
// member).
function vwa_graph_reconcile(rndr, st)
{
    if (st.nextMove != undefined)
    {
        var nm = variable_struct_get(rndr.byKey, st.nextMove);
        if (nm != undefined)
        {
            st.curId = { ref: nm.nid.ref, skey: nm.nid.skey };
        }
        st.nextMove = undefined;
    }

    var resolved = undefined;
    if (st.curId != undefined)
    {
        if (st.curId.ref != undefined)
        {
            for (var i = 0; i < array_length(rndr.order); i++)
            {
                if (vwa_ref_eq(rndr.order[i].nid.ref, st.curId.ref))
                {
                    resolved = rndr.order[i];
                    break;
                }
            }
        }
        if (resolved == undefined)
        {
            resolved = variable_struct_get(rndr.byKey, st.curId.skey);
        }
        if (resolved == undefined && st.keyOrder != undefined)
        {
            var oldIdx = vwa_array_index_of(st.keyOrder, st.curId.skey);
            for (var i = oldIdx; i >= 0; i--)
            {
                var survivor = variable_struct_get(rndr.byKey, st.keyOrder[i]);
                if (survivor != undefined)
                {
                    resolved = survivor;
                    break;
                }
            }
        }
    }

    if (resolved == undefined)
    {
        var startNd = variable_struct_get(rndr.byKey, rndr.startKey);
        var sel = (startNd != undefined)
            ? vwa_graph_selected_in_stop(rndr, startNd.stopKey) : undefined;
        resolved = (sel != undefined) ? sel : startNd;
    }

    vwa_graph_set_current(st, resolved);
    st.keyOrder = vwa_graph_compute_order(rndr);
}

// ---- the navigation engine ----
// gr = {build: fn(builder)|undefined, state: nav state}. The nav state (the
// only thing surviving between renders): {curId, keyOrder, stopMemory,
// nextMove, curRender}. Every operation rebuilds the render from live state
// first (never cache game state), reconciles focus into it, then acts.

function vwa_nav_state_new()
{
    return { curId: undefined, keyOrder: undefined, stopMemory: {},
             nextMove: undefined, curRender: undefined };
}

// Reset in place: the screens layer hands the same struct to the engine, so
// clearing on screen close must mutate, not replace.
function vwa_nav_state_reset(st)
{
    st.curId = undefined;
    st.keyOrder = undefined;
    st.stopMemory = {};
    st.nextMove = undefined;
    st.curRender = undefined;
}

// Rebuild and reconcile. False when there is no build function or it
// declared nothing (treat the graph as closed). Build errors propagate to
// the caller (the screens layer logs and quarantines the screen).
function vwa_graph_rerender(gr)
{
    if (gr.build == undefined)
    {
        gr.state.curRender = undefined;
        return false;
    }
    var b = vwa_gb_new();
    var buildFn = gr.build;
    buildFn(b);
    var rndr = vwa_gb_build(b);
    gr.state.curRender = rndr;
    if (rndr == undefined)
    {
        return false;
    }
    vwa_graph_reconcile(rndr, gr.state);
    return true;
}

// The focused node in the current render, or undefined.
function vwa_graph_node(gr)
{
    if (gr.state.curRender == undefined || gr.state.curId == undefined)
    {
        return undefined;
    }
    return variable_struct_get(gr.state.curRender.byKey, gr.state.curId.skey);
}

// One step in dir. Returns {moved, fromNode, toNode, label}; at an edge (or
// with no graph) moved is false and toNode == fromNode.
function vwa_graph_move(gr, dir)
{
    var result = { moved: false, fromNode: undefined, toNode: undefined, label: undefined };
    if (!vwa_graph_rerender(gr))
    {
        return result;
    }
    var nd = vwa_graph_node(gr);
    result.fromNode = nd;
    result.toNode = nd;
    if (nd == undefined)
    {
        return result;
    }
    var t = variable_struct_get(nd.trans, dir);
    if (t == undefined)
    {
        return result;
    }
    var dest = variable_struct_get(gr.state.curRender.byKey, t.to);
    if (dest == undefined || dest == nd)
    {
        return result;
    }
    vwa_graph_set_current(gr.state, dest);
    result.toNode = dest;
    result.moved = true;
    result.label = t.label;
    return result;
}

// Cycle to the next (+1) / previous (-1) Tab stop in traversal order,
// wrapping past the ends, landing on the stop's remembered position.
function vwa_graph_move_stop(gr, dirNum)
{
    var result = { moved: false, fromNode: undefined, toNode: undefined, label: undefined };
    if (!vwa_graph_rerender(gr))
    {
        return result;
    }
    var nd = vwa_graph_node(gr);
    result.fromNode = nd;
    result.toNode = nd;
    if (nd == undefined)
    {
        return result;
    }
    var rndr = gr.state.curRender;
    var stops = [];
    for (var i = 0; i < array_length(rndr.order); i++)
    {
        if (vwa_array_index_of(stops, rndr.order[i].stopKey) < 0)
        {
            array_push(stops, rndr.order[i].stopKey);
        }
    }
    if (array_length(stops) <= 1)
    {
        return result;
    }
    var idx = vwa_array_index_of(stops, nd.stopKey);
    if (idx < 0)
    {
        return result;
    }
    var cnt = array_length(stops);
    var ni = ((idx + dirNum) % cnt + cnt) % cnt;
    if (ni == idx)
    {
        return result;
    }
    var dest = vwa_graph_stop_landing(rndr, gr.state, stops[ni]);
    if (dest == undefined)
    {
        return result;
    }
    vwa_graph_set_current(gr.state, dest);
    result.toNode = dest;
    result.moved = true;
    return result;
}

// Move focus to a specific control key. False when it isn't in the render.
function vwa_graph_focus(gr, skey)
{
    if (!vwa_graph_rerender(gr))
    {
        return false;
    }
    var nd = variable_struct_get(gr.state.curRender.byKey, skey);
    if (nd == undefined)
    {
        return false;
    }
    vwa_graph_set_current(gr.state, nd);
    return true;
}

// Run the focused control's primary activation. False = it has none.
function vwa_graph_activate(gr)
{
    if (!vwa_graph_rerender(gr))
    {
        return false;
    }
    var nd = vwa_graph_node(gr);
    if (nd == undefined || nd.onActivate == undefined)
    {
        return false;
    }
    var fn = nd.onActivate;
    fn();
    return true;
}

// If the focused control adjusts horizontally (a slider), adjust and return
// true; false = the caller should navigate instead.
function vwa_graph_adjust(gr, sign, large)
{
    if (!vwa_graph_rerender(gr))
    {
        return false;
    }
    var nd = vwa_graph_node(gr);
    if (nd == undefined || nd.onAdjust == undefined)
    {
        return false;
    }
    var fn = nd.onAdjust;
    fn(sign, large);
    return true;
}

// Run the focused control's tooltip behavior. False = it has none.
function vwa_graph_tooltip(gr)
{
    if (!vwa_graph_rerender(gr))
    {
        return false;
    }
    var nd = vwa_graph_node(gr);
    if (nd == undefined || nd.onTooltip == undefined)
    {
        return false;
    }
    var fn = nd.onTooltip;
    fn();
    return true;
}
