// scrVwaMenus - Void War Access real game screens (session 5): the main
// menu, the game-start announcements popup, and name-only placeholders for
// the game menus the main menu can open (real graphs for the settings
// family arrive in session 6, replacing the matching placeholders here).
// Imported by tools/build-mod.csx as a new global script. Ships in release.
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

    // The game-start announcements popup (patch notes). Read-on-demand:
    // titles are list entries, Enter speaks the body. Dismissal is the
    // game's own Escape handler (oGameStartMessage Draw_64); mind the saved
    // once-per-profile double-spawn quirk - the first-ever dismissal
    // respawns the popup once, so Escape may need a second press.
    vwa_screen_register({
        key: "announcements",
        layerNum: 60,
        categories: ["ui"],
        exclusive: true,
        isActive: function() { return instance_exists(oGameStartMessage); },
        name: function() { return global.label_announcements; },
        build: function(b) { vwa_announcements_build(b); }
    });

    // Name-only placeholders for open game menus. Exclusive with no
    // categories: the covered main menu's arrows go dead (nothing moves
    // invisibly underneath) and only Global hotkeys stay live. Separate
    // screen keys per menu so moving settings -> language re-announces.
    // The game's own Escape handling closes these (verified: oMenuSettings
    // Draw_64 closes on Escape; oMainMenuControls Step opens settings on
    // Escape at the bare main menu). All gated on !gameIsLoading: menuToggle
    // is nonzero through the whole boot loading phase (the asset loader
    // clears both at the end), and announcing "Menu" over the loading
    // screen misleads (bit us: a stray "Menu" opened every boot transcript).
    vwa_screen_register({
        key: "menu-settings",
        layerNum: 40,
        categories: [],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle == 9;
        },
        name: function() { return global.label_settings; }
    });
    vwa_screen_register({
        key: "menu-language",
        layerNum: 40,
        categories: [],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle == 10;
        },
        name: function() { return global.label_language; }
    });
    vwa_screen_register({
        key: "menu-generic",
        layerNum: 39,
        categories: [],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && global.menuToggle != 0
                && global.menuToggle != 9 && global.menuToggle != 10;
        },
        name: function() { return vwa_t("vwa--screen-menu"); }
    });

    vwa_log("menus: session-5 screens registered");
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
        vwa_gb_add(b, vwa_id_ref(msg, "ann:" + string(msg.messageTitle)), {
            typeKey: "button",
            parts: [vwa_part_fn("label", method({ msg: msg }, function()
            {
                return self.msg.messageTitle;
            }), false)],
            onActivate: method({ msg: msg }, function()
            {
                // Read the body on demand; no interrupt (the player asked
                // for a long read, key repeat should not shred it).
                vwa_speak([self.msg.messageBody], false);
            })
        });
    }
}
