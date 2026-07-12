// scrVwaMenuSettings - Void War Access settings family (session 6):
// settings, the pause/escape menu, the standalone language menu, and the
// confirmation dialogue - real graphs via the generic widget adapter in
// scrVwaWidgets (which also owns the vwa-dropdown child screen these menus
// open). Registered from vwa_menus_init via vwa_menu_settings_init.
// Imported by tools/build-mod.csx as a new global script. Ships in release.

function vwa_menu_settings_init()
{
    // All gated on !gameIsLoading: menuToggle is nonzero through the whole
    // boot loading phase (the asset loader clears both at the end), and
    // announcing over the loading screen misleads (bit us: a stray "Menu"
    // opened every boot transcript). The game's own Escape handling closes
    // these menus (oMenuSettings Draw_64, oUIConfirmationDialogue Step_0);
    // the mod only claims Escape where the game has no handler for the
    // mod's construct (closing an open dropdown, which is a mouse-only
    // toggle in the game).
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
}

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
