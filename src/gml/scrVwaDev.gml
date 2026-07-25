// scrVwaDev - Void War Access dev-driver command interpreter (eval-lite).
// Imported by tools/build-mod.csx as a new global script, DEV BUILDS ONLY:
// the release build omits this file and the pump append entirely.
//
// Every /cmd body lands in vwa_dev_dispatch via the pump (one command per
// step). GML cannot compile code at runtime, so instead of a true eval this
// interprets a small vocabulary over GML's reflection facilities. All
// validation failures are thrown as plain strings; the pump's catch turns
// them into "ERROR: <msg>" replies. A bad command must never crash the game.
//
// Vocabulary (see vwa_dev_dispatch): ping, say, room, help,
//   get <path> / set <path> <value> / dump <path> [depth]
//   instances <objectName> / call <scriptOrPath> [args...]
//   globals [filter] / scripts [filter] (discovery, name-substring filter)
//   gui.raw [objectName] / gui.mod / screenshot
//   state (input layer dump) / input <actionKey> (fire an action)
// set values and call arguments accept JSON-ish compound literals
// ([1, "two"], {a: 1, b: [2]}) alongside the scalar forms.
//
// Paths: global.name, objectName.var (first live instance), or a numeric
// instance id; segments join with '.' and arrays index with [n], e.g.
//   oMainMenuControls.buttonList[2].buttonStr
//
// This file holds the command implementations and dispatch. The parsing
// and emission substrate (JSON dump, path resolution, literal and token
// parsing) lives in scrVwaDevParse.

// ---- commands ----

function vwa_dev_set(path, literalText)
{
    // Compound or quoted values go through the scanner; anything else keeps
    // the legacy whole-rest scalar parse so an unquoted multi-word string
    // (set global.name hello world) still lands as one string.
    var v;
    var c0 = string_char_at(literalText, 1);
    if (c0 == "[" || c0 == "{" || c0 == "\"")
    {
        var lit = vwa_lit_scan(literalText, 1);
        if (vwa_lit_skip_ws(literalText, lit.next) <= string_length(literalText))
        {
            throw ("unexpected text after the value literal: "
                + string_delete(literalText, 1, lit.next - 1));
        }
        v = lit.v;
    }
    else
    {
        v = vwa_parse_literal(literalText, false);
    }
    var segs = vwa_path_segments(path);
    var n = array_length(segs);
    var last = segs[n - 1];
    var li = array_length(last.idx);

    if (li > 0)
    {
        // Final write is an array slot: resolve through everything except
        // the last index, then assign (arrays are reference types).
        var arr = vwa_resolve_segs(segs, n, li - 1);
        if (!is_array(arr))
        {
            throw ("final index of " + path + " does not land on an array");
        }
        var ix = last.idx[li - 1];
        if (ix < 0 || ix >= array_length(arr))
        {
            throw ("index " + string(ix) + " out of range (array length "
                + string(array_length(arr)) + ")");
        }
        arr[ix] = v;
        return "ok";
    }
    if (n == 1)
    {
        throw "set needs a dotted path, e.g. global.name or oObject.var";
    }
    if (n == 2 && segs[0].name == "global")
    {
        variable_global_set(last.name, v);
        return "ok";
    }
    var parent = vwa_resolve_segs(segs, n - 1, -1);
    if (is_struct(parent))
    {
        variable_struct_set(parent, last.name, v);
        return "ok";
    }
    if (vwa_is_instance(parent))
    {
        variable_instance_set(parent, last.name, v);
        return "ok";
    }
    throw ("cannot set ." + last.name + " on a " + typeof(parent));
}

function vwa_dev_instances(objName)
{
    if (asset_get_type(objName) != asset_object)
    {
        throw ("not an object: " + objName);
    }
    var obj = asset_get_index(objName);
    var cnt = instance_number(obj);
    var out = "{\"count\":" + string(cnt) + ",\"instances\":[";
    for (var i = 0; i < cnt; i++)
    {
        var inst = instance_find(obj, i);
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"id\":" + vwa_instance_id_str(inst)
            + ",\"object\":" + vwa_json_str(object_get_name(inst.object_index))
            + ",\"x\":" + vwa_json_num(inst.x) + ",\"y\":" + vwa_json_num(inst.y)
            + ",\"depth\":" + vwa_json_num(inst.depth)
            + ",\"visible\":" + (inst.visible ? "true" : "false") + "}";
    }
    return out + "]}";
}

// ---- discovery (globals / scripts) ----

// Case-insensitive substring match; an empty filter matches everything.
function vwa_dev_name_match(name, filter)
{
    if (filter == "")
    {
        return true;
    }
    return string_pos(string_lower(filter), string_lower(name)) > 0;
}

// globals [filter]: every global variable name with its value's typeof,
// sorted. The entry point for discovering game state to get/dump.
function vwa_dev_globals(filter)
{
    var names = variable_instance_get_names(global);
    array_sort(names, true);
    var out = "";
    var cnt = 0;
    for (var i = 0; i < array_length(names); i++)
    {
        if (!vwa_dev_name_match(names[i], filter))
        {
            continue;
        }
        if (cnt > 0)
        {
            out += ",";
        }
        out += "{\"name\":" + vwa_json_str(names[i]) + ",\"type\":"
            + vwa_json_str(typeof(variable_global_get(names[i]))) + "}";
        cnt++;
    }
    return "{\"count\":" + string(cnt) + ",\"globals\":[" + out + "]}";
}

// scripts [filter]: scan the script asset table by index. Script assets
// have no enumeration function, so this probes two index ranges: the
// classic asset range from 0 and the GMS 2.3+ function-script range from
// 100000. A linear probe of dead indices is cheap (script_exists), and this
// is a dev command. Output is name-sorted and capped.
function vwa_dev_scripts(filter)
{
    var hits = [];
    var ranges = [[0, 20000], [100000, 120000]];
    for (var r = 0; r < array_length(ranges); r++)
    {
        for (var i = ranges[r][0]; i < ranges[r][1]; i++)
        {
            if (!script_exists(i))
            {
                continue;
            }
            var nm = script_get_name(i);
            if (vwa_dev_name_match(nm, filter))
            {
                array_push(hits, { name: nm, index: i });
            }
        }
    }
    array_sort(hits, function(a, b)
    {
        if (a.name == b.name)
        {
            return 0;
        }
        return (a.name < b.name) ? -1 : 1;
    });
    var shown = min(array_length(hits), 500);
    var out = "";
    for (var i = 0; i < shown; i++)
    {
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"name\":" + vwa_json_str(hits[i].name)
            + ",\"index\":" + string(hits[i].index) + "}";
    }
    return "{\"count\":" + string(array_length(hits))
        + ",\"shown\":" + string(shown) + ",\"scripts\":[" + out + "]}";
}

// argsText: everything after the name; space-separated literals, each of
// which may be a compound (arrays/structs may contain spaces internally).
function vwa_dev_call(nameTok, argsText)
{
    var args = [];
    var ai = vwa_lit_skip_ws(argsText, 1);
    while (ai <= string_length(argsText))
    {
        var lit = vwa_lit_scan(argsText, ai);
        array_push(args, lit.v);
        ai = vwa_lit_skip_ws(argsText, lit.next);
    }
    var fn;
    var isBoundMethod = false;
    if (string_pos(".", nameTok) > 0)
    {
        fn = vwa_resolve(nameTok);
        if (!is_method(fn))
        {
            throw (nameTok + " is not a method (got " + typeof(fn) + ")");
        }
        isBoundMethod = true;
    }
    else
    {
        if (asset_get_type(nameTok) != asset_script)
        {
            throw ("no such script function: " + nameTok);
        }
        fn = asset_get_index(nameTok);
    }
    var result;
    if (isBoundMethod)
    {
        // script_execute_ext on a METHOD value does not call it: the method
        // coerces to a number and some unrelated script index runs instead,
        // silently (bit us session 5 - `call oMenuSettings.closeMenu`
        // returned fresh ds handles and closed nothing). Methods must be
        // invoked directly, which also preserves their bound self.
        var argc = array_length(args);
        if (argc == 0) { result = fn(); }
        else if (argc == 1) { result = fn(args[0]); }
        else if (argc == 2) { result = fn(args[0], args[1]); }
        else if (argc == 3) { result = fn(args[0], args[1], args[2]); }
        else if (argc == 4) { result = fn(args[0], args[1], args[2], args[3]); }
        else { throw "method calls support at most 4 arguments"; }
    }
    else
    {
        result = script_execute_ext(fn, args);
    }
    global.vwaDumpBudget = 5000;
    return "{\"result\":" + vwa_dump_json(result, 2) + "}";
}

// The game-truth UI dump. With no argument, enumerates the known UI widget
// families; with an object name, every live instance of it with ALL its
// variables. Diffed later against /gui/mod (session 4) to find what the mod
// is losing.
function vwa_dev_gui_raw(objName)
{
    global.vwaDumpBudget = 40000;
    var out = "{\"room\":" + vwa_json_str(room_get_name(room));
    out += ",\"menuToggle\":";
    out += variable_global_exists("menuToggle")
        ? vwa_dump_json(global.menuToggle, 1) : "null";
    out += ",\"families\":{";
    var fams;
    var fullVars = false;
    if (objName != "")
    {
        fams = [objName];
        fullVars = true;
    }
    else
    {
        fams = ["oMainMenuControls", "oButton", "oButton_menus", "oMenuElement",
                "obj_gm_button", "o1x1Pixel"];
    }
    // label/state variables worth surfacing per widget, verified against the
    // decompiled Create events of oButton / oButton_menus / oMenuElement /
    // oMainMenuControls; d limits dump depth (parentObj would otherwise pull
    // in its whole owner).
    var wl = [
        { n: "buttonStr", d: 1 }, { n: "text", d: 1 }, { n: "centerText", d: 1 },
        { n: "centerTextOverride", d: 1 }, { n: "leftText", d: 1 }, { n: "rightText", d: 1 },
        { n: "leftLabel", d: 1 }, { n: "rightLabel", d: 1 }, { n: "tooltipStr", d: 1 },
        { n: "hover", d: 1 }, { n: "buttonList", d: 3 }, { n: "parentObj", d: 0 }
    ];
    for (var f = 0; f < array_length(fams); f++)
    {
        if (f > 0)
        {
            out += ",";
        }
        out += vwa_json_str(fams[f]) + ":";
        if (asset_get_type(fams[f]) != asset_object)
        {
            out += vwa_json_str("<no such object>");
            continue;
        }
        var obj = asset_get_index(fams[f]);
        var cnt = instance_number(obj);
        out += "[";
        for (var i = 0; i < cnt; i++)
        {
            var inst = instance_find(obj, i);
            if (i > 0)
            {
                out += ",";
            }
            if (fullVars)
            {
                out += vwa_dump_instance(inst, 3);
            }
            else
            {
                out += "{\"__object\":" + vwa_json_str(object_get_name(inst.object_index))
                    + ",\"__id\":" + vwa_instance_id_str(inst)
                    + ",\"x\":" + vwa_json_num(inst.x) + ",\"y\":" + vwa_json_num(inst.y)
                    + ",\"depth\":" + vwa_json_num(inst.depth)
                    + ",\"visible\":" + (inst.visible ? "true" : "false")
                    + ",\"xscale\":" + vwa_json_num(inst.image_xscale)
                    + ",\"yscale\":" + vwa_json_num(inst.image_yscale);
                for (var w = 0; w < array_length(wl); w++)
                {
                    if (variable_instance_exists(inst, wl[w].n))
                    {
                        out += "," + vwa_json_str(wl[w].n) + ":"
                            + vwa_dump_json(variable_instance_get(inst, wl[w].n), wl[w].d);
                    }
                }
                out += "}";
            }
            if (global.vwaDumpBudget <= 0)
            {
                break;
            }
        }
        out += "]";
    }
    return out + "}}";
}

// ---- input layer introspection (session 3) ----

// GET /state: the game-key gate, screen stack, live categories, every
// registered action, and per-chord shadowing resolution. labelKey is
// reported raw (not localized) so dev test actions need no CSV rows.
function vwa_dev_state_json()
{
    var live = vwa_live_categories();
    var out = "{\"gameKeysOpen\":" + (global.vwaGameKeysOpen ? "true" : "false");
    var vks = variable_struct_get_names(global.vwaGameAllowVks);
    out += ",\"gameAllowVks\":[";
    for (var i = 0; i < array_length(vks); i++)
    {
        if (i > 0)
        {
            out += ",";
        }
        out += vks[i];
    }
    var binds = variable_struct_get_names(global.vwaGameAllowBinds);
    out += "],\"gameAllowBinds\":[";
    for (var i = 0; i < array_length(binds); i++)
    {
        if (i > 0)
        {
            out += ",";
        }
        out += vwa_json_str(binds[i]);
    }
    out += "]"
        + ",\"textFieldInput\":" + (global.textFieldInputEnabled ? "true" : "false")
        + ",\"watchdogTripped\":" + (global.vwaInputWatchdogTripped ? "true" : "false")
        + ",\"ticks\":" + vwa_json_num(global.vwaInputTicks)
        + ",\"keyDelayMs\":" + vwa_json_num(global.vwaKeyDelayMs)
        + ",\"keyRateMs\":" + vwa_json_num(global.vwaKeyRateMs)
        + ",\"shipMode\":" + (vwa_ship_mode_active() ? "true" : "false")
        + ",\"shipFocusAllied\":" + vwa_json_num(global.vwaShipLayer.focusAllied);

    out += ",\"stack\":[";
    for (var i = 0; i < array_length(global.vwaScreenStack); i++)
    {
        var scr = global.vwaScreenStack[i];
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"name\":" + vwa_json_str(scr.key)
            + ",\"layer\":" + vwa_json_num(scr.layerNum)
            + ",\"exclusive\":" + (scr.exclusive ? "true" : "false")
            + ",\"categories\":[";
        for (var j = 0; j < array_length(scr.categories); j++)
        {
            if (j > 0)
            {
                out += ",";
            }
            out += vwa_json_str(scr.categories[j]);
        }
        out += "]}";
    }

    out += "],\"liveCategories\":[";
    for (var i = 0; i < array_length(live); i++)
    {
        if (i > 0)
        {
            out += ",";
        }
        out += vwa_json_str(live[i]);
    }

    out += "],\"actions\":[";
    for (var i = 0; i < array_length(global.vwaActionOrder); i++)
    {
        var a = variable_struct_get(global.vwaActions, global.vwaActionOrder[i]);
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"key\":" + vwa_json_str(a.actionKey)
            + ",\"labelKey\":" + vwa_json_str(a.labelKey)
            + ",\"category\":" + vwa_json_str(a.category)
            + ",\"bindings\":[";
        for (var bi = 0; bi < array_length(a.bindings); bi++)
        {
            var bnd = a.bindings[bi];
            if (bi > 0)
            {
                out += ",";
            }
            out += "{\"vk\":" + vwa_json_num(bnd.vk)
                + ",\"shift\":" + (bnd.shift ? "true" : "false")
                + ",\"ctrl\":" + (bnd.ctrl ? "true" : "false")
                + ",\"alt\":" + (bnd.alt ? "true" : "false") + "}";
        }
        out += "]"
            + ",\"repeats\":" + (a.repeats ? "true" : "false")
            + ",\"live\":" + (vwa_array_index_of(live, a.category) >= 0 ? "true" : "false")
            + "}";
    }

    // Shadowing: chords carried by more than one LIVE action, with the
    // winner dispatch would pick this frame.
    out += "],\"conflicts\":[";
    var groups = {};
    var chordIds = [];
    for (var i = 0; i < array_length(global.vwaActionOrder); i++)
    {
        var a = variable_struct_get(global.vwaActions, global.vwaActionOrder[i]);
        var prio = vwa_array_index_of(live, a.category);
        if (prio < 0)
        {
            continue;
        }
        for (var bi = 0; bi < array_length(a.bindings); bi++)
        {
            var cid = vwa_chord_id(a.bindings[bi]);
            var g = variable_struct_get(groups, cid);
            if (g == undefined)
            {
                g = [];
                variable_struct_set(groups, cid, g);
                array_push(chordIds, cid);
            }
            array_push(g, { key: a.actionKey, prio: prio });
        }
    }
    var first = true;
    for (var i = 0; i < array_length(chordIds); i++)
    {
        var g = variable_struct_get(groups, chordIds[i]);
        if (array_length(g) < 2)
        {
            continue;
        }
        var win = 0;
        for (var j = 1; j < array_length(g); j++)
        {
            if (g[j].prio < g[win].prio)
            {
                win = j;
            }
        }
        if (!first)
        {
            out += ",";
        }
        first = false;
        out += "{\"chord\":" + vwa_json_str(chordIds[i])
            + ",\"winner\":" + vwa_json_str(g[win].key) + ",\"shadowed\":[";
        var shFirst = true;
        for (var j = 0; j < array_length(g); j++)
        {
            if (j == win)
            {
                continue;
            }
            if (!shFirst)
            {
                out += ",";
            }
            shFirst = false;
            out += vwa_json_str(g[j].key);
        }
        out += "]}";
    }
    return out + "]}";
}

// ---- input layer dev helpers (invoked via the call command) ----

// Input-layer test screen: a graph-less, silent screen registered through
// the real screen registry (scrVwaScreens) whose only job is to make a
// chosen category set live. spec: comma-separated category list, or "none";
// a trailing "!" marks the screen exclusive (a hard modal blocking the
// categories of screens below it). Layer 92 puts it above the test menu
// (91) so the exclusive behavior is observable. The stack updates on the
// next screens tick (a frame later), which every caller observes through a
// later HTTP round-trip anyway.
function vwa_dev_test_screen(spec)
{
    if (spec == "none" || spec == "")
    {
        global.vwaDevTestScreenOn = false;
        return "stack cleared";
    }
    var excl = false;
    if (string_char_at(spec, string_length(spec)) == "!")
    {
        excl = true;
        spec = string_copy(spec, 1, string_length(spec) - 1);
    }
    var cats = [];
    var cur = "";
    for (var i = 1; i <= string_length(spec); i++)
    {
        var c = string_char_at(spec, i);
        if (c == ",")
        {
            if (cur != "")
            {
                array_push(cats, cur);
            }
            cur = "";
        }
        else
        {
            cur += c;
        }
    }
    if (cur != "")
    {
        array_push(cats, cur);
    }
    global.vwaDevTestScreenOn = true;
    var scr = vwa_screen_find("vwa-test-screen");
    if (scr == undefined)
    {
        vwa_screen_register({
            key: "vwa-test-screen",
            layerNum: 92,
            categories: cats,
            exclusive: excl,
            isActive: function() { return global.vwaDevTestScreenOn; }
        });
    }
    else
    {
        scr.categories = cats;
        scr.exclusive = excl;
    }
    return "test screen pushed with " + string(array_length(cats)) + " categories";
}

// An intentionally-conflicting chord pair (F8 in global and ui - a key no
// real action binds) plus a repeating action (F9, dev) for typematic
// checks. Spoken text here is dev text, exempt from localization.
function vwa_dev_register_test_actions()
{
    global.vwaDevRepeatCount = 0;
    vwa_action_register("dev-shout-global", "dev", "global",
        vwa_bind(vk_f8, false, false, false), false, function()
        {
            vwa_speak(["test shout global"], true);
        });
    vwa_action_register("dev-shout-ui", "dev", "ui",
        vwa_bind(vk_f8, false, false, false), false, function()
        {
            vwa_speak(["test shout ui"], true);
        });
    vwa_action_register("dev-repeat-tick", "dev", "dev",
        vwa_bind(vk_f9, false, false, false), true, function()
        {
            global.vwaDevRepeatCount += 1;
        });
    return "test actions registered";
}

// Arm a one-shot fault inside vwa_input_tick to prove the watchdog fails
// the game-key gate open (the keys-come-back guarantee).
function vwa_dev_arm_input_fault()
{
    global.vwaInputFault = true;
    return "fault armed";
}

// Prove the game-key gate against the game's real input_check, all in one
// frame with every touched state restored: read with NO allowance (the
// deny default - deniedRead must come back false), grant the allowance,
// read again (allowedRead must come back true), then restore.
// keyboard_key_press cannot provide the key-down signal (bit us: simulated
// keys never reach keyboard_check in this runner, even same-frame), so the
// bind is swapped to vk_nokey (0), which keyboard_check reports as held
// whenever NO key is down - always true on an unattended machine.
function vwa_dev_gate_probe(bindName)
{
    var priorKey = variable_struct_get(global.keybinds, bindName);
    if (priorKey == undefined)
    {
        throw ("no such game keybind: " + bindName);
    }
    var priorAllowed = variable_struct_exists(global.vwaGameAllowBinds, bindName);
    var priorOpen = global.vwaGameKeysOpen;
    variable_struct_set(global.keybinds, bindName, 0);
    // A previously tripped watchdog must not fake the deny read.
    global.vwaGameKeysOpen = false;
    var whileDenied = false;
    var whileAllowed = false;
    var clearedIo = false;
    // The restore below must run even when a probe read throws (a game
    // update reshaping input_check, say): the mutated state is the game's
    // real keybind plus the gate allowance, and an escaped throw lands in
    // the dev pump's catch, which restores nothing - the allowance would
    // linger until restart (session-7 review). No verified try/finally
    // under the UTMT importer, so restore-and-rethrow.
    try
    {
        vwa_game_allow_bind(bindName, false);
        whileDenied = input_check(bindName) ? true : false;
        vwa_game_allow_bind(bindName, true);
        whileAllowed = input_check(bindName) ? true : false;
        if (!whileAllowed)
        {
            // Two known lies in the runner's key bookkeeping: freshly-booted io
            // reports "a key is held" with no key named (keyboard_key 0) for
            // minutes, and the bg keepalive swallows the focus-loss messages
            // that clear key state, so a key whose release went to another
            // window reads held forever (a stale Alt; bit us session 4). In
            // both cases keyboard_check_direct (real OS state) disagrees, and
            // io_clear resets the bookkeeping without discarding real input.
            if (keyboard_key == 0 || !keyboard_check_direct(keyboard_key))
            {
                io_clear();
                clearedIo = true;
                whileAllowed = input_check(bindName) ? true : false;
            }
        }
    }
    catch (probeErr)
    {
        variable_struct_set(global.keybinds, bindName, priorKey);
        vwa_game_allow_bind(bindName, priorAllowed);
        global.vwaGameKeysOpen = priorOpen;
        throw probeErr;
    }
    variable_struct_set(global.keybinds, bindName, priorKey);
    vwa_game_allow_bind(bindName, priorAllowed);
    global.vwaGameKeysOpen = priorOpen;
    // kbKey: what the runner thinks is held; kbDirect: whether the OS
    // agrees. allowedRead=false with kbDirect=true means a human is really
    // holding a key right now - callers should retry.
    // Returned via the call command, whose dumper serializes the struct.
    return { deniedRead: whileDenied, allowedRead: whileAllowed,
             kbKey: keyboard_key,
             kbDirect: (keyboard_key > 0 && keyboard_check_direct(keyboard_key)) ? true : false,
             ioCleared: clearedIo };
}

// GET /gui/mod: the mod's interpreted view - the active screen stack, the
// focused screen's current render (nodes with resolved announcement parts,
// positions, stops, parent chains, edges), and the focused node. Diff
// against /gui/raw to find what the mod is losing. The render is the one
// the last screens tick built (at most a frame old); its part texts resolve
// live right here.
function vwa_dev_gui_mod()
{
    var out = "{\"stack\":[";
    for (var i = 0; i < array_length(global.vwaScreenStack); i++)
    {
        var scr = global.vwaScreenStack[i];
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"key\":" + vwa_json_str(scr.key)
            + ",\"layer\":" + vwa_json_num(scr.layerNum)
            + ",\"exclusive\":" + (scr.exclusive ? "true" : "false") + "}";
    }
    out += "]";

    var focused = global.vwaFocusedScreen;
    if (focused == undefined)
    {
        return out + ",\"focused\":null,\"focusKey\":null,\"nodes\":[]}";
    }
    out += ",\"focused\":" + vwa_json_str(focused.key);

    var st = focused.navState;
    out += ",\"focusKey\":"
        + ((st.curId != undefined) ? vwa_json_str(st.curId.skey) : "null");

    out += ",\"nodes\":[";
    if (st.curRender != undefined)
    {
        var order = st.curRender.order;
        for (var i = 0; i < array_length(order); i++)
        {
            var nd = order[i];
            if (i > 0)
            {
                out += ",";
            }
            out += "{\"skey\":" + vwa_json_str(nd.nid.skey)
                + ",\"hasRef\":" + ((nd.nid.ref != undefined) ? "true" : "false")
                + ",\"type\":" + ((nd.typeKey != undefined) ? vwa_json_str(nd.typeKey) : "null")
                + ",\"stop\":" + vwa_json_str(nd.stopKey)
                + ",\"pos\":[" + vwa_json_num(nd.posIndex) + "," + vwa_json_num(nd.posCount) + "]";

            out += ",\"parents\":[";
            var chain = vwa_ann_path(nd);
            for (var j = 0; j < array_length(chain) - 1; j++)
            {
                if (j > 0)
                {
                    out += ",";
                }
                out += vwa_json_str(chain[j].nid.skey);
            }
            // lines mirrors the announcement's line structure (vwa_ann_leaf:
            // summary line, then one line per tooltip/sheet part); parts is
            // the same content flattened, kept for older smoke helpers.
            out += "],\"lines\":[";
            var leaf = vwa_ann_leaf(nd, global.vwaControlTypes, global.vwaAnnHooks);
            var flat = [];
            for (var j = 0; j < array_length(leaf); j++)
            {
                if (j > 0)
                {
                    out += ",";
                }
                out += "[";
                for (var p = 0; p < array_length(leaf[j]); p++)
                {
                    if (p > 0)
                    {
                        out += ",";
                    }
                    out += vwa_json_str(leaf[j][p]);
                    array_push(flat, leaf[j][p]);
                }
                out += "]";
            }
            out += "],\"parts\":[";
            for (var j = 0; j < array_length(flat); j++)
            {
                if (j > 0)
                {
                    out += ",";
                }
                out += vwa_json_str(flat[j]);
            }
            out += "],\"edges\":{";
            var dirs = variable_struct_get_names(nd.trans);
            for (var j = 0; j < array_length(dirs); j++)
            {
                if (j > 0)
                {
                    out += ",";
                }
                out += vwa_json_str(dirs[j]) + ":"
                    + vwa_json_str(variable_struct_get(nd.trans, dirs[j]).to);
            }
            out += "}}";
        }
    }
    return out + "]}";
}

// Spawn any object by name at (0,0) depth 0 - dev-only scaffolding for
// driving screens that are otherwise reachable only mid-run. Verified safe
// for oMenuPause at the main menu: pause_game() no-ops when no run is live
// (scrPause guards on gameStarted), and its Resume button reverts cleanly.
function vwa_dev_spawn(objName)
{
    if (asset_get_type(objName) != asset_object)
    {
        throw ("no such object: " + string(objName));
    }
    var inst = instance_create_depth(0, 0, 0, asset_get_index(objName));
    return { spawned: objName, id: inst };
}

// Dismiss the game-start popup the exact way the game's own Draw_64
// dismissal does (left click / Escape), including the once-per-profile
// double-spawn quirk (the first-ever dismissal respawns the popup once,
// gated by the SAVED global.gameStartPopupSpawned). Dev-only scaffolding:
// scripted smokes cannot press Escape (this runner ignores synthetic keys,
// bit us session 3); a human dismisses with the real key.
function vwa_dev_dismiss_start_popup()
{
    if (!instance_exists(oGameStartMessage))
    {
        throw "no oGameStartMessage instance to dismiss";
    }
    var orig = instance_find(oGameStartMessage, 0);
    var respawned = false;
    if (!global.gameStartPopupSpawned)
    {
        instance_create_depth(0, 0, 0, oGameStartMessage);
        global.gameStartPopupSpawned = true;
        respawned = true;
    }
    with (orig)
    {
        instance_destroy();
    }
    return { dismissed: true, respawned: respawned };
}

// Leave the commander select screen the exact way its own Escape branch
// does (oUICommanderList Step_0, rmCommanderSelect case: delete the display
// crew, back to the main menu, clear the menu flag, destroy the list).
// Dev-only scaffolding for the commander smoke - synthetic Escape cannot be
// pressed (this runner ignores synthetic keys).
function vwa_dev_close_commander_select()
{
    if (!instance_exists(oUICommanderList))
    {
        throw "no oUICommanderList instance to close";
    }
    if (room != rmCommanderSelect)
    {
        throw "not in rmCommanderSelect (the overlay closes via its own click-away)";
    }
    with (oCrew)
    {
        crewDelete = true;
    }
    room_goto(rmMainMenu);
    gameMenu_setFlag(0);
    with (oUICommanderList)
    {
        instance_destroy();
    }
    return { closed: true };
}

// Feed characters into the live type-ahead path with the same letter/space
// filtering the real tick applies - everything below the raw keyboard read
// (this runner ignores synthetic keys, so keyboard_string cannot be driven
// from here). Returns the resulting search state.
function vwa_dev_typeahead(txt)
{
    txt = string(txt);
    for (var i = 1; i <= string_length(txt); i++)
    {
        var o = string_ord_at(txt, i);
        if (vwa_search_char_is_letter(o))
        {
            vwa_nav_typeahead_char(chr(o));
        }
        else if (o == 32 && global.vwaSearch.buffer != "")
        {
            vwa_nav_typeahead_char(" ");
        }
    }
    return vwa_dev_search_state();
}

function vwa_dev_search_state()
{
    var st = global.vwaSearch;
    var nav = global.vwaSearchNav;
    var skeys = [];
    for (var i = 0; i < array_length(st.results); i++)
    {
        array_push(skeys, nav.scopeSkeys[st.results[i]]);
    }
    return { buffer: st.buffer, active: st.active, cursor: st.cursor,
             resultSkeys: skeys, focusSkey: nav.focusSkey };
}

// Append characters to the runner's typed buffer (keyboard_string is a
// writable builtin - unlike synthetic key PRESSES, which this runner
// ignores). oTextField only moves the buffer into its text while a
// physical key is held (its Step gates on keyboard_check(vk_anykey)), so
// this cannot fake end-to-end typing; what it CAN prove is the boundary:
// mid-edit the buffer must persist untouched (the mod's type-ahead drain
// stays off it). Requires the game's text-field mode; use
// vwa_dev_typeahead for the search layer.
function vwa_dev_type(txt)
{
    if (!global.textFieldInputEnabled)
    {
        throw "text-field input not active; use vwa_dev_typeahead for the search layer";
    }
    vwa_input_inject_typed(string(txt));
    return { typed: string(txt) };
}

// The text edit layer's live state plus the game-side truth it tracks.
// kbString is the runner's raw typed buffer (a read does not drain it):
// the smoke uses it to prove the type-ahead drain keeps its hands off the
// buffer mid-edit. Raw keyboard access in dev code follows the
// vwa_dev_key_direct precedent.
function vwa_dev_text_state()
{
    var st = global.vwaText;
    return { active: st.active, pending: st.pending,
             flag: global.textFieldInputEnabled ? true : false,
             fieldExists: instance_exists(oTextField) ? true : false,
             fieldText: instance_exists(oTextField) ? string(oTextField.text) : "",
             kbString: string(keyboard_string) };
}

// Diagnostic: the runner's view of a key vs the OS's (keyboard_check_direct
// ignores window focus). Disagreement = stale runner bookkeeping (see
// vwa_input_unstick_keys).
function vwa_dev_key_direct(vk)
{
    return { vk: vk,
             runnerCheck: keyboard_check(vk) ? true : false,
             osDirect: keyboard_check_direct(vk) ? true : false };
}

function vwa_dev_screenshot()
{
    // Relative paths land in the save dir; game_save_id is its absolute path.
    var fname = "vwa-shot-" + string(int64(current_time)) + ".png";
    screen_save(fname);
    return "{\"path\":" + vwa_json_str(game_save_id + fname) + "}";
}

// ---- dispatch ----
// Called from the pump (oInputManager Begin Step append) once per frame.
// Throws propagate to the pump's catch and return as "ERROR: <msg>".

function vwa_dev_dispatch(cmd)
{
    // command word + rest of line
    var sp = string_pos(" ", cmd);
    var word = (sp > 0) ? string_copy(cmd, 1, sp - 1) : cmd;
    var rest = (sp > 0) ? string_trim(string_delete(cmd, 1, sp)) : "";

    switch (word)
    {
        case "ping":
            return "pong";

        case "say":
            if (rest == "")
            {
                throw "say needs text";
            }
            vwa_speak([rest], true);
            return "ok";

        case "room":
            return "{\"room\":" + vwa_json_str(room_get_name(room)) + "}";

        case "get":
            if (rest == "")
            {
                throw "get needs a path";
            }
            global.vwaDumpBudget = 5000;
            return vwa_dump_json(vwa_resolve(rest), 2);

        case "dump":
        {
            if (rest == "")
            {
                throw "dump needs a path";
            }
            var dToks = vwa_dev_tokens(rest);
            var dumpDepth = 3; // "depth" is a builtin; var over it is a compile error
            if (array_length(dToks) >= 2)
            {
                dumpDepth = real(dToks[1].t);
            }
            // Depth bounds the recursion; the node budget alone does not: a
            // cyclic instance graph (dialogue -> button -> parentID ->
            // dialogue) recurses one VM frame per node, and a huge depth
            // overflows the GML stack - a hard process crash, not a
            // catchable error (session-7 review).
            dumpDepth = clamp(dumpDepth, 0, 16);
            global.vwaDumpBudget = 40000;
            return vwa_dump_json(vwa_resolve(dToks[0].t), dumpDepth);
        }

        case "set":
        {
            var sp2 = string_pos(" ", rest);
            if (rest == "" || sp2 == 0)
            {
                throw "set needs a path and a value";
            }
            var path = string_copy(rest, 1, sp2 - 1);
            var val = string_trim(string_delete(rest, 1, sp2));
            return vwa_dev_set(path, val);
        }

        case "instances":
            if (rest == "")
            {
                throw "instances needs an object name";
            }
            return vwa_dev_instances(rest);

        case "globals":
            return vwa_dev_globals(rest);

        case "scripts":
            return vwa_dev_scripts(rest);

        case "call":
        {
            if (rest == "")
            {
                throw "call needs a script or method path";
            }
            // name = first space-delimited token; the rest is literal args
            var csp = string_pos(" ", rest);
            var cname = (csp > 0) ? string_copy(rest, 1, csp - 1) : rest;
            var cargs = (csp > 0) ? string_delete(rest, 1, csp) : "";
            return vwa_dev_call(cname, cargs);
        }

        case "gui.raw":
            return vwa_dev_gui_raw(rest);

        case "gui.mod":
            return vwa_dev_gui_mod();

        case "screenshot":
            return vwa_dev_screenshot();

        case "state":
            return vwa_dev_state_json();

        case "input":
            if (rest == "")
            {
                throw "input needs an action key";
            }
            return vwa_input_fire(rest);

        case "help":
            return "commands: ping | say <text> | room | get <path> | "
                + "set <path> <value> | dump <path> [depth] | "
                + "instances <objectName> | globals [filter] | scripts [filter] | "
                + "call <scriptOrPath> [args...] | "
                + "gui.raw [objectName] | gui.mod | screenshot | state | "
                + "input <actionKey> | help; set values and call args accept "
                + "JSON-ish literals: [1, \"two\"] and {a: 1}";

        default:
            return "unknown command: " + word + " (try help)";
    }
}
