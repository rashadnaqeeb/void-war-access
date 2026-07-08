// scrVwaAnnounce - Void War Access announcement composition: announcement
// parts, per-control-type part ordering (as data, not classes), and the
// path-diff compose that turns a focus change into spoken parts.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// PURE MODULE: composition returns ARRAYS OF STRINGS for vwa_speak (the
// chokepoint joins; composition discipline). It never speaks and reads no
// game globals; localized wording (role words, "n of m") arrives through
// the types registry and hooks struct the caller passes in
// (scrVwaScreens builds those from vwa_t at speak time, so a language
// change re-resolves everything).
//
// A part: {kind, live, text, fn}. kind is one of the well-known strings
// "label" / "role" / "value" / "selected" / "enabled" / "tooltip" /
// "position" (or "" for a one-off); parts with fn re-resolve at every speak
// (never cache game state); live parts are additionally watched while their
// node is focused and re-spoken alone when their text changes.
//
// A control type (types registry entry, keyed by node.typeKey):
// {order: [kinds in speak order], common: [parts every control of the type
// shares - the role word]}. A node part overrides a common part of the same
// kind. Parts whose kind is not in order append after, in declaration order.

function vwa_part(kind, text)
{
    return { kind: kind, live: false, text: text, fn: undefined };
}

function vwa_part_fn(kind, fn, live)
{
    return { kind: kind, live: live, text: undefined, fn: fn };
}

// Resolve a part to its current text ("" = silent). A throwing part fn is a
// mod bug: log it and speak the word "error" - audible and actionable, never
// silent.
function vwa_part_resolve(p)
{
    if (p.fn == undefined)
    {
        return (p.text == undefined) ? "" : string(p.text);
    }
    try
    {
        var fn = p.fn;
        var t = fn();
        return (t == undefined) ? "" : string(t);
    }
    catch (err)
    {
        vwa_log("ERROR: announcement part (kind " + string(p.kind)
            + ") threw: " + string(err));
        return "error";
    }
}

function vwa_ann_has_kind(parts, kind)
{
    if (kind == undefined || kind == "")
    {
        return false;
    }
    for (var i = 0; i < array_length(parts); i++)
    {
        if (parts[i].kind == kind)
        {
            return true;
        }
    }
    return false;
}

// A node's effective announcement parts: the control type's common parts
// merged with the node's own (a node part overrides a common part of the
// same kind), sorted by the type's kind order; unknown/absent kinds append
// after in declaration order. Untyped nodes speak their parts as declared.
function vwa_ann_effective(nd, types)
{
    var tp = undefined;
    if (nd.typeKey != undefined && types != undefined)
    {
        tp = variable_struct_get(types, nd.typeKey);
    }

    var merged = [];
    if (tp != undefined)
    {
        for (var i = 0; i < array_length(tp.common); i++)
        {
            if (!vwa_ann_has_kind(nd.parts, tp.common[i].kind))
            {
                array_push(merged, tp.common[i]);
            }
        }
    }
    for (var i = 0; i < array_length(nd.parts); i++)
    {
        array_push(merged, nd.parts[i]);
    }

    if (tp == undefined || array_length(merged) < 2)
    {
        return merged;
    }

    // Stable bucket sort: known kinds in the type's order, then the rest in
    // declaration order.
    var sorted = [];
    var taken = array_create(array_length(merged), false);
    for (var k = 0; k < array_length(tp.order); k++)
    {
        for (var i = 0; i < array_length(merged); i++)
        {
            if (!taken[i] && merged[i].kind == tp.order[k])
            {
                taken[i] = true;
                array_push(sorted, merged[i]);
            }
        }
    }
    for (var i = 0; i < array_length(merged); i++)
    {
        if (!taken[i])
        {
            array_push(sorted, merged[i]);
        }
    }
    return sorted;
}

// The node's effective parts marked live - the ones the navigator watches
// while the node is focused.
function vwa_ann_live_parts(nd, types)
{
    var eff = vwa_ann_effective(nd, types);
    var out = [];
    for (var i = 0; i < array_length(eff); i++)
    {
        if (eff[i].live)
        {
            array_push(out, eff[i]);
        }
    }
    return out;
}

// A node's own readout as resolved strings: effective parts (non-empty
// ones), plus the auto-stamped "n of m" when the node has siblings and the
// hooks provide the wording. hooks: {posText: fn(i, n) -> string,
// groupText: fn() -> string (the generic word for an unnamed row group)}.
function vwa_ann_leaf(nd, types, hooks)
{
    var out = [];
    // A synthesized row group with an empty label speaks the localized
    // generic group word instead, so an unnamed radio row still announces
    // itself before its landing member.
    if (vwa_opt(nd, "isGroup", false) && vwa_ann_first_label(nd) == ""
        && hooks != undefined && vwa_opt(hooks, "groupText", undefined) != undefined)
    {
        var gfn = hooks.groupText;
        var gt = gfn();
        if (gt != "")
        {
            array_push(out, gt);
        }
    }
    var eff = vwa_ann_effective(nd, types);
    for (var i = 0; i < array_length(eff); i++)
    {
        var t = vwa_part_resolve(eff[i]);
        if (t != "")
        {
            array_push(out, t);
        }
    }
    if (nd.posCount > 1 && hooks != undefined && hooks.posText != undefined
        && !vwa_ann_has_kind(nd.parts, "position"))
    {
        var posFn = hooks.posText;
        var pt = posFn(nd.posIndex, nd.posCount);
        if (pt != "")
        {
            array_push(out, pt);
        }
    }
    return out;
}

// The node's first part's resolved text (its label) - for level dedupe.
function vwa_ann_first_label(nd)
{
    if (array_length(nd.parts) == 0)
    {
        return "";
    }
    return vwa_part_resolve(nd.parts[0]);
}

// The node's path: ancestors outermost-first (the parent chain), then the
// node itself.
function vwa_ann_path(nd)
{
    var path = [];
    for (var n = nd; n != undefined; n = n.parent)
    {
        array_push(path, n);
    }
    // reverse in place
    var lo = 0;
    var hi = array_length(path) - 1;
    while (lo < hi)
    {
        var tmp = path[lo];
        path[lo] = path[hi];
        path[hi] = tmp;
        lo++;
        hi--;
    }
    return path;
}

// The spoken parts for landing on toNd having come from fromNd (undefined =
// from nothing: the full path reads). Newly entered levels read
// outermost-first, then the landing control; sibling moves share the whole
// prefix and read just the control; a level whose label duplicates the next
// level's label is skipped. transLabel is the crossed edge's spoken line
// ("" / undefined = none). Returns an array of strings ([] = say nothing).
function vwa_ann_compose(fromNd, toNd, types, hooks, transLabel)
{
    if (toNd == undefined)
    {
        return [];
    }
    var toPath = vwa_ann_path(toNd);
    var fromPath = (fromNd != undefined) ? vwa_ann_path(fromNd) : [];

    // Common prefix by structural identity: levels we were already inside
    // stay silent.
    var i = 0;
    while (i < array_length(fromPath) && i < array_length(toPath)
        && fromPath[i].nid.skey == toPath[i].nid.skey)
    {
        i++;
    }

    var out = [];
    if (transLabel != undefined && transLabel != "")
    {
        array_push(out, transLabel);
    }

    if (i >= array_length(toPath))
    {
        // Ascended (or the same node): just the now-innermost focus.
        var leaf = vwa_ann_leaf(toNd, types, hooks);
        for (var p = 0; p < array_length(leaf); p++)
        {
            array_push(out, leaf[p]);
        }
        return out;
    }

    for (var j = i; j < array_length(toPath); j++)
    {
        // Dedupe: a level whose label just repeats the next level down (a
        // "Sound settings" panel wrapping the "Sound settings" control).
        if (j + 1 < array_length(toPath))
        {
            var lbl = vwa_ann_first_label(toPath[j]);
            var nxt = vwa_ann_first_label(toPath[j + 1]);
            if (lbl != "" && lbl == nxt)
            {
                continue;
            }
        }
        var lvl = vwa_ann_leaf(toPath[j], types, hooks);
        for (var p = 0; p < array_length(lvl); p++)
        {
            array_push(out, lvl[p]);
        }
    }
    return out;
}
