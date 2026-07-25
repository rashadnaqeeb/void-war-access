// scrVwaShipDesc - Void War Access ship shape describer (ship-layer piece:
// one keypress answering "what does this ship look like and where is
// everything", the way a sighted player takes a hull in at a glance).
// D (category "ship", so it follows the focused hull and any stacked
// screen suspends it; the game's own default D bind, power_oxygen, sits
// behind the default-deny gate like K and R already do) speaks a
// multi-LINE description through the chokepoint - each line an alt-arrow
// line-review step - always interrupting (direct user-caused feedback,
// the K/R precedent). Imported by tools/build-mod.csx as a new global
// script. Ships in release.
//
// The description (wording all vwa_t, terse by rule; screen terms only -
// left/right/top/bottom in the cursor's signed-coordinate frame, never
// bow/stern: the room-data audit found vertical hulls and no reliable
// fore/aft system convention, and facing wording is out for good):
// - Line 1, gestalt: "{w} wide, {h} tall, {n} rooms", then a symmetry
//   token (mirror about the long axis: 0 mismatched tiles "symmetric",
//   up to 2 "roughly symmetric", else silent - never announce a
//   negative), then "{n} sections" only when the hull has door-
//   disconnected components (ruins, bosses).
// - Segment lines, a sweep along the LONG axis (width >= height sweeps
//   left to right, else top to bottom; ties sweep horizontally): the
//   hull's outer profile per sweep step (interior holes ignored),
//   adjacent equal profiles merged, then folded to at most 6 segments by
//   repeatedly merging the adjacent pair with the smallest profile
//   change (earliest pair on ties; a folded segment speaks its union
//   extent through the "up to" template - honest coarsening). Validated
//   against every real hull in the room data: typical ships read in 3-7
//   segments, only bosses and ruins hit the cap. Each line: the sweep
//   range in signed cursor coordinates ("{a} to {b}", collapsed to one
//   coordinate for single-step segments), the cross extent ("{n} tall",
//   or "{n} wide" on vertical hulls), an offset token when the segment's
//   center sits a full tile off the hull midline (upper/lower, or
//   left/right on vertical hulls), then the names of the systems whose
//   anchor tile falls in the segment (the scanner's own dedup and
//   anchor-choice backend - console cell first - so both features name
//   one tile per system), in sweep order then cross order then name.
// - Detached components (passability islands - connectivity is the
//   cursor's own graph, doors pass, walls/airlocks block) are described
//   after the main body, largest first, each opening with a "detached
//   section, {n} rooms" line and then its own segment sweep. One
//   component (the whole fleet outside ruins/bosses) adds no section
//   lines at all.
// - Last line, airlocks, only when any exist (enemy hulls author none):
//   total count, then per-side counts (top/bottom/left/right from the
//   airlock edge's outward direction; an airlock between two cells -
//   boarding-bay style - counts as "interior"), sides in fixed
//   top/bottom/left/right/interior order, zeros silent.
//
// Everything is derived at keypress time from the live geometry index,
// its passability graph, and the scanner's systems backend - no state,
// no cache beyond those sanctioned ones. The pure pieces
// (vwa_ship_desc_components, _mirror_mismatch, _sym_class, _segments,
// _seg_index, _airlock_side, _room_count, _lines) take plain
// geom/adj-shaped structs and fixture data; vwa_dev_selftest
// (vwa_test_shipdesc) exercises them on constructed hulls, and the live
// consistency check is vwa_dev_shipdesc (scrVwaTestShip).

function vwa_ship_desc_init()
{
    vwa_action_register("ship-describe", "vwa--action-ship-describe", "ship",
        vwa_bind(ord("D"), false, false, false), false, function()
        {
            vwa_ship_describe();
        });
}

// PURE: sweep axis. Width >= height sweeps horizontally (u = tx,
// v = ty); otherwise vertically (u = ty, v = tx).
function vwa_ship_desc_horiz(geom)
{
    return geom.w >= geom.h;
}

// PURE: the hull's passability components as arrays of {tx, ty, key},
// largest first (ties: earlier top-left-most seed first). Seeds and
// neighbor pushes iterate deterministically (sorted by row then
// column), so the same graph always yields the same component order -
// the double-build identity the live test asserts.
function vwa_ship_desc_components(geom, adj)
{
    var keys = variable_struct_get_names(geom.tiles);
    var nodes = [];
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        array_push(nodes, { tx: t.tx, ty: t.ty, key: keys[i] });
    }
    array_sort(nodes, function(a, b)
    {
        if (a.ty != b.ty)
        {
            return a.ty - b.ty;
        }
        return a.tx - b.tx;
    });
    var dirs = vwa_ship_dirs();
    var seen = {};
    var comps = [];
    for (var i = 0; i < array_length(nodes); i++)
    {
        if (variable_struct_exists(seen, nodes[i].key))
        {
            continue;
        }
        var comp = [];
        var queue = [nodes[i]];
        variable_struct_set(seen, nodes[i].key, true);
        var qi = 0;
        while (qi < array_length(queue))
        {
            var cur = queue[qi];
            qi += 1;
            array_push(comp, cur);
            var node = variable_struct_get(adj, cur.key);
            for (var d = 0; d < array_length(dirs); d++)
            {
                if (!node.pass[d])
                {
                    continue;
                }
                var nk = string(cur.tx + dirs[d].dx) + ","
                    + string(cur.ty + dirs[d].dy);
                if (variable_struct_exists(seen, nk)
                    || !variable_struct_exists(geom.tiles, nk))
                {
                    continue;
                }
                variable_struct_set(seen, nk, true);
                var nt = variable_struct_get(geom.tiles, nk);
                array_push(queue, { tx: nt.tx, ty: nt.ty, key: nk });
            }
        }
        array_push(comps, comp);
    }
    // array_sort's stability is not guaranteed, so the tie-break is
    // explicit: equal sizes order by their seed (each component's first
    // entry, its top-left-most tile).
    array_sort(comps, function(a, b)
    {
        if (array_length(a) != array_length(b))
        {
            return array_length(b) - array_length(a);
        }
        if (a[0].ty != b[0].ty)
        {
            return a[0].ty - b[0].ty;
        }
        return a[0].tx - b[0].tx;
    });
    return comps;
}

// PURE: tiles that break mirror symmetry about the long axis (horiz:
// mirror rows; vertical: mirror columns).
function vwa_ship_desc_mirror_mismatch(geom, horiz)
{
    var keys = variable_struct_get_names(geom.tiles);
    var bad = 0;
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        var mk = horiz
            ? (string(t.tx) + "," + string(geom.h - 1 - t.ty))
            : (string(geom.w - 1 - t.tx) + "," + string(t.ty));
        if (!variable_struct_exists(geom.tiles, mk))
        {
            bad += 1;
        }
    }
    return bad;
}

// PURE: mismatch count to spoken class. 0 = "sym"; tolerance 2 =
// "rough" (half the fleet sits within it, per the audit); else "none"
// (silent - the composer never announces asymmetry).
function vwa_ship_desc_sym_class(mismatch)
{
    if (mismatch == 0)
    {
        return "sym";
    }
    if (mismatch <= 2)
    {
        return "rough";
    }
    return "none";
}

// PURE: one component's sweep segments, [{u0, u1, vMin, vMax, mixed}].
// Per sweep step the component's outer cross extent; adjacent equal
// extents merge; then fold to at most cap segments by merging the
// adjacent pair with the smallest extent change (earliest on ties).
// mixed marks a fold of unequal profiles - the "up to" wording. A
// component is orthogonally connected, so every step in its range
// holds at least one tile.
function vwa_ship_desc_segments(comp, horiz, cap)
{
    var minU = undefined;
    var maxU = undefined;
    for (var i = 0; i < array_length(comp); i++)
    {
        var u = horiz ? comp[i].tx : comp[i].ty;
        if (minU == undefined || u < minU)
        {
            minU = u;
        }
        if (maxU == undefined || u > maxU)
        {
            maxU = u;
        }
    }
    var segs = [];
    for (var u = minU; u <= maxU; u++)
    {
        var vMin = undefined;
        var vMax = undefined;
        for (var i = 0; i < array_length(comp); i++)
        {
            var cu = horiz ? comp[i].tx : comp[i].ty;
            if (cu != u)
            {
                continue;
            }
            var cv = horiz ? comp[i].ty : comp[i].tx;
            if (vMin == undefined || cv < vMin)
            {
                vMin = cv;
            }
            if (vMax == undefined || cv > vMax)
            {
                vMax = cv;
            }
        }
        if (vMin == undefined)
        {
            // Impossible for a connected component; surface loudly in
            // dev rather than describe a hole as a segment.
            throw ("ship desc: empty sweep step " + string(u));
        }
        var last = (array_length(segs) > 0)
            ? segs[array_length(segs) - 1] : undefined;
        if (last != undefined && last.vMin == vMin && last.vMax == vMax)
        {
            last.u1 = u;
        }
        else
        {
            array_push(segs, { u0: u, u1: u, vMin: vMin, vMax: vMax,
                mixed: false });
        }
    }
    while (array_length(segs) > cap)
    {
        var bestIx = -1;
        var bestDiff = 0;
        for (var i = 0; i + 1 < array_length(segs); i++)
        {
            var diff = abs(segs[i].vMin - segs[i + 1].vMin)
                + abs(segs[i].vMax - segs[i + 1].vMax);
            if (bestIx < 0 || diff < bestDiff)
            {
                bestIx = i;
                bestDiff = diff;
            }
        }
        var a = segs[bestIx];
        var b = segs[bestIx + 1];
        var merged = {
            u0: a.u0, u1: b.u1,
            vMin: min(a.vMin, b.vMin), vMax: max(a.vMax, b.vMax),
            mixed: a.mixed || b.mixed || a.vMin != b.vMin || a.vMax != b.vMax
        };
        var next = [];
        for (var i = 0; i < array_length(segs); i++)
        {
            if (i == bestIx)
            {
                array_push(next, merged);
            }
            else if (i != bestIx + 1)
            {
                array_push(next, segs[i]);
            }
        }
        segs = next;
    }
    return segs;
}

// PURE: which segment a sweep coordinate falls in, or -1 outside them
// all (a system from another component).
function vwa_ship_desc_seg_index(segs, u)
{
    for (var i = 0; i < array_length(segs); i++)
    {
        if (u >= segs[i].u0 && u <= segs[i].u1)
        {
            return i;
        }
    }
    return -1;
}

// PURE: an airlock edge's spoken side. Off-hull beyond the edge: the
// outward direction (dirIx in vwa_ship_dirs order - up/down/left/right
// maps to top/bottom/left/right). A cell on both sides: "interior".
function vwa_ship_desc_airlock_side(geom, tx, ty, dirIx)
{
    var dirs = vwa_ship_dirs();
    var nb = vwa_ship_geom_tile(geom, tx + dirs[dirIx].dx,
        ty + dirs[dirIx].dy);
    if (nb != undefined)
    {
        return "interior";
    }
    if (dirIx == 0)
    {
        return "top";
    }
    if (dirIx == 1)
    {
        return "bottom";
    }
    if (dirIx == 2)
    {
        return "left";
    }
    return "right";
}

// PURE: distinct cells among an array of {key} tile refs (undefined
// comp = the whole hull). Cell identity is struct/instance reference
// equality, the sanctioned identity tier.
function vwa_ship_desc_room_count(geom, comp)
{
    var seenCells = [];
    var keys;
    if (comp == undefined)
    {
        keys = variable_struct_get_names(geom.tiles);
    }
    else
    {
        keys = [];
        for (var i = 0; i < array_length(comp); i++)
        {
            array_push(keys, comp[i].key);
        }
    }
    for (var i = 0; i < array_length(keys); i++)
    {
        var c = variable_struct_get(geom.tiles, keys[i]).cell;
        var found = false;
        for (var j = 0; j < array_length(seenCells); j++)
        {
            if (seenCells[j] == c)
            {
                found = true;
                break;
            }
        }
        if (!found)
        {
            array_push(seenCells, c);
        }
    }
    return array_length(seenCells);
}

// PURE (given plain inputs): the full spoken description as an array of
// LINES (each an array of parts). systems: [{name, tx, ty}]; airlocks:
// [{tx, ty, dirIx}]. See the header for the line shapes.
function vwa_ship_desc_lines(geom, adj, systems, airlocks)
{
    var horiz = vwa_ship_desc_horiz(geom);
    var comps = vwa_ship_desc_components(geom, adj);
    var lines = [];

    var gestalt = [vwa_sheet_t("vwa--ship-desc-size", ["w", "h", "n"],
        [geom.w, geom.h, vwa_ship_desc_room_count(geom, undefined)])];
    var symClass = vwa_ship_desc_sym_class(
        vwa_ship_desc_mirror_mismatch(geom, horiz));
    if (symClass == "sym")
    {
        array_push(gestalt, vwa_t("vwa--ship-desc-sym"));
    }
    else if (symClass == "rough")
    {
        array_push(gestalt, vwa_t("vwa--ship-desc-sym-rough"));
    }
    if (array_length(comps) > 1)
    {
        array_push(gestalt, vwa_sheet_t("vwa--ship-desc-sections",
            ["n"], [array_length(comps)]));
    }
    array_push(lines, gestalt);

    for (var ci = 0; ci < array_length(comps); ci++)
    {
        var comp = comps[ci];
        if (ci > 0)
        {
            array_push(lines, [vwa_sheet_t("vwa--ship-desc-detached",
                ["n"], [vwa_ship_desc_room_count(geom, comp)])]);
        }
        var compKeys = {};
        for (var i = 0; i < array_length(comp); i++)
        {
            variable_struct_set(compKeys, comp[i].key, true);
        }
        var segs = vwa_ship_desc_segments(comp, horiz, 6);
        // The segment's systems: normalized to sweep coordinates first
        // (GML function literals do not capture locals, so the
        // comparator cannot read horiz), then sorted sweep order, cross
        // order, name - fully deterministic.
        var segSys = [];
        for (var i = 0; i < array_length(segs); i++)
        {
            array_push(segSys, []);
        }
        var sorted = [];
        for (var i = 0; i < array_length(systems); i++)
        {
            var s = systems[i];
            array_push(sorted, {
                u: horiz ? s.tx : s.ty,
                v: horiz ? s.ty : s.tx,
                name: s.name,
                key: string(s.tx) + "," + string(s.ty)
            });
        }
        array_sort(sorted, function(a, b)
        {
            if (a.u != b.u)
            {
                return a.u - b.u;
            }
            if (a.v != b.v)
            {
                return a.v - b.v;
            }
            return (a.name < b.name) ? -1 : ((a.name > b.name) ? 1 : 0);
        });
        for (var i = 0; i < array_length(sorted); i++)
        {
            var s = sorted[i];
            if (!variable_struct_exists(compKeys, s.key))
            {
                continue;
            }
            var si = vwa_ship_desc_seg_index(segs, s.u);
            if (si < 0)
            {
                // A system on a component tile always falls in one of
                // that component's segments; anything else is a bug.
                throw ("ship desc: system " + string(s.name)
                    + " outside every segment");
            }
            array_push(segSys[si], s.name);
        }
        var crossSize = horiz ? geom.h : geom.w;
        for (var i = 0; i < array_length(segs); i++)
        {
            var seg = segs[i];
            var a = horiz ? (seg.u0 - geom.cx) : (geom.cy - seg.u0);
            var b = horiz ? (seg.u1 - geom.cx) : (geom.cy - seg.u1);
            var parts = [];
            if (seg.u0 == seg.u1)
            {
                array_push(parts, vwa_ship_coord_str(a));
            }
            else
            {
                array_push(parts, vwa_sheet_t("vwa--ship-desc-range",
                    ["a", "b"],
                    [vwa_ship_coord_str(a), vwa_ship_coord_str(b)]));
            }
            var ext = seg.vMax - seg.vMin + 1;
            var extKey = horiz
                ? (seg.mixed ? "vwa--ship-desc-tall-max" : "vwa--ship-desc-tall")
                : (seg.mixed ? "vwa--ship-desc-wide-max" : "vwa--ship-desc-wide");
            array_push(parts, vwa_sheet_t(extKey, ["n"], [ext]));
            var segMid = (seg.vMin + seg.vMax) / 2;
            var hullMid = (crossSize - 1) / 2;
            if (segMid <= hullMid - 1)
            {
                array_push(parts, vwa_t(horiz
                    ? "vwa--ship-desc-upper" : "vwa--ship-desc-left"));
            }
            else if (segMid >= hullMid + 1)
            {
                array_push(parts, vwa_t(horiz
                    ? "vwa--ship-desc-lower" : "vwa--ship-desc-right"));
            }
            for (var j = 0; j < array_length(segSys[i]); j++)
            {
                array_push(parts, segSys[i][j]);
            }
            array_push(lines, parts);
        }
    }

    if (array_length(airlocks) > 0)
    {
        // String keys, not a struct literal: literal fields named after
        // GML builtins have crashed under the importer before, and
        // left/right/top sit too close to that fire.
        var counts = {};
        var sideNames = ["top", "bottom", "left", "right", "interior"];
        for (var i = 0; i < array_length(sideNames); i++)
        {
            variable_struct_set(counts, sideNames[i], 0);
        }
        for (var i = 0; i < array_length(airlocks); i++)
        {
            var side = vwa_ship_desc_airlock_side(geom,
                airlocks[i].tx, airlocks[i].ty, airlocks[i].dirIx);
            variable_struct_set(counts, side,
                variable_struct_get(counts, side) + 1);
        }
        var total = array_length(airlocks);
        var parts = [];
        if (total == 1)
        {
            array_push(parts, vwa_t("vwa--ship-desc-airlock-one"));
        }
        else
        {
            array_push(parts, vwa_sheet_t("vwa--ship-desc-airlocks",
                ["n"], [total]));
        }
        for (var i = 0; i < array_length(sideNames); i++)
        {
            var n = variable_struct_get(counts, sideNames[i]);
            if (n > 0)
            {
                array_push(parts, vwa_sheet_t(
                    "vwa--ship-desc-n-" + sideNames[i], ["n"], [n]));
            }
        }
        array_push(lines, parts);
    }
    return lines;
}

// Live gather: the scanner's systems backend (one entry per system, its
// anchor tile - console cell first) mapped to plain {name, tx, ty}. A
// fresh entry failing its own resolve is a backend bug (the scan
// gather's precedent): logged, skipped.
function vwa_ship_desc_systems(alliedSide, geom)
{
    var out = [];
    var entries = vwa_ship_scan_systems_scan(alliedSide, geom);
    for (var i = 0; i < array_length(entries); i++)
    {
        var res = vwa_ship_scan_systems_resolve(alliedSide, geom, entries[i]);
        if (res == undefined)
        {
            vwa_log("ERROR: ship desc: fresh system failed its own resolve: "
                + string(entries[i].item));
            continue;
        }
        array_push(out, { name: entries[i].item, tx: res.tx, ty: res.ty });
    }
    return out;
}

// Live gather: every airlock edge of the hull as {tx, ty, dirIx},
// resolved through the cursor's own edge resolver. Boundary edges are
// checked from their one on-hull tile; interior cross-cell edges only
// from the up/left tile (down/right directions), so each edge counts
// once. Same-cell edges hold no side instance and are skipped.
function vwa_ship_desc_airlocks(geom)
{
    var out = [];
    var dirs = vwa_ship_dirs();
    var keys = variable_struct_get_names(geom.tiles);
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        for (var d = 0; d < array_length(dirs); d++)
        {
            var nb = vwa_ship_geom_tile(geom, t.tx + dirs[d].dx,
                t.ty + dirs[d].dy);
            if (nb == undefined)
            {
                // Boundary: resolve; airlock means space beyond.
            }
            else if (nb.cell == t.cell || (d != 1 && d != 3))
            {
                continue;
            }
            var edge = vwa_ship_edge_resolve(t, dirs[d].dx, dirs[d].dy);
            if (edge != undefined && edge.kind == "airlock")
            {
                array_push(out, { tx: t.tx, ty: t.ty, dirIx: d });
            }
        }
    }
    return out;
}

// D: describe the focused hull. Fresh derivation every press; speaks
// the lines interrupting (direct user-caused feedback).
function vwa_ship_describe()
{
    var alliedSide = vwa_ship_focus();
    var geom = vwa_ship_geom(alliedSide);
    var adj = vwa_ship_geom_adj(alliedSide);
    vwa_speak(vwa_ship_desc_lines(geom, adj,
        vwa_ship_desc_systems(alliedSide, geom),
        vwa_ship_desc_airlocks(geom)), true);
}
