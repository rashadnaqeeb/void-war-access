// scrVwaSheet - Void War Access crew sheet composer: turns a live crew
// instance into the categorized spoken lines Rashad designed (session 10).
// The commander select screen is the first consumer; the same composer is
// meant for any future surface that reads a crew unit (the in-run crew/map
// reading), so it takes the crew and an options struct and nothing else.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The structure (each returned string is one spoken line, one alt-arrow
// step; category words are localized vwa-- rows):
// - stats:      "Health {cur} of {max}, attack {dps}"
// - type:       "Type: Commander, Psyker" - the crew-type keyword labels.
//               What the unit counts as for targeting and effects.
// - traits:     "Trait: {effect text}" - one line per keyword effect
//               description, the character's permanent passives. Module and
//               temporary effect categories fold in here too (they cannot
//               exist at commander select; in-run they are still effects on
//               the character, and dropping them silently would hide state).
// - innate:     "Innate ability: {name}: {text}" - abilities living in
//               hidden equipment slots (the game's own "(Innate)" marker):
//               built into the character, never unequippable.
// - slots:      one line per VISIBLE slot, in slot order: "{Slot}: {item}:
//               {item text}" or "{Slot}: empty". Anything on a slot line is
//               gear. The item's own description rides its slot line, which
//               is also why item-sourced effect categories are not trait
//               lines - the same text would read twice with no source.
// - additional: "Additional equipment: 2x {name}, ..." - the one-use
//               consumables some commanders bring (opts.additionalEquipment;
//               the game shows these only while no run is live).
// - record:     the game's own "Utmost Vanquished Torment: {level}" line
//               (opts.record; commander select only).
// - flavor:     the description text (opts.flavor; the game gates this on
//               its encyclopedia mode setting, so the caller passes that).
//
// Everything resolves at call time from the live instance - the caller is
// expected to re-call per speak (never cache game state). Composition only:
// no speech, no graph. Effect categorization runs the game's own
// crew_effect_string_updateCategories inside the crew's scope, exactly as
// the game's tooltip object does, so the category split can never drift
// from the game's.

function vwa_sheet_opt_flags(record, additionalEquipment, flavor)
{
    return { record: record, additionalEquipment: additionalEquipment,
             flavor: flavor };
}

// A template row with {x}-style placeholders, resolved through vwa_t.
function vwa_sheet_t(key, names, values)
{
    var s = vwa_t(key);
    for (var i = 0; i < array_length(names); i++)
    {
        s = string_replace(s, "{" + names[i] + "}", string(values[i]));
    }
    return s;
}

// One composed line must stay one line for the alt-arrow cursor: flatten
// any newlines game text carries into comma pauses.
function vwa_sheet_flatten(s)
{
    return string_trim(string_replace_all(string(s), "\n", ", "));
}

// The localized slot word for a game slotType string. An unknown type is a
// game addition we have not mapped: log loudly and speak the raw word
// rather than dropping the slot.
function vwa_sheet_slot_word(slotTypeStr)
{
    if (slotTypeStr == "armor")
    {
        return vwa_t("vwa--slot-armor");
    }
    if (slotTypeStr == "weapon")
    {
        return vwa_t("vwa--slot-weapon");
    }
    if (slotTypeStr == "tool")
    {
        return vwa_t("vwa--slot-tool");
    }
    if (slotTypeStr == "psychic")
    {
        return vwa_t("vwa--slot-psychic");
    }
    vwa_log("ERROR: sheet: unknown slot type '" + string(slotTypeStr) + "'");
    return string(slotTypeStr);
}

// The sheet. crew: a live crew instance. opts: vwa_sheet_opt_flags (or any
// struct with those fields). Returns an array of line strings; [] only for
// a dead reference (logged - a vanished crew mid-read is a bug upstream).
function vwa_sheet_crew_lines(crew, opts)
{
    if (!instance_exists(crew))
    {
        vwa_log("ERROR: sheet: crew instance gone");
        return [];
    }
    var out = [];

    // Stats - same sources as the game's tooltip header block
    // (draw_crew_baseStats): display HP string, maxHP, totalDPS.
    array_push(out, vwa_sheet_t("vwa--sheet-stats",
        ["hp", "maxhp", "atk"],
        [getCrewCurrHPStr(crew), crew.maxHP, crew.totalDPS]));

    // Effect categories, split by the game's own categorizer. Run inside
    // the crew's scope so the desc_* result arrays land on the crew (the
    // game runs it inside its tooltip instance the same way). Dead crew
    // skip effects, mirroring the tooltip's guard.
    var typeParts = [];
    var traitDescs = [];
    if (!crew_is_dead(crew))
    {
        with (crew)
        {
            crew_effect_string_updateCategories(id);
        }
        typeParts = crew.desc_crewType;
        var cats = [crew.desc_buff_keyword, crew.desc_debuff_keyword,
                    crew.desc_buff_module, crew.desc_debuff_module,
                    crew.desc_buff_temp, crew.desc_debuff_temp];
        for (var c = 0; c < array_length(cats); c++)
        {
            for (var i = 0; i < array_length(cats[c]); i++)
            {
                array_push(traitDescs, cats[c][i]);
            }
        }
    }

    // Type line: the crew-type labels, joined.
    var typeList = "";
    for (var i = 0; i < array_length(typeParts); i++)
    {
        var t = string_trim(string(typeParts[i]));
        if (t == "")
        {
            continue;
        }
        if (typeList != "")
        {
            typeList += ", ";
        }
        typeList += t;
    }
    if (typeList != "")
    {
        array_push(out, vwa_sheet_t("vwa--sheet-type", ["list"], [typeList]));
    }

    // Trait lines. A category entry can itself be multiple statements on
    // embedded newlines (the generated "Cannot ..." restriction block);
    // each statement is its own line.
    for (var i = 0; i < array_length(traitDescs); i++)
    {
        var pieces = string_split(string(traitDescs[i]), "\n", true);
        for (var p = 0; p < array_length(pieces); p++)
        {
            var piece = string_trim(pieces[p]);
            if (piece != "")
            {
                array_push(out, vwa_sheet_t("vwa--sheet-trait", ["text"], [piece]));
            }
        }
    }

    // Innate abilities: abilities whose parent slot is hidden. Visible-slot
    // abilities are deliberately absent - their item's slot line below
    // carries the text.
    for (var i = 0; i < ds_list_size(crew.abilityObj); i++)
    {
        var abl = ds_list_find_value(crew.abilityObj, i);
        if (!objInst_exists(abl))
        {
            continue;
        }
        if (crew.hideSlot[abl.parentItemSlot])
        {
            array_push(out, vwa_sheet_t("vwa--sheet-innate",
                ["name", "text"],
                [vwa_sheet_flatten(abl.name), vwa_sheet_flatten(abl.description)]));
        }
    }

    // Slot lines, in slot order. Filled slots name the item and speak its
    // description in place (41 = name, 42 = description in item_get_info;
    // literals because cross-entry enums are not usable under the importer).
    for (var i = 0; i < array_length(crew.slotType); i++)
    {
        if (crew.slotType[i] == "none" || crew.hideSlot[i])
        {
            continue;
        }
        var slotWord = vwa_sheet_slot_word(crew.slotType[i]);
        var itm = ds_list_find_value(crew.setItem, i);
        if (itm != undefined && itm != -1 && object_exists(itm) && objIA(itm, oItem))
        {
            array_push(out, vwa_sheet_t("vwa--sheet-slot-filled",
                ["slot", "item", "text"],
                [slotWord, vwa_sheet_flatten(item_get_info(itm, 41)),
                 vwa_sheet_flatten(item_get_info(itm, 42))]));
        }
        else
        {
            array_push(out, vwa_sheet_t("vwa--sheet-slot-empty",
                ["slot"], [slotWord]));
        }
    }

    // Additional equipment: grouped counts in first-appearance order
    // (mirrors the tooltip's init_additionalEquipmentStr, minus its
    // struct-keyed reordering quirk).
    if (vwa_opt(opts, "additionalEquipment", false)
        && variable_instance_exists(crew, "commanderAdditionalEquipment")
        && array_length(crew.commanderAdditionalEquipment) > 0)
    {
        var names = [];
        var counts = [];
        for (var i = 0; i < array_length(crew.commanderAdditionalEquipment); i++)
        {
            var nm = string(item_get_info(crew.commanderAdditionalEquipment[i], 41));
            var idx = vwa_array_index_of(names, nm);
            if (idx < 0)
            {
                array_push(names, nm);
                array_push(counts, 1);
            }
            else
            {
                counts[idx] += 1;
            }
        }
        var list = "";
        for (var i = 0; i < array_length(names); i++)
        {
            if (list != "")
            {
                list += ", ";
            }
            list += vwa_sheet_t("vwa--sheet-count", ["n", "name"],
                [counts[i], vwa_sheet_flatten(names[i])]);
        }
        array_push(out, vwa_sheet_t("vwa--sheet-add-equip", ["list"], [list]));
    }

    // Win record: the game's own label and Normal-for-zero wording
    // (oUITooltip_crew's commander section).
    if (vwa_opt(opts, "record", false))
    {
        var maxTorm = commanderWinData_get_maxTormWin(crew.object_index);
        if (maxTorm != -1)
        {
            var tormStr = (maxTorm == 0) ? global.label_normal : string(maxTorm);
            array_push(out, global.label_utmostVanquishedTormentLevel + ": " + tormStr);
        }
    }

    // Flavor text, with the game's own fallback (the tooltip's encyclopedia
    // section: commanderDescription for player crew, loreDescription
    // otherwise).
    if (vwa_opt(opts, "flavor", false))
    {
        var flav = objIA(crew.object_index, oCrewPlayer)
            ? crew.commanderDescription : crew.loreDescription;
        if (flav == undefined || flav == "")
        {
            flav = global.label_loreDescription_default_crew;
        }
        array_push(out, vwa_sheet_flatten(flav));
    }

    return out;
}
