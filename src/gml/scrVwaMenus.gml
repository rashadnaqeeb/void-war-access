// scrVwaMenus - Void War Access real game screens: the main menu (with its
// social button bar as a second Tab stop) and the game-start announcements
// popup (session 5), the generic widget adapter and the settings
// family - settings, pause/escape menu, confirmation dialogue, dropdown
// lists as child screens, language menu - (session 6), the commander
// select screen (session 10), and the ship select screen with its ship
// list overlay plus the auto-paging list pattern (session 12; ship speech
// composition lives in scrVwaShip). A name-only placeholder remains for
// menus with no real graph yet (keybinds; the in-run menus arrive
// post-foundation).
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The generic widget adapter (vwa_widgets_emit + vwa_widget_add) covers
// every menu made of the standard widget families: oButton_menus (spawned
// buttons), oSettings_checkbox (toggles), oMenuElement (sliders, dropdowns,
// plain labels), oButton (framed buttons like Configure Keybinds).
// Enumeration is live per build; sorting is visual reading order (y then x,
// same-row tolerance 4px - the game's own alignment test in
// oSettings_checkbox Draw_64). Activation always calls the game's own
// stored callbacks and mirrors the real click path's guards and sounds.
// Documented generic-builder exceptions:
// - Volume sliders have no pointer-free game handler; vwa_widget_slider_adjust
//   mirrors the mouse-wheel path's effect (increment + clamp + update call)
//   per slider object.
// - The language dropdown's per-entry beta hover tooltip is not surfaced;
//   the same warning text arrives in the confirmation dialogue the game
//   raises before committing a beta language, so nothing is missed.
//
// Screen names reuse the game's own localized label globals
// (localization_functionText_add does variable_global_set, so
// global.label_mainMenu etc. hold the current language's text and the game
// re-sets them on a language change). The one mod-authored name in this
// file is the generic menu fallback, vwa--screen-menu.
//
// global.menuToggle values (gameMenu_to_str in scrMenu, verified 1.4.0c):
// 0 none, 1 crew, 2 cargo, 3 shop, 4 upgrade, 5 localMap, 6 sectorMap,
// 7 armament, 8 escape, 9 settings, 10 language, 11 shipListMenu,
// 12 shipSelect, 13 commanderSelect, 14 confirmDialogue,
// 15 configureKeybinds.

function vwa_menus_init()
{
    // The main menu proper. Stays active (covered, focus remembered) while
    // a popup or game menu sits on top; pops only when its instance dies
    // (room change).
    vwa_screen_register({
        key: "main-menu",
        layerNum: 10,
        categories: ["ui"],
        isActive: function() { return instance_exists(oMainMenuControls); },
        name: function() { return global.label_mainMenu; },
        build: function(b) { vwa_main_menu_build(b); }
    });

    // The game-start announcements popup (patch notes). Each announcement
    // is ONE control: the title is the summary line, each body line a
    // tooltip-kind part - landing reads the whole note, Alt+up/down steps
    // it line by line (the same shape as the crew sheet). Down arrow moves
    // straight to the next announcement. Dismissal is the game's own Escape
    // handler (oGameStartMessage Draw_64); mind the saved once-per-profile
    // double-spawn quirk - the first-ever dismissal respawns the popup
    // once, so Escape may need a second press.
    vwa_screen_register({
        key: "announcements",
        layerNum: 60,
        categories: ["ui"],
        exclusive: true,
        isActive: function() { return instance_exists(oGameStartMessage); },
        name: function() { return global.label_announcements; },
        build: function(b) { vwa_announcements_build(b); }
    });

    // The settings family (session 6): real graphs via the generic widget
    // adapter. All gated on !gameIsLoading: menuToggle is nonzero through
    // the whole boot loading phase (the asset loader clears both at the
    // end), and announcing over the loading screen misleads (bit us: a
    // stray "Menu" opened every boot transcript). The game's own Escape
    // handling closes these menus (oMenuSettings Draw_64, oUIConfirmation-
    // Dialogue Step_0); the mod only claims Escape where the game has no
    // handler for the mod's construct (closing an open dropdown, which is a
    // mouse-only toggle in the game).
    vwa_screen_register({
        key: "menu-settings",
        layerNum: 40,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle == 9
                && instance_exists(oMenuSettings);
        },
        name: function() { return global.label_settings; },
        build: function(bd) { vwa_settings_build(bd); }
    });

    // The pause/escape menu (menuToggle 8, in-run; oMenuPause). Everything
    // on it is a spawned oButton_menus. It stays alive underneath while its
    // Settings button opens oMenuSettings on top (menuToggle flips to 9),
    // so the isActive gate needs both the instance and the flag.
    vwa_screen_register({
        key: "menu-escape",
        layerNum: 40,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle == 8
                && instance_exists(oMenuPause);
        },
        name: function() { return vwa_t("vwa--screen-pause"); },
        build: function(bd)
        {
            vwa_widgets_emit(bd, vwa_menu_buttons_collect(instance_find(oMenuPause, 0)));
        }
    });

    // The standalone language menu (menuToggle 10, oMenuLanguage). Dead
    // code in 1.4.0c - nothing instantiates it (the settings language
    // DROPDOWN replaced it) - but covering it costs one generic-builder
    // call and protects against the game reviving it.
    vwa_screen_register({
        key: "menu-language",
        layerNum: 40,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle == 10
                && instance_exists(oMenuLanguage);
        },
        name: function() { return global.label_language; },
        build: function(bd)
        {
            vwa_widgets_emit(bd, vwa_menu_buttons_collect(instance_find(oMenuLanguage, 0)));
        }
    });

    // The confirmation dialogue (menuToggle 14, oUIConfirmationDialogue and
    // children): the message text as a label node, then its Confirm/Cancel
    // oButton_menus. The game handles Escape itself (Step_0 runs onEscape
    // and keyboard_clear's the key). Sits above the other menus - the game
    // spawns it OVER settings (beta-language confirm) and over the pause
    // menu (hangar/restart confirms, which destroy oMenuPause first).
    vwa_screen_register({
        key: "confirm",
        layerNum: 50,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && instance_exists(oUIConfirmationDialogue);
        },
        name: function() { return vwa_t("vwa--screen-confirm"); },
        build: function(bd) { vwa_confirm_build(bd); }
    });

    // An open dropdown list as a child screen: pushed when any oMenuElement
    // flips toggleDropdown (our combo activation mirrors the game's
    // dropdown-button click), popped when it clears. Entering lands on the
    // current selection (its "selected" part drives the graph's
    // selected-member landing). Escape closes just the list via onBack -
    // consumed, so the settings menu underneath survives the press.
    vwa_screen_register({
        key: "vwa-dropdown",
        layerNum: 45,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && vwa_find_open_dropdown() != undefined;
        },
        name: function()
        {
            var dd = vwa_find_open_dropdown();
            return (dd != undefined) ? dd.leftLabel : "";
        },
        build: function(bd) { vwa_dropdown_build(bd); },
        onBack: function()
        {
            var dd = vwa_find_open_dropdown();
            if (dd == undefined)
            {
                return false;
            }
            dd.toggleDropdown = false;
            return true;
        }
    });

    // The commander select screen (menuToggle 13, oUICommanderList) - the
    // first screen of the new game flow, and the same object re-opened as
    // an overlay by the ship select screen's commander button, so one
    // registration covers both. The gate is the list INSTANCE, not the
    // menu flag: the purchase dialogue flips the flag to 14 while the list
    // stays up, and gating on 13 would pop this screen under the dialogue
    // and lose its focus memory. Escape stays the game's own (the list's
    // Step handles it raw: back to the main menu / close the overlay); the
    // purchase dialogue is an oUIConfirmationDialogue child, so the generic
    // confirm screen above covers it with no extra work. Structure and
    // reading model: vwa_commander_build below.
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

    // The ship select screen (menuToggle 12) - step 2 of the new game flow
    // (session 12). A room-per-ship composite: every hull variant is its
    // own GameMaker room holding the LIVE ship (oHull, oSysGroup, oCrew,
    // oModuleManager; weapons as hull data), cycling hulls calls room_goto,
    // and the oShipMenu_* widgets are persistent instances that survive
    // the switch - so focus carries across the room change on stable skeys
    // with no extra machinery. The gate is the persistent selector
    // INSTANCE plus the menu flags that mean the composite is alive: 12
    // (ship select itself, held through the room_goto transition frames),
    // 11 (the ship list overlay above), 13 (the commander overlay above),
    // 14 (a confirmation dialogue above - the ship purchase; same lesson
    // as commander-select's instance gate) - the screen stays stacked,
    // covered with focus remembered, under all three. Launch flips the
    // flag to 0 and the screen pops. The game's own Escape handling stays
    // untouched (the selector's raw Escape goes back to commander select).
    // postDispatch consumes the raw arrow keys the selector's own
    // arrowKeysToCycle would read in its Step: hull cycling must happen
    // ONLY through the cycler node - a left/right the navigator just
    // handled (or one pressed mid-name-edit, a real game quirk) must not
    // also cycle the ship underneath. Structure: vwa_ship_select_build.
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

    // Name-only fallback for menus with no real graph yet (keybinds 15, the
    // in-run menus). Exclusive with no categories: the covered screen's
    // arrows go dead (nothing moves invisibly underneath) and only Global
    // hotkeys stay live. 11/12 are excluded like the settings family: the
    // ship screens above own them (a same-layer fallback on top would kill
    // their arrows).
    vwa_screen_register({
        key: "menu-generic",
        layerNum: 39,
        categories: [],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle != 0
                && global.menuToggle != 8 && global.menuToggle != 9
                && global.menuToggle != 10 && global.menuToggle != 11
                && global.menuToggle != 12 && global.menuToggle != 14;
        },
        name: function() { return vwa_t("vwa--screen-menu"); }
    });

    vwa_log("menus: game screens registered");
}

// Immediate-mode build from the live buttonList (never cache game state):
// one button node per entry, in list order. Identity: the entry struct as
// the tier-1 ref (spawn_buttons creates them once per room entry) and the
// stable label key as the structural key, so conditional entries (Continue,
// Credits) shifting positions never break focus. Arrows wrap top<->bottom.
function vwa_main_menu_build(b)
{
    var mm = instance_find(oMainMenuControls, 0);
    var list = mm.buttonList;
    var cnt = array_length(list);
    var firstKey = undefined;
    var lastKey = undefined;
    for (var i = 0; i < cnt; i++)
    {
        var bt = list[i];
        var skey = "mm:" + ((bt.localizedLabelName != "")
            ? bt.localizedLabelName : string(bt.buttonStr));
        vwa_gb_add(b, vwa_id_ref(bt, skey), {
            typeKey: "button",
            parts: [vwa_part_fn("label", method({ bt: bt }, function()
            {
                return self.bt.buttonStr;
            }), false)],
            onActivate: method({ bt: bt }, function()
            {
                vwa_main_menu_activate(self.bt);
            })
        });
        if (firstKey == undefined)
        {
            firstKey = skey;
        }
        lastKey = skey;
    }
    if (cnt > 1)
    {
        vwa_gb_connect(b, firstKey, "up", lastKey, "");
        vwa_gb_connect(b, lastKey, "down", firstKey, "");
    }
    vwa_main_menu_social_build(b);
}

// The social button bar (oSocialButtonBar spawns oSocialButton instances,
// bottom right): its own Tab stop after the menu proper, a horizontal row
// named by the mod's group word. Each button's visible label is an icon;
// its hover tooltip is the game's own localized name for it
// (label_viewSteamStorePage / label_joinOurDiscord, re-localized every
// frame by oButton's Step), so tooltipStr IS the spoken label and there is
// no separate tooltip part. Visibility mirrors drawConditionsMet (the bar
// hides while the credits overlay is up); a hidden button drops out of the
// build. Activation opens the URL through the game's own path: the shared
// oButton mirror sets triggerButton and oSocialButton's Step calls
// url_open.
function vwa_main_menu_social_build(b)
{
    var list = [];
    var cnt = instance_number(oSocialButton);
    for (var i = 0; i < cnt; i++)
    {
        var sb = instance_find(oSocialButton, i);
        var dc = sb.drawConditionsMet;
        if (dc == -4 || dc())
        {
            array_push(list, sb);
        }
    }
    if (array_length(list) == 0)
    {
        return;
    }
    array_sort(list, function(ia, ib)
    {
        if (ia.x != ib.x)
        {
            return (ia.x < ib.x) ? -1 : 1;
        }
        return 0;
    });
    vwa_gb_begin_stop(b, "social");
    vwa_gb_start_row(b, undefined, vwa_t("vwa--group-social"));
    for (var i = 0; i < array_length(list); i++)
    {
        var sb = list[i];
        vwa_gb_add(b, vwa_id_ref(sb, "social:" + sb.tooltipLabelName), {
            typeKey: "button",
            parts: [vwa_part_fn("label", method({ inst: sb }, function()
            {
                var tt = self.inst.tooltipStr;
                return is_string(tt) ? tt : "";
            }), false)],
            onActivate: method({ inst: sb }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }
    vwa_gb_end_row(b);
}

// Mirror of the game's own click path (oMainMenuControls draw): the same
// overlay guards (credits, announcements popup, settings/keybinds/confirm
// menus - gameMenu_is 9/15/14), the same click sound, then the entry's
// stored onClick. A blocked activation normally cannot happen (the overlay
// owns focus on our stack too), so it logs as a stack bug worth seeing.
function vwa_main_menu_activate(bt)
{
    if (!is_method(bt.onClick))
    {
        vwa_log("ERROR: main-menu entry '" + string(bt.buttonStr)
            + "' has no onClick method");
        return;
    }
    if (instance_exists(oCredits) || instance_exists(oGameStartMessage)
        || gameMenu_is(9, 15, 14))
    {
        vwa_log("ERROR: main-menu activation of '" + string(bt.buttonStr)
            + "' blocked by an overlay the game guards against"
            + " - screen stack out of sync?");
        return;
    }
    sfx_start(global.sfx_click2, 0, 1, 0, 0);
    var fn = bt.onClick;
    fn();
}

// The popup shows either a short warning (spawn_gameStartWarning sets
// shortMessageStr) or the announcements list from global.gameStartMessages,
// whose structs oGameStartMessage's Create localizes in place - so titles
// and bodies read from those structs are current-language text. The structs
// also survive the double-spawn respawn, so they are the tier-1 refs.
function vwa_announcements_build(b)
{
    var inst = instance_find(oGameStartMessage, 0);
    if (inst.shortMessageStr != "")
    {
        vwa_gb_add(b, vwa_id("short"), {
            typeKey: "label",
            parts: [vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.shortMessageStr;
            }), false)]
        });
        return;
    }
    var msgs = global.gameStartMessages;
    for (var i = 0; i < array_length(msgs); i++)
    {
        var msg = msgs[i];
        // One control per announcement: the title is the summary, each
        // non-empty body line a tooltip part (its own line, steppable by
        // the alt-arrow review), split fresh each build (the struct's text
        // is what oGameStartMessage localizes in place). The index keeps
        // the structural key unique: titles are game data, and a duplicate
        // title would make the graph builder throw on every build,
        // quarantining the whole popup (session-7 review). The list is
        // fixed at boot, so the index is stable while the popup lives.
        var parts = [vwa_part_fn("label", method({ msg: msg }, function()
        {
            return self.msg.messageTitle;
        }), false)];
        var lines = string_split(msg.messageBody, "\n");
        for (var j = 0; j < array_length(lines); j++)
        {
            var ln = string_trim(lines[j]);
            if (ln == "")
            {
                continue;
            }
            array_push(parts, vwa_part("tooltip", ln));
        }
        vwa_gb_add(b, vwa_id_ref(msg, "ann:" + string(i) + ":" + string(msg.messageTitle)), {
            typeKey: "label",
            parts: parts
        });
    }
}

// ---- session 6: the generic widget adapter ----

// The settings menu's widgets: every oSettings_checkbox / oMenuElement /
// oButton instance at the settings element depth (each element's Create
// sets depth = global.dpthSettingsMenu1 - the game-truth ownership signal),
// plus the menu's own spawned buttons (Back) via parentID.
function vwa_settings_build(bd)
{
    var list = [];
    var fams = [oSettings_checkbox, oMenuElement, oButton];
    for (var f = 0; f < array_length(fams); f++)
    {
        var cnt = instance_number(fams[f]);
        for (var i = 0; i < cnt; i++)
        {
            var inst = instance_find(fams[f], i);
            if (inst.depth == global.dpthSettingsMenu1)
            {
                array_push(list, inst);
            }
        }
    }
    var mn = instance_find(oMenuSettings, 0);
    var bts = vwa_menu_buttons_collect(mn);
    for (var i = 0; i < array_length(bts); i++)
    {
        array_push(list, bts[i]);
    }
    vwa_widgets_emit(bd, list);
}

// The confirmation dialogue: its live message text, then its buttons.
function vwa_confirm_build(bd)
{
    var dlg = instance_find(oUIConfirmationDialogue, 0);
    vwa_gb_add(bd, vwa_id_ref(dlg, "confirm:msg"), {
        typeKey: "label",
        parts: [vwa_part_fn("label", method({ dlg: dlg }, function()
        {
            return self.dlg.text;
        }), false)]
    });
    vwa_widgets_emit(bd, vwa_menu_buttons_collect(dlg));
}

// Every oButton_menus spawned by ownerInst (menu_spawnButton stamps
// parentID) - the whole control surface of the pause, language, and
// confirmation menus.
function vwa_menu_buttons_collect(ownerInst)
{
    var list = [];
    var cnt = instance_number(oButton_menus);
    for (var i = 0; i < cnt; i++)
    {
        var bm = instance_find(oButton_menus, i);
        if (bm.parentID == ownerInst)
        {
            array_push(list, bm);
        }
    }
    return list;
}

// Sort widget instances into visual reading order (y then x), group
// same-y controls into horizontal rows (tolerance 4px, the game's own
// alignment test), add each through the vtable dispatch, and wire vertical
// wrap between the first and last rows.
function vwa_widgets_emit(bd, list)
{
    if (array_length(list) == 0)
    {
        return;
    }
    array_sort(list, function(ia, ib)
    {
        if (ia.y != ib.y)
        {
            return (ia.y < ib.y) ? -1 : 1;
        }
        if (ia.x != ib.x)
        {
            return (ia.x < ib.x) ? -1 : 1;
        }
        return 0;
    });

    var groups = [];
    var cur = [list[0]];
    var rowY = list[0].y;
    for (var i = 1; i < array_length(list); i++)
    {
        if (abs(list[i].y - rowY) < 4)
        {
            array_push(cur, list[i]);
        }
        else
        {
            array_push(groups, cur);
            cur = [list[i]];
            rowY = list[i].y;
        }
    }
    array_push(groups, cur);

    var rowKeys = [];
    for (var g = 0; g < array_length(groups); g++)
    {
        var grp = groups[g];
        var multi = (array_length(grp) > 1);
        if (multi)
        {
            // Unnamed group: the game draws no header for its same-y widget
            // rows (the window-mode trio); the announcer speaks the generic
            // localized group word (hooks.groupText) on entry instead.
            vwa_gb_start_row(bd, undefined, "");
        }
        var keys = [];
        for (var i = 0; i < array_length(grp); i++)
        {
            var k = vwa_widget_add(bd, grp[i]);
            if (k != undefined)
            {
                array_push(keys, k);
            }
        }
        if (multi)
        {
            vwa_gb_end_row(bd);
        }
        if (array_length(keys) > 0)
        {
            array_push(rowKeys, keys);
        }
    }

    if (array_length(rowKeys) > 1)
    {
        var firstRow = rowKeys[0];
        var lastRow = rowKeys[array_length(rowKeys) - 1];
        for (var i = 0; i < array_length(firstRow); i++)
        {
            vwa_gb_connect(bd, firstRow[i], "up", lastRow[0], "");
        }
        for (var i = 0; i < array_length(lastRow); i++)
        {
            vwa_gb_connect(bd, lastRow[i], "down", firstRow[0], "");
        }
    }
}

// Vtable dispatch by widget family. Returns the node's structural key, or
// undefined for an unhandled family (logged loudly: a menu control the mod
// drops is invisible to a blind player - exactly what the raw-vs-mod diff
// in the smoke scripts exists to catch).
function vwa_widget_add(bd, inst)
{
    var objIdx = inst.object_index;
    if (objIdx == oSettings_checkbox || object_is_ancestor(objIdx, oSettings_checkbox))
    {
        return vwa_widget_add_checkbox(bd, inst);
    }
    if (objIdx == oButton_menus || object_is_ancestor(objIdx, oButton_menus))
    {
        return vwa_widget_add_button_menus(bd, inst);
    }
    if (objIdx == oMenuElement || object_is_ancestor(objIdx, oMenuElement))
    {
        if (inst.enableDropdown)
        {
            return vwa_widget_add_combo(bd, inst);
        }
        // settingsMenuElement_initSlider is what makes an element a slider;
        // "dragging" exists only after it ran.
        if (variable_instance_exists(inst, "dragging"))
        {
            return vwa_widget_add_slider(bd, inst);
        }
        return vwa_widget_add_element_label(bd, inst);
    }
    if (objIdx == oButton || object_is_ancestor(objIdx, oButton))
    {
        return vwa_widget_add_obutton(bd, inst);
    }
    vwa_log("ERROR: widget adapter: unhandled object " + object_get_name(objIdx));
    return undefined;
}

// The widget's tooltip as an announcement part: read inline with the
// control whenever the game gives the widget a tooltipStr, silent when it
// has none. Void War tooltips are flat strings (verified: draw_label
// 9-slice panels; sections/double panels are visual composition only, no
// links or nesting), so inline reading covers the whole tooltip surface.
// oButton defaults tooltipStr to the NUMBER 0, so the string check does
// both jobs.
function vwa_widget_tooltip_part(inst)
{
    return vwa_part_fn("tooltip", method({ inst: inst }, function()
    {
        var tt = self.inst.tooltipStr;
        return (is_string(tt) && tt != "") ? tt : "";
    }), false);
}

// oSettings_checkbox: label in rightText, state in toggled. Activation
// mirrors clickToToggle (oSettings_checkbox Create): the dropdown guard,
// the checkbox sound, then the stored onClick. The flipped state speaks
// through the live value part.
function vwa_widget_add_checkbox(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "toggle",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.rightText;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                return self.inst.toggled ? vwa_t("vwa--state-checked")
                    : vwa_t("vwa--state-unchecked");
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var cb = self.inst;
            if (!all_dropdowns_closed())
            {
                vwa_log("ERROR: checkbox activation with a dropdown open"
                    + " - screen stack out of sync?");
                return;
            }
            if (cb.onClick == -4)
            {
                vwa_log("ERROR: checkbox " + object_get_name(cb.object_index)
                    + " has no onClick");
                return;
            }
            sfx_start_ext(global.sfx_settingsCheckbox, 0, 1, 0, 0, 1);
            var fn = cb.onClick;
            fn();
        })
    });
    return skey;
}

// oButton_menus: label in text (textLabelName is the stable identity when
// present - text re-localizes). Activation mirrors its Step_0: the
// confirmation-dialogue block (unless the button belongs to the dialogue),
// dimButton refuses with audible feedback, hoverConditionsMet guards, then
// the stored onClick and the press sound, in the game's order.
function vwa_widget_add_button_menus(bd, inst)
{
    var lbl = (inst.textLabelName != "") ? inst.textLabelName : string(inst.text);
    var skey = "bm:" + lbl;
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.text;
            }), false),
            vwa_part_fn("enabled", method({ inst: inst }, function()
            {
                return self.inst.dimButton ? vwa_t("vwa--state-disabled") : "";
            }), true)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var bt = self.inst;
            if (instance_exists(oUIConfirmationDialogue))
            {
                var blocked = true;
                if (instance_exists(bt.parentID)
                    && (bt.parentID.object_index == oUIConfirmationDialogue
                        || objIA(bt.parentID.object_index, oUIConfirmationDialogue)))
                {
                    blocked = false;
                }
                if (blocked)
                {
                    vwa_log("ERROR: button '" + string(bt.text)
                        + "' blocked by the confirmation dialogue"
                        + " - screen stack out of sync?");
                    return;
                }
            }
            if (bt.dimButton)
            {
                vwa_speak([vwa_t("vwa--state-disabled")], false);
                return;
            }
            if (bt.hoverConditionsMet != -4)
            {
                var hc = bt.hoverConditionsMet;
                if (!hc())
                {
                    vwa_log("ERROR: button '" + string(bt.text)
                        + "' hover conditions refuse activation"
                        + " - screen stack out of sync?");
                    return;
                }
            }
            // The sound id is read BEFORE onClick: an onClick may destroy
            // its own button (Cancel destroys the dialogue, whose CleanUp
            // kills its buttons), and reading through the dead id from here
            // crashes - the game's own Step survives only because a dying
            // instance's running event keeps its scope (bit us: every
            // keyboard Cancel tripped the input watchdog).
            var pressSfx = bt.sfx_press;
            if (bt.onClick != -4)
            {
                var fn = bt.onClick;
                fn();
            }
            sfx_start_ext(pressSfx, 0, 1, 0, 0, 1);
        })
    });
    return skey;
}

// oMenuElement slider: label in leftLabel, value in rightLabel (the game's
// Step refreshes it every frame). Left/right arrows adjust via the
// per-object mirror below.
function vwa_widget_add_slider(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "slider",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.leftLabel;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                return self.inst.rightLabel;
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onAdjust: method({ inst: inst }, function(sign, large)
        {
            vwa_widget_slider_adjust(self.inst, sign, large);
        })
    });
    return skey;
}

// The volume sliders' only pointer-free adjustment path is the mouse-wheel
// handler, whose body reads live mouse state, so this mirrors its exact
// effect per slider object: the same clamp and the same update call
// (mouseWheelToSlide in oSettings_volume_music Create). The increments are
// OUR keyboard granularity, Rashad's choice: 0.01 per arrow step and 0.1
// per Ctrl+arrow large step (the game's wheel uses 0.05; the effect path
// is what's mirrored, not the wheel's coarseness). A slider without a
// mirror logs loudly: extending this dispatch is the documented
// generic-builder exception for new sliders.
function vwa_widget_slider_adjust(inst, sign, large)
{
    var inc = large ? 0.1 : 0.01;
    var objIdx = inst.object_index;
    if (objIdx == oSettings_volume_music)
    {
        global.currVolume_BGM = clamp(global.currVolume_BGM + sign * inc, 0, 1);
        music_volume_update();
        return;
    }
    if (objIdx == oSettings_volume_sound)
    {
        global.volumeMax_SFX = clamp(global.volumeMax_SFX + sign * inc, 0, 1);
        master_volume_update();
        return;
    }
    vwa_log("ERROR: slider " + object_get_name(objIdx) + " has no adjust mirror");
}

// oMenuElement dropdown, closed state: a combo box. Label in leftLabel,
// value in centerText (centerTextOverride wins when set - fullscreen /
// custom size on the window-size element). Activation mirrors the game's
// dropdown-button click (draw_dropdownButton in init_dropdownVariables):
// refuse while another dropdown is open, the click sound, then open. The
// open list becomes the vwa-dropdown child screen.
function vwa_widget_add_combo(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "combo",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.leftLabel;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                var el = self.inst;
                return (el.centerTextOverride != "") ? el.centerTextOverride
                    : el.centerText;
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var el = self.inst;
            if (dropdown_any_open())
            {
                vwa_log("ERROR: opening a dropdown while another is open"
                    + " - screen stack out of sync?");
                return;
            }
            sfx_start(global.sfx_click, 0, 1, 0, 0);
            el.toggleDropdown = true;
        })
    });
    return skey;
}

// oMenuElement that is neither slider nor dropdown: a plain labeled row.
function vwa_widget_add_element_label(bd, inst)
{
    var skey = object_get_name(inst.object_index) + "#" + string(inst.id);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "label",
        parts: [vwa_part_fn("label", method({ inst: inst }, function()
        {
            var el = self.inst;
            if (el.leftLabel != "")
            {
                return el.leftLabel;
            }
            return (el.centerTextOverride != "") ? el.centerTextOverride
                : el.centerText;
        }), false),
            vwa_widget_tooltip_part(inst)]
    });
    return skey;
}

// The oButton family's activation mirror, shared by the generic widget
// adapter and the main menu's social buttons: update_hover's guards plus
// click_to_trigger_button (oButton Create), in the game's order.
// Confirmation dialogue and open dropdowns block; drawConditionsMet blocks
// (oButton Step_0 gates the whole click path on it - an invisible button
// is unclickable); hoverConditionsMet blocks; an inactive buttonActive
// refuses with audible feedback; then onPress, the press sound, and
// triggerButton = true (the child object's Step does the real work off
// that flag).
function vwa_obutton_activate(bt)
{
    if (instance_exists(oUIConfirmationDialogue) || dropdown_any_open())
    {
        vwa_log("ERROR: button " + object_get_name(bt.object_index)
            + " blocked by an overlay - screen stack out of sync?");
        return;
    }
    if (bt.drawConditionsMet != -4)
    {
        var dc = bt.drawConditionsMet;
        if (!dc())
        {
            vwa_log("ERROR: button " + object_get_name(bt.object_index)
                + " is not drawn - screen stack out of sync?");
            return;
        }
    }
    if (bt.hoverConditionsMet != -4)
    {
        var hc = bt.hoverConditionsMet;
        if (!hc())
        {
            vwa_log("ERROR: button " + object_get_name(bt.object_index)
                + " hover conditions refuse activation"
                + " - screen stack out of sync?");
            return;
        }
    }
    var act = bt.buttonActive;
    if (!act())
    {
        vwa_speak([vwa_t("vwa--state-disabled")], false);
        return;
    }
    // Sound id read before onPress for the same dying-instance reason as
    // oButton_menus; skip triggerButton if onPress destroyed the button
    // (nothing left to trigger).
    var pressSfx = bt.sfx_press;
    if (bt.onPress != -4)
    {
        var fp = bt.onPress;
        fp();
    }
    sfx_start_ext(pressSfx, 0, 1, 0, 0, 1);
    if (instance_exists(bt))
    {
        bt.triggerButton = true;
    }
}

// oButton family (Configure Keybinds): label in centerText, activation via
// the shared oButton mirror above.
function vwa_widget_add_obutton(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.centerText;
            }), false),
            vwa_part_fn("enabled", method({ inst: inst }, function()
            {
                var bt = self.inst;
                if (bt.buttonActive == -4)
                {
                    return "";
                }
                var act = bt.buttonActive;
                return act() ? "" : vwa_t("vwa--state-disabled");
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            vwa_obutton_activate(self.inst);
        })
    });
    return skey;
}

// ---- the dropdown child screen's guts ----

function vwa_find_open_dropdown()
{
    var cnt = instance_number(oMenuElement);
    for (var i = 0; i < cnt; i++)
    {
        var el = instance_find(oMenuElement, i);
        if (el.enableDropdown && el.toggleDropdown)
        {
            return el;
        }
    }
    return undefined;
}

// One node per entry; identity is the list index (a dropdown's entries are
// fixed while it is open). The current selection carries the "selected"
// part, which is also what lands focus there on entry. Disabled entries
// read as unavailable and have no activation ("No action").
function vwa_dropdown_build(bd)
{
    var dd = vwa_find_open_dropdown();
    if (dd == undefined)
    {
        return; // closed this same frame; empty build, screen pops next tick
    }
    var entries = dd.dropdownEntries;
    for (var i = 0; i < array_length(entries); i++)
    {
        var disabled = (i < array_length(dd.dropdownEntry_disabled))
            && dd.dropdownEntry_disabled[i];
        var def = {
            typeKey: "option",
            parts: [
                vwa_part_fn("label", method({ dd: dd, idx: i }, function()
                {
                    return self.dd.dropdownEntries[self.idx];
                }), false),
                vwa_part_fn("selected", method({ dd: dd, idx: i }, function()
                {
                    return (self.dd.dropdown_currSelectedIndex == self.idx)
                        ? vwa_t("vwa--state-selected") : "";
                }), true)
            ]
        };
        if (disabled)
        {
            array_push(def.parts, vwa_part("enabled", vwa_t("vwa--state-disabled")));
        }
        else
        {
            def.onActivate = method({ dd: dd, idx: i }, function()
            {
                vwa_dropdown_choose(self.dd, self.idx);
            });
        }
        vwa_gb_add(bd, vwa_id("opt:" + string(i)), def);
    }
}

// Mirror of the game's entry-click commit (oMenuElement Step_0): blocked by
// a confirmation dialogue, the select sound, the index, then the element's
// stored select_dropdownEntry. One deliberate divergence: the mouse flow
// leaves the list open after a click; the keyboard flow closes it (choose =
// commit + close, combo-box convention) - closing is exactly what clicking
// the dropdown button again does, so no game state is invented.
function vwa_dropdown_choose(dd, idx)
{
    if (instance_exists(oUIConfirmationDialogue))
    {
        vwa_log("ERROR: dropdown choose while a confirmation dialogue is open"
            + " - screen stack out of sync?");
        return;
    }
    sfx_start_ext(global.sfx_selectDropdownEntry, 0, 1, 0, 0, 0);
    dd.dropdown_currSelectedIndex = idx;
    if (dd.select_dropdownEntry != -4)
    {
        var fn = dd.select_dropdownEntry;
        fn();
    }
    // A select that closes its own menu (destroying the element) is
    // legitimate game behavior; only close the list if it survived.
    if (instance_exists(dd))
    {
        dd.toggleDropdown = false;
    }
}

// ---- the auto-paging list pattern (session 12) ----
// Paged game lists are surfaced WHOLE: every row of every page goes into
// the graph, so arrows walk the full list, type-ahead spans pages with no
// search changes (candidates are the focused stop's nodes), and the
// auto-stamped position is a global "n of m". NO pager button nodes are
// emitted. What keeps the game's own view honest is this ensure-visible
// tick, called from the screen's build (the vwa_commander_badge_tick
// pattern: impure per-frame work driven from build): when the focused
// node's row is not on the game widget's current page, the game's OWN
// page-step methods run - shortest wrapping direction - until it is, so
// hover-badge clears, page badges, and whatever a sighted helper sees all
// track focus. The flip happens inside the build that follows a focus
// change, before parts resolve, so the announcement always reads the
// settled page. Idempotent (already visible = no-op), bounded by the page
// count, converges or logs. cfg fields:
//   focusPage  fn(skey) -> 0-based page holding the focused node's row,
//              or -1 when the focused node is not a paged row
//   curPage    fn() -> the widget's 0-based current page
//   pageCount  fn() -> total pages
//   stepNext / stepPrev  fn() - the game's own page-step methods
function vwa_pages_ensure_visible(scr, cfg)
{
    if (scr == undefined || scr.navState.curId == undefined)
    {
        return;
    }
    var fPage = cfg.focusPage;
    var target = fPage(scr.navState.curId.skey);
    if (target < 0)
    {
        return;
    }
    var fCount = cfg.pageCount;
    var n = fCount();
    var fCur = cfg.curPage;
    if (n <= 1 || fCur() == target)
    {
        return;
    }
    var guard = 0;
    while (fCur() != target && guard < n)
    {
        var diff = ((target - fCur()) % n + n) % n;
        var fStep = (diff <= n / 2) ? cfg.stepNext : cfg.stepPrev;
        fStep();
        guard += 1;
    }
    if (fCur() != target)
    {
        vwa_log("ERROR: ensure-visible stuck on page " + string(fCur())
            + " wanting " + string(target) + " of " + string(n));
    }
}

// ---- commander select (session 10; full-list retrofit session 12) ----
// The first real screen of the new game flow. Three Tab stops:
// 1) "commanders" - one row per commander of the FULL set (the game's own
//    commanderList_all, the source its pageData chunks), inside a silent
//    context so the global "n of m" counts commanders only, then the
//    Resonance readout. The game's page window follows focus through the
//    auto-paging pattern above; there are no pager nodes.
// 2) "name" - the commander name text field and its randomize button;
// 3) "confirm" - the Confirm button (room change to ship select).
// A row's summary line is name / selected / locked + cost (+ not enough
// Resonance) / new / position; its sheet - Rashad's categorized crew read -
// comes from vwa_sheet_crew_lines, one tooltip part per line, so alt
// up/down step it. Hidden ("???") commanders read as "Hidden commander,
// locked" with no sheet, mirroring the game's suppressed tooltip.

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


// ---- ship select (session 12) ----
// Step 2 of the new game flow; see the registration comment for the
// room-per-ship architecture and the gate. Four Tab stops:
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
//    auto-paging pattern; the name-toggle button is deliberately NOT
//    surfaced - its only effect is choosing which of the two names we
//    already speak gets painted), Systems, Loadout (weapons then
//    equipment stacks), Modules. On a HIDDEN hull each section collapses
//    to a single NO DATA node (mirrors playerShip_checkVisibilityInShipMenu).
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
function vwa_ship_stop_build(bd)
{
    var sel = instance_find(oShipMenu_shipSelector, 0);

    // The hull cycler. onAdjust drives the game's own
    // selectedIndex_previous/next - the exact methods its native
    // arrow-key cycling calls (they skip disabled hulls themselves). The
    // raw-arrow consume lives in the screen's postDispatch.
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

    // The variant slider (A/B/C). Landing IS selection: onAdjust steps to
    // the next buttonActive variant and runs the game's own stored onPress
    // (badge clear, get_selectedRoom, goToSelectedRoom - the full press
    // path). The second live part speaks the resulting ship.
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

    // The ship name field. Editable exactly when the game's field is
    // (visible and not locked-without-debug: oShipMenu_shipName Draw_64);
    // otherwise a NO DATA label, mirroring what the game paints. The edit
    // adapter mirrors the field's own click-to-edit and Enter-commit
    // branches; commit runs the game's stored set_name (writes
    // customHullName and saves). Keyboard Escape also commits - the text
    // layer cannot distinguish the two exits (both land in vwa_text_exit),
    // and committing what a blind player just typed beats silently
    // discarding it.
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
                        onExit: method({ fld: fld }, function()
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
                                vwa_log("ERROR: ship name field gone on edit exit");
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

    // Randomize name (mirrors oShipMenu_randomShipName's press; the live
    // value part is the current name, so activation speaks the roll).
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
                    var f = instance_find(oShipMenu_shipName, 0);
                    return instance_exists(f) ? string(f.text) : "";
                }, true)
            ],
            onActivate: method({ inst: rnd }, function()
            {
                vwa_obutton_activate(self.inst);
            })
        });
    }

    // View List (opens the ship list overlay; its Step spawns oShipListMenu
    // and flips the flag to 11 - the ship-list screen then stacks on top).
    // The live part mirrors the red badge count on the button: hulls
    // unlocked but never yet hovered.
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

    // Locked hull extras: the game's Purchase button (spawned by the
    // selector's Room Start only while the hull is locked with a price)
    // and the Resonance counter next to it - the same pattern as the
    // commander screen's Resonance node, tooltip mirrored verbatim
    // (game-authored English hardcoded in the counter's draw).
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
// and its Enter-commit branch on exit (assign crewName, save via the
// game's shipSelect_saveCrewNames).
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
        onExit: method({ cb: cb }, function()
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
// ship-select screen underneath regains focus on the new hull.
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
    vwa_gb_add(bd, vwa_id_ref(btn, "hull:" + string(btn.buttonIndex)), {
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
        ],
        onActivate: method({ inst: btn }, function()
        {
            vwa_obutton_activate(self.inst);
        })
    });
}
