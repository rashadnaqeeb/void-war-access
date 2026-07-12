// scrVwaMenuCommander - Void War Access commander select screen (session
// 10; full-list retrofit session 12). Registered from vwa_menus_init via
// vwa_menu_commander_init. The first real screen of the new game flow.
// Three Tab stops:
// 1) "commanders" - one row per commander of the FULL set (the game's own
//    commanderList_all, the source its pageData chunks), inside a silent
//    context so the global "n of m" counts commanders only, then the
//    Resonance readout. The game's page window follows focus through the
//    auto-paging pattern (vwa_pages_ensure_visible in scrVwaWidgets);
//    there are no pager nodes.
// 2) "name" - the commander name text field and its randomize button;
// 3) "confirm" - the Confirm button (room change to ship select).
// A row's summary line is name / selected / locked + cost (+ not enough
// Resonance) / new / position; its sheet - Rashad's categorized crew read -
// comes from vwa_sheet_crew_lines, one tooltip part per line, so alt
// up/down step it. Hidden ("???") commanders read as "Hidden commander,
// locked" with no sheet, mirroring the game's suppressed tooltip.
// Imported by tools/build-mod.csx as a new global script. Ships in release.

function vwa_menu_commander_init()
{
    // The commander select screen (menuToggle 13, oUICommanderList) - the
    // first screen of the new game flow, and the same object re-opened as
    // an overlay by the ship select screen's commander button, so one
    // registration covers both. The gate is the list INSTANCE, not the
    // menu flag: the purchase dialogue flips the flag to 14 while the list
    // stays up, and gating on 13 would pop this screen under the dialogue
    // and lose its focus memory. Escape stays the game's own (the list's
    // Step handles it raw: back to the main menu / close the overlay); the
    // purchase dialogue is an oUIConfirmationDialogue child, so the generic
    // confirm screen covers it with no extra work.
    vwa_screen_register({
        key: "commander-select",
        layerNum: 40,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && instance_exists(oUICommanderList);
        },
        name: function() { return global.label_selectCommander; },
        build: function(bd) { vwa_commander_build(bd); }
    });
    // The "new"-badge armed-clear state (see vwa_commander_badge_tick).
    global.vwaCmdrNewArmed = undefined;
}

// The game clears a locked commander's red "new" badge the moment the
// pointer hovers its row (oUICommanderList Draw_64). Our hover is focus,
// but clearing on the landing frame would reshape the row's announcement
// under the alt-arrow cursor mid-review, so the clear is ARMED on focus and
// COMMITTED when focus leaves the row (page flips and screen closes land in
// the same place: the next build sees focus elsewhere). While armed, the
// badge still reads "new" - the row keeps the exact announcement the
// landing spoke. Never-moving-again loses the clear, which the game's own
// never-hover loses too.
function vwa_commander_badge_tick(lst)
{
    var scr = vwa_screen_find("commander-select");
    var focSkey = undefined;
    if (scr != undefined && scr.navState.curId != undefined)
    {
        focSkey = scr.navState.curId.skey;
    }
    var armed = global.vwaCmdrNewArmed;
    if (armed != undefined && armed != focSkey)
    {
        var objName = string_delete(armed, 1, 5); // strip "cmdr:"
        if (!array_has_value(global.metaProgressionData.commanderHoverBadgeCleared, objName))
        {
            array_push(global.metaProgressionData.commanderHoverBadgeCleared, objName);
            with (lst)
            {
                update_newCommanderBadgeHover();
                update_commanderCtPageBadge();
            }
            vwa_log("commander: new badge cleared for " + objName);
        }
        global.vwaCmdrNewArmed = undefined;
    }
    if (focSkey != undefined && string_pos("cmdr:", focSkey) == 1)
    {
        var focName = string_delete(focSkey, 1, 5);
        if (asset_get_type(focName) == asset_object
            && commander_checkUnlockState(asset_get_index(focName), 1)
            && !array_has_value(global.metaProgressionData.commanderHoverBadgeCleared, focName))
        {
            global.vwaCmdrNewArmed = focSkey;
        }
    }
}

// The game spawns a commander's display instance only when its page first
// shows (update_commanderPage -> spawn_commanders), but the full-list rows
// need those instances for their sheets. When any non-hidden commander has
// no instance yet, flip the game through one full page cycle via its own
// stored page methods - exactly what a player paging through does, sounds
// excluded (the sfx lives on the button press path, not in the callbacks) -
// which spawns every page's instances and wraps back to the current page.
// Runs from build; once every instance exists it never fires again.
function vwa_commander_prespawn(lst)
{
    var needSpawn = false;
    for (var i = 0; i < array_length(lst.commanderList_all); i++)
    {
        var obj = lst.commanderList_all[i];
        if (!commander_checkUnlockState(obj, 2) && !instance_exists(obj))
        {
            needSpawn = true;
            break;
        }
    }
    if (!needSpawn)
    {
        return;
    }
    var pc = lst.pageControls;
    if (!instance_exists(pc))
    {
        vwa_log("ERROR: commander prespawn: page controls missing");
        return;
    }
    var n = array_length(lst.pageData);
    repeat (n)
    {
        var fn = pc.onPress_next;
        fn();
    }
    vwa_log("commander: prespawn page sweep (" + string(n) + " pages)");
}

// The auto-paging tick: the game's visible page follows the focused row.
function vwa_commander_ensure_visible(lst)
{
    vwa_pages_ensure_visible(vwa_screen_find("commander-select"), {
        focusPage: method({ lst: lst }, function(skey)
        {
            if (string_pos("cmdr:", skey) != 1)
            {
                return -1;
            }
            var objName = string_delete(skey, 1, 5);
            var pd = self.lst.pageData;
            for (var p = 0; p < array_length(pd); p++)
            {
                for (var i = 0; i < array_length(pd[p]); i++)
                {
                    if (objGN(pd[p][i]) == objName)
                    {
                        return p;
                    }
                }
            }
            vwa_log("ERROR: commander " + objName + " on no page");
            return -1;
        }),
        curPage: method({ lst: lst }, function()
        {
            return self.lst.currPageIndex;
        }),
        pageCount: method({ lst: lst }, function()
        {
            return array_length(self.lst.pageData);
        }),
        stepNext: method({ lst: lst }, function()
        {
            var pc = self.lst.pageControls;
            if (!instance_exists(pc))
            {
                vwa_log("ERROR: commander page step: page controls missing");
                return;
            }
            var fn = pc.onPress_next;
            fn();
        }),
        stepPrev: method({ lst: lst }, function()
        {
            var pc = self.lst.pageControls;
            if (!instance_exists(pc))
            {
                vwa_log("ERROR: commander page step: page controls missing");
                return;
            }
            var fn = pc.onPress_prev;
            fn();
        })
    });
}

function vwa_commander_build(bd)
{
    var lst = instance_find(oUICommanderList, 0);
    vwa_commander_badge_tick(lst);
    vwa_commander_prespawn(lst);
    vwa_commander_ensure_visible(lst);

    vwa_gb_begin_stop(bd, "commanders");
    vwa_gb_push_context(bd, "");
    for (var i = 0; i < array_length(lst.commanderList_all); i++)
    {
        vwa_commander_row_add(bd, lst, lst.commanderList_all[i]);
    }
    vwa_gb_pop_context(bd);

    // The Resonance balance (oCounterMetaCurrency, top left). The label is
    // the game's own label_resonance; the tooltip string is game-authored
    // English hardcoded in the object's draw (same text in all four
    // languages), mirrored verbatim.
    vwa_gb_add(bd, vwa_id("cmdr-resonance"), {
        parts: [
            vwa_part_fn("label", function() { return global.label_resonance; }, false),
            vwa_part_fn("value", function() { return string(global.currMetaCurrency); }, true),
            vwa_part("tooltip", "Used for unlocking ships and commanders."),
            vwa_part("position", "")
        ]
    });

    vwa_gb_begin_stop(bd, "name");
    var box = instance_find(oCommanderNameBox, 0);
    vwa_gb_add(bd, vwa_id_ref(box, "cmdr-name"), {
        typeKey: "textfield",
        parts: [
            // The game's own "Enter Name" screen label doubles as the
            // field's spoken label. The value is NOT live: while editing,
            // the screen reader echoes keystrokes itself and scrVwaText
            // owns edit feedback - a live part would re-speak the whole
            // text on every character.
            vwa_part_fn("label", function() { return global.label_enterName; }, false),
            vwa_part_fn("value", method({ box: box }, function()
            {
                return string(self.box.text);
            }), false)
        ],
        onActivate: function()
        {
            // oCommanderNameBox's only edit state is the global flag, which
            // is exactly the text layer's default adapter.
            vwa_text_begin(undefined);
        }
    });
    var rnd = instance_find(oCommanderNameRandomizeButton, 0);
    vwa_gb_add(bd, vwa_id_ref(rnd, "cmdr-randomize"), {
        typeKey: "button",
        parts: [
            // The game shows only a shuffle icon - no text, no tooltip - so
            // the label is mod-authored. The live value part is the current
            // name: activation feedback speaks the freshly rolled name.
            vwa_part_fn("label", function() { return vwa_t("vwa--randomize-name"); }, false),
            vwa_part_fn("value", method({ box: box }, function()
            {
                return string(self.box.text);
            }), true)
        ],
        onActivate: method({ inst: rnd }, function()
        {
            vwa_obutton_activate(self.inst);
        })
    });

    vwa_gb_begin_stop(bd, "confirm");
    var cfm = instance_find(oCommanderSelect_confirm, 0);
    vwa_gb_add(bd, vwa_id_ref(cfm, "cmdr-confirm"), {
        typeKey: "button",
        parts: [vwa_part_fn("label", method({ inst: cfm }, function()
        {
            return self.inst.buttonText;
        }), false)],
        onActivate: method({ inst: cfm }, function()
        {
            // Mirror of oMenuButton's click (Step_1 = Begin Step): the
            // hover-conditions guard, the press sound, then the pressed
            // flag. buttonPressed is set directly rather than pressed:
            // our tick and the button's Step_1 both run in Begin Step in
            // undefined relative order, so pressed could be wiped before
            // Draw_64 forwards it; buttonPressed is what the child object's
            // Step_0 consumes later this same frame either way.
            var bt = self.inst;
            if (bt.hoverConditionsMet != -4)
            {
                var hc = bt.hoverConditionsMet;
                if (!hc())
                {
                    vwa_log("ERROR: confirm button hover conditions refuse"
                        + " activation - screen stack out of sync?");
                    return;
                }
            }
            sfx_start_ext(bt.sfx_press, 0, 1, 0, 0, 1);
            bt.buttonPressed = true;
        })
    });
}

// One commander row. Unlock states are the game's (scrMetaProgression):
// 1 = locked (visible, purchasable), 2 = hidden ("???"). Exactly one
// commander is always selected; activation mirrors clickToSelectCommander
// (oUICommanderList Create): guards, the game's own stored methods, the
// same sounds in the same order.
function vwa_commander_row_add(bd, lst, cmdrObj)
{
    var hiddenNow = commander_checkUnlockState(cmdrObj, 2);
    var parts = [
        vwa_part_fn("label", method({ obj: cmdrObj }, function()
        {
            if (commander_checkUnlockState(self.obj, 2))
            {
                return vwa_t("vwa--commander-hidden");
            }
            return string(crew_get_info(self.obj, 31)); // 31 = baseName
        }), false),
        vwa_part_fn("selected", method({ obj: cmdrObj, lst: lst }, function()
        {
            var sel = self.lst.selectedCommanderID;
            if (instance_exists(sel) && sel.object_index == self.obj)
            {
                return vwa_t("vwa--state-selected");
            }
            return "";
        }), true),
        vwa_part_fn("value", method({ obj: cmdrObj }, function()
        {
            if (commander_checkUnlockState(self.obj, 1)
                || commander_checkUnlockState(self.obj, 2))
            {
                return vwa_t("vwa--state-locked");
            }
            return "";
        }), false),
        vwa_part_fn("value", method({ obj: cmdrObj }, function()
        {
            if (!commander_checkUnlockState(self.obj, 1))
            {
                return "";
            }
            var cost = commander_getUnlockCost(self.obj);
            var s = global.label_resonanceCost + ": " + string(cost);
            if (global.currMetaCurrency < cost)
            {
                s += ", " + vwa_t("vwa--not-enough-resonance");
            }
            return s;
        }), false),
        vwa_part_fn("value", method({ obj: cmdrObj }, function()
        {
            if (commander_checkUnlockState(self.obj, 1)
                && !array_has_value(global.metaProgressionData.commanderHoverBadgeCleared,
                    objGN(self.obj)))
            {
                return vwa_t("vwa--state-new");
            }
            return "";
        }), false)
    ];
    // The sheet: resolved fresh every build (immediate mode), one line per
    // part so the alt-arrow review steps it. Hidden commanders get none -
    // the game suppresses their tooltip. The instance the sheet reads is
    // the display crew the game spawned (vwa_commander_prespawn guarantees
    // every non-hidden commander one); it missing is a mod/game bug, and
    // the throw lands in the screen quarantine (logged once, screen inert).
    if (!hiddenNow)
    {
        if (!instance_exists(cmdrObj))
        {
            throw ("commander display instance missing: " + objGN(cmdrObj));
        }
        var lines = vwa_sheet_crew_lines(instance_find(cmdrObj, 0),
            vwa_sheet_opt_flags(true, !global.gameStarted, global.enableEncyclopediaMode));
        for (var i = 0; i < array_length(lines); i++)
        {
            array_push(parts, vwa_part("tooltip", lines[i]));
        }
    }
    vwa_gb_add(bd, vwa_id_ref(cmdrObj, "cmdr:" + objGN(cmdrObj)), {
        parts: parts,
        onActivate: method({ obj: cmdrObj, lst: lst }, function()
        {
            var locked = commander_checkUnlockState(self.obj, 1);
            var hidden = commander_checkUnlockState(self.obj, 2);
            if (hidden)
            {
                // The game's click path ignores hidden rows; match the
                // navigator's no-action wording so Enter is never silent.
                vwa_speak([vwa_t("vwa--no-action")], false);
                return;
            }
            if (locked)
            {
                if (global.currMetaCurrency >= commander_getUnlockCost(self.obj))
                {
                    global.commanderToUnlock = self.obj;
                    instance_create_depth(0, 0, 0, oUIConfirmationDialogue_purchaseCommander);
                    sfx_start(global.sfx_chooseCommanderButton, 0, 1, 0, 0);
                }
                else
                {
                    // The game does nothing on this click; the visible
                    // signal is the greyed row. Speak it instead.
                    vwa_speak([vwa_t("vwa--not-enough-resonance")], true);
                }
                return;
            }
            self.lst.select_specific_commander(self.obj);
            sfx_start(global.sfx_chooseCommanderButton, 0, 1, 0, 0);
        })
    });
}
