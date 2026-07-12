// scrVwaMenus - Void War Access screen registration dispatcher. Each real
// game screen family lives in its own script: scrVwaMenuMain (main menu,
// social bar, announcements popup), scrVwaMenuSettings (settings, pause,
// language, confirmation dialogue), scrVwaMenuCommander (commander
// select), scrVwaMenuShipSelect (ship select + ship list overlay),
// scrVwaMenuEncounter (the encounter dialogue popups - not a menu; keys
// off oPopup, menuToggle stays 0) - all on the shared machinery in
// scrVwaWidgets (the generic widget adapter, the oButton activation
// mirror, the dropdown child screen, the auto-paging list pattern). A new
// screen family = a new scrVwaMenu* file with its own *_init, called from
// vwa_menus_init below. This file keeps only the
// dispatcher, the pieces that span families (the generic name-only
// fallback for menus with no real graph yet - keybinds; the in-run menus
// arrive post-foundation), and the family-wide conventions:
//
// - Screen names reuse the game's own localized label globals
//   (localization_functionText_add does variable_global_set, so
//   global.label_mainMenu etc. hold the current language's text and the
//   game re-sets them on a language change). The one mod-authored name in
//   this file is the generic menu fallback, vwa--screen-menu.
// - global.menuToggle values (gameMenu_to_str in scrMenu, verified 1.4.0c):
//   0 none, 1 crew, 2 cargo, 3 shop, 4 upgrade, 5 localMap, 6 sectorMap,
//   7 armament, 8 escape, 9 settings, 10 language, 11 shipListMenu,
//   12 shipSelect, 13 commanderSelect, 14 confirmDialogue,
//   15 configureKeybinds.
//
// Imported by tools/build-mod.csx as a new global script. Ships in release.

function vwa_menus_init()
{
    vwa_widgets_init();
    vwa_menu_main_init();
    vwa_menu_settings_init();
    vwa_menu_commander_init();
    vwa_menu_ship_init();
    vwa_menu_encounter_init();

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
