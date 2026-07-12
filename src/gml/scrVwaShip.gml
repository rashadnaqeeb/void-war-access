// scrVwaShip - Void War Access ship composer: turns the ship select
// screen's entities - hull rooms, systems, weapons, equipment stacks,
// modules - into spoken lines (session 12). The ship select screen is the
// first consumer; the deferred in-run ship viewer is the intended second,
// so the phrasing seams live here, not inline in the screen code.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// PURE MODULE in the scrVwaSheet sense: composition only - no speech, no
// graph, no caching. Inputs are live instances or object indices (each
// composer takes what the game's own tooltip takes and resolves through
// the game's own getters at call time); outputs are arrays of line
// strings, one alt-arrow step each. Every mod-authored word routes
// through vwa_t.
//
// The composers and their game-truth sources:
// - identity:  vwa_ship_identity_line(rm, variantNumber) -> ONE string:
//              "{hull name}, {class} {letter}[, locked]" or the game's
//              Unknown Vessel label. All sources are ROOM-KEYED data
//              (playerRoomData, hullInfo, metaProgressionData), never live
//              instances, so the line is correct DURING a hull switch: the
//              selector sets selectedRoom before room_goto and feedback
//              resolves while the old room's instances are still alive
//              (never speak stale data). Visibility mirrors the ship
//              menu's own rules (playerShip_checkVisibilityInShipMenu,
//              generalized to any room): hidden = the game's Unknown
//              Vessel label alone; locked hides the name (oShipMenu_-
//              shipName draws NO DATA when locked, debug keys unhide) and
//              appends the locked state word.
// - systems:   vwa_ship_system_lines(sys, opts) - "{name}, level {n}"
//              (the level is the upgrade-bar count the ship menu paints,
//              maxHP), then description lines, then lore (opts.flavor).
//              Mirrors oUITooltip_shipSystems' pre-run sections: name from
//              the live instance (system_get_info for a bare object
//              index), description from system_get_info's description.
// - weapons:   vwa_ship_weapon_lines(wpn, opts) - name (an ordnance is
//              spoken through the missile-template wrapper, the ship
//              tooltip's own framing), description lines, the required
//              power line for non-ordnance, then lore (opts.flavor).
//              Mirrors oUITooltip_shipWeapons' pre-run sections.
// - equipment: vwa_ship_equipment_lines(itm, qty) - "{n}x {name}" (the
//              vwa--sheet-count template scrVwaSheet also uses), then
//              description lines (item_get_info, the codes verified in
//              scrVwaSheet).
// - modules:   vwa_ship_module_lines(mdl, opts) - name, description
//              lines, then lore (opts.flavor). Mirrors oUITooltip_module.
//              An EMPTY module slot is the screen's concern (the game's
//              label_emptyModuleSlot as a plain node), not this module's.
//
// Game text can carry newlines (paragraph breaks); each non-empty piece
// becomes its own line so the alt-arrow review steps paragraphs. A dead or
// missing entity logs and returns [] (a vanished entity mid-read is a bug
// upstream, and silence without a log would be invisible).

function vwa_ship_opt_flags(flavor)
{
    return { flavor: flavor };
}

// Split game text on newlines into trimmed spoken lines. undefined is
// game-data absence (the getters already report unknown indices), not a
// mod failure: contribute nothing.
function vwa_ship_push_text_lines(out, s)
{
    if (s == undefined)
    {
        return;
    }
    var pieces = string_split(string(s), "\n", true);
    for (var i = 0; i < array_length(pieces); i++)
    {
        var piece = string_trim(pieces[i]);
        if (piece != "")
        {
            array_push(out, piece);
        }
    }
}

// Hidden-in-ship-menu for an arbitrary hull room: the game's
// playerShip_checkVisibilityInShipMenu reads the CURRENT room; identity
// lines need the answer for the room being cycled to.
function vwa_ship_room_hidden(rm)
{
    if (global.gameStarted)
    {
        return false;
    }
    if (!playerShip_checkUnlockState(rm, 2) || global.enableDebugKeys)
    {
        return false;
    }
    return true;
}

function vwa_ship_identity_line(rm, variantNumber)
{
    if (vwa_ship_room_hidden(rm))
    {
        return string(global.label_unknownVessel);
    }
    var classStr = string(hullClass_to_str(vs_room_get_info(hullVariant_get(rm, 1), 2)))
        + " " + string(hullVariant_to_str_letterOnly(variantNumber));
    var locked = playerShip_checkUnlockState(rm, 1);
    var s = "";
    if (!locked || global.enableDebugKeys)
    {
        s = vwa_sheet_flatten(hull_get_info(vs_room_get_info(rm, 0), 881)) + ", ";
    }
    s += classStr;
    if (locked)
    {
        s += ", " + vwa_t("vwa--state-locked");
    }
    return s;
}

// sys: a live oSysGroup instance (the ship menu's systemList) or a system
// object index (the future viewer's case; the game's tooltip handles both
// the same way).
function vwa_ship_system_lines(sys, opts)
{
    var out = [];
    var head;
    if (instance_exists(sys))
    {
        head = vwa_sheet_flatten(sys.name)
            + ", " + vwa_sheet_t("vwa--ship-level", ["n"], [sys.maxHP]);
    }
    else if (object_exists(sys))
    {
        head = vwa_sheet_flatten(system_get_info(sys, 171));
    }
    else
    {
        vwa_log("ERROR: ship: system gone");
        return [];
    }
    array_push(out, head);
    // 172 = description, 175 = loreDescription (system_get_info; literals
    // because cross-entry enums are not usable under the importer).
    vwa_ship_push_text_lines(out, system_get_info(sys, 172));
    if (vwa_opt(opts, "flavor", false))
    {
        var lore = instance_exists(sys) ? sys.loreDescription
            : system_get_info(sys, 175);
        if (lore == undefined || lore == "")
        {
            lore = global.label_loreDescription_default_system;
        }
        vwa_ship_push_text_lines(out, lore);
    }
    return out;
}

// wpn: a weapon OBJECT INDEX (oHull.startWeapon / startOrdnance hold
// indices; instances only exist in-run).
function vwa_ship_weapon_lines(wpn, opts)
{
    if (!object_exists(wpn) || !objIA(wpn, oWeapon))
    {
        vwa_log("ERROR: ship: weapon index invalid: " + string(wpn));
        return [];
    }
    // 1 = name, 2 = description, 6 = psiCost, 21 = loreDescription.
    var name = vwa_sheet_flatten(weapon_get_info(wpn, 1));
    if (objIA(wpn, oOrdnance))
    {
        name = vwa_sheet_t("vwa--ship-missile-template", ["name"], [name]);
    }
    var out = [name];
    vwa_ship_push_text_lines(out, weapon_get_info(wpn, 2));
    if (!objIA(wpn, oOrdnance))
    {
        array_push(out, string(global.label_requiredPower) + ": "
            + string(weapon_get_info(wpn, 6)));
    }
    if (vwa_opt(opts, "flavor", false))
    {
        var lore = weapon_get_info(wpn, 21);
        if (lore == undefined || lore == "")
        {
            lore = global.label_loreDescription_default_shipWeapon;
        }
        vwa_ship_push_text_lines(out, lore);
    }
    return out;
}

// itm: an item object index; qty: the stack count the game aggregated
// (oShipMenu_equipmentList.equipmentQt). 41 = name, 42 = description.
function vwa_ship_equipment_lines(itm, qty)
{
    if (!object_exists(itm))
    {
        vwa_log("ERROR: ship: equipment index invalid: " + string(itm));
        return [];
    }
    var out = [vwa_sheet_t("vwa--sheet-count", ["n", "name"],
        [qty, vwa_sheet_flatten(item_get_info(itm, 41))])];
    vwa_ship_push_text_lines(out, item_get_info(itm, 42));
    return out;
}

// mdl: a live oModule instance (oModuleManager.modules_player slot) or a
// module object index. 480 = name, 481 = description, 482 = lore.
function vwa_ship_module_lines(mdl, opts)
{
    var head;
    if (instance_exists(mdl))
    {
        head = vwa_sheet_flatten(mdl.name);
    }
    else if (object_exists(mdl))
    {
        head = vwa_sheet_flatten(module_get_info(mdl, 480));
    }
    else
    {
        vwa_log("ERROR: ship: module gone");
        return [];
    }
    var out = [head];
    vwa_ship_push_text_lines(out, module_get_info(mdl, 481));
    if (vwa_opt(opts, "flavor", false))
    {
        var lore = module_get_info(mdl, 482);
        if (lore == undefined || lore == "")
        {
            lore = global.label_loreDescription_default_module;
        }
        vwa_ship_push_text_lines(out, lore);
    }
    return out;
}
