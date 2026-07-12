// scrVwaMenus - Void War Access real game screens: the main menu (with its
// social button bar as a second Tab stop) and the game-start announcements
// popup (session 5), plus the generic widget adapter and the settings
// family - settings, pause/escape menu, confirmation dialogue, dropdown
// lists as child screens, language menu - (session 6). A name-only
// placeholder remains for menus with no real graph yet (keybinds; the
// in-run menus arrive post-foundation).
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
    // is a submenu: the title is the header, the body's lines are its
    // children - Enter or right arrow expands, then down reads line by
    // line. Dismissal is the game's own Escape handler (oGameStartMessage
    // Draw_64); mind the saved once-per-profile double-spawn quirk - the
    // first-ever dismissal respawns the popup once, so Escape may need a
    // second press.
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

    // Name-only fallback for menus with no real graph yet (keybinds 15, the
    // in-run menus). Exclusive with no categories: the covered screen's
    // arrows go dead (nothing moves invisibly underneath) and only Global
    // hotkeys stay live.
    vwa_screen_register({
        key: "menu-generic",
        layerNum: 39,
        categories: [],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle != 0
                && global.menuToggle != 8 && global.menuToggle != 9
                && global.menuToggle != 10 && global.menuToggle != 14;
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
        // The index keeps the structural key unique: titles are game data,
        // and a duplicate title would make the graph builder throw on every
        // build, quarantining the whole popup (session-7 review). The list
        // is fixed at boot, so the index is stable while the popup lives.
        vwa_gb_begin_submenu(b, vwa_id_ref(msg, "ann:" + string(i) + ":" + string(msg.messageTitle)), {
            parts: [vwa_part_fn("label", method({ msg: msg }, function()
            {
                return self.msg.messageTitle;
            }), false)]
        });
        // One label node per non-empty body line, split fresh each build
        // (the struct's text is what oGameStartMessage localizes in place).
        // Lines carry NO ref: sharing the header's msg struct would make
        // reconcile's ref tier resolve a focused line back to the header
        // (the first ref match in order) on every rebuild.
        var lines = string_split(msg.messageBody, "\n");
        var lineIdx = 0;
        for (var j = 0; j < array_length(lines); j++)
        {
            var ln = string_trim(lines[j]);
            if (ln == "")
            {
                continue;
            }
            vwa_gb_add(b, vwa_id("ann:" + string(i) + ":ln:" + string(lineIdx)), {
                typeKey: "label",
                parts: [vwa_part("label", ln)]
            });
            lineIdx += 1;
        }
        vwa_gb_end_submenu(b);
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

// ---- commander select (session 10) ----
// The first real screen of the new game flow. Three Tab stops:
// 1) "commanders" - the current page's rows (inside a silent context so
//    their "n of m" counts the page's rows only), then the page prev/next
//    buttons and the Resonance readout;
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

function vwa_commander_build(bd)
{
    var lst = instance_find(oUICommanderList, 0);
    vwa_commander_badge_tick(lst);

    vwa_gb_begin_stop(bd, "commanders");
    vwa_gb_push_context(bd, "");
    for (var i = 0; i < array_length(lst.commanderList); i++)
    {
        vwa_commander_row_add(bd, lst, lst.commanderList[i]);
    }
    vwa_gb_pop_context(bd);
    vwa_commander_page_button_add(bd, lst, -1);
    vwa_commander_page_button_add(bd, lst, 1);

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
    // the display crew the list spawned; it missing is a mod/game bug, and
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

// A page arrow (oPageCounter): label, then the live page readout and the
// live count of unhovered commanders in that direction (the red badges on
// the arrows). Both are live so pressing the button speaks the new page
// state as direct feedback. Activation mirrors the counter's click path:
// the press sound, then the stored callback.
function vwa_commander_page_button_add(bd, lst, dirNum)
{
    var skey = (dirNum < 0) ? "cmdr-page-prev" : "cmdr-page-next";
    var lblKey = (dirNum < 0) ? "vwa--page-prev" : "vwa--page-next";
    vwa_gb_add(bd, vwa_id(skey), {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ k: lblKey }, function()
            {
                return vwa_t(self.k);
            }), false),
            vwa_part_fn("value", method({ lst: lst }, function()
            {
                var s = vwa_t("vwa--page-of");
                s = string_replace(s, "{n}", string(self.lst.currPageIndex + 1));
                return string_replace(s, "{m}", string(array_length(self.lst.pageData)));
            }), true),
            vwa_part_fn("value", method({ lst: lst, dirNum: dirNum }, function()
            {
                var pc = self.lst.pageControls;
                if (!instance_exists(pc))
                {
                    return "";
                }
                var k = (self.dirNum < 0) ? pc.newItemBadgeCt_prev
                    : pc.newItemBadgeCt_next;
                if (k <= 0)
                {
                    return "";
                }
                return string_replace(vwa_t("vwa--page-new"), "{k}", string(k));
            }), true),
            vwa_part("position", "")
        ],
        onActivate: method({ lst: lst, dirNum: dirNum }, function()
        {
            var pc = self.lst.pageControls;
            if (!instance_exists(pc))
            {
                vwa_log("ERROR: page controls missing on activation");
                return;
            }
            sfx_start_ext(pc.sfx_press, 0, 1, 0, 0, 1);
            var fn = (self.dirNum < 0) ? pc.onPress_prev : pc.onPress_next;
            if (fn != -4)
            {
                fn();
            }
        })
    });
}
