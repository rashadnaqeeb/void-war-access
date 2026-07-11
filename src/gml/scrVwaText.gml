// scrVwaText - Void War Access text edit layer: the edit-mode tracker for
// the game's text-field input, edit feedback, and the keyboard exit.
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
// Consequences: typed input reaches the game with no help from us
// (oTextField reads keyboard_string raw, upstream of the suppression
// patch), and every edit lands at the end of the string.
//
// There is deliberately NO character/word review cursor here (Rashad's
// call, session 9, replacing the first design): a cursor the player can
// move but cannot edit at teaches a false model of the field. The player
// hears the text on entry, hears every deletion, and can re-hear the whole
// value on demand - and knows that typing and backspace only ever touch
// the end.
//
// Keys while editing (textSafe "global" actions - always live; each handler
// no-ops unless edit mode is on, and while it is on the dispatch filter
// drops every non-textSafe action, so these win the chords they share with
// the ui navigator):
//   up/down       read the whole text
//   Enter/Escape  stop editing (the default exit clears the game's flag,
//                 mirroring the fields' own click-away branch)
// Both are CONSUMED (vwa_input_consume_key) so the game's raw ungated
// handlers never also act mid-edit (oUICommanderList's Escape leaves the
// whole commander screen even while a field is being edited). Other keys
// pass through untouched: the game's own mid-edit quirks (the ship
// selector cycles hulls on raw arrows) are a per-screen concern for the
// field screen's adapter, not this layer. A consumed key that stays held
// re-asserts through OS auto-repeat.
//
// Speech (all through vwa_speak, all interrupting: every line here is
// direct user-caused feedback):
// - entering: "Editing" + the field's current text ("blank" when empty)
// - typing: SILENT - the player's screen reader echoes typed characters
//   through its own keyboard hook; echoing here would double-speak
// - backspace: the deleted character(s), most recent first, from the
//   per-frame text diff (a deleted space speaks as the word "space")
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
// the final value (oTextField is already gone by the time we tick). The
// read-all key re-reads oTextField.text live on every press.

function vwa_text_init()
{
    global.vwaText = {
        active: false,      // edit mode as of the last tick (poll-and-diff)
        pending: false,     // flag is up but oTextField has not appeared yet
        pendingTicks: 0,
        lastText: "",       // diff baseline while active
        adapter: undefined  // { onEnter, onExit } while vwa_text_begin drove entry
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

// A single character as speech text (deletion feedback): a space gets a
// word; everything else is passed through for the screen reader to voice
// at its symbol level.
function vwa_text_char_speech(ch)
{
    if (ch == " ")
    {
        return vwa_t("vwa--char-space");
    }
    return ch;
}

// Read the whole field back. up and down both land here; consume both
// (clearing an un-pressed key is a no-op) so the game's raw handlers never
// see them mid-edit.
function vwa_text_read_all()
{
    if (!global.vwaText.active)
    {
        return;
    }
    vwa_input_consume_key(vk_up);
    vwa_input_consume_key(vk_down);
    var t = vwa_text_current();
    if (t == undefined || t == "")
    {
        vwa_speak([vwa_t("vwa--text-blank")], true);
        return;
    }
    vwa_speak([t], true);
}

// Stop editing from the keyboard. The adapter's onExit mirrors the field's
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
// and all textSafe so the dispatch filter lets them through mid-edit.
// Neither chord can type a character into the field.

function vwa_register_text_actions()
{
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

    variable_struct_get(global.vwaActions, "text-read").textSafe = true;
    variable_struct_get(global.vwaActions, "text-exit").textSafe = true;
}
