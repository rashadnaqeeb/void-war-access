// scrVwaText - Void War Access text edit layer: the edit-mode tracker for
// the game's text-field input, the review cursor, and the keyboard exit.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The game's text-field model (verified 1.4.0c, scrTextField + oTextField):
// - global.textFieldInputEnabled is THE edit-mode flag. The game's fields
//   set it from their own mouse-click branches and clear it on click-away
//   (all fields), Enter/Escape (oShipMenu_shipName only), or menu close.
// - While the flag is up, a singleton oTextField exists (the owning field's
//   Step re-creates it every frame through text_field_input); it appends
//   keyboard_string to its text, and backspace deletes the LAST character.
// - The blinking caret is drawn at x + string_width(text): always at the
//   END of the string. There is no caret position, no selection, and no
//   clipboard anywhere in the game's code.
// Consequences this module is built on: typed input reaches the game with
// no help from us (oTextField reads keyboard_string raw, upstream of the
// suppression patch); every edit lands at the end of the string; and the
// arrow keys are free to drive a mod-side REVIEW cursor - a reading
// position over the live text that moves no insertion point, because the
// game has none to move.
//
// Keys while editing (textSafe "global" actions - always live; each handler
// no-ops unless edit mode is on, and while it is on the dispatch filter
// drops every non-textSafe action, so these win the chords they share with
// the ui navigator):
//   left/right       review one character (speaks it; clamps at the ends)
//   Ctrl+left/right  review by word (a word is a run of non-space chars)
//   Home/End         review the first / last character
//   up/down          read the whole text
//   Enter/Escape     stop editing (the default exit clears the game's flag,
//                    mirroring the fields' own click-away branch)
// Review and exit keys are CONSUMED (vwa_input_consume_key) so the game's
// raw ungated handlers never also act mid-edit: oUICommanderList's Escape
// leaves the whole commander screen, and oShipMenu_shipSelector's arrows
// cycle hulls (a room_goto!) even while a field is being edited. A consumed
// key that stays held re-asserts through OS auto-repeat, so review-key
// repeat rides the OS repeat rate instead of the mod's typematic clock.
//
// Speech (all through vwa_speak, all interrupting: every line here is
// direct user-caused feedback):
// - entering: "Editing" + the field's current text ("blank" when empty)
// - typing: SILENT - the player's screen reader echoes typed characters
//   through its own keyboard hook; echoing here would double-speak
// - backspace: the deleted character(s), most recent first, from the
//   per-frame text diff
// - a change that is neither an append nor an end-deletion (the game
//   replaced the string): "Text changed" + the new text
// - exiting, by ANY path (our keys, a field's own Enter/Escape branch, a
//   mouse click away): "Edit closed" + the final text. The falling edge of
//   the flag announces, so the game's own exits are never missed.
// Known gap: a lone punctuation character is passed through as-is; whether
// the screen reader voices it depends on its symbol level.
//
// vwa_text_begin(adapter) is the entry point for a textfield control's
// onActivate (and the dev driver). adapter = { onEnter, onExit }
// zero-argument methods ("exit"/"end" are GML keywords, unusable as member
// names) mirroring the field's own click-to-edit and exit branches;
// undefined means the plain global-flag default, which matches
// oCommanderNameBox (whose only edit state IS the flag). begin() consumes
// Enter so the activating press cannot bounce straight back out through a
// field's own keyboard_check_pressed(vk_enter) exit branch - and therefore
// holding Enter until OS auto-repeat kicks in exits again; a tap is the
// expected use.
//
// lastText is a diff baseline (like the screens layer's live-part cache),
// never spoken as current state - except on the falling edge, where it IS
// the final value (oTextField is already gone by the time we tick).
// Review keys re-read oTextField.text live on every press.

function vwa_text_init()
{
    global.vwaText = {
        active: false,      // edit mode as of the last tick (poll-and-diff)
        pending: false,     // flag is up but oTextField has not appeared yet
        pendingTicks: 0,
        lastText: "",       // diff baseline while active
        cursor: 0,          // review position: 1-based char index, 0 = unset
        adapter: undefined  // { enter, exit } while vwa_text_begin drove entry
    };
    vwa_register_text_actions();
    vwa_log("text: layer initialized");
}

function vwa_text_active()
{
    return global.vwaText.active;
}

// The live text of the game's input sink; undefined while it does not
// exist. Callers decide what absence means (pending entry vs torn down).
function vwa_text_current()
{
    if (!instance_exists(oTextField))
    {
        return undefined;
    }
    return string(oTextField.text);
}

// Once per frame from vwa_input_tick (between the type-ahead tick and the
// action dispatch, so the dispatch's textOnly filter sees the same flag
// state this tick observed). Announces mode edges and edit feedback.
function vwa_text_tick()
{
    var st = global.vwaText;
    var flag = global.textFieldInputEnabled;

    if (flag && !st.active)
    {
        // Rising edge. The owning field's Step creates oTextField later
        // this same frame, so the text is normally readable on the next
        // tick; announce when it appears.
        st.pending = true;
        var t = vwa_text_current();
        if (t == undefined)
        {
            st.pendingTicks += 1;
            if (st.pendingTicks == 120)
            {
                // Not fatal (the field may still materialize), but two
                // seconds of edit-mode flag with no oTextField means
                // something unexpected owns the mode. Log once per entry.
                vwa_log("text: textFieldInputEnabled held 120 ticks with no oTextField");
            }
            return;
        }
        st.active = true;
        st.pending = false;
        st.pendingTicks = 0;
        st.lastText = t;
        st.cursor = string_length(t);
        vwa_speak([vwa_t("vwa--text-editing"),
                   (t == "") ? vwa_t("vwa--text-blank") : t], true);
        return;
    }

    if (!flag)
    {
        if (st.active)
        {
            // Falling edge, by any path (our exit keys, a field's own
            // Enter/Escape branch, a mouse click away).
            vwa_speak([vwa_t("vwa--text-edit-closed"),
                       (st.lastText == "") ? vwa_t("vwa--text-blank") : st.lastText],
                true);
        }
        st.active = false;
        st.pending = false;
        st.pendingTicks = 0;
        st.adapter = undefined;
        st.lastText = "";
        st.cursor = 0;
        return;
    }

    if (!st.active)
    {
        return;
    }

    // Active: watch the live text for edits.
    var t = vwa_text_current();
    if (t == undefined || t == st.lastText)
    {
        return;
    }
    var oldT = st.lastText;
    st.lastText = t;
    // Every edit lands at the end of the string; review follows it there.
    st.cursor = string_length(t);
    var oldLen = string_length(oldT);
    var newLen = string_length(t);
    if (newLen < oldLen && string_copy(oldT, 1, newLen) == t)
    {
        // Backspace(s): speak the removed characters, most recent first.
        var removed = [];
        for (var i = oldLen; i > newLen; i--)
        {
            array_push(removed, vwa_text_char_speech(string_char_at(oldT, i)));
        }
        vwa_speak(removed, true);
        return;
    }
    if (newLen > oldLen && string_copy(t, 1, oldLen) == oldT)
    {
        // Typing: the screen reader's own key echo covers it.
        return;
    }
    vwa_speak([vwa_t("vwa--text-changed"),
               (t == "") ? vwa_t("vwa--text-blank") : t], true);
}

// Enter edit mode on behalf of a focused textfield control (or the dev
// driver). See the header for the adapter contract.
function vwa_text_begin(adapter)
{
    if (global.textFieldInputEnabled)
    {
        vwa_log("text: begin ignored - text-field input already active");
        return;
    }
    global.vwaText.adapter = adapter;
    var entered = false;
    if (adapter != undefined && variable_struct_exists(adapter, "onEnter")
        && adapter.onEnter != undefined)
    {
        var fnEnter = adapter.onEnter;
        fnEnter();
        entered = true;
    }
    if (!entered)
    {
        // The plain fields' click branch is exactly this assignment.
        global.textFieldInputEnabled = true;
    }
    vwa_input_consume_key(vk_enter);
    // The rising edge announces on the next tick.
}

// ---- review cursor ----

// A single character as speech text: a space gets a word; everything else
// is passed through for the screen reader to voice at its symbol level.
function vwa_text_char_speech(ch)
{
    if (ch == " ")
    {
        return vwa_t("vwa--char-space");
    }
    return ch;
}

// 1-based start index of the word at or before pos (clamps to the first).
function vwa_text_prev_word_start(t, pos)
{
    var i = pos - 1;
    while (i >= 1 && string_char_at(t, i) == " ")
    {
        i -= 1;
    }
    while (i >= 1 && string_char_at(t, i) != " ")
    {
        i -= 1;
    }
    return i + 1;
}

// 1-based start index of the word after pos, or -1 when there is none.
function vwa_text_next_word_start(t, pos)
{
    var ln = string_length(t);
    var i = pos;
    while (i <= ln && string_char_at(t, i) != " ")
    {
        i += 1;
    }
    while (i <= ln && string_char_at(t, i) == " ")
    {
        i += 1;
    }
    return (i > ln) ? -1 : i;
}

// The word containing pos, as speech ("space" when pos sits on a gap).
function vwa_text_word_at(t, pos)
{
    var ln = string_length(t);
    if (pos < 1 || pos > ln || string_char_at(t, pos) == " ")
    {
        return vwa_t("vwa--char-space");
    }
    var s = pos;
    while (s > 1 && string_char_at(t, s - 1) != " ")
    {
        s -= 1;
    }
    var e = pos;
    while (e < ln && string_char_at(t, e + 1) != " ")
    {
        e += 1;
    }
    return string_copy(t, s, e - s + 1);
}

// Shared preamble for the review handlers: only in edit mode; the key is
// consumed even when the move clamps (the game's raw handlers must never
// see a review key mid-edit); an empty field speaks "blank".
// Returns the live text, or undefined when the handler should stop.
function vwa_text_review_take(vk)
{
    var st = global.vwaText;
    if (!st.active)
    {
        return undefined;
    }
    vwa_input_consume_key(vk);
    var t = vwa_text_current();
    if (t == undefined)
    {
        t = "";
    }
    if (t == "")
    {
        vwa_speak([vwa_t("vwa--text-blank")], true);
        return undefined;
    }
    return t;
}

function vwa_text_review_char(sgn, vk)
{
    var t = vwa_text_review_take(vk);
    if (t == undefined)
    {
        return;
    }
    var st = global.vwaText;
    st.cursor = clamp(st.cursor + sgn, 1, string_length(t));
    vwa_speak([vwa_text_char_speech(string_char_at(t, st.cursor))], true);
}

function vwa_text_review_word(sgn, vk)
{
    var t = vwa_text_review_take(vk);
    if (t == undefined)
    {
        return;
    }
    var st = global.vwaText;
    var c;
    if (sgn < 0)
    {
        c = vwa_text_prev_word_start(t, st.cursor);
    }
    else
    {
        c = vwa_text_next_word_start(t, st.cursor);
        if (c < 0)
        {
            // Already in the last word: re-speak it from where we stand.
            c = st.cursor;
        }
    }
    st.cursor = c;
    vwa_speak([vwa_text_word_at(t, c)], true);
}

function vwa_text_review_ends(sgn, vk)
{
    var t = vwa_text_review_take(vk);
    if (t == undefined)
    {
        return;
    }
    var st = global.vwaText;
    st.cursor = (sgn < 0) ? 1 : string_length(t);
    vwa_speak([vwa_text_char_speech(string_char_at(t, st.cursor))], true);
}

// up and down both land here; consume both (clearing an un-pressed key is
// a no-op), matching vwa_text_exit's treatment of its two bindings.
function vwa_text_read_all()
{
    if (!global.vwaText.active)
    {
        return;
    }
    var t = vwa_text_review_take(vk_up);
    vwa_input_consume_key(vk_down);
    if (t == undefined)
    {
        return;
    }
    vwa_speak([t], true);
}

// Stop editing from the keyboard. The adapter's exit mirrors the field's
// own close branch; the default is the flag clear every field's click-away
// path performs. Both Enter and Escape land here (and both get consumed:
// clearing an un-pressed key is a no-op), so a field screen whose game
// object distinguishes commit from cancel supplies an adapter instead.
function vwa_text_exit()
{
    var st = global.vwaText;
    if (!st.active && !st.pending)
    {
        return;
    }
    vwa_input_consume_key(vk_enter);
    vwa_input_consume_key(vk_escape);
    var exited = false;
    if (st.adapter != undefined && variable_struct_exists(st.adapter, "onExit")
        && st.adapter.onExit != undefined)
    {
        var fnExit = st.adapter.onExit;
        fnExit();
        exited = true;
    }
    if (!exited)
    {
        global.textFieldInputEnabled = false;
    }
    // The falling edge announces on the next tick.
}

// ---- actions ----
// All "global" so they stay live with no mod screen focused (a game field
// can be entered with the mouse on a screen the mod has not covered yet),
// and all textSafe so the dispatch filter lets them through mid-edit. None
// of the chords can type a character into the field.

function vwa_register_text_actions()
{
    vwa_action_register("text-review-left", "vwa--action-text-left", "global",
        vwa_bind(vk_left, false, false, false), true, function()
        {
            vwa_text_review_char(-1, vk_left);
        });
    vwa_action_register("text-review-right", "vwa--action-text-right", "global",
        vwa_bind(vk_right, false, false, false), true, function()
        {
            vwa_text_review_char(1, vk_right);
        });
    vwa_action_register("text-review-word-left", "vwa--action-text-word-left", "global",
        vwa_bind(vk_left, false, true, false), true, function()
        {
            vwa_text_review_word(-1, vk_left);
        });
    vwa_action_register("text-review-word-right", "vwa--action-text-word-right", "global",
        vwa_bind(vk_right, false, true, false), true, function()
        {
            vwa_text_review_word(1, vk_right);
        });
    vwa_action_register("text-review-home", "vwa--action-text-home", "global",
        vwa_bind(vk_home, false, false, false), false, function()
        {
            vwa_text_review_ends(-1, vk_home);
        });
    vwa_action_register("text-review-end", "vwa--action-text-end", "global",
        vwa_bind(vk_end, false, false, false), false, function()
        {
            vwa_text_review_ends(1, vk_end);
        });
    vwa_action_register("text-read", "vwa--action-text-read", "global",
        [vwa_bind(vk_up, false, false, false), vwa_bind(vk_down, false, false, false)],
        false, function()
        {
            vwa_text_read_all();
        });
    vwa_action_register("text-exit", "vwa--action-text-exit", "global",
        [vwa_bind(vk_enter, false, false, false), vwa_bind(vk_escape, false, false, false)],
        false, function()
        {
            vwa_text_exit();
        });

    variable_struct_get(global.vwaActions, "text-review-left").textSafe = true;
    variable_struct_get(global.vwaActions, "text-review-right").textSafe = true;
    variable_struct_get(global.vwaActions, "text-review-word-left").textSafe = true;
    variable_struct_get(global.vwaActions, "text-review-word-right").textSafe = true;
    variable_struct_get(global.vwaActions, "text-review-home").textSafe = true;
    variable_struct_get(global.vwaActions, "text-review-end").textSafe = true;
    variable_struct_get(global.vwaActions, "text-read").textSafe = true;
    variable_struct_get(global.vwaActions, "text-exit").textSafe = true;
}
