// scrVwaShipLayer - Void War Access in-run ship layer, pieces 1-3: the
// substrate everything spatial sits on, the tile cursor, and the full
// tile speech model - sections, visibility gating, on-demand reads
// (docs/ship-layer-plan.md is the build-to document; this header is the
// authoritative spec of what is built; piece 4, the scanner, lives in
// scrVwaShipScan on this substrate). The ship layer is a MODE, not a
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
// quarantine, the scanner state (owned by scrVwaShipScan), and the hull
// instance they belong to. Positions are
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
// survive). The tile-passability graph (vwa_ship_geom_adj) is part of
// the same cache, built lazily onto the index from the same edge
// resolution the cursor uses: same-cell neighbors pass, cross-cell
// neighbors pass only through a door (whatever its state - every door
// state passes the cursor, so passability is topology, not state),
// walls/airlocks/off-hull block. The scanner's path distances and
// spoken path legs ride on it. Everything stateful is re-queried live.
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
// - across a cell edge holding an oDoor: passes whatever the door state,
//   and every state (0 open, 1 closed, 2 destroyed) plays its own
//   door-cross earcon (vwa_earcon, scrVwaEarcon - the door channel is
//   audio-only, the piece-5 decision). The old spoken state token
//   survives ONLY as the never-strand fallback, prepended to the tile
//   speech when the earcon reports failure;
// - an oWall, an oAirlock, or off the hull entirely: blocked, cursor
//   stays, the block earcon plays - wall-block for walls and bare
//   off-hull edges, or the airlock-block pair carrying the airlock's
//   live state (0 open, 1 closed; airlocks have no HP and cannot be
//   destroyed - the game's door-attack path scans oDoor only). The
//   spoken wall/airlock tokens are the same never-strand fallback on
//   earcon failure. A blocked bump with a working earcon no longer
//   interrupts ongoing speech (the cursor did not move, so it is not
//   focus movement); the fallback token, when it must speak, interrupts
//   as refusal feedback.
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
// each is { name, slotLevel, interior, read } with read(hull, cell,
// slot, ctx) -> array of parts, invoked directly (never
// script_execute_ext). ctx carries what the move computed once:
// cellChanged (did this move cross into a different cell), the landed
// tile tx/ty with the spoken origin cx/cy, and vision - the landed cell's playerHasVision,
// stamped by vwa_ship_move_parts at compose time (the game's own
// per-room visibility rule: own rooms need own sensors, enemy rooms
// sensor parity, a room holding own crew always visible).
// Granularity stays behavioral: cell sections return [] when
// ctx.cellChanged is false; slot sections speak every move. The declared
// flags carry the two facts behavior cannot: slotLevel tells the fixture
// tests which sections touch live instances (and so are exercised by the
// live shipwalk, not fixtures); interior drives the VISIBILITY GATE IN
// THE COMPOSER - with ctx.vision false every interior section is skipped
// and one localized "unknown" token speaks in the first skipped one's
// place, only when ctx.cellChanged (a dark room announces its darkness
// on entry, not on every step inside; the details key forces a fresh
// full read). Geometry-level sections run regardless, mirroring what
// the game draws without vision.
// All content is re-queried live inside read. A section that throws is
// QUARANTINED: logged once, skipped for the rest of the container's life
// (the quarantine set lives in the hull container, so a new
// encounter/run retries), and the composer keeps running the remaining
// sections - a broken section must not silence the cursor (the
// sanctioned swallow-and-log, mirroring the screen-callback quarantine).
// The order is decision-criticality behind the room-name anchor: speech
// is a linear channel and a fast-arrowing player may only hear the first
// words, so the system name leads as the room's identity (the game has
// no room names; the system IS the name), the alarms follow immediately,
// and detail trails. Empty sections are silent, so alarms cost nothing
// in calm rooms - they only speak where something is wrong, which is
// exactly where they must come early.
// Sections in order (* = interior):
// - system (cell): the overlapping oSysGroup's name plus damaged n-of-m
//   or destroyed from currHP/maxHP; empty room contributes nothing.
//   Geometry-level: the game shows enemy systems and their damage
//   without sensor parity.
// - hostiles* (cell): hostile crew count ("1 hostile" / "n hostiles"),
//   enumerated fresh from oCrew instances (alive and position_meeting
//   the cell; the game's throttled crewInCell lists are never read - a
//   ~10-step lag could speak stale). The most urgent fact a room can
//   carry, so it is the first interior section - which also puts the
//   dark-room "unknown" token right behind the system name.
// - hazards* (cell): fire / warp fire / breach counts, grouped by the
//   hazard instances' currentCellID (one/many wording via
//   vwa_ship_count_parts; zero is silent).
// - air* (cell): "vacuum" on lethalVacuum, else "venting" while
//   cell.vacuum; "poisoned" on isPoisoned; oxygen percent only when
//   below full - a full room is the norm and stays silent.
// - identity (cell): the room's shape word from the oCell subclass.
// - crew-count* (cell): own crew count ("1 crew" / "n crew"), same live
//   enumeration as hostiles.
// - fire-here* / breach-here* (slot): this slot's own oFire (warp fire
//   distinguished) / oBreach instance.
// - crew* (slot): the slot's occupants by channel (occupant1ID..4ID via
//   cell_get_crew_at_slot), hostile first (critical first), each spoken
//   only when alive AND physically in the cell - an occupant entry can
//   be a reservation by still-walking crew, and a name for a crew not
//   yet in the room would be stale speech. Hostile crew speak "{name},
//   hostile"; own crew speak crewName.
// - console (slot): "console" when the cell's system is mannable and
//   sysConsoleSlot is this slot. Geometry-level, but "manned" (from
//   sys.manned, the game's own per-step manning state) is appended only
//   under vision - manning reveals interior.
// - selected* (slot): "selected" when the slot's allied occupant sits in
//   oUICursor.currSelected, the game's selection truth, read live.
// - position (slot): signed x/y from the hull's center, the every-move
//   feedback that a move landed (kept after weighing the slot sections:
//   blocked moves sound their block earcon, so a silent success would
//   be ambiguous). Spoken coordinates are SIGNED X/Y FROM THE HULL'S
//   CENTER: the origin is the bounding-box center tile
//   (floor((w-1)/2), floor((h-1)/2) - for even dimensions the tile just
//   left/above true center), x positive right, y positive UP (up-arrow
//   increases y), negatives spoken with a localized "minus" word
//   (synthesizers disagree on bare hyphens). Internal tile storage stays
//   0-based from the top-left; only vwa_ship_coord_str and the position
//   section convert.
//
// On-demand keys (category "ship", chosen at build; piece 7's key map
// decides around them): K - where am I: position, then system name,
// then shape, through the same section reads and quarantine (the game
// has NO room names, verified - cells carry no name field, so system
// plus shape is all the identity a room has). R - details: a full
// forced section read of the current tile (ctx.cellChanged true),
// visibility-gated like any read. Both interrupt: direct user-caused
// feedback, like the cursor keys.
//
// Pure and fixture-tested in vwa_dev_selftest (vwa_test_shiplayer):
// vwa_ship_geom_build (records -> index: origin normalization, bounds,
// dupe counting, default tile = top-left-most slot, min row then min
// column), vwa_ship_focus_next (the Tab decision), vwa_ship_move_plan
// (the edge rules), vwa_ship_side_kind, vwa_ship_count_parts, and
// vwa_ship_compose_run (granularity dampening, quarantine-on-throw, the
// visibility gate and its token placement, the where-am-I read order).
// The mode-provider suspension rule is asserted against
// vwa_live_categories directly. The live analog is vwa_dev_shipwalk
// (scrVwaTestShip): a full arrow-driven sweep of the focused hull against
// fresh resolves and the game's own connectivity lists, which also
// drives every slot-level section on live instances and cross-checks
// the cached passability graph (vwa_ship_geom_adj) against every real
// move's outcome.

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
            // The scanner's Ctrl+F capture suspends the ship category
            // (letters must type, not fire status keys); the ship-search
            // mode's own category carries the capture keys meanwhile
            // (scrVwaShipScan).
            return vwa_ship_mode_active() && !vwa_ship_scan_search_armed();
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
    vwa_action_register("ship-where", "vwa--action-ship-where", "ship",
        vwa_bind(ord("K"), false, false, false), false, function()
        {
            vwa_ship_where();
        });
    vwa_action_register("ship-details", "vwa--action-ship-details", "ship",
        vwa_bind(ord("R"), false, false, false), false, function()
        {
            vwa_ship_details();
        });
    vwa_ship_sections_init();
    vwa_log("ship: layer initialized");
}

function vwa_ship_container_new()
{
    // scan is owned by scrVwaShipScan (piece 4): the hull's scanner
    // state, lazily created there, reset with the container.
    return { cursor: undefined, geom: undefined, hullInst: undefined,
             quar: {}, scan: undefined };
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
        c.scan = undefined;
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
// cx/cy is the spoken-coordinate origin: the bounding-box center tile
// (see header; it need not be an on-hull tile on concave ships).
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
    // the literal at runtime under the UTMT importer). ox/oy is the world
    // origin the tiles were normalized against, kept so arbitrary world
    // positions (a mid-walk crew, the scanner's quantization) map to
    // tiles: tile = round((worldCoord - origin) / 36). adj is the
    // passability graph, built lazily by vwa_ship_geom_adj (it needs
    // live edge instances, so the pure builder leaves it empty).
    // curDists is the scanner's cursor-BFS memo ({fromKey, dists}), a
    // pure derivation of adj keyed by the cursor tile
    // (vwa_ship_scan_cursor_dists); it resets with the index.
    return {
        tiles: tiles, count: count, dupes: dupes,
        w: maxTx + 1, h: maxTy + 1,
        cx: floor(maxTx / 2), cy: floor(maxTy / 2),
        defaultTile: { tx: defTx, ty: defTy },
        ox: minX, oy: minY,
        builtRoom: undefined,
        adj: undefined,
        curDists: undefined
    };
}

// A signed spoken coordinate: negatives carry the localized minus word.
function vwa_ship_coord_str(v)
{
    if (v < 0)
    {
        return vwa_t("vwa--minus") + " " + string(-v);
    }
    return string(v);
}

// Tile lookup: the {tx, ty, cell, slot} entry, or undefined off-hull.
function vwa_ship_geom_tile(geom, tx, ty)
{
    return variable_struct_get(geom.tiles, string(tx) + "," + string(ty));
}

// The cursor's four moves, in the ONE deterministic order every
// adjacency and path consumer iterates. Vertical entries first: path
// ties resolve toward this order, so a straight-shot phrase keeps the
// vertical-before-horizontal convention. Each entry's key names the
// vwa--ship-scan-* direction token.
function vwa_ship_dirs()
{
    return [
        { key: "up", dx: 0, dy: -1 },
        { key: "down", dx: 0, dy: 1 },
        { key: "left", dx: -1, dy: 0 },
        { key: "right", dx: 1, dy: 0 }
    ];
}

// The hull's tile-passability graph, built lazily onto the geometry
// index and cached with it (see the cache note in the header: door
// PRESENCE is topology and every door state passes the cursor, so
// passability never changes within an encounter; door state is not
// stored). Keyed like the tile index ("tx,ty"): { tx, ty, pass } with
// one boolean per vwa_ship_dirs entry. A cross-cell neighbor with no
// resolvable edge instance blocks as a wall, logged - the cursor's own
// rule.
function vwa_ship_geom_adj(alliedSide)
{
    var geom = vwa_ship_geom(alliedSide);
    if (geom.adj != undefined)
    {
        return geom.adj;
    }
    var dirs = vwa_ship_dirs();
    var adj = {};
    var keys = variable_struct_get_names(geom.tiles);
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        var pass = [false, false, false, false];
        for (var d = 0; d < array_length(dirs); d++)
        {
            var toE = vwa_ship_geom_tile(geom,
                t.tx + dirs[d].dx, t.ty + dirs[d].dy);
            if (toE == undefined)
            {
                continue;
            }
            if (t.cell == toE.cell)
            {
                pass[d] = true;
                continue;
            }
            var edge = vwa_ship_edge_resolve(t, dirs[d].dx, dirs[d].dy);
            if (edge == undefined)
            {
                vwa_log("ERROR: ship: no edge instance between tiles "
                    + string(t.tx) + "," + string(t.ty) + " and "
                    + string(t.tx + dirs[d].dx) + ","
                    + string(t.ty + dirs[d].dy) + " on allied "
                    + string(alliedSide) + " (adjacency build)");
                continue;
            }
            pass[d] = (edge.kind == "door");
        }
        variable_struct_set(adj, keys[i], { tx: t.tx, ty: t.ty, pass: pass });
    }
    geom.adj = adj;
    vwa_log("ship: passability graph built for allied " + string(alliedSide));
    return adj;
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
            doorState: (kind == "door" || kind == "airlock")
                ? inst.state : undefined,
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

// One/many count wording: silent at zero, the bare one-token at one, the
// {n} template above. The one-tokens carry their own numeral where the
// language wants one ("1 crew") and none where it doesn't ("fire").
function vwa_ship_count_parts(n, oneKey, manyKey)
{
    if (n <= 0)
    {
        return [];
    }
    if (n == 1)
    {
        return [vwa_t(oneKey)];
    }
    return [vwa_sheet_t(manyKey, ["n"], [n])];
}

// The slot's occupant on one channel (1 allied, 0 hostile), only when
// alive and physically standing in the cell (see header: an occupant
// entry can be a reservation by still-walking crew). undefined otherwise.
function vwa_ship_slot_occupant(cell, slotNum, alliedChannel)
{
    var crew = cell_get_crew_at_slot(cell, slotNum, alliedChannel);
    if (crew == 0 || crew_is_dead(crew)
        || !position_meeting(crew.x, crew.y, cell))
    {
        return undefined;
    }
    return crew;
}

// Live crew count for one channel: alive and physically in the cell
// (see the hostiles section note - the throttled crewInCell lists are
// never read).
function vwa_ship_cell_crew_count(cell, wantAllied)
{
    var n = 0;
    with (oCrew)
    {
        if (!crew_is_dead(id) && position_meeting(x, y, cell)
            && allied == wantAllied)
        {
            n += 1;
        }
    }
    return n;
}

// The section registry (see header, including the criticality ordering).
// Sections are ordered; each read is stateless and re-queries the game
// live.
function vwa_ship_sections_init()
{
    global.vwaShipSections = [
        { name: "system", slotLevel: false, interior: false,
          read: function(hull, cell, slot, ctx)
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
        { name: "hostiles", slotLevel: false, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            return vwa_ship_count_parts(vwa_ship_cell_crew_count(cell, false),
                "vwa--ship-hostile-one", "vwa--ship-hostile-many");
        } },
        { name: "hazards", slotLevel: false, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            var fires = 0;
            var warps = 0;
            var breaches = 0;
            with (oFire)
            {
                if (currentCellID == cell)
                {
                    if (object_index == oWarpFire)
                    {
                        warps += 1;
                    }
                    else
                    {
                        fires += 1;
                    }
                }
            }
            with (oBreach)
            {
                if (currentCellID == cell)
                {
                    breaches += 1;
                }
            }
            var groups = [
                vwa_ship_count_parts(fires,
                    "vwa--ship-fire-one", "vwa--ship-fire-many"),
                vwa_ship_count_parts(warps,
                    "vwa--ship-warpfire-one", "vwa--ship-warpfire-many"),
                vwa_ship_count_parts(breaches,
                    "vwa--ship-breach-one", "vwa--ship-breach-many")
            ];
            var parts = [];
            for (var i = 0; i < array_length(groups); i++)
            {
                for (var j = 0; j < array_length(groups[i]); j++)
                {
                    array_push(parts, groups[i][j]);
                }
            }
            return parts;
        } },
        { name: "air", slotLevel: false, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            var parts = [];
            if (cell.lethalVacuum)
            {
                array_push(parts, vwa_t("vwa--ship-vacuum"));
            }
            else if (cell.vacuum)
            {
                array_push(parts, vwa_t("vwa--ship-venting"));
            }
            if (cell.isPoisoned)
            {
                array_push(parts, vwa_t("vwa--ship-poisoned"));
            }
            if (!cell.lethalVacuum)
            {
                var pct = round(cell.currOxygen * 100 / cell.maxOxygen);
                if (pct < 100)
                {
                    array_push(parts, vwa_sheet_t("vwa--ship-oxygen",
                        ["n"], [pct]));
                }
            }
            return parts;
        } },
        { name: "identity", slotLevel: false, interior: false,
          read: function(hull, cell, slot, ctx)
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
        { name: "crew-count", slotLevel: false, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            if (!ctx.cellChanged)
            {
                return [];
            }
            return vwa_ship_count_parts(vwa_ship_cell_crew_count(cell, true),
                "vwa--ship-crew-one", "vwa--ship-crew-many");
        } },
        { name: "fire-here", slotLevel: true, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            var hereKey = undefined;
            with (oFire)
            {
                if (currentCellID == cell && currentCellSlot == slot)
                {
                    hereKey = (object_index == oWarpFire)
                        ? "vwa--ship-warpfire-here" : "vwa--ship-fire-here";
                    break;
                }
            }
            return (hereKey == undefined) ? [] : [vwa_t(hereKey)];
        } },
        { name: "breach-here", slotLevel: true, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            var found = false;
            with (oBreach)
            {
                if (currentCellID == cell && currentCellSlot == slot)
                {
                    found = true;
                    break;
                }
            }
            return found ? [vwa_t("vwa--ship-breach-here")] : [];
        } },
        { name: "crew", slotLevel: true, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            var parts = [];
            var foe = vwa_ship_slot_occupant(cell, slot, 0);
            if (foe != undefined)
            {
                array_push(parts, vwa_sheet_t("vwa--ship-crew-hostile",
                    ["name"], [string(foe.crewName)]));
            }
            var ally = vwa_ship_slot_occupant(cell, slot, 1);
            if (ally != undefined)
            {
                array_push(parts, string(ally.crewName));
            }
            return parts;
        } },
        { name: "console", slotLevel: true, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            if (cell.system == 0 || !cell.system.mannable
                || cell.sysConsoleSlot != slot)
            {
                return [];
            }
            var parts = [vwa_t("vwa--ship-console")];
            if (ctx.vision && cell.system.manned)
            {
                array_push(parts, vwa_t("vwa--ship-manned"));
            }
            return parts;
        } },
        { name: "selected", slotLevel: true, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            var ally = vwa_ship_slot_occupant(cell, slot, 1);
            if (ally == undefined
                || ds_list_find_index(oUICursor.currSelected, ally) < 0)
            {
                return [];
            }
            return [vwa_t("vwa--ship-selected")];
        } },
        { name: "position", slotLevel: true, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            return [vwa_sheet_t("vwa--ship-pos", ["x", "y"],
                [vwa_ship_coord_str(ctx.tx - ctx.cx),
                 vwa_ship_coord_str(ctx.cy - ctx.ty)])];
        } }
    ];
}

// Section lookup by name; a missing name is a mod bug.
function vwa_ship_section_get(name)
{
    for (var i = 0; i < array_length(global.vwaShipSections); i++)
    {
        if (global.vwaShipSections[i].name == name)
        {
            return global.vwaShipSections[i];
        }
    }
    throw ("ship: no section named " + string(name));
}

// The where-am-I read order: position first (the question asked), then
// the room's system name and shape (see header - all the identity a
// room has, name before shape like every tile read).
function vwa_ship_where_sections()
{
    return [vwa_ship_section_get("position"),
            vwa_ship_section_get("system"),
            vwa_ship_section_get("identity")];
}

// The composer runner: every non-quarantined section in order, each
// section's parts appended flat. quar is the caller's quarantine set
// (section name -> true); a throwing section joins it, logged once, and
// the remaining sections still run (see header). The visibility gate
// lives here: with ctx.vision false, interior sections are skipped and
// one "interior unknown" token speaks in the first one's place, only
// when ctx.cellChanged (see header).
function vwa_ship_compose_run(sections, quar, hull, cell, slot, ctx)
{
    var parts = [];
    var unknownSpoken = false;
    for (var i = 0; i < array_length(sections); i++)
    {
        var sec = sections[i];
        if (variable_struct_exists(quar, sec.name))
        {
            continue;
        }
        if (!ctx.vision && sec.interior)
        {
            if (!unknownSpoken && ctx.cellChanged)
            {
                array_push(parts, vwa_t("vwa--ship-unknown"));
                unknownSpoken = true;
            }
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

// The door-state mappings, shared by the cursor, the scanner, and the
// dev walker: state (0 open, 1 closed, 2 destroyed - the game's own
// mechanics: a zero-HP door force-opens, passes crew and air, and
// repairs only at a warp jump with no enemy crew aboard) to the
// door-cross earcon event and to its never-strand fallback token key.
function vwa_ship_door_earcon(doorState)
{
    if (doorState == 1)
    {
        return "door-closed";
    }
    if (doorState == 2)
    {
        return "door-destroyed";
    }
    return "door-open";
}

function vwa_ship_door_token(doorState)
{
    if (doorState == 1)
    {
        return "vwa--ship-door-closed";
    }
    if (doorState == 2)
    {
        return "vwa--ship-door-destroyed";
    }
    return "vwa--ship-door-open";
}

// The spoken parts for landing on a tile: the sections in order. The
// door-cross channel is the caller's (audio, with the spoken token only
// on earcon failure - vwa_ship_cursor_move).
function vwa_ship_move_parts(alliedSide, entry, ctx)
{
    var parts = [];
    var hull = get_hull(alliedSide);
    if (hull == 0 || !instance_exists(hull))
    {
        throw ("ship: no hull for move parts, allied " + string(alliedSide));
    }
    var c = vwa_ship_container(alliedSide);
    // The one place vision is resolved: the landed cell's own
    // playerHasVision, recomputed by the game every step.
    ctx.vision = entry.cell.playerHasVision;
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
        // The block channel is audio; the spoken token is the
        // never-strand fallback on earcon failure (see header).
        // blocked == "airlock" only when a live airlock edge resolved, so
        // its captured state (0 open, 1 closed) is always present.
        var earName = "wall-block";
        var blockedKey = "vwa--ship-wall";
        if (plan.blocked == "airlock")
        {
            earName = (edge.doorState == 1)
                ? "airlock-closed-block" : "airlock-open-block";
            blockedKey = (edge.doorState == 1)
                ? "vwa--ship-airlock-closed" : "vwa--ship-airlock-open";
        }
        if (!vwa_earcon(earName))
        {
            vwa_speak([vwa_t(blockedKey)], true);
        }
        return;
    }
    cur.tx += dx;
    cur.ty += dy;
    var parts = [];
    if (plan.door != undefined)
    {
        // Door-cross is audio-only; the spoken state token survives as
        // the fallback ahead of the tile speech.
        if (!vwa_earcon(vwa_ship_door_earcon(plan.door.doorState)))
        {
            array_push(parts, vwa_t(vwa_ship_door_token(plan.door.doorState)));
        }
    }
    var ctx = { cellChanged: plan.cellChanged,
                tx: cur.tx, ty: cur.ty, cx: geom.cx, cy: geom.cy };
    var body = vwa_ship_move_parts(alliedSide, toE, ctx);
    for (var i = 0; i < array_length(body); i++)
    {
        array_push(parts, body[i]);
    }
    vwa_speak(parts, true);
}

// A full-read ctx for the cursor tile: nothing dampened.
// vwa_ship_move_parts stamps the vision field.
function vwa_ship_read_ctx(geom, cur)
{
    return { cellChanged: true, tx: cur.tx, ty: cur.ty,
             cx: geom.cx, cy: geom.cy };
}

// K, where am I: position, room identity, system, on demand through the
// filtered section list (same reads, same quarantine). Interrupts:
// direct user-caused feedback.
function vwa_ship_where()
{
    var alliedSide = vwa_ship_focus();
    var geom = vwa_ship_geom(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var entry = vwa_ship_geom_tile(geom, cur.tx, cur.ty);
    var hull = get_hull(alliedSide);
    if (hull == 0 || !instance_exists(hull))
    {
        throw ("ship: no hull for where, allied " + string(alliedSide));
    }
    var c = vwa_ship_container(alliedSide);
    var ctx = vwa_ship_read_ctx(geom, cur);
    ctx.vision = entry.cell.playerHasVision;
    vwa_speak(vwa_ship_compose_run(vwa_ship_where_sections(), c.quar,
        hull, entry.cell, entry.slot, ctx), true);
}

// R, details: a full re-read of the current tile regardless of
// granularity dampening, visibility-gated like any read. Interrupts
// likewise.
function vwa_ship_details()
{
    var alliedSide = vwa_ship_focus();
    var geom = vwa_ship_geom(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var entry = vwa_ship_geom_tile(geom, cur.tx, cur.ty);
    vwa_speak(vwa_ship_move_parts(alliedSide, entry,
        vwa_ship_read_ctx(geom, cur)), true);
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
    // The toggled-to ship's scanner snapshot rebuilds fresh on its next
    // scanner key (scrVwaShipScan).
    vwa_ship_scan_drop(next.allied);
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
        vwa_ship_read_ctx(geom, cur));
    for (var i = 0; i < array_length(body); i++)
    {
        array_push(parts, body[i]);
    }
    vwa_speak(parts, true);
}
