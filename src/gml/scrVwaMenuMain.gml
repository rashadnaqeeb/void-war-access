// scrVwaMenuMain - Void War Access main menu family (session 5): the main
// menu proper (with its social button bar as a second Tab stop) and the
// game-start announcements popup. Registered from vwa_menus_init via
// vwa_menu_main_init; shared activation mirrors live in scrVwaWidgets.
// Imported by tools/build-mod.csx as a new global script. Ships in release.

function vwa_menu_main_init()
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
