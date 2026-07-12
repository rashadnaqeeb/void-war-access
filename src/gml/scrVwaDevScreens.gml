// scrVwaDevScreens - Void War Access synthetic test screens: known-data
// fixtures exercising the navigator and submenu engines end to end; the
// screen smoke (scripts/smoke.ps1) walks both. Toggled through the dev
// driver: call vwa_dev_test_menu on|off, call vwa_dev_test_submenu on|off.
// Imported by tools/build-mod.csx, DEV BUILDS ONLY (like scrVwaDev): the
// release build omits this file.

// ---- the synthetic test menu (session 4) ----
// A fake screen exercising every navigator behavior against known data:
// labeled single-item rows (auto "n of m"), a two-item row, a toggle with a
// live value part, a slider with onAdjust, a second Tab stop under a labeled
// context, a no-action label, plus helpers to move focus and rename an item
// (tier-1 identity: the skey changes, the backing ref struct does not).
// All text here is dev text, exempt from localization.

function vwa_dev_test_menu(spec)
{
    if (spec == "off")
    {
        global.vwaDevMenuOn = false;
        return "test menu off";
    }
    if (spec != "on")
    {
        throw "vwa_dev_test_menu wants on or off";
    }
    // Fresh state on every "on" so scripted transcripts are deterministic.
    global.vwaDevMenu = {
        items: [{ nm: "Alpha" }, { nm: "Beta" }, { nm: "Gamma" }],
        soundOn: false,
        volume: 5,
        hideBeta: false
    };
    global.vwaDevMenuOn = true;
    var scr = vwa_screen_find("vwa-test-menu");
    if (scr == undefined)
    {
        vwa_screen_register({
            key: "vwa-test-menu",
            layerNum: 91,
            categories: ["ui"],
            isActive: function() { return global.vwaDevMenuOn; },
            name: function() { return "Test menu"; },
            build: function(b) { vwa_dev_menu_build(b); }
        });
    }
    else
    {
        vwa_nav_state_reset(scr.navState);
    }
    return "test menu on";
}

function vwa_dev_menu_build(b)
{
    var m = global.vwaDevMenu;

    vwa_gb_begin_stop(b, "main");
    for (var i = 0; i < array_length(m.items); i++)
    {
        var it = m.items[i];
        if (m.hideBeta && it.nm == "Beta")
        {
            continue;
        }
        vwa_gb_add(b, vwa_id_ref(it, "item:" + it.nm), {
            typeKey: "button",
            parts: [vwa_part_fn("label",
                method({ it: it }, function() { return self.it.nm; }), false)],
            onActivate: method({ it: it }, function()
            {
                vwa_speak([self.it.nm + " pressed"], false);
            })
        });
    }
    vwa_gb_add(b, vwa_id("sound"), {
        typeKey: "toggle",
        parts: [vwa_part("label", "Sound"),
            vwa_part_fn("value", function()
            {
                return global.vwaDevMenu.soundOn ? "on" : "off";
            }, true)],
        onActivate: function()
        {
            global.vwaDevMenu.soundOn = !global.vwaDevMenu.soundOn;
        }
    });
    vwa_gb_add(b, vwa_id("volume"), {
        typeKey: "slider",
        parts: [vwa_part("label", "Volume"),
            vwa_part_fn("value", function()
            {
                return string(global.vwaDevMenu.volume);
            }, true)],
        onAdjust: function(sign, large)
        {
            var stepSize = large ? 5 : 1;
            global.vwaDevMenu.volume = clamp(
                global.vwaDevMenu.volume + sign * stepSize, 0, 10);
        }
    });
    // Named group: exercises the explicit groupLabel path (the settings
    // screen's unnamed rows exercise the generic fallback).
    vwa_gb_start_row(b, undefined, "Actions");
    vwa_gb_add(b, vwa_id("ok"), {
        typeKey: "button",
        parts: [vwa_part("label", "OK")],
        onActivate: function() { vwa_speak(["OK pressed"], false); }
    });
    vwa_gb_add(b, vwa_id("cancel"), {
        typeKey: "button",
        parts: [vwa_part("label", "Cancel")],
        onActivate: function() { vwa_speak(["Cancel pressed"], false); }
    });
    vwa_gb_end_row(b);

    vwa_gb_begin_stop(b, "extras");
    vwa_gb_push_context(b, "Extras");
    vwa_gb_add(b, vwa_id("one"), {
        typeKey: "button",
        parts: [vwa_part("label", "One")],
        onActivate: function() { vwa_speak(["One pressed"], false); }
    });
    vwa_gb_add(b, vwa_id("two"), {
        typeKey: "button",
        parts: [vwa_part("label", "Two")],
        onActivate: function() { vwa_speak(["Two pressed"], false); }
    });
    vwa_gb_add(b, vwa_id("status"), {
        typeKey: "label",
        parts: [vwa_part("label", "Status")]
    });
    vwa_gb_pop_context(b);
}

// Ask the test menu's navigator to land on a node next frame (goes through
// the normal reconcile path, so the landing is announced by observe).
function vwa_dev_menu_focus(skey)
{
    var scr = vwa_screen_find("vwa-test-menu");
    if (scr == undefined)
    {
        throw "test menu not registered (call vwa_dev_test_menu on)";
    }
    scr.navState.nextMove = skey;
    return "focus requested: " + skey;
}

// Rename an item in place: its structural key changes with the label while
// its backing ref struct stays - the tier-1 focus-follow test.
function vwa_dev_menu_rename(oldName, newName)
{
    var m = global.vwaDevMenu;
    for (var i = 0; i < array_length(m.items); i++)
    {
        if (m.items[i].nm == oldName)
        {
            m.items[i].nm = newName;
            return "renamed " + oldName + " to " + newName;
        }
    }
    throw ("no test menu item named " + oldName);
}

// ---- the synthetic submenu test screen (session 8) ----
// A fake screen exercising every submenu behavior against known data: a
// plain item, two sibling submenus (one holding a slider - left/right stay
// the slider's own, so left must NOT exit there - and one holding a nested
// submenu as its LAST child, so the bottom exit recurses through two
// levels), and a plain item after them.
// All text here is dev text, exempt from localization.

function vwa_dev_test_submenu(spec)
{
    if (spec == "off")
    {
        global.vwaDevSubmenuOn = false;
        return "submenu test screen off";
    }
    if (spec != "on")
    {
        throw "vwa_dev_test_submenu wants on or off";
    }
    // Fresh state on every "on" so scripted transcripts are deterministic.
    global.vwaDevSubmenu = { master: 5, fullscreen: false };
    global.vwaDevSubmenuOn = true;
    var scr = vwa_screen_find("vwa-test-submenu");
    if (scr == undefined)
    {
        vwa_screen_register({
            key: "vwa-test-submenu",
            layerNum: 93,
            categories: ["ui"],
            isActive: function() { return global.vwaDevSubmenuOn; },
            name: function() { return "Submenu test"; },
            build: function(b) { vwa_dev_submenu_build(b); }
        });
    }
    else
    {
        vwa_nav_state_reset(scr.navState);
    }
    return "submenu test screen on";
}

function vwa_dev_submenu_build(b)
{
    vwa_gb_begin_stop(b, "main");
    vwa_gb_add(b, vwa_id("intro"), {
        typeKey: "button",
        parts: [vwa_part("label", "Intro")],
        onActivate: function() { vwa_speak(["Intro pressed"], false); }
    });

    vwa_gb_begin_submenu(b, vwa_id("sm:audio"), {
        parts: [vwa_part("label", "Audio")]
    });
    vwa_gb_add(b, vwa_id("master"), {
        typeKey: "slider",
        parts: [vwa_part("label", "Master"),
            vwa_part_fn("value", function()
            {
                return string(global.vwaDevSubmenu.master);
            }, true)],
        onAdjust: function(sign, large)
        {
            var stepSize = large ? 5 : 1;
            global.vwaDevSubmenu.master = clamp(
                global.vwaDevSubmenu.master + sign * stepSize, 0, 10);
        }
    });
    vwa_gb_add(b, vwa_id("music"), {
        typeKey: "button",
        parts: [vwa_part("label", "Music")],
        onActivate: function() { vwa_speak(["Music pressed"], false); }
    });
    vwa_gb_end_submenu(b);

    vwa_gb_begin_submenu(b, vwa_id("sm:video"), {
        parts: [vwa_part("label", "Video")]
    });
    vwa_gb_add(b, vwa_id("fullscreen"), {
        typeKey: "toggle",
        parts: [vwa_part("label", "Fullscreen"),
            vwa_part_fn("value", function()
            {
                return global.vwaDevSubmenu.fullscreen ? "on" : "off";
            }, true)],
        onActivate: function()
        {
            global.vwaDevSubmenu.fullscreen = !global.vwaDevSubmenu.fullscreen;
        }
    });
    vwa_gb_begin_submenu(b, vwa_id("sm:adv"), {
        parts: [vwa_part("label", "Advanced")]
    });
    vwa_gb_add(b, vwa_id("gamma"), {
        typeKey: "button",
        parts: [vwa_part("label", "Gamma")],
        onActivate: function() { vwa_speak(["Gamma pressed"], false); }
    });
    vwa_gb_add(b, vwa_id("delta"), {
        typeKey: "button",
        parts: [vwa_part("label", "Delta")],
        onActivate: function() { vwa_speak(["Delta pressed"], false); }
    });
    vwa_gb_end_submenu(b);
    vwa_gb_end_submenu(b);

    vwa_gb_add(b, vwa_id("outro"), {
        typeKey: "button",
        parts: [vwa_part("label", "Outro")],
        onActivate: function() { vwa_speak(["Outro pressed"], false); }
    });
}
