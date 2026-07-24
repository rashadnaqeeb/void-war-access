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
    vwa_test_gate(tc);
    vwa_test_graph(tc);
    vwa_test_announce(tc);
    vwa_test_search(tc);
    vwa_test_ship(tc);
    vwa_test_encounter(tc);
    vwa_test_shiplayer(tc);
    return { checks: tc.checks, failures: tc.failures };
}

// The ship-layer substrate (scrVwaShipLayer): the pure geometry-index
// builder and focus decision on fixtures, plus the mode-provider
// suspension rule in vwa_live_categories (live globals saved/restored,
// the gate-test pattern) and the live mode gate outside a run.
function vwa_test_shiplayer(tc)
{
    // A wide cell (two tiles across the top) and a single below-left,
    // world coords deliberately off-origin: origin normalization is under
    // test. Slot coords are tile centers, as scrInitializeRoom lays them.
    var g = vwa_ship_geom_build([
        { sx: 738, sy: 306, cell: "wide", slot: 1 },
        { sx: 774, sy: 306, cell: "wide", slot: 2 },
        { sx: 738, sy: 342, cell: "single", slot: 1 }
    ]);
    vwa_test_eq(tc, "shiplayer: geom tile count", g.count, 3);
    vwa_test_eq(tc, "shiplayer: geom dupes", g.dupes, 0);
    vwa_test_eq(tc, "shiplayer: geom width", g.w, 2);
    vwa_test_eq(tc, "shiplayer: geom height", g.h, 2);
    var t = vwa_ship_geom_tile(g, 1, 0);
    vwa_test_ok(tc, "shiplayer: tile 1,0 resolves", t != undefined, "missing");
    if (t != undefined)
    {
        vwa_test_eq(tc, "shiplayer: tile 1,0 cell", t.cell, "wide");
        vwa_test_eq(tc, "shiplayer: tile 1,0 slot", t.slot, 2);
    }
    vwa_test_eq(tc, "shiplayer: off-hull tile undefined",
        vwa_ship_geom_tile(g, 1, 1), undefined);
    vwa_test_ok(tc, "shiplayer: default tile top-left",
        g.defaultTile.tx == 0 && g.defaultTile.ty == 0,
        string(g.defaultTile.tx) + "," + string(g.defaultTile.ty));
    vwa_test_ok(tc, "shiplayer: 2x2 origin at the left/upper center tile",
        g.cx == 0 && g.cy == 0, string(g.cx) + "," + string(g.cy));

    // Default tile picks minimum row first, then minimum column.
    var g2 = vwa_ship_geom_build([
        { sx: 36, sy: 0, cell: "a", slot: 1 },
        { sx: 0, sy: 36, cell: "b", slot: 1 }
    ]);
    vwa_test_ok(tc, "shiplayer: default tile row-major",
        g2.defaultTile.tx == 1 && g2.defaultTile.ty == 0,
        string(g2.defaultTile.tx) + "," + string(g2.defaultTile.ty));

    // Duplicate tile: first record kept, dupe counted for the caller's log.
    var g3 = vwa_ship_geom_build([
        { sx: 0, sy: 0, cell: "a", slot: 1 },
        { sx: 0, sy: 0, cell: "b", slot: 1 }
    ]);
    vwa_test_eq(tc, "shiplayer: dupe counted", g3.dupes, 1);
    vwa_test_eq(tc, "shiplayer: dupe keeps first", vwa_ship_geom_tile(g3, 0, 0).cell, "a");

    // The Tab decision.
    var f = vwa_ship_focus_next(1, false);
    vwa_test_eq(tc, "shiplayer: toggle blocked without enemy", f.blocked, true);
    f = vwa_ship_focus_next(1, true);
    vwa_test_ok(tc, "shiplayer: player to enemy", !f.blocked && f.allied == 0, string(f.allied));
    f = vwa_ship_focus_next(0, true);
    vwa_test_ok(tc, "shiplayer: enemy to player", !f.blocked && f.allied == 1, string(f.allied));
    f = vwa_ship_focus_next(0, false);
    vwa_test_ok(tc, "shiplayer: enemy to player without enemy",
        !f.blocked && f.allied == 1, string(f.allied));

    // The movement decision on fixture entries (cell identity is struct
    // reference equality): interior free, door passes whatever its state,
    // wall and airlock block, off-hull blocks, a missing edge instance
    // blocks as a wall and flags for the caller's log.
    var ca = { t: "a" };
    var cb = { t: "b" };
    var fA1 = { cell: ca, slot: 1 };
    var fA2 = { cell: ca, slot: 2 };
    var fB = { cell: cb, slot: 1 };
    var mp = vwa_ship_move_plan(fA1, fA2, undefined);
    vwa_test_ok(tc, "shiplayer: interior move free",
        mp.moved && !mp.cellChanged && mp.door == undefined, string(mp));
    for (var ds = 0; ds <= 2; ds++)
    {
        mp = vwa_ship_move_plan(fA1, fB,
            { kind: "door", doorState: ds, inst: undefined });
        vwa_test_ok(tc, "shiplayer: door state " + string(ds) + " passes",
            mp.moved && mp.cellChanged && mp.door != undefined
                && mp.door.doorState == ds, string(mp));
    }
    mp = vwa_ship_move_plan(fA1, fB, { kind: "wall", doorState: undefined, inst: undefined });
    vwa_test_ok(tc, "shiplayer: wall blocks",
        !mp.moved && mp.blocked == "wall" && !mp.missingEdge, string(mp));
    mp = vwa_ship_move_plan(fA1, fB, { kind: "airlock", doorState: undefined, inst: undefined });
    vwa_test_ok(tc, "shiplayer: airlock blocks",
        !mp.moved && mp.blocked == "airlock", string(mp));
    mp = vwa_ship_move_plan(fA1, undefined, { kind: "airlock", doorState: undefined, inst: undefined });
    vwa_test_ok(tc, "shiplayer: off-hull airlock edge blocks as airlock",
        !mp.moved && mp.blocked == "airlock" && !mp.missingEdge, string(mp));
    mp = vwa_ship_move_plan(fA1, undefined, undefined);
    vwa_test_ok(tc, "shiplayer: off-hull with no edge blocks as wall",
        !mp.moved && mp.blocked == "wall" && mp.missingEdge, string(mp));
    mp = vwa_ship_move_plan(fA1, fB, undefined);
    vwa_test_ok(tc, "shiplayer: cross-cell missing edge blocks and flags",
        !mp.moved && mp.blocked == "wall" && mp.missingEdge, string(mp));

    // Edge classification against the real object table.
    vwa_test_eq(tc, "shiplayer: oDoor is a door", vwa_ship_side_kind(oDoor), "door");
    vwa_test_eq(tc, "shiplayer: oAirlock is an airlock",
        vwa_ship_side_kind(oAirlock), "airlock");
    vwa_test_eq(tc, "shiplayer: oWall is a wall", vwa_ship_side_kind(oWall), "wall");
    vwa_test_eq(tc, "shiplayer: oWall_dungeon is a wall",
        vwa_ship_side_kind(oWall_dungeon), "wall");
    vwa_test_eq(tc, "shiplayer: bare oCellSide is unknown",
        vwa_ship_side_kind(oCellSide), undefined);

    // The composer runner on fixture sections: order kept, a throwing
    // section quarantines (once) while the rest still run. The quarantine
    // log line this writes is the sanctioned once-per-quarantine log.
    var quar = {};
    var fsecs = [
        { name: "cellsec", slotLevel: false, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            return ctx.cellChanged ? ["CELL"] : [];
        } },
        // The marker phrase keeps the smoke's ERROR-line diff from
        // counting this deliberate quarantine log (see ModLogErrorCount).
        { name: "boom", slotLevel: false, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            throw "injected test fault (section quarantine)";
        } },
        { name: "slotsec", slotLevel: true, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            return ["SLOT"];
        } }
    ];
    var ctxT = { cellChanged: true, door: undefined, tx: 0, ty: 0,
                 vision: true };
    vwa_test_eq(tc, "shiplayer: composer runs past a throw",
        vwa_test_join(vwa_ship_compose_run(fsecs, quar, undefined, undefined, 1, ctxT)),
        "CELL | SLOT");
    vwa_test_ok(tc, "shiplayer: throwing section quarantined",
        variable_struct_exists(quar, "boom"), "not quarantined");
    var ctxF = { cellChanged: false, door: undefined, tx: 0, ty: 0,
                 vision: true };
    vwa_test_eq(tc, "shiplayer: cell fixture dampens when cell unchanged",
        vwa_test_join(vwa_ship_compose_run(fsecs, quar, undefined, undefined, 1, ctxF)),
        "SLOT");
    vwa_test_eq(tc, "shiplayer: quarantine holds across reruns",
        array_length(variable_struct_get_names(quar)), 1);

    // The visibility gate lives in the composer: with vision false every
    // interior section is skipped and one "interior unknown" token speaks
    // in the first one's place - only on a cell change (a dark room
    // announces on entry, not per step); geometry sections still run at
    // both levels.
    var gsecs = [
        { name: "geo-cell", slotLevel: false, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            return ctx.cellChanged ? ["GEOC"] : [];
        } },
        { name: "int-cell", slotLevel: false, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            return ctx.cellChanged ? ["INTC"] : [];
        } },
        { name: "int-slot", slotLevel: true, interior: true,
          read: function(hull, cell, slot, ctx)
        {
            return ["INTS"];
        } },
        { name: "geo-slot", slotLevel: true, interior: false,
          read: function(hull, cell, slot, ctx)
        {
            return ["GEOS"];
        } }
    ];
    var gq = {};
    vwa_test_eq(tc, "shiplayer: vision true runs every section",
        vwa_test_join(vwa_ship_compose_run(gsecs, gq, undefined, undefined, 1,
            { cellChanged: true, door: undefined, vision: true })),
        "GEOC | INTC | INTS | GEOS");
    vwa_test_eq(tc, "shiplayer: vision false speaks unknown in place",
        vwa_test_join(vwa_ship_compose_run(gsecs, gq, undefined, undefined, 1,
            { cellChanged: true, door: undefined, vision: false })),
        "GEOC | " + vwa_t("vwa--ship-unknown") + " | GEOS");
    vwa_test_eq(tc, "shiplayer: dark within-room step stays terse",
        vwa_test_join(vwa_ship_compose_run(gsecs, gq, undefined, undefined, 1,
            { cellChanged: false, door: undefined, vision: false })),
        "GEOS");

    // One/many count wording: silent at zero, bare token at one,
    // templated above.
    vwa_test_eq(tc, "shiplayer: count zero silent",
        array_length(vwa_ship_count_parts(0,
            "vwa--ship-fire-one", "vwa--ship-fire-many")), 0);
    vwa_test_eq(tc, "shiplayer: count one bare token",
        vwa_test_join(vwa_ship_count_parts(1,
            "vwa--ship-fire-one", "vwa--ship-fire-many")),
        vwa_t("vwa--ship-fire-one"));
    vwa_test_eq(tc, "shiplayer: count many templated",
        vwa_test_join(vwa_ship_count_parts(3,
            "vwa--ship-fire-one", "vwa--ship-fire-many")),
        vwa_sheet_t("vwa--ship-fire-many", ["n"], [3]));

    // Signed spoken coordinates: negatives carry the localized minus word.
    vwa_test_eq(tc, "shiplayer: positive coord plain", vwa_ship_coord_str(3), "3");
    vwa_test_eq(tc, "shiplayer: zero coord plain", vwa_ship_coord_str(0), "0");
    vwa_test_eq(tc, "shiplayer: negative coord speaks minus",
        vwa_ship_coord_str(-2), vwa_t("vwa--minus") + " 2");

    // The real registry: every section declares its flags, and with the
    // cell unchanged every cell-level section bails before touching the
    // (dummy) cell. Slot-level sections read live instances and are
    // exercised by the live shipwalk, not fixtures.
    var dctx = { cellChanged: false, door: undefined, tx: 4, ty: 2,
                 cx: 1, cy: 3, vision: true };
    for (var i = 0; i < array_length(global.vwaShipSections); i++)
    {
        var sec = global.vwaShipSections[i];
        vwa_test_ok(tc, "shiplayer: section " + sec.name + " declares flags",
            is_bool(sec.slotLevel) && is_bool(sec.interior), "missing flags");
        if (!sec.slotLevel)
        {
            vwa_test_eq(tc, "shiplayer: section " + sec.name + " dampens",
                array_length(sec.read(undefined, {}, 1, dctx)), 0);
        }
    }
    // The position stub speaks every move - center-origin x/y, y positive
    // up, matching its own live template (tile 4,2 with origin 1,3 is
    // x 3, y 1; tile 0,4 is x minus 1, y minus 1).
    var posSec = vwa_ship_section_get("position");
    vwa_test_eq(tc, "shiplayer: position section speaks every move",
        vwa_test_join(posSec.read(undefined, {}, 1, dctx)),
        vwa_sheet_t("vwa--ship-pos", ["x", "y"], ["3", "1"]));
    var nctx = { cellChanged: false, door: undefined, tx: 0, ty: 4,
                 cx: 1, cy: 3, vision: true };
    vwa_test_eq(tc, "shiplayer: position section negative coords",
        vwa_test_join(posSec.read(undefined, {}, 1, nctx)),
        vwa_sheet_t("vwa--ship-pos", ["x", "y"],
            [vwa_t("vwa--minus") + " 1", vwa_t("vwa--minus") + " 1"]));

    // The where-am-I read: position, then the system name, then the
    // shape word (name before shape, like every tile read), through the
    // real registry sections on a fixture cell (geometry-only, so safe
    // outside a run). Tile 2,1 with origin 1,3 is x 1, y 2.
    var wcell = { object_index: oCellSingle,
                  system: { name: "Test System", currHP: 2, maxHP: 2 } };
    var wctx = { cellChanged: true, door: undefined, tx: 2, ty: 1,
                 cx: 1, cy: 3, vision: true };
    vwa_test_eq(tc, "shiplayer: where reads position, name, then shape",
        vwa_test_join(vwa_ship_compose_run(vwa_ship_where_sections(), {},
            undefined, wcell, 1, wctx)),
        vwa_sheet_t("vwa--ship-pos", ["x", "y"], ["1", "2"])
            + " | Test System | " + vwa_t("vwa--ship-room-small"));

    // Mode-provider suspension: a mode category is live only while the
    // screen stack is empty. Live globals saved and restored.
    var priorStack = global.vwaScreenStack;
    var priorModes = global.vwaModes;
    global.vwaScreenStack = [];
    global.vwaModes = [{ key: "test-mode", category: "test-mode-cat",
        isActive: function() { return true; } }];
    var cats = vwa_live_categories();
    vwa_test_ok(tc, "shiplayer: mode category live on empty stack",
        vwa_array_index_of(cats, "test-mode-cat") >= 0, vwa_test_join(cats));
    global.vwaScreenStack = [{ key: "test-screen", categories: [], exclusive: false }];
    cats = vwa_live_categories();
    vwa_test_ok(tc, "shiplayer: stacked screen suspends mode",
        vwa_array_index_of(cats, "test-mode-cat") < 0, vwa_test_join(cats));
    global.vwaScreenStack = priorStack;
    global.vwaModes = priorModes;

    // Live gate: outside a run the ship mode must be inactive and its
    // category dead (derived live; the in-run positive case is exercised
    // by playing, not fixtures).
    if (!global.gameStarted)
    {
        vwa_test_eq(tc, "shiplayer: mode inactive outside a run",
            vwa_ship_mode_active(), false);
        vwa_test_ok(tc, "shiplayer: ship category dead outside a run",
            vwa_array_index_of(vwa_live_categories(), "ship") < 0,
            vwa_test_join(vwa_live_categories()));
    }
}

// The game-key gate predicates (scrVwaInput): deny by default on both
// axes, an allowance flips exactly the named key, and the watchdog's
// fail-open flag overrides both lists. The gate is live state, not a
// fixture - every touched global is saved and restored.
function vwa_test_gate(tc)
{
    var priorOpen = global.vwaGameKeysOpen;
    var bindWas = variable_struct_exists(global.vwaGameAllowBinds, "vwa-test-bind");
    var vkWas = variable_struct_exists(global.vwaGameAllowVks, "999");
    global.vwaGameKeysOpen = false;
    vwa_test_eq(tc, "gate: unknown bind denied", vwa_game_bind_allowed("vwa-test-bind"), false);
    vwa_test_eq(tc, "gate: unknown vk denied", vwa_game_vk_allowed(999), false);
    vwa_test_eq(tc, "gate: escape on the base allowance", vwa_game_vk_allowed(vk_escape), true);
    vwa_game_allow_bind("vwa-test-bind", true);
    vwa_test_eq(tc, "gate: allowed bind passes", vwa_game_bind_allowed("vwa-test-bind"), true);
    vwa_game_allow_bind("vwa-test-bind", false);
    vwa_test_eq(tc, "gate: revoked bind denied again", vwa_game_bind_allowed("vwa-test-bind"), false);
    vwa_game_allow_vk(999, true);
    vwa_test_eq(tc, "gate: allowed vk passes", vwa_game_vk_allowed(999), true);
    vwa_game_allow_vk(999, false);
    vwa_test_eq(tc, "gate: revoked vk denied again", vwa_game_vk_allowed(999), false);
    global.vwaGameKeysOpen = true;
    vwa_test_eq(tc, "gate: fail-open overrides bind deny", vwa_game_bind_allowed("vwa-test-bind"), true);
    vwa_test_eq(tc, "gate: fail-open overrides vk deny", vwa_game_vk_allowed(999), true);
    global.vwaGameKeysOpen = priorOpen;
    if (bindWas)
    {
        vwa_game_allow_bind("vwa-test-bind", true);
    }
    if (vkWas)
    {
        vwa_game_allow_vk(999, true);
    }
}

// The encounter body splitter (scrVwaMenuEncounter's pure piece): one
// spoken line per non-empty trimmed text line, blank runs and edge
// whitespace vanishing, non-strings empty.
function vwa_test_encounter(tc)
{
    vwa_test_eq(tc, "enc: split trims and drops blanks",
        vwa_test_join(vwa_enc_split_paragraphs("\nFirst line. \n\n Second\n")),
        "First line. | Second");
    vwa_test_eq(tc, "enc: split single line",
        vwa_test_join(vwa_enc_split_paragraphs("Only")), "Only");
    vwa_test_eq(tc, "enc: split empty string",
        array_length(vwa_enc_split_paragraphs("")), 0);
    vwa_test_eq(tc, "enc: split non-string",
        array_length(vwa_enc_split_paragraphs(0)), 0);
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

// The ship composer (scrVwaShip) on live game data. The selftest runs
// in-game (any room), where oGameData and the meta progression are up but
// entities may exist only as object indices - exactly the index paths the
// composers must handle. Behavior checks only: shapes, the visibility
// rules, agreement with the game getters the composers mirror - never
// hardcoded composed text. Expectations honor the same live flags the
// composers read (unlock state, debug keys), so profile state can never
// fail the test, only composition logic can.
function vwa_test_ship(tc)
{
    // Identity: the first-slot hull (never locked, never hidden - the
    // game's starting ship) reads name then class; a LOCKED hull (when the
    // profile has one) hides its name unless debug keys and appends the
    // locked word; a HIDDEN one is exactly the Unknown Vessel label.
    var rm = global.shipUnlockOrder_ship1A;
    var line = vwa_ship_identity_line(rm, 1);
    var name = vwa_sheet_flatten(hull_get_info(vs_room_get_info(rm, 0), 881));
    var cls = string(hullClass_to_str(vs_room_get_info(rm, 2)));
    vwa_test_ok(tc, "ship: identity starts with the hull name",
        string_pos(name, line) == 1, line);
    vwa_test_ok(tc, "ship: identity carries the class",
        string_pos(cls, line) > 0, line);
    vwa_test_ok(tc, "ship: identity variant letters differ",
        vwa_ship_identity_line(rm, 1) != vwa_ship_identity_line(rm, 2),
        line);

    var allShips = playerShipList_all();
    for (var i = 0; i < array_length(allShips); i++)
    {
        var lrm = allShips[i];
        if (playerShip_checkUnlockState(lrm, 1))
        {
            var lline = vwa_ship_identity_line(lrm, 1);
            vwa_test_ok(tc, "ship: locked identity carries the locked word",
                string_pos(vwa_t("vwa--state-locked"), lline) > 0, lline);
            var lname = vwa_sheet_flatten(hull_get_info(vs_room_get_info(lrm, 0), 881));
            vwa_test_eq(tc, "ship: locked identity name follows debug keys",
                string_pos(lname, lline) == 1, global.enableDebugKeys ? true : false);
            break;
        }
    }
    for (var i = 0; i < array_length(allShips); i++)
    {
        var hrm = allShips[i];
        if (vwa_ship_room_hidden(hrm))
        {
            vwa_test_eq(tc, "ship: hidden identity is the Unknown Vessel label",
                vwa_ship_identity_line(hrm, 1), string(global.label_unknownVessel));
            break;
        }
    }

    // Systems, by object index (the tooltip's own no-instance path): head
    // is the game's name; flavor adds at least one lore line.
    var sysNames = variable_struct_get_names(oGameData.systemInfo);
    if (array_length(sysNames) > 0)
    {
        var sysObj = asset_get_index(sysNames[0]);
        var sysLines = vwa_ship_system_lines(sysObj, vwa_ship_opt_flags(false));
        vwa_test_ok(tc, "ship: system lines non-empty",
            array_length(sysLines) >= 1, sysNames[0]);
        if (array_length(sysLines) >= 1)
        {
            vwa_test_eq(tc, "ship: system head is the game's name", sysLines[0],
                vwa_sheet_flatten(system_get_info(sysObj, 171)));
        }
        vwa_test_ok(tc, "ship: system flavor adds lore",
            array_length(vwa_ship_system_lines(sysObj, vwa_ship_opt_flags(true)))
                > array_length(sysLines), sysNames[0]);
    }

    // Weapons: a non-ordnance carries the required power line; an ordnance
    // head goes through the missile-template wrapper.
    var wpnNames = variable_struct_get_names(oGameData.weaponInfo);
    var plainDone = false;
    var ordDone = false;
    for (var i = 0; i < array_length(wpnNames); i++)
    {
        var wObj = asset_get_index(wpnNames[i]);
        if (!object_exists(wObj) || !objIA(wObj, oWeapon))
        {
            continue;
        }
        if (!ordDone && objIA(wObj, oOrdnance))
        {
            ordDone = true;
            var oLines = vwa_ship_weapon_lines(wObj, vwa_ship_opt_flags(false));
            if (array_length(oLines) >= 1)
            {
                vwa_test_eq(tc, "ship: ordnance head is the template wrapper",
                    oLines[0], vwa_sheet_t("vwa--ship-missile-template",
                        ["name"],
                        [vwa_sheet_flatten(weapon_get_info(wObj, 1))]));
            }
        }
        else if (!plainDone && !objIA(wObj, oOrdnance))
        {
            plainDone = true;
            var wLines = vwa_ship_weapon_lines(wObj, vwa_ship_opt_flags(false));
            vwa_test_ok(tc, "ship: weapon lines non-empty",
                array_length(wLines) >= 2, wpnNames[i]);
            if (array_length(wLines) >= 2)
            {
                vwa_test_eq(tc, "ship: weapon head is the game's name",
                    wLines[0], vwa_sheet_flatten(weapon_get_info(wObj, 1)));
                vwa_test_eq(tc, "ship: weapon required power line",
                    wLines[array_length(wLines) - 1],
                    string(global.label_requiredPower) + ": "
                        + string(weapon_get_info(wObj, 6)));
            }
        }
        if (plainDone && ordDone)
        {
            break;
        }
    }
    vwa_test_ok(tc, "ship: found a non-ordnance weapon to test", plainDone, "none");

    // Equipment stacks: the count template leads.
    var itmNames = variable_struct_get_names(oGameData.itemInfo);
    if (array_length(itmNames) > 0)
    {
        var itmObj = asset_get_index(itmNames[0]);
        var eqLines = vwa_ship_equipment_lines(itmObj, 2);
        vwa_test_ok(tc, "ship: equipment lines non-empty",
            array_length(eqLines) >= 1, itmNames[0]);
        if (array_length(eqLines) >= 1)
        {
            vwa_test_eq(tc, "ship: equipment head is the counted name",
                eqLines[0], vwa_sheet_t("vwa--sheet-count", ["n", "name"],
                    [2, vwa_sheet_flatten(item_get_info(itmObj, 41))]));
        }
    }

    // Modules, by object index: head is the game's name.
    var mdlNames = variable_struct_get_names(oGameData.moduleInfo);
    if (array_length(mdlNames) > 0)
    {
        var mdlObj = asset_get_index(mdlNames[0]);
        var mdLines = vwa_ship_module_lines(mdlObj, vwa_ship_opt_flags(false));
        vwa_test_ok(tc, "ship: module lines non-empty",
            array_length(mdLines) >= 1, mdlNames[0]);
        if (array_length(mdLines) >= 1)
        {
            vwa_test_eq(tc, "ship: module head is the game's name", mdLines[0],
                vwa_sheet_flatten(module_get_info(mdlObj, 480)));
        }
    }
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
// exactly one utterance through the speak tap whose text matches a fresh
// vwa_ship_move_parts / block-token render, and the game's own
// connectivity truth - a door crossing's target cell must sit in the
// from-cell's connectedCellList and the door in its doorsList; a
// wall-blocked existing neighbor must still be in adjCellList. At the
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
    var w = { tap: [] };
    // The tap global is lazily owned (the chokepoint reads it through
    // variable_global_exists); a fresh session may reach here before
    // anything has set it.
    var priorTap = variable_global_exists("vwaSpeakTap")
        ? global.vwaSpeakTap : undefined;
    global.vwaSpeakTap = method({ w: w }, function(text, intr)
    {
        array_push(self.w.tap, text);
    });
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
        throw err;
    }
    global.vwaSpeakTap = priorTap;
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
    var expected;
    if (plan.moved)
    {
        expected = vwa_speak_render(vwa_ship_move_parts(alliedSide, toE,
            { cellChanged: plan.cellChanged, door: plan.door,
              tx: oldTx + dx, ty: oldTy + dy, cx: geom.cx, cy: geom.cy }));
    }
    else
    {
        expected = vwa_speak_render([vwa_t((plan.blocked == "airlock")
            ? "vwa--ship-airlock" : "vwa--ship-wall")]);
    }
    vwa_test_ok(tc, "shipwalk: one utterance " + tag,
        array_length(w.tap) == 1, vwa_test_join(w.tap));
    if (array_length(w.tap) == 1)
    {
        vwa_test_eq(tc, "shipwalk: speech " + tag, w.tap[0], expected);
    }
    return { moved: movedActual };
}
