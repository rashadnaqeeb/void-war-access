// scrVwaShipLayer - Void War Access in-run ship layer, piece 1: the
// substrate everything spatial sits on (docs/ship-layer-plan.md is the
// build-to document; this header is the authoritative spec of what is
// built). The ship layer is a MODE, not a screen: it never enters the
// screen stack (screens are control graphs; this is spatial). Its input
// category "ship" goes live through the mode-provider hook in scrVwaInput,
// which admits mode categories only while the screen stack is empty - any
// stacked screen (menu, encounter popup screen, dev synthetic screen)
// suspends the mode; it resumes when the stack clears. No per-frame tick:
// everything here is resolved at key-press or speak time.
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
// plus one container per hull - cursor tile, geometry index, and the hull
// instance they belong to. Positions are HULL-RELATIVE tile coordinates
// (36px grid, origin the hull's top-left slot), never cell instance ids;
// the cell and slot resolve from coordinates at speak time. A container
// self-resets when its hull instance changes: the enemy hull is fresh
// instances every encounter, the player hull only on a new run (it is
// persistent across jumps). The geometry index is the ONE sanctioned
// cache (topology is immutable within an encounter): tile -> cell/slot,
// built by enumerating the hull's oCell instances once (each tile of a
// cell is one crew slot; slot world coords slot1x..slot4y), invalidated
// on room change (a jump is a room_goto and world coords shift; relative
// coords are what survive). Everything stateful is re-queried live.
//
// Focus: the ship-focus-toggle action (Tab; the game's own Tab, the map
// toggle, stays behind the default-deny gate - the map gets screen
// support later and the jump button remains the game's path to it).
// Toggling announces the focused ship - its hullName, the exact string
// the game's own enemy box draws - and the cursor position on that ship,
// interrupting (genuine focus movement). Tab toward a non-engaged enemy
// (!global.drawEnemyBox) speaks a localized "no enemy ship" and stays
// put; enemy focus held when the enemy disengages falls back to the
// player ship (logged) at the next resolve. The position announcement is
// the piece-1 stub (1-based row/column within the hull's bounding box);
// the cursor pieces replace it with real sections.
//
// Pure and fixture-tested in vwa_dev_selftest (vwa_test_shiplayer):
// vwa_ship_geom_build (records -> index: origin normalization, bounds,
// dupe counting, default tile = top-left-most slot, min row then min
// column) and vwa_ship_focus_next (the Tab decision). The mode-provider
// suspension rule is asserted against vwa_live_categories directly.

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
    vwa_log("ship: layer initialized");
}

function vwa_ship_container_new()
{
    return { cursor: undefined, geom: undefined, hullInst: undefined };
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

// Speak the focused ship and the cursor position on it. Interrupts:
// genuine focus movement. hullName is the exact string the game's own
// enemy box draws for the enemy hull; player hulls carry it identically.
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
    var cur = vwa_ship_cursor(alliedSide);
    var pos = string_replace(vwa_t("vwa--ship-pos"), "{r}", string(cur.ty + 1));
    pos = string_replace(pos, "{c}", string(cur.tx + 1));
    vwa_speak([nameLine, pos], true);
}
