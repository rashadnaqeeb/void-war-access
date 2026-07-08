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
//   gui.raw [objectName] / screenshot
//   state (input layer dump) / input <actionKey> (fire an action)
//
// Paths: global.name, objectName.var (first live instance), or a numeric
// instance id; segments join with '.' and arrays index with [n], e.g.
//   oMainMenuControls.buttonList[2].buttonStr

// ---- JSON emission ----
// Hand-rolled instead of json_stringify: the dumper must summarize methods,
// live instances, and over-deep values, none of which json_stringify handles,
// and string(<real>) truncates to two decimals so numbers get their own path.

function vwa_json_str(s)
{
    var out = "\"";
    var n = string_length(s);
    for (var i = 1; i <= n; i++)
    {
        var c = string_char_at(s, i);
        var o = ord(c);
        if (c == "\"")
        {
            out += "\\\"";
        }
        else if (c == "\\")
        {
            out += "\\\\";
        }
        else if (o == 10)
        {
            out += "\\n";
        }
        else if (o == 13)
        {
            out += "\\r";
        }
        else if (o == 9)
        {
            out += "\\t";
        }
        else if (o < 32)
        {
            var hex = "0123456789abcdef";
            out += "\\u00" + string_char_at(hex, (o div 16) + 1) + string_char_at(hex, (o mod 16) + 1);
        }
        else
        {
            out += c;
        }
    }
    return out + "\"";
}

function vwa_json_num(v)
{
    if (v == floor(v) && abs(v) < 9007199254740992)
    {
        return string(int64(v));
    }
    // string() truncates reals to 2 decimals; format wide then trim zeros.
    var s = string_format(v, 0, 10);
    while (string_char_at(s, string_length(s)) == "0")
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    if (string_char_at(s, string_length(s)) == ".")
    {
        s = string_copy(s, 1, string_length(s) - 1);
    }
    return s;
}

// An instance reference or a real that names a live instance.
function vwa_is_instance(v)
{
    if (typeof(v) == "ref")
    {
        return instance_exists(v);
    }
    if (is_real(v))
    {
        return v >= 100000 && instance_exists(v);
    }
    return false;
}

function vwa_instance_id_str(inst)
{
    try
    {
        return string(int64(inst.id));
    }
    catch (e)
    {
        return string(inst.id);
    }
}

// Recursive JSON dump of any GML value. depth limits recursion (over-deep
// values become summary strings); global.vwaDumpBudget caps total nodes so a
// dump of a huge graph cannot wedge the frame or exhaust memory.
function vwa_dump_json(v, depth)
{
    global.vwaDumpBudget -= 1;
    if (global.vwaDumpBudget <= 0)
    {
        return vwa_json_str("<truncated: dump budget exhausted>");
    }
    if (is_undefined(v))
    {
        return "null";
    }
    if (is_method(v))
    {
        return vwa_json_str("<method>");
    }
    if (is_string(v))
    {
        return vwa_json_str(v);
    }
    if (is_bool(v))
    {
        return v ? "true" : "false";
    }
    if (is_array(v))
    {
        var len = array_length(v);
        if (depth <= 0)
        {
            return vwa_json_str("<array of " + string(len) + ">");
        }
        var out = "[";
        for (var i = 0; i < len; i++)
        {
            if (i > 0)
            {
                out += ",";
            }
            out += vwa_dump_json(v[i], depth - 1);
            if (global.vwaDumpBudget <= 0)
            {
                break;
            }
        }
        return out + "]";
    }
    if (is_struct(v))
    {
        var names = variable_struct_get_names(v);
        if (depth <= 0)
        {
            return vwa_json_str("<struct " + string(array_length(names)) + " keys>");
        }
        var out = "{";
        for (var i = 0; i < array_length(names); i++)
        {
            if (i > 0)
            {
                out += ",";
            }
            out += vwa_json_str(names[i]) + ":"
                + vwa_dump_json(variable_struct_get(v, names[i]), depth - 1);
            if (global.vwaDumpBudget <= 0)
            {
                break;
            }
        }
        return out + "}";
    }
    if (vwa_is_instance(v))
    {
        return vwa_dump_instance(v, depth);
    }
    if (is_real(v) || is_int32(v) || is_int64(v))
    {
        return vwa_json_num(v);
    }
    // asset refs, pointers, other handles
    return vwa_json_str(typeof(v) + " " + string(v));
}

function vwa_dump_instance(inst, depth)
{
    var objName = object_get_name(inst.object_index);
    var idStr = vwa_instance_id_str(inst);
    if (depth <= 0)
    {
        return vwa_json_str("<" + objName + " #" + idStr + ">");
    }
    var out = "{\"__object\":" + vwa_json_str(objName) + ",\"__id\":" + idStr
        + ",\"x\":" + vwa_json_num(inst.x) + ",\"y\":" + vwa_json_num(inst.y)
        + ",\"depth\":" + vwa_json_num(inst.depth)
        + ",\"visible\":" + (inst.visible ? "true" : "false");
    var names = variable_instance_get_names(inst);
    for (var i = 0; i < array_length(names); i++)
    {
        out += "," + vwa_json_str(names[i]) + ":"
            + vwa_dump_json(variable_instance_get(inst, names[i]), depth - 1);
        if (global.vwaDumpBudget <= 0)
        {
            break;
        }
    }
    return out + "}";
}

// ---- path parsing and resolution ----

// "a.b[2].c" -> [{name:"a",idx:[]},{name:"b",idx:[2]},{name:"c",idx:[]}]
function vwa_path_segments(path)
{
    var segs = [];
    var i = 1;
    var n = string_length(path);
    while (i <= n)
    {
        var name = "";
        while (i <= n)
        {
            var c = string_char_at(path, i);
            if (c == "." || c == "[")
            {
                break;
            }
            name += c;
            i++;
        }
        var seg = { name: name, idx: [] };
        while (i <= n && string_char_at(path, i) == "[")
        {
            i++;
            var num = "";
            while (i <= n && string_char_at(path, i) != "]")
            {
                num += string_char_at(path, i);
                i++;
            }
            if (i > n)
            {
                throw ("unclosed [ in path: " + path);
            }
            i++;
            try
            {
                array_push(seg.idx, real(num));
            }
            catch (e)
            {
                throw ("bad array index '" + num + "' in path: " + path);
            }
        }
        if (seg.name == "" && array_length(seg.idx) == 0)
        {
            throw ("empty segment in path: " + path);
        }
        array_push(segs, seg);
        if (i <= n)
        {
            if (string_char_at(path, i) != ".")
            {
                throw ("unexpected '" + string_char_at(path, i) + "' in path: " + path);
            }
            i++;
            if (i > n)
            {
                throw ("trailing dot in path: " + path);
            }
        }
    }
    if (array_length(segs) == 0)
    {
        throw "empty path";
    }
    return segs;
}

function vwa_string_is_digits(s)
{
    if (string_length(s) == 0)
    {
        return false;
    }
    for (var i = 1; i <= string_length(s); i++)
    {
        var o = ord(string_char_at(s, i));
        if (o < 48 || o > 57)
        {
            return false;
        }
    }
    return true;
}

// First path segment -> a live instance: numeric id, "id<digits>", or an
// object name (first live instance, children included).
function vwa_base_instance(seg)
{
    var name = seg.name;
    var digits = "";
    if (vwa_string_is_digits(name))
    {
        digits = name;
    }
    else if (string_copy(name, 1, 2) == "id" && vwa_string_is_digits(string_delete(name, 1, 2)))
    {
        digits = string_delete(name, 1, 2);
    }
    if (digits != "")
    {
        var idNum = real(digits);
        if (!instance_exists(idNum))
        {
            throw ("no instance with id " + digits);
        }
        return idNum;
    }
    if (asset_get_type(name) != asset_object)
    {
        throw ("not a global, instance id, or object name: " + name);
    }
    var obj = asset_get_index(name);
    if (instance_number(obj) == 0)
    {
        throw ("no live instances of " + name);
    }
    return instance_find(obj, 0);
}

function vwa_member_read(cur, name)
{
    if (name == "")
    {
        throw "empty member name";
    }
    if (is_struct(cur))
    {
        if (!variable_struct_exists(cur, name))
        {
            throw ("no such struct member: " + name);
        }
        return variable_struct_get(cur, name);
    }
    if (vwa_is_instance(cur))
    {
        // variable_instance_exists is false for built-ins (x, sprite_index...)
        // which variable_instance_get still reads, so probe rather than gate.
        var v = variable_instance_get(cur, name);
        if (is_undefined(v) && !variable_instance_exists(cur, name))
        {
            throw ("no such variable '" + name + "' on "
                + object_get_name(cur.object_index));
        }
        return v;
    }
    if (is_array(cur))
    {
        throw ("use [n] to index into an array, at ." + name);
    }
    throw ("cannot read ." + name + " from a " + typeof(cur));
}

// Apply seg indices to cur. idxCap >= 0 applies only the first idxCap of
// them (set resolves up to, not through, the final index).
function vwa_apply_indices(cur, idx, idxCap)
{
    var count = (idxCap >= 0) ? idxCap : array_length(idx);
    for (var i = 0; i < count; i++)
    {
        if (!is_array(cur))
        {
            throw ("[" + string(idx[i]) + "] applied to a " + typeof(cur) + ", not an array");
        }
        var ix = idx[i];
        if (ix < 0 || ix >= array_length(cur))
        {
            throw ("index " + string(ix) + " out of range (array length "
                + string(array_length(cur)) + ")");
        }
        cur = cur[ix];
    }
    return cur;
}

// Resolve segs[0..segCount-1]; lastIdxCap caps how many indices of the FINAL
// resolved segment apply (-1 = all). The global scope is never a value:
// "global" is special-cased here at position 0 only.
function vwa_resolve_segs(segs, segCount, lastIdxCap)
{
    if (segCount < 1)
    {
        throw "empty path";
    }
    var cur;
    var k;
    var s0 = segs[0];
    if (s0.name == "global")
    {
        if (array_length(s0.idx) > 0)
        {
            throw "global cannot be indexed";
        }
        if (segCount < 2)
        {
            throw "name a specific global, e.g. global.menuToggle";
        }
        var s1 = segs[1];
        if (!variable_global_exists(s1.name))
        {
            throw ("no such global: " + s1.name);
        }
        cur = variable_global_get(s1.name);
        cur = vwa_apply_indices(cur, s1.idx, (segCount == 2) ? lastIdxCap : -1);
        k = 2;
    }
    else
    {
        cur = vwa_base_instance(s0);
        cur = vwa_apply_indices(cur, s0.idx, (segCount == 1) ? lastIdxCap : -1);
        k = 1;
    }
    while (k < segCount)
    {
        var sg = segs[k];
        cur = vwa_member_read(cur, sg.name);
        cur = vwa_apply_indices(cur, sg.idx, (k == segCount - 1) ? lastIdxCap : -1);
        k++;
    }
    return cur;
}

function vwa_resolve(path)
{
    var segs = vwa_path_segments(path);
    return vwa_resolve_segs(segs, array_length(segs), -1);
}

// ---- literal parsing (set values, call arguments) ----

// quoted: the token came from double quotes, so it is always a string.
function vwa_parse_literal(s, quoted)
{
    if (quoted)
    {
        return s;
    }
    if (s == "true")
    {
        return true;
    }
    if (s == "false")
    {
        return false;
    }
    if (s == "undefined")
    {
        return undefined;
    }
    try
    {
        return real(s);
    }
    catch (e)
    {
        return s; // bare word: a string
    }
}

// Whitespace-split honoring double quotes; returns [{t, q}].
function vwa_dev_tokens(s)
{
    var toks = [];
    var cur = "";
    var inQ = false;
    var hadQ = false;
    var n = string_length(s);
    for (var i = 1; i <= n; i++)
    {
        var c = string_char_at(s, i);
        if (inQ)
        {
            if (c == "\"")
            {
                inQ = false;
            }
            else
            {
                cur += c;
            }
        }
        else if (c == "\"")
        {
            inQ = true;
            hadQ = true;
        }
        else if (c == " " || c == "\t" || c == "\r" || c == "\n")
        {
            if (cur != "" || hadQ)
            {
                array_push(toks, { t: cur, q: hadQ });
            }
            cur = "";
            hadQ = false;
        }
        else
        {
            cur += c;
        }
    }
    if (inQ)
    {
        throw "unclosed quote";
    }
    if (cur != "" || hadQ)
    {
        array_push(toks, { t: cur, q: hadQ });
    }
    return toks;
}

// ---- commands ----

function vwa_dev_set(path, literalText)
{
    var v = vwa_parse_literal(literalText, false);
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

function vwa_dev_call(nameTok, argToks)
{
    var args = [];
    for (var i = 0; i < array_length(argToks); i++)
    {
        array_push(args, vwa_parse_literal(argToks[i].t, argToks[i].q));
    }
    var fn;
    if (string_pos(".", nameTok) > 0)
    {
        fn = vwa_resolve(nameTok);
        if (!is_method(fn))
        {
            throw (nameTok + " is not a method (got " + typeof(fn) + ")");
        }
    }
    else
    {
        if (asset_get_type(nameTok) != asset_script)
        {
            throw ("no such script function: " + nameTok);
        }
        fn = asset_get_index(nameTok);
    }
    var result = script_execute_ext(fn, args);
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

// GET /state: suppression, screen-stack stub, live categories, every
// registered action, and per-chord shadowing resolution. labelKey is
// reported raw (not localized) so dev test actions need no CSV rows.
function vwa_dev_state_json()
{
    var live = vwa_live_categories();
    var out = "{\"suppressGameKeys\":" + (global.vwaSuppressGameKeys ? "true" : "false")
        + ",\"textFieldInput\":" + (global.textFieldInputEnabled ? "true" : "false")
        + ",\"watchdogTripped\":" + (global.vwaInputWatchdogTripped ? "true" : "false")
        + ",\"ticks\":" + vwa_json_num(global.vwaInputTicks)
        + ",\"keyDelayMs\":" + vwa_json_num(global.vwaKeyDelayMs)
        + ",\"keyRateMs\":" + vwa_json_num(global.vwaKeyRateMs);

    out += ",\"stack\":[";
    for (var i = 0; i < array_length(global.vwaScreenStack); i++)
    {
        var scr = global.vwaScreenStack[i];
        if (i > 0)
        {
            out += ",";
        }
        out += "{\"name\":" + vwa_json_str(scr.name) + ",\"categories\":[";
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
            + ",\"binding\":{\"vk\":" + vwa_json_num(a.binding.vk)
            + ",\"shift\":" + (a.binding.shift ? "true" : "false")
            + ",\"ctrl\":" + (a.binding.ctrl ? "true" : "false")
            + ",\"alt\":" + (a.binding.alt ? "true" : "false") + "}"
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
        var cid = vwa_chord_id(a.binding);
        var g = variable_struct_get(groups, cid);
        if (g == undefined)
        {
            g = [];
            variable_struct_set(groups, cid, g);
            array_push(chordIds, cid);
        }
        array_push(g, { key: a.actionKey, prio: prio });
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

// Stub screen-stack control until the real screen layer (session 4).
// spec: comma-separated category list for one test screen, or "none".
function vwa_dev_test_screen(spec)
{
    if (spec == "none" || spec == "")
    {
        global.vwaScreenStack = [];
        return "stack cleared";
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
    global.vwaScreenStack = [{ name: "vwa-test-screen", categories: cats }];
    return "test screen pushed with " + string(array_length(cats)) + " categories";
}

// An intentionally-conflicting chord pair (F10 in global and ui) plus a
// repeating action (F9, dev) for typematic checks. Spoken text here is dev
// text, exempt from localization.
function vwa_dev_register_test_actions()
{
    global.vwaDevRepeatCount = 0;
    vwa_action_register("dev-shout-global", "dev", "global",
        vwa_bind(vk_f10, false, false, false), false, function()
        {
            vwa_speak(["test shout global"], true);
        });
    vwa_action_register("dev-shout-ui", "dev", "ui",
        vwa_bind(vk_f10, false, false, false), false, function()
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

// Arm a one-shot fault inside vwa_input_tick to prove the watchdog clears
// the suppression flag (the keys-come-back guarantee).
function vwa_dev_arm_input_fault()
{
    global.vwaInputFault = true;
    return "fault armed";
}

// Prove the suppression lever against the game's real input_check, all in
// one frame with every touched state restored. keyboard_key_press cannot
// provide the key-down signal (bit us: simulated keys never reach
// keyboard_check in this runner, even same-frame), so the bind is swapped
// to vk_nokey (0), which keyboard_check reports as held whenever NO key is
// down - always true on an unattended machine.
function vwa_dev_suppression_probe(bindName)
{
    var priorFlag = global.vwaSuppressGameKeys;
    var priorKey = variable_struct_get(global.keybinds, bindName);
    if (priorKey == undefined)
    {
        throw ("no such game keybind: " + bindName);
    }
    variable_struct_set(global.keybinds, bindName, 0);
    global.vwaSuppressGameKeys = true;
    var whileSuppressed = input_check(bindName) ? true : false;
    global.vwaSuppressGameKeys = false;
    var whileLive = input_check(bindName) ? true : false;
    var clearedIo = false;
    if (!whileLive && keyboard_key == 0)
    {
        // Freshly-booted runner io can report "a key is held" with no key
        // named (vk_nokey false, vk_anykey false, keyboard_key 0) for
        // minutes; io_clear resets the bookkeeping. Only reached in that
        // inconsistent state, so no real user input can be discarded.
        io_clear();
        clearedIo = true;
        whileLive = input_check(bindName) ? true : false;
    }
    variable_struct_set(global.keybinds, bindName, priorKey);
    global.vwaSuppressGameKeys = priorFlag;
    // kbKey: what the runner thinks is held. The keepalive keeps key state
    // updating while backgrounded, so a human typing anywhere on the machine
    // makes vk_nokey read false; callers should retry on live=false and use
    // kbKey to tell "user was typing" from a real break.
    // Returned via the call command, whose dumper serializes the struct.
    return { suppressed: whileSuppressed, live: whileLive,
             kbKey: keyboard_key, ioCleared: clearedIo };
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

        case "call":
        {
            if (rest == "")
            {
                throw "call needs a script or method path";
            }
            var cToks = vwa_dev_tokens(rest);
            var argToks = [];
            for (var i = 1; i < array_length(cToks); i++)
            {
                array_push(argToks, cToks[i]);
            }
            return vwa_dev_call(cToks[0].t, argToks);
        }

        case "gui.raw":
            return vwa_dev_gui_raw(rest);

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
                + "instances <objectName> | call <scriptOrPath> [args...] | "
                + "gui.raw [objectName] | screenshot | state | "
                + "input <actionKey> | help";

        default:
            return "unknown command: " + word + " (try help)";
    }
}
