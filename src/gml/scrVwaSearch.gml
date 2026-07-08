// scrVwaSearch - Void War Access type-ahead search: the buffer state and the
// tiered matcher that filters a flat item list as the player types.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// PURE MODULE: no instance, global, or game references, no speech - callers
// pass the item names and callbacks in, so every rule here is testable
// through the dev driver with literal strings.
//
// Matching model:
// - TIERED: 0 start-of-string whole word, 1 start-of-string prefix, 2
//   mid-string whole word, 3 mid-string word prefix, 4 substring anywhere,
//   5 space-delimited word-prefix abbreviation ("ga pi" matches "gas pipe").
//   Word boundaries are space and comma.
// - Within a tier, items keep their LIST ORDER (the screen's element order:
//   "l" must land on Load Game by menu position, not on a shorter name).
// - A comma splits an item's text into its NAME (before the first comma)
//   and appended metadata; name matches rank ahead of metadata matches
//   across ALL tiers. The abbreviation tier never crosses a comma.
// - Diacritics fold away on both sides ("Séance" matches "seance"); the
//   ligatures oe/ae expand. Case is ignored.
// - Typing the same letter repeatedly collapses the buffer back to one
//   letter and cycles ALL of that letter's matches in result order,
//   wrapping - so a single letter reaches every match, strongest tier
//   first.
// - Trailing spaces are trimmed for matching but stay in the buffer (they
//   are how an abbreviation's next token starts).
// - An empty or matchless buffer reports through the no-match callback with
//   the raw buffer text; the search stays active so typing can continue.

// ---- buffer state ----
// {buffer, active, results (item indices, best first), cursor}

function vwa_search_new()
{
    return { buffer: "", active: false, results: [], cursor: 0 };
}

// Reset in place (callers hold the struct).
function vwa_search_reset(st)
{
    st.buffer = "";
    st.active = false;
    st.results = [];
    st.cursor = 0;
}

function vwa_search_add_char(st, ch)
{
    st.buffer += ch;
}

// ---- the search ----
// itemCount items, nameFn(i) -> item text, announceFn(i) called with the
// ORIGINAL item index of the best (or newly stepped-to) result, noMatchFn
// (bufferText) when nothing matches.

function vwa_search_run(st, itemCount, nameFn, announceFn, noMatchFn)
{
    // Repeat single-letter: typing the same letter again collapses the
    // buffer to one letter and steps to the next of its matches, wrapping.
    if (st.active && array_length(st.results) > 0
        && string_length(st.buffer) > 1 && vwa_search_all_same_char(st.buffer))
    {
        st.buffer = string_copy(st.buffer, 1, 1);
        vwa_search_navigate(st, 1, announceFn);
        return;
    }

    var trimmed = vwa_search_trim_end(st.buffer);
    if (st.buffer == "" || itemCount == 0 || trimmed == "")
    {
        st.results = [];
        st.cursor = 0;
        st.active = true;
        noMatchFn(st.buffer);
        return;
    }

    var foldedPrefix = vwa_search_fold(trimmed);
    var matched = [];
    for (var i = 0; i < itemCount; i++)
    {
        var nm = nameFn(i);
        if (nm == undefined || nm == "")
        {
            continue;
        }
        var folded = vwa_search_fold(string(nm));
        var m = vwa_search_match_tier_folded(folded, foldedPrefix);
        if (m.tier < 0)
        {
            continue;
        }
        // Name-vs-metadata split: a match before the first comma outranks a
        // match in the appended metadata, whatever its tier.
        var comma = string_pos(",", folded);
        var nameLen = (comma > 0) ? comma - 1 : string_length(folded);
        array_push(matched, { idx: i, tier: m.tier,
                              inMeta: (m.matchPos > nameLen) ? 1 : 0 });
    }

    if (array_length(matched) == 0)
    {
        st.results = [];
        st.cursor = 0;
        st.active = true;
        noMatchFn(st.buffer);
        return;
    }

    // Order: name matches across all tiers before metadata matches; within
    // (segment, tier), item order. idx as the final key makes the sort's
    // stability irrelevant.
    array_sort(matched, function(a, b)
    {
        if (a.inMeta != b.inMeta)
        {
            return a.inMeta - b.inMeta;
        }
        if (a.tier != b.tier)
        {
            return a.tier - b.tier;
        }
        return a.idx - b.idx;
    });
    var res = [];
    for (var i = 0; i < array_length(matched); i++)
    {
        array_push(res, matched[i].idx);
    }
    st.results = res;
    st.cursor = 0;
    st.active = true;
    announceFn(st.results[0]);
}

// Step within the results (wrapping): +1 next, -1 previous.
function vwa_search_navigate(st, dirNum, announceFn)
{
    var cnt = array_length(st.results);
    if (cnt == 0)
    {
        return;
    }
    st.cursor = ((st.cursor + dirNum) % cnt + cnt) % cnt;
    announceFn(st.results[st.cursor]);
}

// Jump to the first (last = false) or last (last = true) result.
function vwa_search_jump(st, last, announceFn)
{
    var cnt = array_length(st.results);
    if (cnt == 0)
    {
        return;
    }
    st.cursor = last ? cnt - 1 : 0;
    announceFn(st.results[st.cursor]);
}

// ---- the matcher ----

// Match tier of prefix against name (any case, diacritics welcome), with
// the 1-indexed match position IN FOLDED COORDINATES. tier -1 = no match.
function vwa_search_match_tier(nm, prefix)
{
    return vwa_search_match_tier_folded(vwa_search_fold(nm),
        vwa_search_fold(prefix));
}

// Both arguments already folded (vwa_search_fold). Returns {tier, matchPos}.
function vwa_search_match_tier_folded(n, p)
{
    var nlen = string_length(n);
    var plen = string_length(p);
    if (plen == 0 || plen > nlen)
    {
        return { tier: -1, matchPos: 0 };
    }

    if (string_copy(n, 1, plen) == p)
    {
        var whole = (nlen == plen)
            || vwa_search_is_boundary(string_char_at(n, plen + 1));
        return { tier: whole ? 0 : 1, matchPos: 1 };
    }

    for (var i = 2; i <= nlen; i++)
    {
        var prev = string_char_at(n, i - 1);
        if (prev != " " && prev != ",")
        {
            continue;
        }
        if (string_char_at(n, i) == " ")
        {
            continue;
        }
        if (nlen - i + 1 < plen)
        {
            break;
        }
        if (string_copy(n, i, plen) == p)
        {
            var after = i + plen;
            var whole = (after > nlen)
                || vwa_search_is_boundary(string_char_at(n, after));
            return { tier: whole ? 2 : 3, matchPos: i };
        }
    }

    var idx = string_pos(p, n);
    if (idx > 0)
    {
        return { tier: 4, matchPos: idx };
    }

    if (string_pos(" ", p) > 0)
    {
        var ap = vwa_search_match_tokens(n, p);
        if (ap > 0)
        {
            return { tier: 5, matchPos: ap };
        }
    }

    return { tier: -1, matchPos: 0 };
}

// Abbreviation: every space-delimited token of p must prefix a distinct
// word of n, consumed left to right, all within one comma-delimited
// segment. Returns the first matched word's position, or 0.
function vwa_search_match_tokens(n, p)
{
    var tokens = [];
    var cur = "";
    var plen = string_length(p);
    for (var i = 1; i <= plen; i++)
    {
        var c = string_char_at(p, i);
        if (c == " ")
        {
            if (cur != "")
            {
                array_push(tokens, cur);
                cur = "";
            }
        }
        else
        {
            cur += c;
        }
    }
    if (cur != "")
    {
        array_push(tokens, cur);
    }
    var tokenCount = array_length(tokens);
    if (tokenCount == 0)
    {
        return 0;
    }

    var tokenIdx = 0;
    var firstPos = 0;
    var nlen = string_length(n);
    var i = 1;
    while (i <= nlen)
    {
        var c = string_char_at(n, i);
        if (c == ",")
        {
            // A comma restarts the abbreviation: it never spans segments.
            tokenIdx = 0;
            firstPos = 0;
            i++;
            continue;
        }
        if (c == " ")
        {
            i++;
            continue;
        }

        // At a word start: try the pending token as its prefix.
        if (tokenIdx < tokenCount)
        {
            var tok = tokens[tokenIdx];
            var tlen = string_length(tok);
            if (i + tlen - 1 <= nlen && string_copy(n, i, tlen) == tok)
            {
                if (tokenIdx == 0)
                {
                    firstPos = i;
                }
                tokenIdx++;
                if (tokenIdx == tokenCount)
                {
                    return firstPos;
                }
                i += tlen;
            }
        }
        // Skip the rest of the word either way.
        while (i <= nlen)
        {
            var cc = string_char_at(n, i);
            if (cc == " " || cc == ",")
            {
                break;
            }
            i++;
        }
    }

    return 0;
}

function vwa_search_is_boundary(ch)
{
    return ch == " " || ch == ",";
}

// ---- text helpers ----

// Lowercase and fold diacritics to base ASCII letters; the oe/ae ligatures
// expand to two letters. Covers the Latin-1 accent block plus Œ/œ and Ÿ,
// which spans all four shipped languages; letters with no plain-letter
// decomposition (ß, ø, ð, þ) pass through unchanged.
function vwa_search_fold(s)
{
    var out = "";
    var n = string_length(s);
    for (var i = 1; i <= n; i++)
    {
        out += vwa_search_fold_char(string_ord_at(s, i));
    }
    return out;
}

function vwa_search_fold_char(o)
{
    if (o >= 65 && o <= 90)
    {
        return chr(o + 32); // ASCII upper -> lower
    }
    if (o < $C0)
    {
        return chr(o);
    }
    if (o == $C6 || o == $E6)
    {
        return "ae"; // Æ æ
    }
    if (o == $152 || o == $153)
    {
        return "oe"; // Œ œ
    }
    if ((o >= $C0 && o <= $C5) || (o >= $E0 && o <= $E5))
    {
        return "a";
    }
    if (o == $C7 || o == $E7)
    {
        return "c";
    }
    if ((o >= $C8 && o <= $CB) || (o >= $E8 && o <= $EB))
    {
        return "e";
    }
    if ((o >= $CC && o <= $CF) || (o >= $EC && o <= $EF))
    {
        return "i";
    }
    if (o == $D1 || o == $F1)
    {
        return "n";
    }
    if ((o >= $D2 && o <= $D6) || (o >= $F2 && o <= $F6))
    {
        return "o";
    }
    if ((o >= $D9 && o <= $DC) || (o >= $F9 && o <= $FC))
    {
        return "u";
    }
    if (o == $DD || o == $FD || o == $FF || o == $178)
    {
        return "y";
    }
    return chr(o);
}

// The characters that type into a search: letters, ASCII or accented (the
// fold above covers the same range). Space is the caller's call - it only
// extends a non-empty buffer.
function vwa_search_char_is_letter(o)
{
    if (o >= 65 && o <= 90)
    {
        return true;
    }
    if (o >= 97 && o <= 122)
    {
        return true;
    }
    if (o >= $C0 && o <= $17F && o != $D7 && o != $F7)
    {
        return true;
    }
    return false;
}

function vwa_search_trim_end(s)
{
    var n = string_length(s);
    while (n > 0 && string_char_at(s, n) == " ")
    {
        n--;
    }
    return string_copy(s, 1, n);
}

function vwa_search_all_same_char(s)
{
    var first = string_char_at(s, 1);
    for (var i = 2; i <= string_length(s); i++)
    {
        if (string_char_at(s, i) != first)
        {
            return false;
        }
    }
    return true;
}
