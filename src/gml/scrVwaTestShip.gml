// scrVwaTestShip - Void War Access live ship-layer sweeps, DEV BUILDS ONLY
// (one of the three test scripts; the assertion collector, the selftest,
// and the derive-expectations-live design rule live in scrVwaTest). Two
// SYNCHRONOUS entry points, both invoked through the dev driver's `call`
// command and both requiring the ship mode active with no stacked screen:
//
// - vwa_dev_shipwalk: the walker analog for the spatial mode
//   (scrVwaShipLayer) - a DFS cursor sweep of the FOCUSED hull by real
//   arrow moves. Full spec in its doc comment below.
//
// - vwa_dev_shipscan: the live scanner contract check (scrVwaShipScan) -
//   a category lap, per-entry backend validation, and the browse, jump,
//   return, and search probes. Full spec in its doc comment below.

// ---- the ship-layer cursor sweep ----

// vwa_dev_shipwalk() - the walker analog for the spatial mode
// (scrVwaShipLayer), invoked as `call vwa_dev_shipwalk`. SYNCHRONOUS, one
// call: the ship layer has no per-frame settle, so there is no status
// polling. Requires the ship mode active (in a run, no menu/popup/warp)
// and no stacked screen; sweeps the FOCUSED hull.
//
// DFS by REAL arrow moves (vwa_ship_cursor_move) from the current cursor
// tile: every direction is attempted from every tile, and a successful
// move onto an already-visited tile is immediately walked back, so every
// tile edge gets exercised from both sides. Per attempted move, the
// expected outcome is resolved fresh (geometry lookup, sideData edge,
// vwa_ship_move_plan) and checked against: the cursor's actual movement,
// both feedback channels - the earcon tap (a door crossing or a block
// fires exactly one event, named from the live edge state; interior
// moves fire none) and the speak tap (a moved tile speaks one utterance
// matching a fresh vwa_ship_move_parts render, prefixed by the door
// fallback token only when the earcon reported failure; a block with a
// working earcon is audio-only, its token render expected only on
// earcon failure) - and the game's own connectivity truth - a door crossing's target cell must sit in the
// from-cell's connectedCellList and the door in its doorsList; a
// wall-blocked existing neighbor must still be in adjCellList. The
// cached passability graph (vwa_ship_geom_adj, what the scanner's
// paths ride on) is cross-checked per move: its pass bit must equal
// the move plan's outcome. At the
// end: the visited set must exactly cover the geometry index (membership
// derived live from the built index, never hardcoded), no section may
// have quarantined, and the cursor is restored to its starting tile.
// Returns {checks, failures, tiles, visited, moves}.
function vwa_dev_shipwalk()
{
    if (!vwa_ship_mode_active())
    {
        throw "shipwalk: ship mode is not active";
    }
    if (array_length(global.vwaScreenStack) > 0)
    {
        throw "shipwalk: a screen is stacked";
    }
    var tc = vwa_test_ctx();
    var alliedSide = vwa_ship_focus();
    var geom = vwa_ship_geom(alliedSide);
    var c = vwa_ship_container(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var w = { tap: [], ear: [] };
    // The tap globals are lazily owned (the chokepoints read them through
    // variable_global_exists); a fresh session may reach here before
    // anything has set them.
    var priorTap = variable_global_exists("vwaSpeakTap")
        ? global.vwaSpeakTap : undefined;
    global.vwaSpeakTap = method({ w: w }, function(text, intr)
    {
        array_push(self.w.tap, text);
    });
    var priorEarTap = variable_global_exists("vwaEarconTap")
        ? global.vwaEarconTap : undefined;
    global.vwaEarconTap = method({ w: w }, function(name, ok, info)
    {
        array_push(self.w.ear, { name: name, ok: ok, info: info });
    });
    // The sweep drives hundreds of real moves; earcons still PLAY (the
    // chokepoint's whole path stays under test) but muted, so a
    // dev-driven run does not bombard whoever is at the machine. The
    // flag is restored on every exit path.
    var priorMute = global.vwaEarconMute;
    global.vwaEarconMute = true;
    var startTx = cur.tx;
    var startTy = cur.ty;
    var visited = {};
    variable_struct_set(visited, string(startTx) + "," + string(startTy), true);
    var frames = [{ tx: startTx, ty: startTy, di: 0 }];
    var dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    var moves = 0;
    var moveCap = (geom.count * 10) + 100;
    try
    {
        while (array_length(frames) > 0)
        {
            if (moves >= moveCap)
            {
                vwa_test_ok(tc, "shipwalk: move cap not hit", false,
                    string(moves) + " moves");
                break;
            }
            var fr = frames[array_length(frames) - 1];
            if (fr.di >= 4)
            {
                array_pop(frames);
                if (array_length(frames) > 0)
                {
                    var par = frames[array_length(frames) - 1];
                    vwa_dev_shipwalk_move(tc, w, alliedSide,
                        par.tx - fr.tx, par.ty - fr.ty, true);
                    moves += 1;
                }
                continue;
            }
            var d = dirs[fr.di];
            fr.di += 1;
            var res = vwa_dev_shipwalk_move(tc, w, alliedSide, d[0], d[1], false);
            moves += 1;
            if (!res.moved)
            {
                continue;
            }
            var k = string(fr.tx + d[0]) + "," + string(fr.ty + d[1]);
            if (!variable_struct_exists(visited, k))
            {
                variable_struct_set(visited, k, true);
                array_push(frames, { tx: fr.tx + d[0], ty: fr.ty + d[1], di: 0 });
            }
            else
            {
                vwa_dev_shipwalk_move(tc, w, alliedSide, -d[0], -d[1], true);
                moves += 1;
            }
        }
    }
    catch (err)
    {
        // try/finally is unverified under the importer: restore-and-rethrow.
        global.vwaSpeakTap = priorTap;
        global.vwaEarconTap = priorEarTap;
        global.vwaEarconMute = priorMute;
        throw err;
    }
    global.vwaSpeakTap = priorTap;
    global.vwaEarconTap = priorEarTap;
    global.vwaEarconMute = priorMute;
    var tileKeys = variable_struct_get_names(geom.tiles);
    var missing = 0;
    for (var i = 0; i < array_length(tileKeys); i++)
    {
        if (!variable_struct_exists(visited, tileKeys[i]))
        {
            missing += 1;
        }
    }
    vwa_test_eq(tc, "shipwalk: every hull tile visited", missing, 0);
    vwa_test_eq(tc, "shipwalk: visited count matches the index",
        array_length(variable_struct_get_names(visited)), geom.count);
    vwa_test_eq(tc, "shipwalk: no section quarantined",
        array_length(variable_struct_get_names(c.quar)), 0);
    c.cursor = { tx: startTx, ty: startTy };
    vwa_log("shipwalk: allied " + string(alliedSide) + " done, "
        + string(moves) + " moves, " + string(tc.checks) + " checks, "
        + string(array_length(tc.failures)) + " failures");
    return { checks: tc.checks, failures: tc.failures, tiles: geom.count,
             visited: array_length(variable_struct_get_names(visited)),
             moves: moves };
}

// One attempted move: fresh expected resolve, the game-truth cross-checks,
// then the real move and its speech verified. Returns the ACTUAL cursor
// outcome so the sweep follows reality even through a failing check.
function vwa_dev_shipwalk_move(tc, w, alliedSide, dx, dy, mustMove)
{
    var geom = vwa_ship_geom(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var oldTx = cur.tx;
    var oldTy = cur.ty;
    var fromE = vwa_ship_geom_tile(geom, oldTx, oldTy);
    var toE = vwa_ship_geom_tile(geom, oldTx + dx, oldTy + dy);
    var edge = undefined;
    if (toE == undefined || fromE.cell != toE.cell)
    {
        edge = vwa_ship_edge_resolve(fromE, dx, dy);
    }
    var plan = vwa_ship_move_plan(fromE, toE, edge);
    var tag = string(oldTx) + "," + string(oldTy)
        + " d" + string(dx) + "," + string(dy);
    // The cached passability graph must agree with this move's live
    // resolve - the scanner's path distances and legs ride on it.
    var adjNode = variable_struct_get(vwa_ship_geom_adj(alliedSide),
        string(oldTx) + "," + string(oldTy));
    var dirsTbl = vwa_ship_dirs();
    var dirIx = -1;
    for (var i = 0; i < array_length(dirsTbl); i++)
    {
        if (dirsTbl[i].dx == dx && dirsTbl[i].dy == dy)
        {
            dirIx = i;
            break;
        }
    }
    vwa_test_ok(tc, "shipwalk: passability graph agrees with the plan " + tag,
        adjNode != undefined && dirIx >= 0
            && adjNode.pass[dirIx] == plan.moved,
        (adjNode == undefined) ? "tile not on the graph"
            : ("pass " + string(adjNode.pass[dirIx])
                + " plan " + string(plan.moved)));
    if (plan.moved && plan.cellChanged)
    {
        vwa_test_ok(tc, "shipwalk: door cross agrees with connectedCellList " + tag,
            ds_list_find_index(fromE.cell.connectedCellList, toE.cell) >= 0,
            "target cell not door-connected");
        vwa_test_ok(tc, "shipwalk: crossed door in doorsList " + tag,
            ds_list_find_index(fromE.cell.doorsList, plan.door.inst) >= 0,
            "door not in the cell's doorsList");
    }
    if (!plan.moved && toE != undefined && edge != undefined && edge.kind == "wall")
    {
        vwa_test_ok(tc, "shipwalk: walled neighbor in adjCellList " + tag,
            ds_list_find_index(fromE.cell.adjCellList, toE.cell) >= 0,
            "blocked neighbor not adjacent");
    }
    if (mustMove)
    {
        vwa_test_ok(tc, "shipwalk: return path passable " + tag,
            plan.moved, string(plan.blocked));
    }
    w.tap = [];
    w.ear = [];
    vwa_ship_cursor_move(dx, dy);
    var movedActual = (cur.tx != oldTx || cur.ty != oldTy);
    vwa_test_eq(tc, "shipwalk: cursor agrees with the plan " + tag,
        movedActual, plan.moved);
    if (movedActual)
    {
        vwa_test_ok(tc, "shipwalk: cursor landed " + tag,
            cur.tx == oldTx + dx && cur.ty == oldTy + dy,
            string(cur.tx) + "," + string(cur.ty));
    }
    // Both feedback channels, expectations re-derived from the live edge
    // state (like the airlock speech before the earcon layer). The
    // speech expectation follows the ACTUAL earcon outcome: on a
    // reported earcon failure the never-strand fallback token must
    // speak.
    if (plan.moved)
    {
        if (plan.cellChanged)
        {
            vwa_test_ok(tc, "shipwalk: door-cross earcon " + tag,
                array_length(w.ear) == 1
                    && w.ear[0].name == vwa_ship_door_earcon(edge.inst.state),
                vwa_dev_shipwalk_earjoin(w.ear));
        }
        else
        {
            vwa_test_ok(tc, "shipwalk: no earcon inside a cell " + tag,
                array_length(w.ear) == 0, vwa_dev_shipwalk_earjoin(w.ear));
        }
        var pref = [];
        if (plan.cellChanged
            && !(array_length(w.ear) == 1 && w.ear[0].ok))
        {
            array_push(pref, vwa_t(vwa_ship_door_token(edge.inst.state)));
        }
        var body = vwa_ship_move_parts(alliedSide, toE,
            { cellChanged: plan.cellChanged,
              tx: oldTx + dx, ty: oldTy + dy, cx: geom.cx, cy: geom.cy });
        for (var i = 0; i < array_length(body); i++)
        {
            array_push(pref, body[i]);
        }
        vwa_test_ok(tc, "shipwalk: one utterance " + tag,
            array_length(w.tap) == 1, vwa_test_join(w.tap));
        if (array_length(w.tap) == 1)
        {
            vwa_test_eq(tc, "shipwalk: speech " + tag, w.tap[0],
                vwa_speak_render(pref));
        }
    }
    else
    {
        var wantEar = "wall-block";
        var blockedKey = "vwa--ship-wall";
        if (plan.blocked == "airlock")
        {
            wantEar = (edge.inst.state == 1)
                ? "airlock-closed-block" : "airlock-open-block";
            blockedKey = (edge.inst.state == 1)
                ? "vwa--ship-airlock-closed" : "vwa--ship-airlock-open";
        }
        vwa_test_ok(tc, "shipwalk: block earcon " + tag,
            array_length(w.ear) == 1 && w.ear[0].name == wantEar,
            vwa_dev_shipwalk_earjoin(w.ear));
        if (array_length(w.ear) == 1 && w.ear[0].ok)
        {
            vwa_test_ok(tc, "shipwalk: block is audio-only " + tag,
                array_length(w.tap) == 0, vwa_test_join(w.tap));
        }
        else
        {
            vwa_test_ok(tc, "shipwalk: block fallback spoke " + tag,
                array_length(w.tap) == 1
                    && w.tap[0] == vwa_speak_render([vwa_t(blockedKey)]),
                vwa_test_join(w.tap));
        }
    }
    return { moved: movedActual };
}

// Earcon tap entries joined into a check's detail string.
function vwa_dev_shipwalk_earjoin(ear)
{
    var s = "";
    for (var i = 0; i < array_length(ear); i++)
    {
        if (i > 0)
        {
            s += " | ";
        }
        s += ear[i].name + (ear[i].ok ? "" : " (failed)");
    }
    return (s == "") ? "(no earcons)" : s;
}

// ---- the ship-scanner live check ----

// vwa_dev_shipscan() - live scanner contract check (scrVwaShipScan),
// invoked as `call vwa_dev_shipscan`. SYNCHRONOUS. Requires the ship
// mode active and no stacked screen; checks the FOCUSED hull. One full
// category lap through the real cycle handler: per press exactly one
// utterance whose text matches a fresh announce compose, landing only on
// non-empty categories (the skip rule; the bare empty token when every
// category is empty), and the earcon channel verified per announcement
// (vwa_dev_shipscan_earcheck: the direction tone with its straight-line
// offset on every entry announcement, the wrap click exactly on item/
// instance wraps, silence on jump and return; earcons run muted with
// the tone toggle forced on, both restored); after each rebuild every snapshot entry - of all
// categories, skipped ones included - must pass its own backend's
// resolve, sit in its category, carry a stable key, and honor the
// visibility gate
// (gated entries only on vision-true cells), with per-category totals
// cross-checked against direct live enumeration (deduplicated crew on
// visible cells, distinct visible systems, per-type hazard rooms) -
// membership derived live, never hardcoded. Then, on the first non-empty
// category: an identity-preserving refresh must re-seat the browse on
// the same entry key; an item cycle, an instance cycle, and an orient
// speak one verified utterance each; a Home jump's cursor must land on
// the entry's resolved tile with the full-tile-read utterance and a
// Backspace return must land it back where it left; and a live search
// apply (query = a prefix of a real item name) must install a frozen
// search snapshot whose every entry matches the query and resolves,
// with the category cycle exiting it back to a normal snapshot at the
// pre-search category. Scanner state and cursor are restored, the
// snapshot dropped; no section may have quarantined.
// Returns {checks, failures, entries}.
function vwa_dev_shipscan()
{
    if (!vwa_ship_mode_active())
    {
        throw "shipscan: ship mode is not active";
    }
    if (array_length(global.vwaScreenStack) > 0)
    {
        throw "shipscan: a screen is stacked";
    }
    var tc = vwa_test_ctx();
    var alliedSide = vwa_ship_focus();
    var st = vwa_ship_scan_state(alliedSide);
    var geom = vwa_ship_geom(alliedSide);
    var c = vwa_ship_container(alliedSide);
    var cur = vwa_ship_cursor(alliedSide);
    var save = { catIx: st.catIx, itemIx: st.itemIx, instIx: st.instIx,
                 tx: cur.tx, ty: cur.ty };
    var w = { tap: [], ear: [] };
    var priorTap = variable_global_exists("vwaSpeakTap")
        ? global.vwaSpeakTap : undefined;
    global.vwaSpeakTap = method({ w: w }, function(text, intr)
    {
        array_push(self.w.tap, text);
    });
    var priorEarTap = variable_global_exists("vwaEarconTap")
        ? global.vwaEarconTap : undefined;
    global.vwaEarconTap = method({ w: w }, function(name, ok, info)
    {
        array_push(self.w.ear, { name: name, ok: ok, info: info });
    });
    // Earcons play muted through the whole check (the walker's rule: the
    // full chokepoint path under test without bombarding the machine);
    // the direction-tone toggle is forced on so the tone channel is
    // always exercised. Both restored on every exit path.
    var priorMute = global.vwaEarconMute;
    var priorTones = global.vwaEarconDirTones;
    global.vwaEarconMute = true;
    global.vwaEarconDirTones = true;
    var total = 0;
    try
    {
        // The category lap: nCats presses through the real handler. The
        // game is frozen within this call (the dev pump runs one command
        // per frame), so a recompute of the same announce must render
        // identically. The cycle skips empty categories, so every landing
        // must be non-empty (bare empty token when everything is); ALL
        // categories of each fresh snapshot are validated, landed on or
        // skipped - the want-zero cross-check on an empty category is the
        // vision gate's negative test.
        var nCats = array_length(vwa_ship_scan_cats());
        var firstFull = -1;
        for (var lap = 0; lap < nCats; lap++)
        {
            w.tap = [];
            w.ear = [];
            vwa_ship_scan_cat_cycle(1);
            var anyFull = false;
            for (var ci = 0; ci < array_length(st.snap.cats); ci++)
            {
                if (array_length(st.snap.cats[ci].items) > 0)
                {
                    anyFull = true;
                    break;
                }
            }
            var catKey = st.snap.cats[st.catIx].key;
            vwa_test_ok(tc, "shipscan: one utterance on category press " + string(lap),
                array_length(w.tap) == 1, vwa_test_join(w.tap));
            if (array_length(w.tap) == 1)
            {
                if (anyFull)
                {
                    vwa_test_ok(tc, "shipscan: cycle skips empty categories (" + catKey + ")",
                        array_length(st.snap.cats[st.catIx].items) > 0,
                        "landed on an empty category");
                    vwa_test_eq(tc, "shipscan: category speech " + catKey, w.tap[0],
                        vwa_speak_render(
                            vwa_ship_scan_announce_parts(alliedSide, st, true)));
                }
                else
                {
                    vwa_test_eq(tc, "shipscan: all-empty speaks the bare token",
                        w.tap[0],
                        vwa_speak_render([vwa_t("vwa--ship-scan-empty")]));
                }
            }
            if (anyFull)
            {
                vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear, false,
                    "cat press " + string(lap));
            }
            else
            {
                vwa_test_eq(tc, "shipscan: all-empty fires no earcon",
                    vwa_dev_shipwalk_earjoin(w.ear), "(no earcons)");
            }
            total = 0;
            for (var ci = 0; ci < array_length(st.snap.cats); ci++)
            {
                total += vwa_dev_shipscan_validate(tc, alliedSide, st, geom, ci);
            }
            if (firstFull < 0 && array_length(st.snap.cats[st.catIx].items) > 0)
            {
                firstFull = st.catIx;
            }
        }
        if (firstFull >= 0)
        {
            st.catIx = firstFull;
            st.itemIx = 0;
            st.instIx = 0;
            // The identity-preserving refresh: same entity, same key,
            // after a full rebuild.
            var keyBefore = vwa_ship_scan_current_key(st);
            var rr = vwa_ship_scan_refresh(alliedSide, st);
            vwa_test_ok(tc, "shipscan: refresh preserves identity",
                !rr.built && !rr.lost
                    && vwa_ship_scan_current_key(st) == keyBefore,
                string(keyBefore) + " -> " + string(vwa_ship_scan_current_key(st)));
            // Wrap expectation derived live: from index 0, one forward
            // step wraps exactly when the list holds a single item (the
            // wrap click joins the direction tone in one event).
            var wrapItem =
                (array_length(st.snap.cats[st.catIx].items) == 1);
            w.tap = [];
            w.ear = [];
            vwa_ship_scan_item_cycle(1);
            vwa_test_ok(tc, "shipscan: one utterance on item cycle",
                array_length(w.tap) == 1, vwa_test_join(w.tap));
            if (array_length(w.tap) == 1)
            {
                vwa_test_eq(tc, "shipscan: item cycle speech", w.tap[0],
                    vwa_speak_render(
                        vwa_ship_scan_announce_parts(alliedSide, st, false)));
            }
            vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear, wrapItem,
                "item cycle");
            var wrapInst = (array_length(
                st.snap.cats[st.catIx].items[st.itemIx].entries) == 1);
            w.tap = [];
            w.ear = [];
            vwa_ship_scan_inst_cycle(1);
            vwa_test_ok(tc, "shipscan: one utterance on instance cycle",
                array_length(w.tap) == 1, vwa_test_join(w.tap));
            vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear, wrapInst,
                "instance cycle");
            w.tap = [];
            w.ear = [];
            vwa_ship_scan_orient();
            vwa_test_ok(tc, "shipscan: one utterance on orient",
                array_length(w.tap) == 1, vwa_test_join(w.tap));
            if (array_length(w.tap) == 1)
            {
                vwa_test_eq(tc, "shipscan: orient speech", w.tap[0],
                    vwa_speak_render(
                        vwa_ship_scan_announce_parts(alliedSide, st, false)));
            }
            vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear, false,
                "orient");
            var curE = vwa_ship_scan_current(alliedSide, st);
            vwa_test_ok(tc, "shipscan: current entry resolves for the jump",
                curE != undefined, "none");
            if (curE != undefined)
            {
                var fromTx = cur.tx;
                var fromTy = cur.ty;
                w.tap = [];
                w.ear = [];
                vwa_ship_scan_jump();
                vwa_test_ok(tc, "shipscan: cursor landed on the entry",
                    cur.tx == curE.res.tx && cur.ty == curE.res.ty,
                    string(cur.tx) + "," + string(cur.ty));
                vwa_test_eq(tc, "shipscan: jump fires no scanner earcon",
                    vwa_dev_shipwalk_earjoin(w.ear), "(no earcons)");
                var entryTile = vwa_ship_geom_tile(geom, cur.tx, cur.ty);
                vwa_test_ok(tc, "shipscan: one utterance on jump",
                    array_length(w.tap) == 1, vwa_test_join(w.tap));
                if (array_length(w.tap) == 1 && entryTile != undefined)
                {
                    vwa_test_eq(tc, "shipscan: jump speech", w.tap[0],
                        vwa_speak_render(vwa_ship_move_parts(alliedSide,
                            entryTile, vwa_ship_read_ctx(geom, cur))));
                }
                // Backspace return, only when the jump actually moved
                // (an in-place jump keeps the anchor by design).
                if (cur.tx != fromTx || cur.ty != fromTy)
                {
                    w.tap = [];
                    w.ear = [];
                    vwa_ship_scan_return();
                    vwa_test_ok(tc, "shipscan: return lands on the pre-jump tile",
                        cur.tx == fromTx && cur.ty == fromTy,
                        string(cur.tx) + "," + string(cur.ty));
                    vwa_test_ok(tc, "shipscan: one utterance on return",
                        array_length(w.tap) == 1, vwa_test_join(w.tap));
                    vwa_test_eq(tc, "shipscan: return fires no scanner earcon",
                        vwa_dev_shipwalk_earjoin(w.ear), "(no earcons)");
                    w.tap = [];
                    vwa_ship_scan_return();
                    vwa_test_ok(tc, "shipscan: second return refuses",
                        array_length(w.tap) == 1
                            && w.tap[0] == vwa_speak_render(
                                [vwa_t("vwa--ship-scan-no-return")]),
                        vwa_test_join(w.tap));
                }
            }
            // Live search: a prefix of a real item name must match; the
            // installed snapshot is frozen, every entry resolves and
            // matches; the category cycle exits back to a normal
            // snapshot at the pre-search category.
            var itemName = st.snap.cats[st.catIx].items[0].name;
            var q = string_copy(string(itemName), 1,
                min(3, string_length(string(itemName))));
            var preCat = st.catIx;
            w.tap = [];
            w.ear = [];
            vwa_ship_scan_search_apply(q);
            vwa_test_ok(tc, "shipscan: one utterance on search apply",
                array_length(w.tap) == 1, vwa_test_join(w.tap));
            vwa_test_ok(tc, "shipscan: search snapshot installed",
                st.snap.isSearch == true, "not a search snapshot");
            if (st.snap.isSearch)
            {
                vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear, false,
                    "search apply");
            }
            if (st.snap.isSearch)
            {
                var sitems = st.snap.cats[0].items;
                vwa_test_ok(tc, "shipscan: search found the seed item",
                    array_length(sitems) > 0, "no items");
                for (var i = 0; i < array_length(sitems); i++)
                {
                    vwa_test_ok(tc, "shipscan: search item matches "
                        + string(sitems[i].name),
                        vwa_search_match_tier(string(sitems[i].name), q).tier >= 0,
                        "tier below zero");
                    for (var j = 0; j < array_length(sitems[i].entries); j++)
                    {
                        var se = sitems[i].entries[j];
                        vwa_test_ok(tc, "shipscan: search entry resolves "
                            + string(se.item),
                            vwa_ship_scan_backend(se.cat)
                                .resolve(alliedSide, geom, se) != undefined,
                            "stale in a fresh search snapshot");
                    }
                }
                w.tap = [];
                w.ear = [];
                vwa_ship_scan_cat_cycle(1);
                vwa_test_ok(tc, "shipscan: category cycle exits search",
                    !st.snap.isSearch, "still a search snapshot");
                // The expected landing derives through the skip rule on
                // the fresh snapshot: the next NON-EMPTY category after
                // the pre-search one.
                var wantIx = vwa_scan_next_nonempty(st.snap.cats, preCat, 1);
                if (wantIx >= 0)
                {
                    vwa_test_eq(tc, "shipscan: search exit restores the category",
                        st.catIx, wantIx);
                    vwa_dev_shipscan_earcheck(tc, alliedSide, st, w.ear,
                        false, "search exit");
                }
            }
        }
        else
        {
            vwa_log("shipscan: every category empty (browse keys not exercised)");
        }
    }
    catch (err)
    {
        // try/finally is unverified under the importer: restore-and-rethrow.
        global.vwaSpeakTap = priorTap;
        global.vwaEarconTap = priorEarTap;
        global.vwaEarconMute = priorMute;
        global.vwaEarconDirTones = priorTones;
        c.cursor = { tx: save.tx, ty: save.ty };
        st.catIx = save.catIx;
        st.itemIx = save.itemIx;
        st.instIx = save.instIx;
        st.snap = undefined;
        st.preJump = undefined;
        st.preSearchCatIx = undefined;
        throw err;
    }
    global.vwaSpeakTap = priorTap;
    global.vwaEarconTap = priorEarTap;
    global.vwaEarconMute = priorMute;
    global.vwaEarconDirTones = priorTones;
    c.cursor = { tx: save.tx, ty: save.ty };
    st.catIx = save.catIx;
    st.itemIx = save.itemIx;
    st.instIx = save.instIx;
    st.snap = undefined;
    st.preJump = undefined;
    st.preSearchCatIx = undefined;
    vwa_test_eq(tc, "shipscan: no section quarantined",
        array_length(variable_struct_get_names(c.quar)), 0);
    vwa_log("shipscan: allied " + string(alliedSide) + " done, "
        + string(total) + " entries, " + string(tc.checks) + " checks, "
        + string(array_length(tc.failures)) + " failures");
    return { checks: tc.checks, failures: tc.failures, entries: total };
}

// One scanner announcement's earcon channel verified: the tap holds
// exactly the expected events in order (scan-wrap only on a wrap,
// always before the tone; the earjoin's failed-markers make a
// failed-to-start sound break the equality), and the direction tone's
// offset matches a fresh STRAIGHT-LINE compute from the live cursor to
// the current entry - the spatial-pointer contract, deliberately not
// the spoken walking legs.
function vwa_dev_shipscan_earcheck(tc, alliedSide, st, ear, wantWrap, tag)
{
    vwa_test_eq(tc, "shipscan: earcon events on " + tag,
        vwa_dev_shipwalk_earjoin(ear),
        wantWrap ? "scan-wrap | scan-dir" : "scan-dir");
    var d = undefined;
    for (var i = 0; i < array_length(ear); i++)
    {
        if (ear[i].name == "scan-dir")
        {
            d = ear[i];
        }
    }
    if (d == undefined)
    {
        return;
    }
    var curE = vwa_ship_scan_current(alliedSide, st);
    var cur = vwa_ship_cursor(alliedSide);
    vwa_test_ok(tc, "shipscan: tone is the straight-line offset on " + tag,
        curE != undefined && d.info != undefined
            && d.info.up == cur.ty - curE.res.ty
            && d.info.rt == curE.res.tx - cur.tx,
        (d.info == undefined) ? "no info"
            : (string(d.info.up) + "," + string(d.info.rt)));
}

// One just-rebuilt category validated (by index - skipped-over empty
// categories get checked too): every entry re-resolves through its own
// backend, wears the right category, honors the vision gate; the entry
// total matches a direct, independent live enumeration. Returns the
// entry count.
function vwa_dev_shipscan_validate(tc, alliedSide, st, geom, catIx)
{
    var cat = st.snap.cats[catIx];
    var b = vwa_ship_scan_backend(cat.key);
    var n = 0;
    for (var i = 0; i < array_length(cat.items); i++)
    {
        var item = cat.items[i];
        for (var j = 0; j < array_length(item.entries); j++)
        {
            var e = item.entries[j];
            n += 1;
            vwa_test_eq(tc, "shipscan: entry category " + cat.key, e.cat, cat.key);
            vwa_test_ok(tc, "shipscan: entry carries a key " + string(e.item),
                is_string(e.key) && e.key != "", string(e.key));
            var res = b.resolve(alliedSide, geom, e);
            vwa_test_ok(tc, "shipscan: fresh entry resolves " + cat.key
                + " " + string(e.item), res != undefined,
                "stale immediately after rebuild");
            if (cat.key != "systems")
            {
                vwa_test_ok(tc, "shipscan: gated entry has vision " + cat.key
                    + " " + string(e.item), e.cell.playerHasVision,
                    "vision-false cell in a gated category");
            }
        }
    }
    var want = 0;
    var cells = vwa_ship_scan_cells(geom);
    if (cat.key == "my-crew" || cat.key == "enemy-crew")
    {
        var channel = (cat.key == "my-crew") ? 1 : 0;
        var seen = [];
        for (var i = 0; i < array_length(cells); i++)
        {
            var cc = cells[i].cell;
            if (!cc.playerHasVision)
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
                }
            }
        }
        want = array_length(seen);
    }
    else if (cat.key == "systems")
    {
        var seenSys = [];
        for (var i = 0; i < array_length(cells); i++)
        {
            var cc = cells[i].cell;
            if (cc.system != 0
                && vwa_ship_scan_cell_visible(alliedSide, cc, false)
                && vwa_array_index_of(seenSys, cc.system) < 0)
            {
                array_push(seenSys, cc.system);
                want += 1;
            }
        }
    }
    else
    {
        var types = ["fire", "warpfire", "breach"];
        for (var i = 0; i < array_length(cells); i++)
        {
            var cc = cells[i].cell;
            if (!cc.playerHasVision)
            {
                continue;
            }
            for (var j = 0; j < array_length(types); j++)
            {
                if (vwa_ship_scan_hazard_count(cc, types[j]) > 0)
                {
                    want += 1;
                }
            }
        }
    }
    vwa_test_eq(tc, "shipscan: " + cat.key + " total matches live enumeration",
        n, want);
    return n;
}
