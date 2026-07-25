// scrVwaMenuShipSelect - Void War Access ship select screen and its ship
// list overlay (session 12). Registered from vwa_menus_init via
// vwa_menu_ship_init. Step 2 of the new game flow. A room-per-ship
// composite: every hull variant is its own GameMaker room holding the LIVE
// ship (oHull, oSysGroup, oCrew, oModuleManager; weapons as hull data),
// cycling hulls calls room_goto, and the oShipMenu_* widgets are
// persistent instances that survive the switch - so focus carries across
// the room change on stable skeys with no extra machinery.
// Four Tab stops:
// 1) "ship" - the hull cycler (one slider over the game's hull cycle), the
//    variant slider (A/B/C; landing IS selection, mirroring the game's
//    variant press including its badge clear and room switch), the ship
//    name text field, the randomize-name button, the View List button,
//    and - locked hulls only - the game's Purchase button and the
//    Resonance counter.
// 2) "details" - four submenu sections labeled with the game's own
//    painted labels: Crew (one node per crew of the FULL list, personal
//    name then type name plus the crew sheet; Enter renames through the
//    text edit layer; the game's crew pages follow focus through the
//    auto-paging pattern in scrVwaWidgets; the name-toggle button is
//    deliberately NOT surfaced - its only effect is choosing which of the
//    two names we already speak gets painted), Systems, Loadout (weapons
//    then equipment stacks), Modules. On a HIDDEN hull each section
//    collapses to a single NO DATA node (mirrors
//    playerShip_checkVisibilityInShipMenu).
// 3) "commander" - the commander button (opens the commander overlay, the
//    registered commander-select screen auto-stacks on top), the
//    victorious-commanders and highest-torment records (emitted only when
//    the game draws them), and the difficulty slider (Normal through the
//    highest unlocked Torment; the game's dash marker verbalized as
//    "completed"; the per-level tooltip as a detail line; adjusting
//    applies through the game's own select_dropdownEntry, matching its
//    entry-click path).
// 4) "actions" - Launch (no confirmation, mirrors the game exactly; when
//    locked speaks the locked reason - game-hardcoded English, ours via
//    vwa_t), Randomize Hull (live identity part speaks the rolled ship),
//    View Exterior (a toggle speaking on/off), Main Menu.
// Speech text composition lives in scrVwaShip (pure); this file only
// wires nodes and mirrors activation paths.
// Imported by tools/build-mod.csx as a new global script. Ships in release.

function vwa_menu_ship_init()
{
    // The ship select screen (menuToggle 12). The gate is the persistent
    // selector INSTANCE plus the menu flags that mean the composite is
    // alive: 12 (ship select itself, held through the room_goto transition
    // frames), 11 (the ship list overlay above), 13 (the commander overlay
    // above), 14 (a confirmation dialogue above - the ship purchase; same
    // lesson as commander-select's instance gate) - the screen stays
    // stacked, covered with focus remembered, under all three. Launch
    // flips the flag to 0 and the screen pops. The game's own Escape
    // handling stays untouched (the selector's raw Escape goes back to
    // commander select). postDispatch consumes the raw arrow keys the
    // selector's own arrowKeysToCycle would read in its Step: hull cycling
    // must happen ONLY through the cycler node - a left/right the
    // navigator just handled (or one pressed mid-name-edit, a real game
    // quirk) must not also cycle the ship underneath. Structure:
    // vwa_ship_select_build.
    vwa_screen_register({
        key: "ship-select",
        layerNum: 38,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading
                && instance_exists(oShipMenu_shipSelector)
                && (global.menuToggle == 11 || global.menuToggle == 12
                    || global.menuToggle == 13 || global.menuToggle == 14);
        },
        name: function() { return global.label_hangar; },
        build: function(bd) { vwa_ship_select_build(bd); },
        postDispatch: function()
        {
            if (global.menuToggle == 12)
            {
                vwa_input_consume_key(vk_left);
                vwa_input_consume_key(vk_right);
            }
        }
    });

    // The ship list overlay (menuToggle 11, oShipListMenu): every hull as
    // one button plus the overlay's own variant selector. Above
    // ship-select, below commander-select and the confirm screen. Escape
    // closes it through the game's own closeMenu (consumed, so nothing
    // underneath also reacts). Structure: vwa_ship_list_build.
    vwa_screen_register({
        key: "ship-list",
        layerNum: 39,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && instance_exists(oShipListMenu);
        },
        name: function() { return global.label_selectHull; },
        build: function(bd) { vwa_ship_list_build(bd); },
        onBack: function()
        {
            var mn = instance_find(oShipListMenu, 0);
            if (!instance_exists(mn))
            {
                return false;
            }
            with (mn)
            {
                closeMenu();
            }
            return true;
        }
    });
}

// The MAIN screen's variant selector: the ship list overlay spawns a
// second oShipMenu_variantSelector parented to itself.
function vwa_ship_variant_selector()
{
    var cnt = instance_number(oShipMenu_variantSelector);
    for (var i = 0; i < cnt; i++)
    {
        var vs = instance_find(oShipMenu_variantSelector, i);
        if (vs.parentObjIndex != oShipListMenu)
        {
            return vs;
        }
    }
    return undefined;
}

function vwa_ship_variant_number()
{
    var vs = vwa_ship_variant_selector();
    return (vs != undefined) ? vs.selectedIndex + 1 : 1;
}

// The ship name the GAME paints: the field's text only while the field
// draws it (oShipMenu_shipName Draw_64's gate - visible and not
// locked-without-debug), the game's own NO DATA marker otherwise. A hidden
// hull's field still HOLDS its real name; speaking that would reveal an
// unrevealed vessel, so every name readout goes through this.
function vwa_ship_name_visible_text()
{
    var f = instance_find(oShipMenu_shipName, 0);
    if (!instance_exists(f))
    {
        return "";
    }
    if (playerShip_checkVisibilityInShipMenu()
        && !(playerShip_checkUnlockState(room, 1) && !global.enableDebugKeys))
    {
        return string(f.text);
    }
    return string(global.label_noData);
}

// The identity of the ship the selector is ON (or heading to): selectedRoom
// is set synchronously BEFORE room_goto, so this is never stale, even on
// the transition frame (scrVwaShip composes from room-keyed data only).
function vwa_ship_current_identity()
{
    var sel = instance_find(oShipMenu_shipSelector, 0);
    var rm = room;
    if (instance_exists(sel) && sel.selectedRoom != -4)
    {
        rm = sel.selectedRoom;
    }
    return vwa_ship_identity_line(rm, vwa_ship_variant_number());
}

// Called after one of the game's own cycle/press methods ran. A cycle that
// leaves the current room queues a room_goto; a SECOND cycle in the same
// frame that lands back on the CURRENT room hits goToSelectedRoom's
// same-name guard (it skips re-queuing), which would leave the first, now
// stale goto to fire at frame end and desync room from selectedRoom.
// Physically impossible from a keyboard (one press per frame) but the
// walker's net-zero adjust probe does exactly this. Re-target the pending
// goto at the current room: a same-room goto is a room restart, the same
// event class as any real hull switch (the persistent widgets survive and
// the ship respawns), and create_objects_in_array's exists-check keeps the
// selector singular.
function vwa_ship_goto_sync()
{
    var sel = instance_find(oShipMenu_shipSelector, 0);
    if (!instance_exists(sel))
    {
        return;
    }
    if (sel.selectedRoom != -4 && sel.selectedRoom != room)
    {
        global.vwaShipGotoTick = global.vwaInputTicks;
        return;
    }
    if (variable_global_exists("vwaShipGotoTick")
        && global.vwaShipGotoTick == global.vwaInputTicks)
    {
        global.vwaShipGotoTick = -1;
        vwa_log("ship: same-frame cycle returned to the current room;"
            + " restarting it to clear the stale goto");
        room_goto(room);
    }
}

// The auto-paging tick for the crew section: the game windows six crew
// per page (gridW x gridH) and only pages the DRAWING - the instances all
// live in the room - so this only keeps the visible page under focus.
// Steps mirror the game's own mouse-wheel path (nextPage/prevPage bare,
// no sfx - the sound belongs to its click path).
function vwa_ship_crew_ensure_visible()
{
    var cb = instance_find(oShipMenu_crewButton, 0);
    if (!instance_exists(cb))
    {
        return;
    }
    vwa_pages_ensure_visible(vwa_screen_find("ship-select"), {
        focusPage: method({ cb: cb }, function(skey)
        {
            if (string_pos("ship-crew:", skey) != 1)
            {
                return -1;
            }
            var idx = real(string_delete(skey, 1, 10));
            var per = self.cb.gridW * self.cb.gridH;
            return floor(idx / per);
        }),
        curPage: method({ cb: cb }, function()
        {
            return self.cb.currPage - 1; // the game's page is 1-based
        }),
        pageCount: method({ cb: cb }, function()
        {
            var c = self.cb;
            var per = c.gridW * c.gridH;
            return clamp(ceil(array_length(c.crewList) / per), 1, 999);
        }),
        stepNext: method({ cb: cb }, function()
        {
            with (self.cb)
            {
                nextPage();
            }
        }),
        stepPrev: method({ cb: cb }, function()
        {
            with (self.cb)
            {
                prevPage();
            }
        })
    });
}

function vwa_ship_select_build(bd)
{
    vwa_ship_crew_ensure_visible();

    vwa_gb_begin_stop(bd, "ship");
    vwa_ship_stop_build(bd);

    vwa_gb_begin_stop(bd, "details");
    vwa_gb_push_context(bd, vwa_t("vwa--stop-ship-details"));
    vwa_ship_crew_section(bd);
    vwa_ship_systems_section(bd);
    vwa_ship_loadout_section(bd);
    vwa_ship_modules_section(bd);
    vwa_gb_pop_context(bd);

    vwa_gb_begin_stop(bd, "commander");
    vwa_gb_push_context(bd, vwa_t("vwa--stop-cmdr-difficulty"));
    vwa_ship_commander_stop_build(bd);
    vwa_gb_pop_context(bd);

    vwa_gb_begin_stop(bd, "actions");
    vwa_gb_push_context(bd, vwa_t("vwa--stop-actions"));
    vwa_ship_actions_stop_build(bd);
    vwa_gb_pop_context(bd);
}

// ---- stop 1: the ship ----

// One function per control cluster, in painted order.
function vwa_ship_stop_build(bd)
{
    vwa_ship_cycler_add(bd);
    vwa_ship_variant_add(bd);
    vwa_ship_name_add(bd);
    vwa_ship_randomize_add(bd);
    vwa_ship_view_list_add(bd);
    vwa_ship_unlock_add(bd);
}

// The hull cycler. onAdjust drives the game's own
// selectedIndex_previous/next - the exact methods its native
// arrow-key cycling calls (they skip disabled hulls themselves). The
// raw-arrow consume lives in the screen's postDispatch.
function vwa_ship_cycler_add(bd)
{
    var sel = instance_find(oShipMenu_shipSelector, 0);
    vwa_gb_add(bd, vwa_id_ref(sel, "ship-cycler"), {
        typeKey: "slider",
        parts: [
            vwa_part_fn("label", function()
            {
                return vwa_t("vwa--ship-cycler");
            }, false),
            vwa_part_fn("value", function()
            {
                return vwa_ship_current_identity();
            }, true)
        ],
        onAdjust: method({ sel: sel }, function(sign, large)
        {
            with (self.sel)
            {
                if (sign > 0)
                {
                    selectedIndex_next();
                }
                else
                {
                    selectedIndex_previous();
                }
            }
            vwa_ship_goto_sync();
        })
    });
}

// The variant slider (A/B/C). Landing IS selection: onAdjust steps to
// the next buttonActive variant and runs the game's own stored onPress
// (badge clear, get_selectedRoom, goToSelectedRoom - the full press
// path). The second live part speaks the resulting ship.
function vwa_ship_variant_add(bd)
{
    var vs = vwa_ship_variant_selector();
    if (vs != undefined)
    {
        vwa_gb_add(bd, vwa_id_ref(vs, "ship-variant"), {
            typeKey: "slider",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_variant;
                }, false),
                vwa_part_fn("value", method({ vs: vs }, function()
                {
                    return self.vs.buttonLabel[self.vs.selectedIndex];
                }), true),
                vwa_part_fn("value", function()
                {
                    return vwa_ship_current_identity();
                }, true)
            ],
            onAdjust: method({ vs: vs }, function(sign, large)
            {
                var v = self.vs;
                var idx = v.selectedIndex + sign;
                while (idx >= 0 && idx <= 2 && !v.buttonActive[idx])
                {
                    idx += sign;
                }
                if (idx < 0 || idx > 2 || idx == v.selectedIndex)
                {
                    return; // range edge, like any slider end
                }
                var fn = v.onPress;
                fn(idx);
                vwa_ship_goto_sync();
            })
        });
    }
}

// The ship name field. Editable exactly when the game's field is
// (visible and not locked-without-debug: oShipMenu_shipName Draw_64);
// otherwise a NO DATA label, mirroring what the game paints. The edit
// adapter mirrors all three of the field's own branches: click-to-edit
// on entry, the Enter branch on commit (the game's stored set_name -
// writes customHullName and saves), and the Escape branch on cancel
// (flags only, nothing written; the field's own Step then repaints the
// stored name while no custom name is set - its behavior, mirrored).
function vwa_ship_name_add(bd)
{
    var sn = instance_find(oShipMenu_shipName, 0);
    if (instance_exists(sn))
    {
        var editable = playerShip_checkVisibilityInShipMenu()
            && !(playerShip_checkUnlockState(room, 1) && !global.enableDebugKeys);
        if (editable)
        {
            vwa_gb_add(bd, vwa_id_ref(sn, "ship-name"), {
                typeKey: "textfield",
                parts: [
                    vwa_part_fn("label", function()
                    {
                        return vwa_t("vwa--ship-name");
                    }, false),
                    vwa_part_fn("value", method({ sn: sn }, function()
                    {
                        // Not live: scrVwaText owns edit feedback.
                        return string(self.sn.text);
                    }), false),
                    vwa_part_fn("tooltip", function()
                    {
                        return global.label_clickToEditShipName;
                    }, false)
                ],
                onActivate: method({ sn: sn }, function()
                {
                    var fld = self.sn;
                    vwa_text_begin({
                        onEnter: method({ fld: fld }, function()
                        {
                            global.textFieldInputEnabled = true;
                            self.fld.UIFocus = true;
                        }),
                        onCommit: method({ fld: fld }, function()
                        {
                            global.textFieldInputEnabled = false;
                            if (instance_exists(self.fld))
                            {
                                self.fld.UIFocus = false;
                                var fn = self.fld.set_name;
                                fn();
                            }
                            else
                            {
                                vwa_log("ERROR: ship name field gone on edit commit");
                            }
                        }),
                        onCancel: method({ fld: fld }, function()
                        {
                            global.textFieldInputEnabled = false;
                            if (instance_exists(self.fld))
                            {
                                self.fld.UIFocus = false;
                            }
                        })
                    });
                })
            });
        }
        else
        {
            vwa_gb_add(bd, vwa_id_ref(sn, "ship-name"), {
                typeKey: "label",
                parts: [
                    vwa_part_fn("label", function()
                    {
                        return vwa_t("vwa--ship-name");
                    }, false),
                    vwa_part_fn("value", function()
                    {
                        return global.label_noData;
                    }, false)
                ]
            });
        }
    }
}

// Randomize name (mirrors oShipMenu_randomShipName's press; the live
// value part is the name the game paints, so activation speaks the
// roll - and stays NO DATA on a hidden or locked hull, where the game
// rolls invisibly behind its NO DATA field).
function vwa_ship_randomize_add(bd)
{
    var rnd = instance_find(oShipMenu_randomShipName, 0);
    if (instance_exists(rnd))
    {
        vwa_gb_add(bd, vwa_id_ref(rnd, "ship-randomize-name"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return vwa_t("vwa--randomize-name");
                }, false),
                vwa_part_fn("value", function()
                {
                    return vwa_ship_name_visible_text();
                }, true)
            ],
            onActivate: method({ inst: rnd }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }
}

// View List (opens the ship list overlay; its Step spawns oShipListMenu
// and flips the flag to 11 - the ship-list screen then stacks on top).
// The live part mirrors the red badge count on the button: hulls
// unlocked but never yet hovered.
function vwa_ship_view_list_add(bd)
{
    var lbtn = instance_find(oShipMenu_shipListButton, 0);
    if (instance_exists(lbtn))
    {
        vwa_gb_add(bd, vwa_id_ref(lbtn, "ship-view-list"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_list;
                }, false),
                vwa_part_fn("value", method({ inst: lbtn }, function()
                {
                    var b = self.inst;
                    var fn = b.shipListUnlockHoverBadge_getCount;
                    var k = fn();
                    if (k <= 0)
                    {
                        return "";
                    }
                    return string_replace(vwa_t("vwa--page-new"), "{k}", string(k));
                }), false),
                vwa_part_fn("tooltip", function()
                {
                    return global.label_viewShipList;
                }, false)
            ],
            onActivate: method({ inst: lbtn }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }
}

// Locked hull extras: the game's Purchase button (spawned by the
// selector's Room Start only while the hull is locked with a price)
// and the Resonance counter next to it - the same pattern as the
// commander screen's Resonance node, tooltip mirrored verbatim
// (game-authored English hardcoded in the counter's draw).
function vwa_ship_unlock_add(bd)
{
    var ub = instance_find(oButton_metaUnlock, 0);
    if (instance_exists(ub))
    {
        vwa_gb_add(bd, vwa_id_ref(ub, "ship-unlock"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return vwa_t("vwa--ship-purchase");
                }, false),
                vwa_part_fn("value", method({ inst: ub }, function()
                {
                    return string(global.label_resonanceCost) + ": "
                        + string(self.inst.price);
                }), false),
                vwa_part_fn("value", method({ inst: ub }, function()
                {
                    if (global.currMetaCurrency < self.inst.price)
                    {
                        return vwa_t("vwa--not-enough-resonance");
                    }
                    return "";
                }), false)
            ],
            onActivate: method({ inst: ub }, function()
            {
                // Mirror of its Draw click path: blocked by an open
                // dialogue, is_pressable refuses (the game's click just
                // does nothing then; speak the reason instead), then the
                // stored onPress (spawns the purchase dialogue + click
                // sound; the generic confirm screen covers it).
                var bt = self.inst;
                if (instance_exists(oUIConfirmationDialogue))
                {
                    vwa_log("ERROR: unlock press with a dialogue open"
                        + " - screen stack out of sync?");
                    return;
                }
                var fp = bt.is_pressable;
                if (!fp())
                {
                    vwa_speak([vwa_t("vwa--not-enough-resonance")], true);
                    return;
                }
                var fn = bt.onPress;
                fn();
            })
        });
        var cm = instance_find(oCounterMetaCurrency, 0);
        if (instance_exists(cm))
        {
            vwa_gb_add(bd, vwa_id_ref(cm, "ship-resonance"), {
                parts: [
                    vwa_part_fn("label", function()
                    {
                        return global.label_resonance;
                    }, false),
                    vwa_part_fn("value", function()
                    {
                        return string(global.currMetaCurrency);
                    }, true),
                    vwa_part("tooltip", "Used for unlocking ships and commanders.")
                ]
            });
        }
    }
}

// ---- stop 2: ship details ----

// A hidden hull's section body: the game's own NO DATA marker.
function vwa_ship_nodata_add(bd, skey)
{
    vwa_gb_add(bd, vwa_id(skey), {
        typeKey: "label",
        parts: [vwa_part_fn("label", function()
        {
            return global.label_noData;
        }, false)]
    });
}

function vwa_ship_crew_section(bd)
{
    vwa_gb_begin_submenu(bd, vwa_id("ship-crew"), {
        parts: [vwa_part_fn("label", function()
        {
            return global.label_crew;
        }, false)]
    });
    if (!playerShip_checkVisibilityInShipMenu())
    {
        vwa_ship_nodata_add(bd, "ship-crew-nodata");
    }
    else
    {
        var cb = instance_find(oShipMenu_crewButton, 0);
        var lst = instance_exists(cb) ? cb.crewList : [];
        for (var i = 0; i < array_length(lst); i++)
        {
            var crew = lst[i];
            if (!instance_exists(crew))
            {
                continue; // transition frame: the old ship's crew died
            }
            // Personal name first, then the type name (always both -
            // Rashad's call; the game's toggle merely picks which one it
            // paints). The sheet mirrors the game's hover crew tooltip.
            var parts = [
                vwa_part_fn("label", method({ crew: crew }, function()
                {
                    return instance_exists(self.crew)
                        ? string(self.crew.crewName) : "";
                }), false),
                vwa_part_fn("value", method({ crew: crew }, function()
                {
                    return instance_exists(self.crew)
                        ? string(self.crew.baseName) : "";
                }), false)
            ];
            var lines = vwa_sheet_crew_lines(crew,
                vwa_sheet_opt_flags(false, false, global.enableEncyclopediaMode));
            for (var j = 0; j < array_length(lines); j++)
            {
                array_push(parts, vwa_part("tooltip", lines[j]));
            }
            vwa_gb_add(bd, vwa_id_ref(crew, "ship-crew:" + string(i)), {
                typeKey: "textfield",
                parts: parts,
                onActivate: method({ cb: cb, idx: i }, function()
                {
                    vwa_ship_crew_rename(self.cb, self.idx);
                })
            });
        }
    }
    vwa_gb_end_submenu(bd);
}

// Enter on a crew node: rename through the text edit layer. The adapter
// mirrors the crew button's own click-to-edit branch (Draw_64) on entry
// and its Enter-commit branch on commit (assign crewName, save via the
// game's shipSelect_saveCrewNames). The game gives crew rename NO cancel
// path (only mouse/Enter commits), so cancel is simply not-committing:
// crewName is only ever written on commit, and clearing the edit state
// leaves the original name standing.
function vwa_ship_crew_rename(cb, idx)
{
    if (!instance_exists(cb) || idx >= array_length(cb.crewList)
        || !instance_exists(cb.crewList[idx]))
    {
        vwa_log("ERROR: crew rename: row " + string(idx) + " gone");
        return;
    }
    vwa_text_begin({
        onEnter: method({ cb: cb, idx: idx }, function()
        {
            var c = self.cb;
            c.toggleCrewNames = true;
            c.indexToEdit = self.idx;
            c.editCrewNameStr = string(c.crewList[self.idx].crewName);
            global.textFieldInputEnabled = true;
            if (instance_exists(oTextField))
            {
                oTextField.text = c.editCrewNameStr;
            }
            with (all)
            {
                if (id != c.id && variable_instance_exists(id, "UIFocus"))
                {
                    UIFocus = false;
                }
            }
            c.UIFocus = true;
        }),
        onCommit: method({ cb: cb }, function()
        {
            var c = self.cb;
            global.textFieldInputEnabled = false;
            c.UIFocus = false;
            if (c.indexToEdit != -4 && c.indexToEdit < array_length(c.crewList)
                && instance_exists(c.crewList[c.indexToEdit]))
            {
                c.crewList[c.indexToEdit].crewName = c.editCrewNameStr;
                shipSelect_saveCrewNames();
            }
            else
            {
                vwa_log("ERROR: crew rename commit: row gone");
            }
            c.editCrewNameStr = "";
            c.indexToEdit = -4;
        }),
        onCancel: method({ cb: cb }, function()
        {
            var c = self.cb;
            global.textFieldInputEnabled = false;
            c.UIFocus = false;
            c.editCrewNameStr = "";
            c.indexToEdit = -4;
        })
    });
}

function vwa_ship_systems_section(bd)
{
    vwa_gb_begin_submenu(bd, vwa_id("ship-systems"), {
        parts: [vwa_part_fn("label", function()
        {
            return global.label_systems;
        }, false)]
    });
    if (!playerShip_checkVisibilityInShipMenu())
    {
        vwa_ship_nodata_add(bd, "ship-systems-nodata");
    }
    else
    {
        var sysWidget = instance_find(oShipMenu_systems, 0);
        var lst = instance_exists(sysWidget) ? sysWidget.systemList : [];
        for (var i = 0; i < array_length(lst); i++)
        {
            var sys = lst[i];
            if (!instance_exists(sys))
            {
                continue; // transition frame
            }
            var lines = vwa_ship_system_lines(sys,
                vwa_ship_opt_flags(global.enableEncyclopediaMode));
            if (array_length(lines) == 0)
            {
                continue; // already logged by the composer
            }
            var parts = [vwa_part("label", lines[0])];
            for (var j = 1; j < array_length(lines); j++)
            {
                array_push(parts, vwa_part("tooltip", lines[j]));
            }
            vwa_gb_add(bd, vwa_id_ref(sys, "ship-sys:" + string(i)), {
                typeKey: "label",
                parts: parts
            });
        }
    }
    vwa_gb_end_submenu(bd);
}

function vwa_ship_loadout_section(bd)
{
    vwa_gb_begin_submenu(bd, vwa_id("ship-loadout"), {
        parts: [vwa_part_fn("label", function()
        {
            return global.label_loadout;
        }, false)]
    });
    if (!playerShip_checkVisibilityInShipMenu())
    {
        vwa_ship_nodata_add(bd, "ship-loadout-nodata");
    }
    else
    {
        // Weapons and ordnance: the armament widget's list (object
        // indices from the hull's startWeapon/startOrdnance, rebuilt by
        // the game's room init).
        var arm = instance_find(oShipMenu_armamentSlots, 0);
        var wl = instance_exists(arm) ? arm.weaponList : [];
        for (var i = 0; i < array_length(wl); i++)
        {
            var lines = vwa_ship_weapon_lines(wl[i],
                vwa_ship_opt_flags(global.enableEncyclopediaMode));
            if (array_length(lines) == 0)
            {
                continue;
            }
            var parts = [vwa_part("label", lines[0])];
            for (var j = 1; j < array_length(lines); j++)
            {
                array_push(parts, vwa_part("tooltip", lines[j]));
            }
            vwa_gb_add(bd, vwa_id("ship-wpn:" + string(i)), {
                typeKey: "label",
                parts: parts
            });
        }
        // Equipment stacks (the game aggregates quantities per item).
        var eq = instance_find(oShipMenu_equipmentList, 0);
        var el = instance_exists(eq) ? eq.equipmentList : [];
        for (var i = 0; i < array_length(el); i++)
        {
            var lines = vwa_ship_equipment_lines(el[i], eq.equipmentQt[i]);
            if (array_length(lines) == 0)
            {
                continue;
            }
            var parts = [vwa_part("label", lines[0])];
            for (var j = 1; j < array_length(lines); j++)
            {
                array_push(parts, vwa_part("tooltip", lines[j]));
            }
            vwa_gb_add(bd, vwa_id("ship-eq:" + string(i)), {
                typeKey: "label",
                parts: parts
            });
        }
    }
    vwa_gb_end_submenu(bd);
}

function vwa_ship_modules_section(bd)
{
    vwa_gb_begin_submenu(bd, vwa_id("ship-modules"), {
        parts: [vwa_part_fn("label", function()
        {
            return global.label_modules;
        }, false)]
    });
    if (!playerShip_checkVisibilityInShipMenu())
    {
        vwa_ship_nodata_add(bd, "ship-modules-nodata");
    }
    else if (instance_exists(oModuleManager))
    {
        // One node per painted slot widget, in slot order; a filled slot
        // speaks the module lines, an empty one the game's own label.
        var slots = [];
        var cnt = instance_number(oShipMenu_moduleSlots);
        for (var i = 0; i < cnt; i++)
        {
            array_push(slots, instance_find(oShipMenu_moduleSlots, i));
        }
        array_sort(slots, function(a, b)
        {
            if (a.moduleSlot != b.moduleSlot)
            {
                return (a.moduleSlot < b.moduleSlot) ? -1 : 1;
            }
            return 0;
        });
        var mgr = instance_find(oModuleManager, 0);
        for (var i = 0; i < array_length(slots); i++)
        {
            var slotNum = slots[i].moduleSlot;
            var mdl = (slotNum < array_length(mgr.modules_player))
                ? mgr.modules_player[slotNum] : -4;
            var parts;
            if (objInst_exists(mdl))
            {
                var lines = vwa_ship_module_lines(mdl,
                    vwa_ship_opt_flags(global.enableEncyclopediaMode));
                if (array_length(lines) == 0)
                {
                    continue;
                }
                parts = [vwa_part("label", lines[0])];
                for (var j = 1; j < array_length(lines); j++)
                {
                    array_push(parts, vwa_part("tooltip", lines[j]));
                }
            }
            else
            {
                parts = [vwa_part_fn("label", function()
                {
                    return global.label_emptyModuleSlot;
                }, false)];
            }
            vwa_gb_add(bd, vwa_id_ref(slots[i], "ship-mod:" + string(slotNum)), {
                typeKey: "label",
                parts: parts
            });
        }
    }
    vwa_gb_end_submenu(bd);
}

// ---- stop 3: commander and difficulty ----
function vwa_ship_commander_stop_build(bd)
{
    // The commander button: speaks the selected commander, Enter mirrors
    // its Step click (sound, spawn the commander list, flag 13) - the
    // registered commander-select screen then stacks on top by itself.
    var cbn = instance_find(oShipMenu_commanderButton, 0);
    if (instance_exists(cbn))
    {
        vwa_gb_add(bd, vwa_id_ref(cbn, "ship-commander"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_selectCommander;
                }, false),
                vwa_part_fn("value", method({ inst: cbn }, function()
                {
                    var pc = self.inst.playerCrewID;
                    if (!instance_exists(pc))
                    {
                        return "";
                    }
                    return string(pc.crewName) + ", " + string(pc.baseName);
                }), true)
            ],
            onActivate: method({ inst: cbn }, function()
            {
                var bt = self.inst;
                if (instance_exists(oUICommanderPanel)
                    || global.menuToggle != 12 || bt.buttonDisabled)
                {
                    vwa_log("ERROR: commander button blocked"
                        + " - screen stack out of sync?");
                    return;
                }
                sfx_start(global.sfx_click3, 0, 1, 0, 0);
                instance_create_depth(0, 0, 0, oUICommanderList);
                gameMenu_setFlag(13);
            })
        });
    }

    // The records, emitted only when the game draws them: the highest
    // torment icon requires a completed run on this hull, and the
    // victorious-commanders counter additionally requires at least one
    // winner (oShipMenu_commanderWins Draw_64's own gates). Tooltip lines
    // mirror its header tooltip: one "name (difficulty)" line per winner.
    var ht = instance_find(oShipMenu_highestTorment, 0);
    var showRecord = instance_exists(ht)
        && ht.highestTormentCompletedCurrRoom != -1;
    var vw = instance_find(oShipMenu_commanderWins, 0);
    if (instance_exists(vw) && vw.commanderWinCt > 0 && showRecord)
    {
        var winners = array_combine(commanderList_startingCommanders(),
            commanderList_hiddenCommanders());
        var parts = [
            vwa_part_fn("label", function()
            {
                return global.label_victoriousCommanders;
            }, false),
            vwa_part_fn("value", method({ inst: vw, total: array_length(winners) },
                function()
            {
                return string(self.inst.commanderWinCt) + "/" + string(self.total);
            }), false)
        ];
        for (var i = 0; i < array_length(winners); i++)
        {
            if (commanderWinData_won_with_ship(winners[i], room))
            {
                array_push(parts, vwa_part("tooltip",
                    string(crew_get_info(winners[i], 31)) + " ("
                    + string(runDifficulty_to_str(
                        commanderWinData_get_ship_win_difficulty(winners[i], room)))
                    + ")"));
            }
        }
        vwa_gb_add(bd, vwa_id_ref(vw, "ship-cmdr-wins"), {
            typeKey: "label",
            parts: parts
        });
    }
    if (showRecord)
    {
        vwa_gb_add(bd, vwa_id_ref(ht, "ship-torment-record"), {
            typeKey: "label",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_utmostVanquishedTormentLevel;
                }, false),
                vwa_part_fn("value", method({ inst: ht }, function()
                {
                    var t = self.inst.highestTormentCompletedCurrRoom;
                    // The game's own tooltip wording: Normal for level 0,
                    // the plain number otherwise.
                    return (t == 0) ? string(global.label_normal) : string(t);
                }), false)
            ]
        });
    }

    // The difficulty slider over the game's dropdown: entries already span
    // Normal through the highest unlocked Torment (init_dropdownEntries).
    // The dash-wrapped entry is the game's completed marker - stripped and
    // verbalized. Adjusting mirrors the dropdown's entry-click commit
    // (vwa_dropdown_choose's path: the select sound, the index, the stored
    // select_dropdownEntry - the game re-applies on launch either way).
    // Mouse users can still open the real dropdown; the vwa-dropdown child
    // screen covers that as on any settings menu.
    var ds = instance_find(oShipMenu_difficultySelector, 0);
    if (instance_exists(ds))
    {
        vwa_gb_add(bd, vwa_id_ref(ds, "ship-difficulty"), {
            typeKey: "slider",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_difficulty;
                }, false),
                vwa_part_fn("value", method({ inst: ds }, function()
                {
                    var el = self.inst;
                    var s = string(el.dropdownEntries[el.dropdown_currSelectedIndex]);
                    var n = string_length(s);
                    if (n >= 2 && string_char_at(s, 1) == "-"
                        && string_char_at(s, n) == "-")
                    {
                        s = string_copy(s, 2, n - 2) + ", "
                            + vwa_t("vwa--difficulty-completed");
                    }
                    return s;
                }), true),
                vwa_part_fn("tooltip", method({ inst: ds }, function()
                {
                    var el = self.inst;
                    var i = el.dropdown_currSelectedIndex;
                    if (i < 0 || i >= array_length(el.dropdownTooltipStr))
                    {
                        return "";
                    }
                    return string(el.dropdownTooltipStr[i]);
                }), false)
            ],
            onAdjust: method({ inst: ds }, function(sign, large)
            {
                var el = self.inst;
                var n = array_length(el.dropdownEntries);
                var idx = clamp(el.dropdown_currSelectedIndex + sign, 0, n - 1);
                if (idx == el.dropdown_currSelectedIndex)
                {
                    return;
                }
                sfx_start_ext(global.sfx_selectDropdownEntry, 0, 1, 0, 0, 0);
                el.dropdown_currSelectedIndex = idx;
                if (el.select_dropdownEntry != -4)
                {
                    var fn = el.select_dropdownEntry;
                    fn();
                }
            })
        });
    }
}

// ---- stop 4: actions ----
function vwa_ship_actions_stop_build(bd)
{
    // Launch: mirrors the game exactly - no confirmation, the run starts.
    // The locked refusal speaks the game's locked-tooltip reason (the
    // game hardcodes it in English; ours is a vwa_t row).
    var lb = instance_find(oShipMenu_launchButton, 0);
    if (instance_exists(lb))
    {
        vwa_gb_add(bd, vwa_id_ref(lb, "ship-launch"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_launch;
                }, false),
                vwa_part_fn("enabled", method({ inst: lb }, function()
                {
                    var act = self.inst.buttonActive;
                    return act() ? "" : vwa_t("vwa--state-disabled");
                }), true),
                vwa_part_fn("tooltip", method({ inst: lb }, function()
                {
                    var act = self.inst.buttonActive;
                    return act() ? "" : vwa_t("vwa--launch-locked");
                }), false)
            ],
            onActivate: method({ inst: lb }, function()
            {
                var bt = self.inst;
                var act = bt.buttonActive;
                if (!act())
                {
                    vwa_speak([vwa_t("vwa--launch-locked")], false);
                    return;
                }
                vwa_obutton_activate(bt);
            })
        });
    }

    // Randomize Hull: the live identity part speaks the rolled ship (the
    // game's method no-ops until a second hull is unlocked - the value
    // then stays put and nothing false is spoken).
    var rl = instance_find(oShipMenu_randomizeLayout, 0);
    if (instance_exists(rl))
    {
        vwa_gb_add(bd, vwa_id_ref(rl, "ship-randomize-hull"), {
            typeKey: "button",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_randomizeHull;
                }, false),
                vwa_part_fn("value", function()
                {
                    return vwa_ship_current_identity();
                }, true)
            ],
            onActivate: method({ inst: rl }, function()
            {
                vwa_obutton_activate(self.inst);
                vwa_ship_goto_sync();
            })
        });
    }

    // View Exterior: a toggle on global.hullViewExterior.
    var ve = instance_find(oShipMenu_viewExterior, 0);
    if (instance_exists(ve))
    {
        vwa_gb_add(bd, vwa_id_ref(ve, "ship-view-exterior"), {
            typeKey: "toggle",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_viewExterior;
                }, false),
                vwa_part_fn("value", function()
                {
                    return global.hullViewExterior
                        ? vwa_t("vwa--state-on") : vwa_t("vwa--state-off");
                }, true)
            ],
            onActivate: method({ inst: ve }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }

    // Main Menu (VS_reset through the button's own Step).
    var mm = instance_find(oShipMenu_mainMenu, 0);
    if (instance_exists(mm))
    {
        vwa_gb_add(bd, vwa_id_ref(mm, "ship-main-menu"), {
            typeKey: "button",
            parts: [vwa_part_fn("label", function()
            {
                return global.label_mainMenu;
            }, false)],
            onActivate: method({ inst: mm }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }
}

// ---- the ship list overlay (menuToggle 11) ----
// One node per drawn hull button (buttonIndex order): identity by the
// BUTTON's own state fields (shipHidden there means reveal-condition
// hidden - the list's rule, wider than the main screen's), unlock cost
// with affordability, the quest unlock tooltip line, and the new badge.
// Then the overlay's own variant slider (its onPress path re-targets
// every hull button, no room switch). Hull activation runs the button's
// full press path: queue the room, flag back to 12, closeMenu - the
// ship-select screen underneath regains focus on the new hull. Hidden and
// coming-soon hulls carry no action (the game's own button is inert on
// them), so Enter speaks the no-action line.
function vwa_ship_list_build(bd)
{
    var mn = instance_find(oShipListMenu, 0);
    if (!instance_exists(mn))
    {
        return; // closed this same frame; empty build, screen pops next tick
    }
    var btns = [];
    var cnt = instance_number(oShipListMenu_hullButton);
    for (var i = 0; i < cnt; i++)
    {
        var b = instance_find(oShipListMenu_hullButton, i);
        var dc = b.drawConditionsMet;
        if (dc == -4 || dc())
        {
            array_push(btns, b);
        }
    }
    array_sort(btns, function(a, b)
    {
        if (a.buttonIndex != b.buttonIndex)
        {
            return (a.buttonIndex < b.buttonIndex) ? -1 : 1;
        }
        return 0;
    });
    for (var i = 0; i < array_length(btns); i++)
    {
        vwa_ship_list_hull_add(bd, mn, btns[i]);
    }

    var vs = mn.variantSelector;
    if (instance_exists(vs))
    {
        vwa_gb_add(bd, vwa_id_ref(vs, "list-variant"), {
            typeKey: "slider",
            parts: [
                vwa_part_fn("label", function()
                {
                    return global.label_variant;
                }, false),
                vwa_part_fn("value", method({ vs: vs }, function()
                {
                    return self.vs.buttonLabel[self.vs.selectedIndex];
                }), true)
            ],
            onAdjust: method({ vs: vs }, function(sign, large)
            {
                var v = self.vs;
                var idx = clamp(v.selectedIndex + sign, 0, 2);
                if (idx == v.selectedIndex)
                {
                    return;
                }
                var fn = v.onPress;
                fn(idx);
            })
        });
    }
}

function vwa_ship_list_hull_add(bd, mn, btn)
{
    var cfg = {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ btn: btn }, function()
            {
                // Mirror of drawLabels: hidden or coming-soon variants are
                // the Unknown Vessel; otherwise class + the overlay's
                // current variant letter, the hull name when unlocked, and
                // the locked state word.
                var b = self.btn;
                if (b.shipHidden || b.variantIsComingSoon)
                {
                    return string(global.label_unknownVessel);
                }
                var s = string(hullClass_to_str(
                    vs_room_get_info(hullVariant_get(b.hullRoom, 1), 2)));
                with (oShipListMenu)
                {
                    s += " " + string(hullVariant_to_str_letterOnly(
                        variantSelector.selectedIndex + 1));
                }
                if (b.shipLocked)
                {
                    return s + ", " + vwa_t("vwa--state-locked");
                }
                return vwa_sheet_flatten(hull_get_info(b.hullIndex, 881))
                    + ", " + s;
            }), false),
            vwa_part_fn("value", method({ btn: btn }, function()
            {
                var b = self.btn;
                if (!b.shipLocked || b.variantIsComingSoon || b.shipHidden)
                {
                    return "";
                }
                var cost = playerShip_getUnlockCost(b.hullRoom);
                if (cost == undefined)
                {
                    return "";
                }
                var s = string(global.label_resonanceCost) + ": " + string(cost);
                if (global.currMetaCurrency < cost)
                {
                    s += ", " + vwa_t("vwa--not-enough-resonance");
                }
                return s;
            }), false),
            vwa_part_fn("value", method({ btn: btn }, function()
            {
                var b = self.btn;
                if (!b.shipLocked && !b.shipHidden
                    && !unlockBadgeHoverDone_ship(b.hullRoom))
                {
                    return vwa_t("vwa--state-new");
                }
                return "";
            }), false),
            vwa_part_fn("tooltip", method({ btn: btn }, function()
            {
                // Locked only, and never for a HIDDEN hull: the game's
                // draw spawns this tooltip for a hidden-but-locked hull
                // too, but its hover conditions exclude hidden buttons,
                // so the hint never actually shows - speaking it would
                // leak an unrevealed vessel's unlock condition.
                var b = self.btn;
                if (!b.shipLocked || b.shipHidden || b.variantIsComingSoon)
                {
                    return "";
                }
                var desc = playerShip_getQuestUnlockConditionDescription(b.hullRoom);
                if (desc == "struct missing description")
                {
                    return "";
                }
                return string_replace_all(
                    string(global.label_shipQuestTooltip_unlockTemplate),
                    "[unlockDescription]", string(desc));
            }), false)
        ]
    };
    // A hidden or coming-soon hull is inert in the game too (its
    // hoverConditionsMet excludes both and onPress refuses hidden), so the
    // node carries no action: Enter speaks the standard no-action line
    // instead of firing a silent no-op.
    if (!btn.shipHidden && !btn.variantIsComingSoon)
    {
        cfg.onActivate = method({ inst: btn }, function()
        {
            vwa_obutton_activate(self.inst);
        });
    }
    vwa_gb_add(bd, vwa_id_ref(btn, "hull:" + string(btn.buttonIndex)), cfg);
}
