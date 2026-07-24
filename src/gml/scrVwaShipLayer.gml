// scrVwaShipLayer - Void War Access in-run ship layer, pieces 1-2: the
// substrate everything spatial sits on, plus the tile cursor
// (docs/ship-layer-plan.md is the build-to document; this header is the
// authoritative spec of what is built). The ship layer is a MODE, not a
// screen: it never enters the screen stack (screens are control graphs;
// this is spatial). Its input category "ship" goes live through the
// mode-provider hook in scrVwaInput, which admits mode categories only
// while the screen stack is empty - any stacked screen (menu, encounter
// popup screen, dev synthetic screen) suspends the mode; it resumes when
// the stack clears. No per-frame tick: everything here is resolved at
// key-press or speak time.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// Mode predicate (vwa_ship_mode_active): in a run (global.gameStarted, not
// global.gameIsLoading), no menu (global.menuToggle == 0), the run's
// initial popup has been dealt with (global.initialPopupSpawned), no
// oPopup/oPopupGroup alive (the game's own scrAllPopupsClosed set), and
// not arriving_from_warp() (the game's warp-settling window, during which
// its HUD also suppresses interaction).
//
// State model: global.vwaShipLayer holds focusAllied (1 player, 0 enemy)
// plus one container per hull - cursor tile, geometry index, section
// quarantine, and the hull instance they belong to. Positions are
// HULL-RELATIVE tile coordinates (36px grid, origin the hull's top-left
// slot), never cell instance ids; the cell and slot resolve from
// coordinates at speak time. A container self-resets when its hull
// instance changes: the enemy hull is fresh instances every encounter,
// the player hull only on a new run (it is persistent across jumps). The
// geometry index is the ONE sanctioned cache (topology is immutable
// within an encounter): tile -> cell/slot, built by enumerating the
// hull's oCell instances once (each tile of a cell is one crew slot;
// slot world coords slot1x..slot4y), invalidated on room change (a jump
// is a room_goto and world coords shift; relative coords are what
// survive). Everything stateful is re-queried live.
//
// Focus: the ship-focus-toggle action (Tab; the game's own Tab, the map
// toggle, stays behind the default-deny gate - the map gets screen
// support later and the jump button remains the game's path to it).
// Toggling announces the focused ship - its hullName, the exact string
// the game's own enemy box draws - then a full section read of the
// cursor tile, interrupting (genuine focus movement). Tab toward a
// non-engaged enemy (!global.drawEnemyBox) speaks a localized "no enemy
// ship" and stays put; enemy focus held when the enemy disengages falls
// back to the player ship (logged) at the next resolve.
//
// The cursor (piece 2): arrows move one tile on the focused hull, with
// the edge rules evaluated at move time (vwa_ship_move_plan, PURE):
// - target tile inside the same cell: free move, no edge resolution;
// - across a cell edge holding an oDoor: passes whatever the door state
//   (0 open silent, 1 closed and 2 battered each speak a short localized
//   token before the tile - the spoken interim until the earcon layer
//   exists, revisited at piece 7);
// - an oWall, an oAirlock, or off the hull entirely: blocked, cursor
//   stays, a localized "wall" or "airlock" token speaks (airlock only
//   when an airlock edge instance is actually there - space beyond).
// The edge is resolved from the from-cell's sideData (the game's own
// per-edge cache): the entry whose sideID's bounding box contains the
// midpoint between the two slot centers (midpoints sit 18px from segment
// ends, so segment bboxes are unambiguous; bbox, not precise collision,
// because an open door's mask has a hole in the middle). A cross-cell
// move with no resolvable edge instance is blocked as a wall and logged
// (the game generates a side on every touching edge; missing means the
// index or the hull is wrong). Kinds via object ancestry: oDoor, oAirlock,
// oWall are separate direct children of oCellSide (vwa_ship_side_kind).
//
// Tile speech is composed by ordered stateless SECTIONS
// (global.vwaShipSections), the screen framework's pure-composer shape:
// each is { name, read } with read(hull, cell, slot, ctx) -> array of
// parts, invoked directly (never script_execute_ext). ctx carries what
// the move computed once: cellChanged (did this move cross into a
// different cell), door (the edge crossed, when it was a door), and the
// landed tile tx/ty. Sections declare granularity by behavior:
// cell-granularity sections return [] when ctx.cellChanged is false;
// slot-granularity sections speak every move. All content is re-queried
// live inside read. A section that throws is QUARANTINED: logged once,
// skipped for the rest of the container's life (the quarantine set lives
// in the hull container, so a new encounter/run retries), and the
// composer keeps running the remaining sections - a broken section must
// not silence the cursor (the sanctioned swallow-and-log, mirroring the
// screen-callback quarantine). Piece-2 sections, in order: identity
// (cell: the room's shape word from the oCell subclass), system (cell:
// the overlapping oSysGroup's name, with damaged n-of-m or destroyed
// state from currHP/maxHP; empty room contributes nothing), position
// (slot: 1-based row/column - the every-move stub that keeps a
// within-room move audible; piece 3's slot sections and the where-am-I
// key revisit it). Visibility gating arrives with piece 3's interior
// sections.
//
// Pure and fixture-tested in vwa_dev_selftest (vwa_test_shiplayer):
// vwa_ship_geom_build (records -> index: origin normalization, bounds,
// dupe counting, default tile = top-left-most slot, min row then min
// column), vwa_ship_focus_next (the Tab decision), vwa_ship_move_plan
// (the edge rules), vwa_ship_side_kind, and vwa_ship_compose_run
// (granularity dampening, quarantine-on-throw). The mode-provider
// suspension rule is asserted against vwa_live_categories directly. The
// live analog is vwa_dev_shipwalk (scrVwaTest): a full arrow-driven
// sweep of the focused hull against fresh resolves and the game's own
// connectivity lists.

function vwa_ship_layer_init()
{
    global.vwaShipLayer = {
        focusAllied: 1,
        player: vwa_ship_container_new(),
        enemy: vwa_ship_container_new()
    };
    vwa_mode_register({
        key: "ship",
        category: "ship",
        isActive: function()
        {
            return vwa_ship_mode_active();
        }
    });
    vwa_action_register("ship-focus-toggle", "vwa--action-ship-focus", "ship",
        vwa_bind(vk_tab, false, false, false), false, function()
        {
            vwa_ship_focus_toggle();
        });
    vwa_action_register("ship-cursor-up", "vwa--action-ship-up", "ship",
        vwa_bind(vk_up, false, false, false), true, function()
        {
            vwa_ship_cursor_move(0, -1);
        });
    vwa_action_register("ship-cursor-down", "vwa--action-ship-down", "ship",
        vwa_bind(vk_down, false, false, false), true, function()
        {
            vwa_ship_cursor_move(0, 1);
        });
    vwa_action_register("ship-cursor-left", "vwa--action-ship-left", "ship",
        vwa_bind(vk_left, false, false, false), true, function()
        {
            vwa_ship_cursor_move(-1, 0);
        });
    vwa_action_register("ship-cursor-right", "vwa--action-ship-right", "ship",
        vwa_bind(vk_right, false, false, false), true, function()
        {
            vwa_ship_cursor_move(1, 0);
        });
    vwa_ship_sections_init();
    vwa_log("ship: layer initialized");
}

function vwa_ship_container_new()
{
    return { cursor: undefined, geom: undefined, hullInst: undefined, quar: {} };
}

// The ship layer's liveness gate (see header). Stateless: the game owns
// every flag read here, so suspend/resume needs no tracking.
function vwa_ship_mode_active()
{
    return global.gameStarted && !global.gameIsLoading
        && global.menuToggle == 0
        && global.initialPopupSpawned
        && !instance_exists(oPopup)
        && !instance_exists(oPopupGroup)
        && !arriving_from_warp();
}

// One hull's ship-layer state, self-resetting when the hull instance
// changed (new encounter for the enemy, new run for the player). Throws
// when no such hull is alive - callers gate on mode/drawEnemyBox first,
// so a missing hull is a mod bug and the input watchdog reports it.
function vwa_ship_container(alliedSide)
{
    var hull = get_hull(alliedSide);
    if (hull == 0 || !instance_exists(hull))
    {
        throw ("ship: no hull for allied " + string(alliedSide));
    }
    var st = global.vwaShipLayer;
    var c = alliedSide ? st.player : st.enemy;
    if (c.hullInst != hull)
    {
        if (c.hullInst != undefined)
        {
            vwa_log("ship: " + (alliedSide ? "player" : "enemy")
                + " container reset (hull instance changed)");
        }
        c.cursor = undefined;
        c.geom = undefined;
        c.quar = {};
        c.hullInst = hull;
    }
    return c;
}

// The hull's geometry index, rebuilt when absent or the room changed.
function vwa_ship_geom(alliedSide)
{
    var c = vwa_ship_container(alliedSide);
    if (c.geom != undefined && c.geom.builtRoom == room)
    {
        return c.geom;
    }
    var records = [];
    with (oCell)
    {
        if (allied == alliedSide)
        {
            var n = cell_get_slot_count(id);
            for (var s = 1; s <= n; s++)
            {
                array_push(records, {
                    sx: cell_get_slot_x(id, s),
                    sy: cell_get_slot_y(id, s),
                    cell: id,
                    slot: s
                });
            }
        }
    }
    if (array_length(records) == 0)
    {
        throw ("ship: no cells for allied " + string(alliedSide));
    }
    var geom = vwa_ship_geom_build(records);
    if (geom.dupes > 0)
    {
        vwa_log("ERROR: ship: geometry index for allied " + string(alliedSide)
            + " had " + string(geom.dupes) + " duplicate tiles (first kept)");
    }
    geom.builtRoom = room;
    c.geom = geom;
    vwa_log("ship: geometry index built for allied " + string(alliedSide)
        + ": " + string(geom.count) + " tiles, " + string(geom.w) + "x" + string(geom.h));
    return geom;
}

// PURE: slot records ({sx, sy, cell, slot} in world pixels) -> geometry
// index. Tiles quantize on the 36px grid relative to the hull's own
// minimum slot coordinates, so the index is identical wherever the hull
// sits in the room. Duplicate tiles keep the first record and count in
// .dupes (the impure caller logs). defaultTile is the top-left-most slot
// (minimum row, then minimum column) - the cursor's first landing.
function vwa_ship_geom_build(records)
{
    var minX = records[0].sx;
    var minY = records[0].sy;
    for (var i = 1; i < array_length(records); i++)
    {
        minX = min(minX, records[i].sx);
        minY = min(minY, records[i].sy);
    }
    var tiles = {};
    var count = 0;
    var dupes = 0;
    var maxTx = 0;
    var maxTy = 0;
    var defTx = -1;
    var defTy = -1;
    for (var i = 0; i < array_length(records); i++)
    {
        var r = records[i];
        var tx = floor((r.sx - minX) / 36);
        var ty = floor((r.sy - minY) / 36);
        var k = string(tx) + "," + string(ty);
        if (variable_struct_exists(tiles, k))
        {
            dupes += 1;
            continue;
        }
        variable_struct_set(tiles, k, { tx: tx, ty: ty, cell: r.cell, slot: r.slot });
        count += 1;
        maxTx = max(maxTx, tx);
        maxTy = max(maxTy, ty);
        if (defTy < 0 || ty < defTy || (ty == defTy && tx < defTx))
        {
            defTx = tx;
            defTy = ty;
        }
    }
    // builtRoom (set by the impure caller): the room the index was built
    // in - never name a struct field after a GML builtin ("room" crashed
    // the literal at runtime under the UTMT importer).
    return {
        tiles: tiles, count: count, dupes: dupes,
        w: maxTx + 1, h: maxTy + 1,
        defaultTile: { tx: defTx, ty: defTy },
        builtRoom: undefined
    };
}

// Tile lookup: the {tx, ty, cell, slot} entry, or undefined off-hull.
function vwa_ship_geom_tile(geom, tx, ty)
{
    return variable_struct_get(geom.tiles, string(tx) + "," + string(ty));
}

// The focused hull's cursor tile, initialized to the geometry's default
// tile on first use; a stored tile that no longer resolves (geometry
// rebuilt differently) resets there too, logged - never speak from a
// tile that is not on the ship.
function vwa_ship_cursor(alliedSide)
{
    var c = vwa_ship_container(alliedSide);
    var geom = vwa_ship_geom(alliedSide);
    if (c.cursor != undefined
        && vwa_ship_geom_tile(geom, c.cursor.tx, c.cursor.ty) == undefined)
    {
        vwa_log("ship: cursor tile " + string(c.cursor.tx) + "," + string(c.cursor.ty)
            + " no longer resolves; reset to default");
        c.cursor = undefined;
    }
    if (c.cursor == undefined)
    {
        c.cursor = { tx: geom.defaultTile.tx, ty: geom.defaultTile.ty };
    }
    return c.cursor;
}

// PURE (given the object index): the edge classification. oDoor,
// oAirlock, oWall are separate direct children of oCellSide; equality or
// ancestry covers game subclasses (oWall_dungeon). Unknown: undefined.
function vwa_ship_side_kind(objIx)
{
    if (objIx == oDoor || object_is_ancestor(objIx, oDoor))
    {
        return "door";
    }
    if (objIx == oAirlock || object_is_ancestor(objIx, oAirlock))
    {
        return "airlock";
    }
    if (objIx == oWall || object_is_ancestor(objIx, oWall))
    {
        return "wall";
    }
    return undefined;
}

// The edge instance crossed leaving fromEntry's slot toward (dx, dy),
// resolved against the from-cell's sideData (see header for the bbox
// midpoint rule), or undefined when no side instance sits there. An
// unclassifiable side instance reads as a wall, logged.
function vwa_ship_edge_resolve(fromEntry, dx, dy)
{
    var mx = cell_get_slot_x(fromEntry.cell, fromEntry.slot) + (dx * 18);
    var my = cell_get_slot_y(fromEntry.cell, fromEntry.slot) + (dy * 18);
    var sd = fromEntry.cell.sideData;
    for (var i = 0; i < array_length(sd); i++)
    {
        var inst = sd[i].sideID;
        if (mx < inst.bbox_left || mx > inst.bbox_right
            || my < inst.bbox_top || my > inst.bbox_bottom)
        {
            continue;
        }
        var kind = vwa_ship_side_kind(inst.object_index);
        if (kind == undefined)
        {
            vwa_log("ERROR: ship: unclassifiable edge instance "
                + object_get_name(inst.object_index) + " at " + string(mx)
                + "," + string(my) + "; treating as a wall");
            kind = "wall";
        }
        return {
            kind: kind,
            doorState: (kind == "door") ? inst.state : undefined,
            inst: inst
        };
    }
    return undefined;
}

// PURE: the movement decision. fromEntry/toEntry are geometry-index tile
// entries (toEntry undefined = off the hull); edge is vwa_ship_edge_-
// resolve's result for the crossing (undefined for same-cell moves, where
// it is not consulted). missingEdge flags a crossing with no resolvable
// side instance - the impure caller logs it; the move blocks as a wall.
function vwa_ship_move_plan(fromEntry, toEntry, edge)
{
    var p = { moved: false, cellChanged: false, door: undefined,
              blocked: undefined, missingEdge: false };
    if (toEntry == undefined)
    {
        p.blocked = (edge != undefined && edge.kind == "airlock")
            ? "airlock" : "wall";
        p.missingEdge = (edge == undefined);
        return p;
    }
    if (fromEntry.cell == toEntry.cell)
    {
        p.moved = true;
        return p;
    }
    if (edge == undefined)
    {
        p.blocked = "wall";
        p.missingEdge = true;
        return p;
    }
    if (edge.kind == "door")
    {
        p.moved = true;
        p.cellChanged = true;
        p.door = edge;
        return p;
    }
    p.blocked = edge.kind;
    return p;
}

// The section registry (see header). Sections are ordered; each read is
// stateless and re-queries the game live.
function vwa_ship_sections_init()
{
    global.vwaShipSections = [
        { name: "identity", read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            var ix = cell.object_index;
            if (ix == oCellSingle)
            {
                return [vwa_t("vwa--ship-room-small")];
            }
            if (ix == oCellWide)
            {
                return [vwa_t("vwa--ship-room-wide")];
            }
            if (ix == oCellTall)
            {
                return [vwa_t("vwa--ship-room-tall")];
            }
            if (ix == oCellLarge)
            {
                return [vwa_t("vwa--ship-room-large")];
            }
            throw ("unknown cell shape " + object_get_name(ix));
        } },
        { name: "system", read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            if (cell.system == 0)
            {
                return [];
            }
            var sys = cell.system;
            var parts = [vwa_sheet_flatten(sys.name)];
            if (sys.currHP <= 0)
            {
                array_push(parts, vwa_t("vwa--ship-sys-destroyed"));
            }
            else if (sys.currHP < sys.maxHP)
            {
                array_push(parts, vwa_sheet_t("vwa--ship-sys-damaged",
                    ["n", "m"], [sys.currHP, sys.maxHP]));
            }
            return parts;
        } },
        { name: "position", read: function(hull, cell, slot, ctx)
        {
            return [vwa_sheet_t("vwa--ship-pos", ["r", "c"],
                [ctx.ty + 1, ctx.tx + 1])];
        } }
    ];
}

// The composer runner: every non-quarantined section in order, each
// section's parts appended flat. quar is the caller's quarantine set
// (section name -> true); a throwing section joins it, logged once, and
// the remaining sections still run (see header).
function vwa_ship_compose_run(sections, quar, hull, cell, slot, ctx)
{
    var parts = [];
    for (var i = 0; i < array_length(sections); i++)
    {
        var sec = sections[i];
        if (variable_struct_exists(quar, sec.name))
        {
            continue;
        }
        var r = undefined;
        try
        {
            r = sec.read(hull, cell, slot, ctx);
        }
        catch (err)
        {
            variable_struct_set(quar, sec.name, true);
            vwa_log("ERROR: ship: section " + sec.name
                + " quarantined: " + string(err));
            continue;
        }
        for (var j = 0; j < array_length(r); j++)
        {
            array_push(parts, r[j]);
        }
    }
    return parts;
}

// The full spoken parts for landing on a tile: the door-crossing token
// when a non-open door was crossed, then the sections.
function vwa_ship_move_parts(alliedSide, entry, ctx)
{
    var parts = [];
    if (ctx.door != undefined && ctx.door.doorState == 1)
    {
        array_push(parts, vwa_t("vwa--ship-door-closed"));
    }
    if (ctx.door != undefined && ctx.door.doorState == 2)
    {
        array_push(parts, vwa_t("vwa--ship-door-battered"));
    }
    var hull = get_hull(alliedSide);
    if (hull == 0 || !instance_exists(hull))
    {
        throw ("ship: no hull for move parts, allied " + string(alliedSide));
    }
    var c = vwa_ship_container(alliedSide);
    var body = vwa_ship_compose_run(global.vwaShipSections, c.quar,
        hull, entry.cell, entry.slot, ctx);
    for (var i = 0; i < array_length(body); i++)
    {
        array_push(parts, body[i]);
    }
    return parts;
}

// One arrow press: evaluate the edge rules, move or refuse, speak. Both
// outcomes interrupt - direct user-caused focus movement or its refusal.
function vwa_ship_cursor_move(dx, dy)
{
    var alliedSide = vwa_ship_focus();
    var geom = vwa_ship_geom(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var fromE = vwa_ship_geom_tile(geom, cur.tx, cur.ty);
    var toE = vwa_ship_geom_tile(geom, cur.tx + dx, cur.ty + dy);
    var edge = undefined;
    if (toE == undefined || fromE.cell != toE.cell)
    {
        edge = vwa_ship_edge_resolve(fromE, dx, dy);
    }
    var plan = vwa_ship_move_plan(fromE, toE, edge);
    if (plan.missingEdge && toE != undefined)
    {
        vwa_log("ERROR: ship: no edge instance between tiles "
            + string(cur.tx) + "," + string(cur.ty) + " and "
            + string(cur.tx + dx) + "," + string(cur.ty + dy)
            + " on allied " + string(alliedSide));
    }
    if (!plan.moved)
    {
        vwa_speak([vwa_t((plan.blocked == "airlock")
            ? "vwa--ship-airlock" : "vwa--ship-wall")], true);
        return;
    }
    cur.tx += dx;
    cur.ty += dy;
    var ctx = { cellChanged: plan.cellChanged, door: plan.door,
                tx: cur.tx, ty: cur.ty };
    vwa_speak(vwa_ship_move_parts(alliedSide, toE, ctx), true);
}

// PURE: the Tab decision. Toward a non-engaged enemy: blocked, stay put.
function vwa_ship_focus_next(currAllied, enemyEngaged)
{
    if (currAllied == 1 && !enemyEngaged)
    {
        return { allied: 1, blocked: true };
    }
    return { allied: (currAllied == 1) ? 0 : 1, blocked: false };
}

// Focus resolution: enemy focus with no engaged enemy falls back to the
// player ship (logged) - the enemy's instances may already be gone.
function vwa_ship_focus()
{
    var st = global.vwaShipLayer;
    if (st.focusAllied == 0 && !global.drawEnemyBox)
    {
        vwa_log("ship: enemy disengaged; focus falls back to player ship");
        st.focusAllied = 1;
    }
    return st.focusAllied;
}

function vwa_ship_focus_toggle()
{
    var st = global.vwaShipLayer;
    var next = vwa_ship_focus_next(vwa_ship_focus(), global.drawEnemyBox);
    if (next.blocked)
    {
        vwa_speak([vwa_t("vwa--ship-no-enemy")], true);
        return;
    }
    st.focusAllied = next.allied;
    vwa_ship_announce_focus();
}

// Speak the focused ship, then a full section read of the cursor tile
// (cellChanged forced true: focus landed here, nothing is dampened).
// Interrupts: genuine focus movement. hullName is the exact string the
// game's own enemy box draws for the enemy hull; player hulls carry it
// identically.
function vwa_ship_announce_focus()
{
    var alliedSide = vwa_ship_focus();
    var hull = get_hull(alliedSide);
    if (hull == 0 || !instance_exists(hull))
    {
        throw ("ship: no hull to announce for allied " + string(alliedSide));
    }
    var nameLine = string_replace(
        vwa_t(alliedSide ? "vwa--ship-your" : "vwa--ship-enemy"),
        "{name}", string(hull.hullName));
    var geom = vwa_ship_geom(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var entry = vwa_ship_geom_tile(geom, cur.tx, cur.ty);
    var parts = [nameLine];
    var body = vwa_ship_move_parts(alliedSide, entry,
        { cellChanged: true, door: undefined, tx: cur.tx, ty: cur.ty });
    for (var i = 0; i < array_length(body); i++)
    {
        array_push(parts, body[i]);
    }
    vwa_speak(parts, true);
}
