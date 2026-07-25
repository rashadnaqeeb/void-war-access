// scrVwaDevParse - Void War Access dev-driver parsing and emission
// substrate, DEV BUILDS ONLY (split from scrVwaDev; the command
// implementations and dispatch stay there, and its header holds the
// interpreter's vocabulary and path syntax). Three sections, all
// exercised only through scrVwaDev:
//
// - JSON emission: vwa_json_str / vwa_json_num / vwa_dump_json /
//   vwa_dump_instance. Hand-rolled instead of json_stringify because the
//   dumper must summarize methods, live instances, and over-deep values,
//   and string(<real>) truncates to two decimals. global.vwaDumpBudget
//   caps total dumped nodes so a huge graph cannot wedge the frame.
//
// - Path parsing and resolution: vwa_path_segments through vwa_resolve.
//   Paths are global.name, objectName.var (first live instance), or a
//   numeric instance id; segments join with '.' and arrays index with
//   [n]. Resolution walks live game state through GML reflection; every
//   validation failure throws a plain string for the pump's catch.
//
// - Literal and token parsing: vwa_parse_literal (scalar coercion),
//   vwa_lit_scan (JSON-ish compound literals: [1, "two"], {a: 1}),
//   vwa_dev_tokens (the command line's quote-aware tokenizer).

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
// Scalars: numbers, true/false/undefined, quoted strings, bare words as
// strings. Compound literals (vwa_lit_scan) add JSON-ish arrays and structs:
//   [1, "two", {a: 3}]      {name: "x", tags: [1, 2]}
// Struct keys are bare identifiers or quoted strings; quoted strings have no
// escape sequences (a " always closes, matching the tokenizer).

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

function vwa_lit_skip_ws(s, i)
{
    var n = string_length(s);
    while (i <= n)
    {
        var c = string_char_at(s, i);
        if (c != " " && c != "\t" && c != "\r" && c != "\n")
        {
            break;
        }
        i++;
    }
    return i;
}

// Scan ONE literal starting at index i (1-based; caller skips leading
// whitespace). Returns { v, next }. Bare words end at whitespace or at a
// compound delimiter (, ] }) so they compose inside arrays and structs; a
// bare word that needs those characters must be quoted.
function vwa_lit_scan(s, i)
{
    var n = string_length(s);
    if (i > n)
    {
        throw "expected a value, got end of input";
    }
    var c = string_char_at(s, i);
    if (c == "\"")
    {
        var qs = "";
        i++;
        while (i <= n && string_char_at(s, i) != "\"")
        {
            qs += string_char_at(s, i);
            i++;
        }
        if (i > n)
        {
            throw "unclosed quote in literal";
        }
        return { v: qs, next: i + 1 };
    }
    if (c == "[")
    {
        var arr = [];
        i = vwa_lit_skip_ws(s, i + 1);
        if (i <= n && string_char_at(s, i) == "]")
        {
            return { v: arr, next: i + 1 };
        }
        for (;;)
        {
            var el = vwa_lit_scan(s, i);
            array_push(arr, el.v);
            i = vwa_lit_skip_ws(s, el.next);
            if (i > n)
            {
                throw "unclosed [ in literal";
            }
            var ad = string_char_at(s, i);
            if (ad == "]")
            {
                return { v: arr, next: i + 1 };
            }
            if (ad != ",")
            {
                throw ("expected , or ] in array literal, got '" + ad + "'");
            }
            i = vwa_lit_skip_ws(s, i + 1);
        }
    }
    if (c == "{")
    {
        var st = {};
        i = vwa_lit_skip_ws(s, i + 1);
        if (i <= n && string_char_at(s, i) == "}")
        {
            return { v: st, next: i + 1 };
        }
        for (;;)
        {
            if (i > n)
            {
                throw "unclosed { in literal";
            }
            var skey = "";
            if (string_char_at(s, i) == "\"")
            {
                var kr = vwa_lit_scan(s, i);
                skey = kr.v;
                i = kr.next;
            }
            else
            {
                while (i <= n)
                {
                    var kc = string_char_at(s, i);
                    if (kc == ":" || kc == "," || kc == "}" || kc == " "
                        || kc == "\t" || kc == "\r" || kc == "\n")
                    {
                        break;
                    }
                    skey += kc;
                    i++;
                }
            }
            if (skey == "")
            {
                throw "empty key in struct literal";
            }
            i = vwa_lit_skip_ws(s, i);
            if (i > n || string_char_at(s, i) != ":")
            {
                throw ("expected : after struct key '" + skey + "'");
            }
            i = vwa_lit_skip_ws(s, i + 1);
            var vr = vwa_lit_scan(s, i);
            variable_struct_set(st, skey, vr.v);
            i = vwa_lit_skip_ws(s, vr.next);
            if (i > n)
            {
                throw "unclosed { in literal";
            }
            var sd = string_char_at(s, i);
            if (sd == "}")
            {
                return { v: st, next: i + 1 };
            }
            if (sd != ",")
            {
                throw ("expected , or } in struct literal, got '" + sd + "'");
            }
            i = vwa_lit_skip_ws(s, i + 1);
        }
    }
    var word = "";
    while (i <= n)
    {
        var bc = string_char_at(s, i);
        if (bc == " " || bc == "\t" || bc == "\r" || bc == "\n"
            || bc == "," || bc == "]" || bc == "}")
        {
            break;
        }
        word += bc;
        i++;
    }
    if (word == "")
    {
        throw ("unexpected '" + c + "' in literal");
    }
    return { v: vwa_parse_literal(word, false), next: i };
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
