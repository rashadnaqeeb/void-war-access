// scrVwaShipScan - Void War Access ship scanner (ship-layer piece 4): the
// "what's on this ship" browser over the FOCUSED hull
// (docs/ship-layer-plan.md is the build-to document; this header is the
// authoritative spec of what is built). Hierarchy is category > item >
// instance, no subcategories: categories cycle with Ctrl+PageUp/PageDown,
// items with PageUp/PageDown, instances with Alt+PageUp/PageDown. Action
// keys on the announced entry: Home jumps the tile cursor to it (the
// bridge from perception to orders), End re-speaks its path without
// moving, Backspace returns the cursor to where it was before the last
// jump. Ctrl+F opens a typed search over every entry on the ship. All
// scanner keys live in the "ship" input category (scrVwaShipLayer's
// mode), so any stacked screen suspends them.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// Categories (v1, a fixed set, empty allowed in the snapshot): my crew,
// enemy crew, systems, hazards - all scoped to the focused ship, which
// does real work: "enemy crew" while focused on the player ship IS the
// boarder list. The category cycle SKIPS empty categories (revised in
// play with Rashad: if there's nothing in them, they shouldn't be
// discoverable - no boarders means "enemy crew" never comes up); with
// every category empty it speaks the bare empty token and stays put. A
// category that empties out mid-browse still announces itself plus
// "empty" on the item/instance keys - the honest answer beats a silent
// jump elsewhere. (Doors/airlocks as a fifth category is an open plan
// decision, settled in play.)
//
// Backends, one per category, stateless. scan(alliedSide, geom) emits
// identity-only entries ({item, key, cell, ref/htype}); resolve(
// alliedSide, geom, entry) is the ONE source of location and detail,
// called fresh at build AND before every announcement - it re-validates
// the entry against live state and returns {tx, ty, detail} or undefined
// for stale (dead, vanished, off this hull, vision lost, burned out). A
// stale entry is pruned at speak time and the browse advances in place,
// iteration-capped and logged - stale speech is the cardinal sin and
// this is the last line of defense. Every entry carries a STABLE KEY
// ("crew:"/"sys:" + its instance, "haz:" + type + cell) - the identity
// that survives rebuilds. The backends:
// - my crew / enemy crew (channel = the crew's allied flag, 1/0): one
//   entry per oCrew alive and physically standing (position_meeting) in a
//   cell of the hull, deduplicated by instance (a doorway-straddling crew
//   can meet two cells); item = crew name. The game's throttled
//   crewInCell lists are never read. Tile: the crew's world position
//   quantized on the geometry index's world origin when that tile
//   resolves (a standing crew sits exactly on its slot center), else the
//   current cell's anchor tile (a mid-walk doorway position). resolve
//   re-locates the crew, so a crew that walked announces its CURRENT
//   room, never the built one. my-crew detail: "selected" when the crew
//   sits in oUICursor.currSelected, read live.
// - systems: one entry per oSysGroup on the hull (deduplicated by
//   instance; a system can overlap several cells, and the entry's cell
//   is chosen deterministically - console cell first, then top-left-most
//   anchor - because cell iteration order is not guaranteed); item =
//   system name; detail = damaged n-of-m / destroyed, the tile-section
//   wording. Tile: the console slot's tile when the system is mannable,
//   else the cell anchor.
// - hazards: one entry per (type, room) - fire, warp fire, breach -
//   grouped by the hazard instances' currentCellID; item = the bare type
//   word; detail = the count wording only above one ("3 fires" - slot
//   count is the honest severity number; at one the item name already
//   said it). resolve recounts and prunes at zero. Tile: the cell anchor.
// Visibility lives in the backends, so the snapshot can never contain
// what a sighted player can't see: crew and hazards (gated) emit only for
// cells with playerHasVision; systems respect playerHasVision on the own
// hull (dark below sensor level 1) and emit regardless on the enemy hull,
// matching what the game draws without sensor parity.
//
// REFRESH MODEL (identity-preserving; the state is per hull, in the hull
// container's scan field: {catIx, itemIx, instIx, snap, preJump,
// preSearchCatIx}, reset with the container):
// - The category cycle is the explicit REORIENT: it rebuilds the snapshot
//   with the sort origin re-anchored to the live cursor and lands at the
//   front of the new category - the "forget where I was" escape hatch.
//   The ship focus toggle drops the toggled-to hull's snapshot outright
//   (vwa_ship_scan_drop).
// - EVERY other scanner key (item/instance cycles, Home, End, Backspace
//   aside - it only moves the cursor) first rebuilds the snapshot from
//   live backends via vwa_ship_scan_refresh, PRESERVING the previous
//   snapshot's sort origin so ordering stays stable, then re-seats the
//   browse on the same entity by its key (vwa_scan_locate). New entries
//   appear immediately, dead ones vanish immediately, counts stay
//   current, and a resort never moves the browse off its entity. When
//   the identity died across the rebuild, a cycle key lands on the
//   scope's endpoint in the pressed direction (first for next, last for
//   previous) rather than stepping past it.
// - A key that found NO snapshot at all (first use, post-toggle,
//   post-reset) builds one from the live cursor, prefixes the category
//   name, and announces the nearest entry WITHOUT stepping - its job was
//   opening the browser.
// - Sort keys (dist from the snapshot origin, then row, then column;
//   stable sort so full ties - co-located hazard types - keep emission
//   order) are stamped at build for SORTING only; announcements always
//   recompute the path live from the cursor. dist is CURSOR-PATH
//   distance, not geometric: BFS moves over the ship layer's
//   passability graph (vwa_ship_geom_adj - rooms connect only through
//   doors), so "nearest" means nearest to walk to. An entry unreachable
//   from the origin sits in a DETACHED SECTION - real topology, not a
//   bug: ruin and boss hulls ship door-disconnected sections (audited
//   from the room data: both DM ruins, the demon and empire bosses).
//   Sorted last, one non-error log per build.
//
// Announcements (always interrupt: direct user-caused feedback): item
// name, then the CURSOR PATH to the entry as ONE space-joined phrase of
// walking legs in walking order ("1 down 2 right 1 up": follow the legs
// and you arrive - never a straight-line offset the cursor cannot
// follow). The path is the shortest in MOVES, with TURNS as the
// tie-break (a straight "3 up 2 left" beats an equal-length zigzag) and
// remaining ties resolved toward vwa_ship_dirs order, so a same-room
// straight shot keeps the old vertical-then-horizontal convention. One
// part, so the chokepoint puts no pause between the leg tokens; "here"
// at zero. An entry with no path speaks the localized "detached" token
// in the path's place when its tile is on the passability graph (a
// detached section - Home still jumps there), and "error" with a log
// when it is not (a mod bug, the announce part guard's precedent).
// Then instance position n of m only when the
// item has more than one instance, then the backend detail clause. A category cycle prefixes
// the category name; an emptied-out category speaks the category name
// plus "empty". Every entry announcement also fires the scanner
// direction tone through the earcon chokepoint
// (vwa_ship_scan_announce): the STRAIGHT-LINE tile offset from the
// cursor to the announced entry, a spatial pointer deliberately
// distinct from the spoken walking legs (tone spec, falloff, and the
// global.vwaEarconDirTones toggle in scrVwaEarcon's header). An empty
// category, Home, Backspace, and the plain tile reads fire no scanner
// audio (a wrap click on item/instance wraps shipped briefly and was
// removed in play - not needed). Home resolves the entry, remembers the
// cursor tile (preJump), moves the cursor, and speaks the full tile read
// (vwa_ship_move_parts, nothing dampened); Home with the cursor already
// on the entry speaks "here" and leaves the preJump anchor alone.
// Backspace restores the preJump tile with a full read, once ("nothing
// to return to" after that, or when the tile no longer resolves). End
// re-announces the current entry, the path recomputed from the cursor.
//
// SEARCH (Ctrl+F): arms a typed-query capture. While armed the ship
// category goes dead (scrVwaShipLayer's mode gates on
// vwa_ship_scan_search_armed, so letters like K/R stop being status keys)
// and the "ship-search" mode's category carries Enter (commit), Escape
// (cancel, consumed), and Backspace (delete one character, spoken).
// Characters arrive through the type-ahead tick's no-focused-screen
// branch (scrVwaScreens calls vwa_ship_scan_typed with each frame's
// drained keyboard_string): letters append, space extends a non-empty
// buffer, everything else is ignored. Typing itself is SILENT -
// scrVwaText's rule: the player's screen reader echoes typed keys
// through its own hook, and echoing here would double-speak. The capture
// survives a transient screen or popup (the mode suspends, typing goes
// nowhere, Escape still ends it once the ship layer is back).
// Commit gathers FRESH entries from every backend, filters them through
// the tiered type-ahead matcher (scrVwaSearch) against each entry's item
// name, and installs a FROZEN search snapshot: one synthetic "search"
// category, items ordered by best match tier then nearest distance. The
// normal browse keys walk it unchanged (per-announce validation still
// prunes); identity-preserving rebuilds skip it (frozen slice). A commit
// with no matches speaks "{query}, no match" and keeps the capture armed
// with the buffer intact for editing. Ctrl+PageUp/PageDown from a search
// snapshot EXITS it: the pre-search category is restored, a fresh normal
// snapshot builds, and the cycle proceeds; the focus toggle's snapshot
// drop also restores the pre-search category.
//
// Pure and fixture-tested in vwa_dev_selftest (vwa_test_shipscan):
// vwa_scan_group (grouping, both sorts, tie-breaks, empty categories),
// vwa_scan_path_dists (BFS distances, door-only room crossings),
// vwa_scan_path_legs (shortest-move min-turn legs, tie order,
// unreachable), vwa_scan_path_str (the leg phrase, "here" at zero),
// vwa_scan_next_nonempty (the category skip rule),
// vwa_scan_prune (instance removal, item drop,
// prune-to-empty), vwa_scan_locate (re-seat by key), and
// vwa_scan_search_group (tier filter and ordering, no-match undefined).
// The live analog is vwa_dev_shipscan (scrVwaTestShip): a full category lap
// through the real handlers with every utterance verified against a
// fresh compose, every snapshot entry re-resolved through its own
// backend, the vision gate and per-category totals cross-checked against
// direct live enumeration, an identity-preserving refresh check, a live
// jump with Backspace return, and a live search apply/exit.

function vwa_ship_scan_init()
{
    global.vwaShipScanSearch = { armed: false, buffer: "" };
    vwa_ship_scan_backends_init();
    vwa_mode_register({
        key: "ship-search",
        category: "ship-search",
        isActive: function()
        {
            return vwa_ship_scan_search_armed() && vwa_ship_mode_active();
        }
    });
    vwa_action_register("ship-scan-cat-prev", "vwa--action-ship-scan-cat-prev",
        "ship", vwa_bind(vk_pageup, false, true, false), true, function()
        {
            vwa_ship_scan_cat_cycle(-1);
        });
    vwa_action_register("ship-scan-cat-next", "vwa--action-ship-scan-cat-next",
        "ship", vwa_bind(vk_pagedown, false, true, false), true, function()
        {
            vwa_ship_scan_cat_cycle(1);
        });
    vwa_action_register("ship-scan-item-prev", "vwa--action-ship-scan-item-prev",
        "ship", vwa_bind(vk_pageup, false, false, false), true, function()
        {
            vwa_ship_scan_item_cycle(-1);
        });
    vwa_action_register("ship-scan-item-next", "vwa--action-ship-scan-item-next",
        "ship", vwa_bind(vk_pagedown, false, false, false), true, function()
        {
            vwa_ship_scan_item_cycle(1);
        });
    vwa_action_register("ship-scan-inst-prev", "vwa--action-ship-scan-inst-prev",
        "ship", vwa_bind(vk_pageup, false, false, true), true, function()
        {
            vwa_ship_scan_inst_cycle(-1);
        });
    vwa_action_register("ship-scan-inst-next", "vwa--action-ship-scan-inst-next",
        "ship", vwa_bind(vk_pagedown, false, false, true), true, function()
        {
            vwa_ship_scan_inst_cycle(1);
        });
    vwa_action_register("ship-scan-jump", "vwa--action-ship-scan-jump",
        "ship", vwa_bind(vk_home, false, false, false), false, function()
        {
            vwa_ship_scan_jump();
        });
    vwa_action_register("ship-scan-orient", "vwa--action-ship-scan-orient",
        "ship", vwa_bind(vk_end, false, false, false), false, function()
        {
            vwa_ship_scan_orient();
        });
    vwa_action_register("ship-scan-return", "vwa--action-ship-scan-return",
        "ship", vwa_bind(vk_backspace, false, false, false), false, function()
        {
            vwa_ship_scan_return();
        });
    vwa_action_register("ship-scan-search", "vwa--action-ship-scan-search",
        "ship", vwa_bind(ord("F"), false, true, false), false, function()
        {
            vwa_ship_scan_search_open();
        });
    vwa_action_register("ship-search-commit", "vwa--action-ship-search-commit",
        "ship-search", vwa_bind(vk_enter, false, false, false), false, function()
        {
            vwa_ship_scan_search_commit();
        });
    vwa_action_register("ship-search-cancel", "vwa--action-ship-search-cancel",
        "ship-search", vwa_bind(vk_escape, false, false, false), false, function()
        {
            vwa_ship_scan_search_cancel();
        });
    vwa_action_register("ship-search-delete", "vwa--action-ship-search-delete",
        "ship-search", vwa_bind(vk_backspace, false, false, false), true, function()
        {
            vwa_ship_scan_search_delete();
        });
    vwa_log("ship scan: initialized");
}

// The fixed category set, in cycle order.
function vwa_ship_scan_cats()
{
    return ["my-crew", "enemy-crew", "systems", "hazards"];
}

// Category key -> spoken label; the synthetic "search" category resolves
// through the same concatenation (vwa--ship-scan-search).
function vwa_ship_scan_cat_label(catKey)
{
    return vwa_t("vwa--ship-scan-" + catKey);
}

// The backend registry (see header). gated marks the interior-vision
// rule; the systems backend carries its own hull-dependent rule.
function vwa_ship_scan_backends_init()
{
    global.vwaShipScanBackends = [
        { cat: "my-crew", gated: true,
          scan: function(alliedSide, geom)
        {
            return vwa_ship_scan_crew_scan(alliedSide, geom, 1);
        },
          resolve: function(alliedSide, geom, e)
        {
            return vwa_ship_scan_crew_resolve(alliedSide, geom, e, 1);
        } },
        { cat: "enemy-crew", gated: true,
          scan: function(alliedSide, geom)
        {
            return vwa_ship_scan_crew_scan(alliedSide, geom, 0);
        },
          resolve: function(alliedSide, geom, e)
        {
            return vwa_ship_scan_crew_resolve(alliedSide, geom, e, 0);
        } },
        { cat: "systems", gated: false,
          scan: function(alliedSide, geom)
        {
            return vwa_ship_scan_systems_scan(alliedSide, geom);
        },
          resolve: function(alliedSide, geom, e)
        {
            return vwa_ship_scan_systems_resolve(alliedSide, geom, e);
        } },
        { cat: "hazards", gated: true,
          scan: function(alliedSide, geom)
        {
            return vwa_ship_scan_hazards_scan(alliedSide, geom);
        },
          resolve: function(alliedSide, geom, e)
        {
            return vwa_ship_scan_hazards_resolve(alliedSide, geom, e);
        } }
    ];
}

// Backend lookup by category key; a missing one is a mod bug. Dispatch is
// per ENTRY (e.cat), so search-snapshot entries resolve through their
// real backend whatever category container they sit in.
function vwa_ship_scan_backend(catKey)
{
    var bs = global.vwaShipScanBackends;
    for (var i = 0; i < array_length(bs); i++)
    {
        if (bs[i].cat == catKey)
        {
            return bs[i];
        }
    }
    throw ("scan: no backend for category " + string(catKey));
}

// ---- geometry helpers ----

// The hull's distinct cells, each with its anchor tile (top-left-most:
// minimum row, then column) - anchors are computed as minima because
// struct field iteration order is not guaranteed.
function vwa_ship_scan_cells(geom)
{
    var out = [];
    var keys = variable_struct_get_names(geom.tiles);
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        var rec = undefined;
        for (var j = 0; j < array_length(out); j++)
        {
            if (out[j].cell == t.cell)
            {
                rec = out[j];
                break;
            }
        }
        if (rec == undefined)
        {
            array_push(out, { cell: t.cell, tx: t.tx, ty: t.ty });
        }
        else if (t.ty < rec.ty || (t.ty == rec.ty && t.tx < rec.tx))
        {
            rec.tx = t.tx;
            rec.ty = t.ty;
        }
    }
    return out;
}

// One cell's anchor tile. A hull cell missing from the index is a mod bug
// (topology is immutable within an encounter): throw, the input watchdog
// reports it.
function vwa_ship_scan_cell_anchor(geom, cell)
{
    var cells = vwa_ship_scan_cells(geom);
    for (var i = 0; i < array_length(cells); i++)
    {
        if (cells[i].cell == cell)
        {
            return { tx: cells[i].tx, ty: cells[i].ty };
        }
    }
    throw ("scan: cell not in the geometry index");
}

// The tile of one slot of a cell, or undefined when the pair is not in
// the index.
function vwa_ship_scan_slot_tile(geom, cell, slotNum)
{
    var keys = variable_struct_get_names(geom.tiles);
    for (var i = 0; i < array_length(keys); i++)
    {
        var t = variable_struct_get(geom.tiles, keys[i]);
        if (t.cell == cell && t.slot == slotNum)
        {
            return { tx: t.tx, ty: t.ty };
        }
    }
    return undefined;
}

// The per-category visibility rule (see header): gated categories mirror
// the interior sections; the systems rule mirrors what the game draws.
function vwa_ship_scan_cell_visible(alliedSide, cell, gated)
{
    if (gated)
    {
        return cell.playerHasVision;
    }
    return alliedSide ? cell.playerHasVision : true;
}

// ---- crew backend ----

function vwa_ship_scan_crew_scan(alliedSide, geom, channel)
{
    var entries = [];
    var seen = [];
    var cells = vwa_ship_scan_cells(geom);
    for (var i = 0; i < array_length(cells); i++)
    {
        var cc = cells[i].cell;
        if (!vwa_ship_scan_cell_visible(alliedSide, cc, true))
        {
            continue;
        }
        with (oCrew)
        {
            if (!crew_is_dead(id) && allied == channel
                && position_meeting(x, y, cc)
                && vwa_array_index_of(seen, id) < 0)
            {
                array_push(seen, id);
                array_push(entries, { item: string(crewName),
                    key: "crew:" + string(id), cell: cc, ref: id });
            }
        }
    }
    return entries;
}

// The cell of THIS hull the crew physically stands in, or undefined.
function vwa_ship_scan_crew_cell(alliedSide, crew)
{
    var found = undefined;
    with (oCell)
    {
        if (allied == alliedSide && position_meeting(crew.x, crew.y, id))
        {
            found = id;
            break;
        }
    }
    return found;
}

// A standing crew sits exactly on its slot center, so quantizing on the
// geometry origin lands the exact tile; a mid-walk crew quantizes to the
// nearest tile, falling back to its cell's anchor when that tile is not
// on the hull (a doorway midpoint).
function vwa_ship_scan_crew_tile(geom, crew, cell)
{
    var tx = round((crew.x - geom.ox) / 36);
    var ty = round((crew.y - geom.oy) / 36);
    if (vwa_ship_geom_tile(geom, tx, ty) != undefined)
    {
        return { tx: tx, ty: ty };
    }
    return vwa_ship_scan_cell_anchor(geom, cell);
}

function vwa_ship_scan_crew_resolve(alliedSide, geom, e, channel)
{
    var crew = e.ref;
    if (!instance_exists(crew) || crew_is_dead(crew) || crew.allied != channel)
    {
        return undefined;
    }
    var cell = vwa_ship_scan_crew_cell(alliedSide, crew);
    if (cell == undefined || !vwa_ship_scan_cell_visible(alliedSide, cell, true))
    {
        return undefined;
    }
    // Live re-location: announcements speak the crew's CURRENT room.
    e.cell = cell;
    var tile = vwa_ship_scan_crew_tile(geom, crew, cell);
    var detail = [];
    if (channel == 1 && ds_list_find_index(oUICursor.currSelected, crew) >= 0)
    {
        array_push(detail, vwa_t("vwa--ship-selected"));
    }
    return { tx: tile.tx, ty: tile.ty, detail: detail };
}

// ---- systems backend ----

// One entry per oSysGroup - but a system can OVERLAP SEVERAL CELLS, and
// cell iteration order is not guaranteed, so the entry's cell is chosen
// deterministically: the console cell wins (jump lands where manning
// happens), then the top-left-most anchor. First-seen bit us live: the
// same system announced different tiles across rebuilds.
function vwa_ship_scan_systems_scan(alliedSide, geom)
{
    var entries = [];
    var recs = [];
    var cells = vwa_ship_scan_cells(geom);
    for (var i = 0; i < array_length(cells); i++)
    {
        var cc = cells[i].cell;
        if (cc.system == 0
            || !vwa_ship_scan_cell_visible(alliedSide, cc, false))
        {
            continue;
        }
        var hasConsole = (cc.system.mannable && cc.sysConsoleSlot > 0);
        var rec = undefined;
        for (var j = 0; j < array_length(recs); j++)
        {
            if (recs[j].entry.ref == cc.system)
            {
                rec = recs[j];
                break;
            }
        }
        if (rec == undefined)
        {
            var e = { item: vwa_sheet_flatten(cc.system.name),
                key: "sys:" + string(cc.system), cell: cc, ref: cc.system };
            array_push(entries, e);
            array_push(recs, { entry: e, ax: cells[i].tx, ay: cells[i].ty,
                console: hasConsole });
            continue;
        }
        if ((hasConsole && !rec.console)
            || (hasConsole == rec.console
                && (cells[i].ty < rec.ay
                    || (cells[i].ty == rec.ay && cells[i].tx < rec.ax))))
        {
            rec.entry.cell = cc;
            rec.ax = cells[i].tx;
            rec.ay = cells[i].ty;
            rec.console = hasConsole;
        }
    }
    return entries;
}

function vwa_ship_scan_systems_resolve(alliedSide, geom, e)
{
    var sys = e.ref;
    if (!instance_exists(sys) || !instance_exists(e.cell)
        || !vwa_ship_scan_cell_visible(alliedSide, e.cell, false))
    {
        return undefined;
    }
    var tile = undefined;
    if (sys.mannable && e.cell.sysConsoleSlot > 0)
    {
        tile = vwa_ship_scan_slot_tile(geom, e.cell, e.cell.sysConsoleSlot);
    }
    if (tile == undefined)
    {
        tile = vwa_ship_scan_cell_anchor(geom, e.cell);
    }
    var detail = [];
    if (sys.currHP <= 0)
    {
        array_push(detail, vwa_t("vwa--ship-sys-destroyed"));
    }
    else if (sys.currHP < sys.maxHP)
    {
        array_push(detail, vwa_sheet_t("vwa--ship-sys-damaged", ["n", "m"],
            [sys.currHP, sys.maxHP]));
    }
    return { tx: tile.tx, ty: tile.ty, detail: detail };
}

// ---- hazards backend ----

function vwa_ship_scan_hazard_count(cell, htype)
{
    var n = 0;
    if (htype == "breach")
    {
        with (oBreach)
        {
            if (currentCellID == cell)
            {
                n += 1;
            }
        }
        return n;
    }
    var wantWarp = (htype == "warpfire");
    with (oFire)
    {
        if (currentCellID == cell && ((object_index == oWarpFire) == wantWarp))
        {
            n += 1;
        }
    }
    return n;
}

function vwa_ship_scan_hazards_scan(alliedSide, geom)
{
    var entries = [];
    var types = ["fire", "warpfire", "breach"];
    var cells = vwa_ship_scan_cells(geom);
    for (var i = 0; i < array_length(cells); i++)
    {
        var cc = cells[i].cell;
        if (!vwa_ship_scan_cell_visible(alliedSide, cc, true))
        {
            continue;
        }
        for (var j = 0; j < array_length(types); j++)
        {
            if (vwa_ship_scan_hazard_count(cc, types[j]) > 0)
            {
                array_push(entries, {
                    item: vwa_t("vwa--ship-" + types[j] + "-one"),
                    key: "haz:" + types[j] + ":" + string(cc),
                    cell: cc, htype: types[j] });
            }
        }
    }
    return entries;
}

function vwa_ship_scan_hazards_resolve(alliedSide, geom, e)
{
    if (!instance_exists(e.cell)
        || !vwa_ship_scan_cell_visible(alliedSide, e.cell, true))
    {
        return undefined;
    }
    var n = vwa_ship_scan_hazard_count(e.cell, e.htype);
    if (n <= 0)
    {
        return undefined;
    }
    var tile = vwa_ship_scan_cell_anchor(geom, e.cell);
    var detail = (n > 1)
        ? vwa_ship_count_parts(n, "vwa--ship-" + e.htype + "-one",
            "vwa--ship-" + e.htype + "-many")
        : [];
    return { tx: tile.tx, ty: tile.ty, detail: detail };
}

// ---- pure snapshot machinery ----

// PURE: lexicographic greater-than on equal-length numeric key arrays.
function vwa_scan_key_gt(a, b)
{
    for (var i = 0; i < array_length(a); i++)
    {
        if (a[i] != b[i])
        {
            return a[i] > b[i];
        }
    }
    return false;
}

// PURE: STABLE insertion sort by a numeric key array (arrays here are
// tens of elements; stability is what makes full ties - co-located
// hazard types - keep their deterministic emission order).
function vwa_scan_sort(arr, keyFn)
{
    for (var i = 1; i < array_length(arr); i++)
    {
        var v = arr[i];
        var kv = keyFn(v);
        var j = i - 1;
        while (j >= 0 && vwa_scan_key_gt(keyFn(arr[j]), kv))
        {
            arr[j + 1] = arr[j];
            j -= 1;
        }
        arr[j + 1] = v;
    }
}

// PURE: raw entries ({cat, item, key, dist, tx, ty, ...}) -> the snapshot
// body ({cats: [{key, items: [{name, entries}]}]}). Every given category
// key is present, in the given order, empty allowed; items group by name;
// entries within an item sort by (dist, ty, tx), items by their first
// (nearest) entry under the same key. An entry naming an unknown
// category is a backend bug: throw.
function vwa_scan_group(catKeys, entries)
{
    var cats = [];
    for (var i = 0; i < array_length(catKeys); i++)
    {
        array_push(cats, { key: catKeys[i], items: [] });
    }
    for (var i = 0; i < array_length(entries); i++)
    {
        var e = entries[i];
        var cat = undefined;
        for (var j = 0; j < array_length(cats); j++)
        {
            if (cats[j].key == e.cat)
            {
                cat = cats[j];
                break;
            }
        }
        if (cat == undefined)
        {
            throw ("scan: entry category not in the set: " + string(e.cat));
        }
        var item = undefined;
        for (var j = 0; j < array_length(cat.items); j++)
        {
            if (cat.items[j].name == e.item)
            {
                item = cat.items[j];
                break;
            }
        }
        if (item == undefined)
        {
            item = { name: e.item, entries: [] };
            array_push(cat.items, item);
        }
        array_push(item.entries, e);
    }
    for (var i = 0; i < array_length(cats); i++)
    {
        var items = cats[i].items;
        for (var j = 0; j < array_length(items); j++)
        {
            vwa_scan_sort(items[j].entries, function(e)
            {
                return [e.dist, e.ty, e.tx];
            });
        }
        vwa_scan_sort(items, function(it)
        {
            var e = it.entries[0];
            return [e.dist, e.ty, e.tx];
        });
    }
    return { cats: cats };
}

// PURE: remove the instance at (itemIx, instIx) from a snapshot
// category, dropping the item when its last instance goes.
function vwa_scan_prune(cat, itemIx, instIx)
{
    var item = cat.items[itemIx];
    array_delete(item.entries, instIx, 1);
    if (array_length(item.entries) == 0)
    {
        array_delete(cat.items, itemIx, 1);
    }
}

// PURE: find the entry with this stable key anywhere in the snapshot;
// {catIx, itemIx, instIx} or undefined. How a rebuild re-seats the
// browse on the same entity (see the refresh model in the header).
function vwa_scan_locate(snap, key)
{
    for (var c = 0; c < array_length(snap.cats); c++)
    {
        var items = snap.cats[c].items;
        for (var i = 0; i < array_length(items); i++)
        {
            var es = items[i].entries;
            for (var j = 0; j < array_length(es); j++)
            {
                if (es[j].key == key)
                {
                    return { catIx: c, itemIx: i, instIx: j };
                }
            }
        }
    }
    return undefined;
}

// PURE (given the matcher): committed-query filter. Entries whose item
// name matches the query (vwa_search_match_tier, any tier) land in one
// synthetic "search" category: items group by name and carry the best
// tier of any of their entries, instances sort by (dist, ty, tx), items
// by (tier, dist, ty, tx) - start-of-string hits surface before
// substring hits, nearest first within a tier. Returns {cats: [cat]} or
// undefined when nothing matches (the caller speaks no-match and
// installs nothing).
function vwa_scan_search_group(entries, query)
{
    var cat = { key: "search", items: [] };
    for (var i = 0; i < array_length(entries); i++)
    {
        var e = entries[i];
        var m = vwa_search_match_tier(string(e.item), query);
        if (m.tier < 0)
        {
            continue;
        }
        var item = undefined;
        for (var j = 0; j < array_length(cat.items); j++)
        {
            if (cat.items[j].name == e.item)
            {
                item = cat.items[j];
                break;
            }
        }
        if (item == undefined)
        {
            item = { name: e.item, entries: [], tier: m.tier };
            array_push(cat.items, item);
        }
        else if (m.tier < item.tier)
        {
            item.tier = m.tier;
        }
        array_push(item.entries, e);
    }
    if (array_length(cat.items) == 0)
    {
        return undefined;
    }
    for (var i = 0; i < array_length(cat.items); i++)
    {
        vwa_scan_sort(cat.items[i].entries, function(e)
        {
            return [e.dist, e.ty, e.tx];
        });
    }
    vwa_scan_sort(cat.items, function(it)
    {
        var e = it.entries[0];
        return [it.tier, e.dist, e.ty, e.tx];
    });
    return { cats: [cat] };
}

// PURE: breadth-first cursor-move distances from one tile over the
// passability graph ({tileKey: moves} for every REACHABLE tile) - the
// scanner's sort metric. A tile absent from the result is unreachable;
// a from-tile not on the graph answers the empty struct (the impure
// caller logs).
function vwa_scan_path_dists(adj, fromKey)
{
    var dists = {};
    if (!variable_struct_exists(adj, fromKey))
    {
        return dists;
    }
    var dirs = vwa_ship_dirs();
    variable_struct_set(dists, fromKey, 0);
    var queue = [fromKey];
    var qi = 0;
    while (qi < array_length(queue))
    {
        var k = queue[qi];
        qi += 1;
        var node = variable_struct_get(adj, k);
        var nd = variable_struct_get(dists, k) + 1;
        for (var i = 0; i < array_length(dirs); i++)
        {
            if (!node.pass[i])
            {
                continue;
            }
            var nk = string(node.tx + dirs[i].dx) + ","
                + string(node.ty + dirs[i].dy);
            if (!variable_struct_exists(adj, nk)
                || variable_struct_exists(dists, nk))
            {
                continue;
            }
            variable_struct_set(dists, nk, nd);
            array_push(queue, nk);
        }
    }
    return dists;
}

// PURE: the shortest cursor path between two tiles of the passability
// graph, as walking legs [{dir, n}] in walking order - minimal in MOVES
// first, then in TURNS (a straight "3 up 2 left" beats an equal-length
// zigzag), remaining ties toward vwa_ship_dirs order (vertical legs
// surface first, the convention the phrase inherits). [] for the same
// tile; undefined when no path exists (the impure caller decides: a
// detached section when the target tile is on the graph, a mod bug
// when it is not). Dijkstra over
// (tile, arrival direction) states with scalar cost moves * stride +
// turns; turns never exceeds moves and moves never exceeds the state
// count, so the stride keeps the ranking lexicographic. State arrays
// stay in creation order and the min scan takes the first minimum, so
// the result is deterministic.
function vwa_scan_path_legs(adj, fromKey, toKey)
{
    if (fromKey == toKey)
    {
        return [];
    }
    if (!variable_struct_exists(adj, fromKey)
        || !variable_struct_exists(adj, toKey))
    {
        return undefined;
    }
    var dirs = vwa_ship_dirs();
    var stride = (array_length(variable_struct_get_names(adj)) * 4) + 1;
    var states = [{ tileKey: fromKey, dirIx: -1, cost: 0,
                    prevIx: -1, closed: false }];
    var lookup = {};
    variable_struct_set(lookup, fromKey + ":-1", 0);
    var goalIx = -1;
    while (goalIx < 0)
    {
        var curIx = -1;
        for (var i = 0; i < array_length(states); i++)
        {
            if (!states[i].closed
                && (curIx < 0 || states[i].cost < states[curIx].cost))
            {
                curIx = i;
            }
        }
        if (curIx < 0)
        {
            return undefined;
        }
        var s = states[curIx];
        s.closed = true;
        if (s.tileKey == toKey)
        {
            goalIx = curIx;
            break;
        }
        var node = variable_struct_get(adj, s.tileKey);
        for (var d = 0; d < array_length(dirs); d++)
        {
            if (!node.pass[d])
            {
                continue;
            }
            var nk = string(node.tx + dirs[d].dx) + ","
                + string(node.ty + dirs[d].dy);
            if (!variable_struct_exists(adj, nk))
            {
                continue;
            }
            var turn = (s.dirIx >= 0 && s.dirIx != d) ? 1 : 0;
            var cost = s.cost + stride + turn;
            var lk = nk + ":" + string(d);
            if (!variable_struct_exists(lookup, lk))
            {
                variable_struct_set(lookup, lk, array_length(states));
                array_push(states, { tileKey: nk, dirIx: d, cost: cost,
                    prevIx: curIx, closed: false });
            }
            else
            {
                var ex = states[variable_struct_get(lookup, lk)];
                if (!ex.closed && cost < ex.cost)
                {
                    ex.cost = cost;
                    ex.prevIx = curIx;
                }
            }
        }
    }
    // The predecessor chain, straight runs compressed into legs.
    var legs = [];
    var ix = goalIx;
    while (ix >= 0 && states[ix].dirIx >= 0)
    {
        var dkey = dirs[states[ix].dirIx].key;
        if (array_length(legs) > 0 && legs[0].dir == dkey)
        {
            legs[0].n += 1;
        }
        else
        {
            array_insert(legs, 0, { dir: dkey, n: 1 });
        }
        ix = states[ix].prevIx;
    }
    return legs;
}

// PURE: the spoken phrase for path legs - ONE space-joined string, the
// legs in walking order, each through its direction token, no comma
// between legs (a single part, so the chokepoint's join puts no pause
// inside it). No legs speaks "here".
function vwa_scan_path_str(legs)
{
    if (array_length(legs) == 0)
    {
        return vwa_t("vwa--ship-scan-here");
    }
    var s = "";
    for (var i = 0; i < array_length(legs); i++)
    {
        var part = vwa_sheet_t("vwa--ship-scan-" + legs[i].dir,
            ["n"], [legs[i].n]);
        s = (s == "") ? part : (s + " " + part);
    }
    return s;
}

// PURE: the next category index holding items, stepping dir from startIx
// and wrapping, or -1 when every category is empty - the category
// cycle's skip rule (empty categories are not discoverable). A lone
// non-empty category wraps back to itself.
function vwa_scan_next_nonempty(cats, startIx, dir)
{
    var n = array_length(cats);
    var ix = startIx;
    for (var s = 0; s < n; s++)
    {
        ix = ((ix + dir) + n) mod n;
        if (array_length(cats[ix].items) > 0)
        {
            return ix;
        }
    }
    return -1;
}

// ---- state, snapshot build, refresh ----

// The focused hull's scanner state, from the hull container (resets with
// it: new encounter, new run).
function vwa_ship_scan_state(alliedSide)
{
    var c = vwa_ship_container(alliedSide);
    if (c.scan == undefined)
    {
        c.scan = { catIx: 0, itemIx: 0, instIx: 0, snap: undefined,
                   preJump: undefined, preSearchCatIx: undefined };
    }
    return c.scan;
}

// Drop a hull's snapshot; the ship focus toggle calls this so a
// toggled-to ship rebuilds fresh on its next scanner key. Dropping a
// search snapshot restores the pre-search category.
function vwa_ship_scan_drop(alliedSide)
{
    var st = vwa_ship_scan_state(alliedSide);
    if (st.snap != undefined && st.snap.isSearch
        && st.preSearchCatIx != undefined)
    {
        st.catIx = st.preSearchCatIx;
    }
    st.preSearchCatIx = undefined;
    st.snap = undefined;
}

// Gather the flat entry list from every backend, sort keys stamped
// against the given origin. dist is cursor-path moves from the origin
// (vwa_scan_path_dists over the passability graph); an unreachable
// entry sits in a DETACHED SECTION (real topology: ruin and boss hulls
// ship door-disconnected sections) - sorted last, counted in one
// non-error log per build. An origin missing from the graph is a mod
// bug (it was a cursor tile of this same immutable geometry) - logged,
// Manhattan keeps this build's sort usable. Fresh entries are resolved
// immediately; an entry its own backend cannot resolve straight after
// scanning is a backend bug - logged, skipped.
function vwa_ship_scan_gather(alliedSide, originTx, originTy)
{
    var geom = vwa_ship_geom(alliedSide);
    var adj = vwa_ship_geom_adj(alliedSide);
    var originKey = string(originTx) + "," + string(originTy);
    var dists = vwa_scan_path_dists(adj, originKey);
    if (!variable_struct_exists(dists, originKey))
    {
        vwa_log("ERROR: ship scan: sort origin " + originKey
            + " not on the passability graph; Manhattan fallback");
        dists = undefined;
    }
    var entries = [];
    var detached = 0;
    var bs = global.vwaShipScanBackends;
    for (var i = 0; i < array_length(bs); i++)
    {
        var b = bs[i];
        var es = b.scan(alliedSide, geom);
        for (var j = 0; j < array_length(es); j++)
        {
            var e = es[j];
            e.cat = b.cat;
            var res = b.resolve(alliedSide, geom, e);
            if (res == undefined)
            {
                vwa_log("ERROR: ship scan: fresh entry failed its own resolve: "
                    + b.cat + " " + string(e.item));
                continue;
            }
            e.tx = res.tx;
            e.ty = res.ty;
            var ek = string(res.tx) + "," + string(res.ty);
            if (dists == undefined)
            {
                e.dist = abs(res.tx - originTx) + abs(res.ty - originTy);
            }
            else if (variable_struct_exists(dists, ek))
            {
                e.dist = variable_struct_get(dists, ek);
            }
            else
            {
                detached += 1;
                e.dist = 1000000;
            }
            array_push(entries, e);
        }
    }
    if (detached > 0)
    {
        vwa_log("ship scan: " + string(detached)
            + " entries in detached sections (sorted last)");
    }
    return entries;
}

// Build a normal snapshot sorted against the given origin (worst case
// tens of entries: freshness is cheaper than invalidation bookkeeping).
function vwa_ship_scan_build(alliedSide, originTx, originTy)
{
    var snap = vwa_scan_group(vwa_ship_scan_cats(),
        vwa_ship_scan_gather(alliedSide, originTx, originTy));
    snap.originTx = originTx;
    snap.originTy = originTy;
    snap.isSearch = false;
    return snap;
}

// The current entry's stable key, positionally (no resolve), or
// undefined on an empty category.
function vwa_ship_scan_current_key(st)
{
    var cat = st.snap.cats[st.catIx];
    if (array_length(cat.items) == 0)
    {
        return undefined;
    }
    var ii = clamp(st.itemIx, 0, array_length(cat.items) - 1);
    var item = cat.items[ii];
    var ni = clamp(st.instIx, 0, array_length(item.entries) - 1);
    return item.entries[ni].key;
}

// The identity-preserving rebuild every browse key runs first (see the
// refresh model in the header). Returns {built, lost}: built - there was
// no snapshot, one was created from the live cursor (the caller
// announces the nearest entry with the category name, no stepping);
// lost - the entity browsed to died across the rebuild (the caller lands
// on the endpoint in the pressed direction). Search snapshots are frozen
// slices: no rebuild.
function vwa_ship_scan_refresh(alliedSide, st)
{
    if (st.snap == undefined)
    {
        var cur = vwa_ship_cursor(alliedSide);
        st.snap = vwa_ship_scan_build(alliedSide, cur.tx, cur.ty);
        st.itemIx = 0;
        st.instIx = 0;
        return { built: true, lost: false };
    }
    if (st.snap.isSearch)
    {
        return { built: false, lost: false };
    }
    var key = vwa_ship_scan_current_key(st);
    st.snap = vwa_ship_scan_build(alliedSide,
        st.snap.originTx, st.snap.originTy);
    if (key == undefined)
    {
        return { built: false, lost: false };
    }
    var loc = vwa_scan_locate(st.snap, key);
    if (loc != undefined)
    {
        st.catIx = loc.catIx;
        st.itemIx = loc.itemIx;
        st.instIx = loc.instIx;
        return { built: false, lost: false };
    }
    return { built: false, lost: true };
}

// ---- browsing ----

// The current entry resolved live (see header): indexes clamp to the
// live arrays, stale entries prune and the browse advances in place,
// capped at the category's entry count plus one - a category gone
// entirely stale ends at the empty announcement, never a spin. Returns
// {item, entry, res} or undefined for an empty category.
function vwa_ship_scan_current(alliedSide, st)
{
    var cat = st.snap.cats[st.catIx];
    var cap = 1;
    for (var i = 0; i < array_length(cat.items); i++)
    {
        cap += array_length(cat.items[i].entries);
    }
    var geom = vwa_ship_geom(alliedSide);
    while (cap > 0)
    {
        cap -= 1;
        if (array_length(cat.items) == 0)
        {
            return undefined;
        }
        st.itemIx = clamp(st.itemIx, 0, array_length(cat.items) - 1);
        var item = cat.items[st.itemIx];
        st.instIx = clamp(st.instIx, 0, array_length(item.entries) - 1);
        var e = item.entries[st.instIx];
        var b = vwa_ship_scan_backend(e.cat);
        var res = b.resolve(alliedSide, geom, e);
        if (res != undefined)
        {
            return { item: item, entry: e, res: res };
        }
        vwa_log("ship scan: pruned stale " + string(e.cat) + " entry "
            + string(e.item));
        vwa_scan_prune(cat, st.itemIx, st.instIx);
    }
    vwa_log("ERROR: ship scan: prune cap hit in category " + cat.key);
    return undefined;
}

// The current entry's spoken parts (see header for the shape). withCat
// prefixes the category name; an empty category names itself either way.
function vwa_ship_scan_announce_parts(alliedSide, st, withCat)
{
    var cat = st.snap.cats[st.catIx];
    var parts = [];
    if (withCat)
    {
        array_push(parts, vwa_ship_scan_cat_label(cat.key));
    }
    var curE = vwa_ship_scan_current(alliedSide, st);
    if (curE == undefined)
    {
        if (!withCat)
        {
            array_push(parts, vwa_ship_scan_cat_label(cat.key));
        }
        array_push(parts, vwa_t("vwa--ship-scan-empty"));
        return parts;
    }
    array_push(parts, curE.entry.item);
    var cur = vwa_ship_cursor(alliedSide);
    var adj = vwa_ship_geom_adj(alliedSide);
    var toKey = string(curE.res.tx) + "," + string(curE.res.ty);
    var legs = vwa_scan_path_legs(adj,
        string(cur.tx) + "," + string(cur.ty), toKey);
    if (legs == undefined)
    {
        if (variable_struct_exists(adj, toKey))
        {
            // On the graph but no path: a detached section (ruin and
            // boss hulls ship these). No walking legs exist; Home still
            // jumps the cursor there.
            array_push(parts, vwa_t("vwa--ship-detached"));
        }
        else
        {
            // A resolved tile missing from the graph entirely IS a mod
            // bug. Audible and actionable, the announce part guard's
            // precedent.
            vwa_log("ERROR: ship scan: entry tile off the passability graph: "
                + string(curE.entry.item) + " at " + toKey);
            array_push(parts, "error");
        }
    }
    else
    {
        array_push(parts, vwa_scan_path_str(legs));
    }
    var n = array_length(curE.item.entries);
    if (n > 1)
    {
        array_push(parts, vwa_sheet_t("vwa--pos-of", ["n", "m"],
            [st.instIx + 1, n]));
    }
    for (var i = 0; i < array_length(curE.res.detail); i++)
    {
        array_push(parts, curE.res.detail[i]);
    }
    return parts;
}

// ---- key handlers ----

// Speak an announcement and fire the direction tone - the
// STRAIGHT-LINE tile offset from the cursor to the announced entry
// (up/right positive, the spoken coordinate convention), NEVER the
// walking legs the speech carries. The tone is a spatial pointer, the
// legs are the route: a zigzag path must not become a multi-tone
// sequence (Rashad's rule). No announced entry (empty category), no
// tone.
function vwa_ship_scan_announce(alliedSide, st, withCat)
{
    vwa_speak(vwa_ship_scan_announce_parts(alliedSide, st, withCat), true);
    var curE = vwa_ship_scan_current(alliedSide, st);
    if (curE == undefined)
    {
        return;
    }
    var cur = vwa_ship_cursor(alliedSide);
    vwa_earcon_dir(cur.ty - curE.res.ty, curE.res.tx - cur.tx);
}

// Ctrl+PageUp/PageDown: the explicit reorient (see header) - and, from a
// search snapshot, the exit back to the pre-search category. Rebuilds
// FIRST, then steps to the next category holding entries (empty
// categories are skipped, not discoverable); with everything empty it
// speaks the bare empty token and stays put.
function vwa_ship_scan_cat_cycle(dir)
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    if (st.snap != undefined && st.snap.isSearch)
    {
        if (st.preSearchCatIx != undefined)
        {
            st.catIx = st.preSearchCatIx;
        }
        st.preSearchCatIx = undefined;
    }
    var cur = vwa_ship_cursor(alliedSide);
    st.snap = vwa_ship_scan_build(alliedSide, cur.tx, cur.ty);
    var n = array_length(st.snap.cats);
    st.catIx = clamp(st.catIx, 0, n - 1);
    var ix = vwa_scan_next_nonempty(st.snap.cats, st.catIx, dir);
    if (ix < 0)
    {
        vwa_speak([vwa_t("vwa--ship-scan-empty")], true);
        return;
    }
    st.catIx = ix;
    st.itemIx = 0;
    st.instIx = 0;
    vwa_ship_scan_announce(alliedSide, st, true);
}

function vwa_ship_scan_item_cycle(dir)
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var r = vwa_ship_scan_refresh(alliedSide, st);
    var cat = st.snap.cats[st.catIx];
    var n = array_length(cat.items);
    if (n > 0 && !r.built)
    {
        if (r.lost)
        {
            st.itemIx = (dir < 0) ? n - 1 : 0;
        }
        else
        {
            st.itemIx = ((st.itemIx + dir) + n) mod n;
        }
        st.instIx = 0;
    }
    vwa_ship_scan_announce(alliedSide, st, r.built);
}

function vwa_ship_scan_inst_cycle(dir)
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var r = vwa_ship_scan_refresh(alliedSide, st);
    var cat = st.snap.cats[st.catIx];
    if (array_length(cat.items) > 0 && !r.built)
    {
        if (r.lost)
        {
            st.itemIx = 0;
        }
        st.itemIx = clamp(st.itemIx, 0, array_length(cat.items) - 1);
        var n = array_length(cat.items[st.itemIx].entries);
        if (r.lost)
        {
            st.instIx = (dir < 0) ? n - 1 : 0;
        }
        else
        {
            st.instIx = ((st.instIx + dir) + n) mod n;
        }
    }
    vwa_ship_scan_announce(alliedSide, st, r.built);
}

// Home: move the tile cursor to the announced entry and speak the full
// tile read there (nothing dampened) - the bridge from perception to
// orders. Remembers the departed tile for Backspace; already standing on
// the entry speaks "here" and keeps the existing anchor. An empty
// category announces itself instead.
function vwa_ship_scan_jump()
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var r = vwa_ship_scan_refresh(alliedSide, st);
    var curE = vwa_ship_scan_current(alliedSide, st);
    if (curE == undefined)
    {
        vwa_speak(vwa_ship_scan_announce_parts(alliedSide, st, r.built), true);
        return;
    }
    var geom = vwa_ship_geom(alliedSide);
    var entryTile = vwa_ship_geom_tile(geom, curE.res.tx, curE.res.ty);
    if (entryTile == undefined)
    {
        // Backends only emit on-hull tiles; off-hull here is a mod bug.
        throw ("scan: jump target off the hull: " + string(curE.res.tx)
            + "," + string(curE.res.ty));
    }
    var cur = vwa_ship_cursor(alliedSide);
    if (cur.tx == curE.res.tx && cur.ty == curE.res.ty)
    {
        vwa_speak([vwa_t("vwa--ship-scan-here")], true);
        return;
    }
    st.preJump = { tx: cur.tx, ty: cur.ty };
    cur.tx = curE.res.tx;
    cur.ty = curE.res.ty;
    vwa_speak(vwa_ship_move_parts(alliedSide, entryTile,
        vwa_ship_read_ctx(geom, cur)), true);
}

// End: re-announce the current entry, offsets recomputed from the
// cursor, without moving anything.
function vwa_ship_scan_orient()
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var r = vwa_ship_scan_refresh(alliedSide, st);
    vwa_ship_scan_announce(alliedSide, st, r.built);
}

// Backspace: restore the cursor to the tile it left on the last jump,
// with a full tile read; one-shot.
function vwa_ship_scan_return()
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    if (st.preJump == undefined)
    {
        vwa_speak([vwa_t("vwa--ship-scan-no-return")], true);
        return;
    }
    var target = st.preJump;
    st.preJump = undefined;
    var geom = vwa_ship_geom(alliedSide);
    var entry = vwa_ship_geom_tile(geom, target.tx, target.ty);
    if (entry == undefined)
    {
        vwa_log("ship scan: pre-jump tile " + string(target.tx) + ","
            + string(target.ty) + " no longer resolves");
        vwa_speak([vwa_t("vwa--ship-scan-no-return")], true);
        return;
    }
    var cur = vwa_ship_cursor(alliedSide);
    cur.tx = target.tx;
    cur.ty = target.ty;
    vwa_speak(vwa_ship_move_parts(alliedSide, entry,
        vwa_ship_read_ctx(geom, cur)), true);
}

// ---- search (Ctrl+F) ----

function vwa_ship_scan_search_armed()
{
    return variable_global_exists("vwaShipScanSearch")
        && global.vwaShipScanSearch.armed;
}

function vwa_ship_scan_search_open()
{
    global.vwaShipScanSearch.armed = true;
    global.vwaShipScanSearch.buffer = "";
    vwa_speak([vwa_t("vwa--ship-scan-search-prompt")], true);
}

// Typed-character sink, called once per frame by the type-ahead tick's
// no-focused-screen branch (scrVwaScreens) with that frame's drained
// keyboard_string. Letters append; space extends a non-empty buffer.
// Typing is SILENT (scrVwaText's rule: the screen reader's own key echo
// covers it; echoing here would double-speak).
function vwa_ship_scan_typed(typed)
{
    if (typed == "" || !vwa_ship_scan_search_armed() || !vwa_ship_mode_active())
    {
        return;
    }
    var s = global.vwaShipScanSearch;
    for (var i = 1; i <= string_length(typed); i++)
    {
        var o = string_ord_at(typed, i);
        if (vwa_search_char_is_letter(o))
        {
            s.buffer += chr(o);
        }
        else if (o == 32 && s.buffer != "")
        {
            s.buffer += " ";
        }
    }
}

// Backspace while armed: delete the last character, spoken (the deletion
// is mod-side state the screen reader cannot see, unlike typing).
function vwa_ship_scan_search_delete()
{
    var s = global.vwaShipScanSearch;
    if (s.buffer == "")
    {
        vwa_speak([vwa_t("vwa--text-blank")], true);
        return;
    }
    var lastCh = string_char_at(s.buffer, string_length(s.buffer));
    s.buffer = string_copy(s.buffer, 1, string_length(s.buffer) - 1);
    vwa_speak([vwa_text_char_speech(lastCh)], true);
}

// Escape while armed: cancel the capture. Consumed, like every mod
// Escape that acts (the game's pause menu must not also open).
function vwa_ship_scan_search_cancel()
{
    global.vwaShipScanSearch.armed = false;
    global.vwaShipScanSearch.buffer = "";
    vwa_input_consume_escape();
    vwa_speak([vwa_t("vwa--search-cleared")], true);
}

function vwa_ship_scan_search_commit()
{
    vwa_input_consume_key(vk_enter);
    vwa_ship_scan_search_apply(global.vwaShipScanSearch.buffer);
}

// Apply a committed query (see the search paragraph in the header):
// gather fresh entries, filter through the tiered matcher, install the
// frozen search snapshot and announce its first entry. No matches: speak
// "{query}, no match" and keep the capture armed with the buffer intact.
function vwa_ship_scan_search_apply(query)
{
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var grouped = vwa_scan_search_group(
        vwa_ship_scan_gather(alliedSide, cur.tx, cur.ty), query);
    if (grouped == undefined)
    {
        vwa_speak([string_replace(vwa_t("vwa--search-no-match"),
            "{text}", query)], true);
        return;
    }
    global.vwaShipScanSearch.armed = false;
    global.vwaShipScanSearch.buffer = "";
    if (st.snap == undefined || !st.snap.isSearch)
    {
        st.preSearchCatIx = st.catIx;
    }
    grouped.originTx = cur.tx;
    grouped.originTy = cur.ty;
    grouped.isSearch = true;
    st.snap = grouped;
    st.catIx = 0;
    st.itemIx = 0;
    st.instIx = 0;
    vwa_ship_scan_announce(alliedSide, st, true);
}
