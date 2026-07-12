// scrVwaWidgets - Void War Access shared menu machinery (session 6; paging
// session 12): the generic widget adapter, the shared oButton activation
// mirror, the dropdown child screen, and the auto-paging list pattern.
// Every screen-family script (scrVwaMenu*) builds on this file.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// The generic widget adapter (vwa_widgets_emit + vwa_widget_add) covers
// every menu made of the standard widget families: oButton_menus (spawned
// buttons), oSettings_checkbox (toggles), oMenuElement (sliders, dropdowns,
// plain labels), oButton (framed buttons like Configure Keybinds).
// Enumeration is live per build; sorting is visual reading order (y then x,
// same-row tolerance 4px - the game's own alignment test in
// oSettings_checkbox Draw_64). Activation always calls the game's own
// stored callbacks and mirrors the real click path's guards and sounds.
// Documented generic-builder exceptions:
// - Volume sliders have no pointer-free game handler; vwa_widget_slider_adjust
//   mirrors the mouse-wheel path's effect (increment + clamp + update call)
//   per slider object.
// - The language dropdown's per-entry beta hover tooltip is not surfaced;
//   the same warning text arrives in the confirmation dialogue the game
//   raises before committing a beta language, so nothing is missed.

function vwa_widgets_init()
{
    // An open dropdown list as a child screen: pushed when any oMenuElement
    // flips toggleDropdown (our combo activation mirrors the game's
    // dropdown-button click), popped when it clears. Entering lands on the
    // current selection (its "selected" part drives the graph's
    // selected-member landing). Escape closes just the list via onBack -
    // consumed, so the screen underneath survives the press.
    vwa_screen_register({
        key: "vwa-dropdown",
        layerNum: 45,
        categories: ["ui"],
        exclusive: true,
        isActive: function()
        {
            return !global.gameIsLoading && vwa_find_open_dropdown() != undefined;
        },
        name: function()
        {
            var dd = vwa_find_open_dropdown();
            return (dd != undefined) ? dd.leftLabel : "";
        },
        build: function(bd) { vwa_dropdown_build(bd); },
        onBack: function()
        {
            var dd = vwa_find_open_dropdown();
            if (dd == undefined)
            {
                return false;
            }
            dd.toggleDropdown = false;
            return true;
        }
    });
}

// Every oButton_menus spawned by ownerInst (menu_spawnButton stamps
// parentID) - the whole control surface of the pause, language, and
// confirmation menus.
function vwa_menu_buttons_collect(ownerInst)
{
    var list = [];
    var cnt = instance_number(oButton_menus);
    for (var i = 0; i < cnt; i++)
    {
        var bm = instance_find(oButton_menus, i);
        if (bm.parentID == ownerInst)
        {
            array_push(list, bm);
        }
    }
    return list;
}

// Sort widget instances into visual reading order (y then x), group
// same-y controls into horizontal rows (tolerance 4px, the game's own
// alignment test), add each through the vtable dispatch, and wire vertical
// wrap between the first and last rows.
function vwa_widgets_emit(bd, list)
{
    if (array_length(list) == 0)
    {
        return;
    }
    array_sort(list, function(ia, ib)
    {
        if (ia.y != ib.y)
        {
            return (ia.y < ib.y) ? -1 : 1;
        }
        if (ia.x != ib.x)
        {
            return (ia.x < ib.x) ? -1 : 1;
        }
        return 0;
    });

    var groups = [];
    var cur = [list[0]];
    var rowY = list[0].y;
    for (var i = 1; i < array_length(list); i++)
    {
        if (abs(list[i].y - rowY) < 4)
        {
            array_push(cur, list[i]);
        }
        else
        {
            array_push(groups, cur);
            cur = [list[i]];
            rowY = list[i].y;
        }
    }
    array_push(groups, cur);

    var rowKeys = [];
    for (var g = 0; g < array_length(groups); g++)
    {
        var grp = groups[g];
        var multi = (array_length(grp) > 1);
        if (multi)
        {
            // Unnamed group: the game draws no header for its same-y widget
            // rows (the window-mode trio); the announcer speaks the generic
            // localized group word (hooks.groupText) on entry instead.
            vwa_gb_start_row(bd, undefined, "");
        }
        var keys = [];
        for (var i = 0; i < array_length(grp); i++)
        {
            var k = vwa_widget_add(bd, grp[i]);
            if (k != undefined)
            {
                array_push(keys, k);
            }
        }
        if (multi)
        {
            vwa_gb_end_row(bd);
        }
        if (array_length(keys) > 0)
        {
            array_push(rowKeys, keys);
        }
    }

    if (array_length(rowKeys) > 1)
    {
        var firstRow = rowKeys[0];
        var lastRow = rowKeys[array_length(rowKeys) - 1];
        for (var i = 0; i < array_length(firstRow); i++)
        {
            vwa_gb_connect(bd, firstRow[i], "up", lastRow[0], "");
        }
        for (var i = 0; i < array_length(lastRow); i++)
        {
            vwa_gb_connect(bd, lastRow[i], "down", firstRow[0], "");
        }
    }
}

// Vtable dispatch by widget family. Returns the node's structural key, or
// undefined for an unhandled family (logged loudly: a menu control the mod
// drops is invisible to a blind player - exactly what the raw-vs-mod diff
// in the smoke scripts exists to catch).
function vwa_widget_add(bd, inst)
{
    var objIdx = inst.object_index;
    if (objIdx == oSettings_checkbox || object_is_ancestor(objIdx, oSettings_checkbox))
    {
        return vwa_widget_add_checkbox(bd, inst);
    }
    if (objIdx == oButton_menus || object_is_ancestor(objIdx, oButton_menus))
    {
        return vwa_widget_add_button_menus(bd, inst);
    }
    if (objIdx == oMenuElement || object_is_ancestor(objIdx, oMenuElement))
    {
        if (inst.enableDropdown)
        {
            return vwa_widget_add_combo(bd, inst);
        }
        // settingsMenuElement_initSlider is what makes an element a slider;
        // "dragging" exists only after it ran.
        if (variable_instance_exists(inst, "dragging"))
        {
            return vwa_widget_add_slider(bd, inst);
        }
        return vwa_widget_add_element_label(bd, inst);
    }
    if (objIdx == oButton || object_is_ancestor(objIdx, oButton))
    {
        return vwa_widget_add_obutton(bd, inst);
    }
    vwa_log("ERROR: widget adapter: unhandled object " + object_get_name(objIdx));
    return undefined;
}

// The widget's tooltip as an announcement part: read inline with the
// control whenever the game gives the widget a tooltipStr, silent when it
// has none. Void War tooltips are flat strings (verified: draw_label
// 9-slice panels; sections/double panels are visual composition only, no
// links or nesting), so inline reading covers the whole tooltip surface.
// oButton defaults tooltipStr to the NUMBER 0, so the string check does
// both jobs.
function vwa_widget_tooltip_part(inst)
{
    return vwa_part_fn("tooltip", method({ inst: inst }, function()
    {
        var tt = self.inst.tooltipStr;
        return (is_string(tt) && tt != "") ? tt : "";
    }), false);
}

// oSettings_checkbox: label in rightText, state in toggled. Activation
// mirrors clickToToggle (oSettings_checkbox Create): the dropdown guard,
// the checkbox sound, then the stored onClick. The flipped state speaks
// through the live value part.
function vwa_widget_add_checkbox(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "toggle",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.rightText;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                return self.inst.toggled ? vwa_t("vwa--state-checked")
                    : vwa_t("vwa--state-unchecked");
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var cb = self.inst;
            if (!all_dropdowns_closed())
            {
                vwa_log("ERROR: checkbox activation with a dropdown open"
                    + " - screen stack out of sync?");
                return;
            }
            if (cb.onClick == -4)
            {
                vwa_log("ERROR: checkbox " + object_get_name(cb.object_index)
                    + " has no onClick");
                return;
            }
            sfx_start_ext(global.sfx_settingsCheckbox, 0, 1, 0, 0, 1);
            var fn = cb.onClick;
            fn();
        })
    });
    return skey;
}

// oButton_menus: label in text (textLabelName is the stable identity when
// present - text re-localizes). Activation mirrors its Step_0: the
// confirmation-dialogue block (unless the button belongs to the dialogue),
// dimButton refuses with audible feedback, hoverConditionsMet guards, then
// the stored onClick and the press sound, in the game's order.
function vwa_widget_add_button_menus(bd, inst)
{
    var lbl = (inst.textLabelName != "") ? inst.textLabelName : string(inst.text);
    var skey = "bm:" + lbl;
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.text;
            }), false),
            vwa_part_fn("enabled", method({ inst: inst }, function()
            {
                return self.inst.dimButton ? vwa_t("vwa--state-disabled") : "";
            }), true)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var bt = self.inst;
            if (instance_exists(oUIConfirmationDialogue))
            {
                var blocked = true;
                if (instance_exists(bt.parentID)
                    && (bt.parentID.object_index == oUIConfirmationDialogue
                        || objIA(bt.parentID.object_index, oUIConfirmationDialogue)))
                {
                    blocked = false;
                }
                if (blocked)
                {
                    vwa_log("ERROR: button '" + string(bt.text)
                        + "' blocked by the confirmation dialogue"
                        + " - screen stack out of sync?");
                    return;
                }
            }
            if (bt.dimButton)
            {
                vwa_speak([vwa_t("vwa--state-disabled")], false);
                return;
            }
            if (bt.hoverConditionsMet != -4)
            {
                var hc = bt.hoverConditionsMet;
                if (!hc())
                {
                    vwa_log("ERROR: button '" + string(bt.text)
                        + "' hover conditions refuse activation"
                        + " - screen stack out of sync?");
                    return;
                }
            }
            // The sound id is read BEFORE onClick: an onClick may destroy
            // its own button (Cancel destroys the dialogue, whose CleanUp
            // kills its buttons), and reading through the dead id from here
            // crashes - the game's own Step survives only because a dying
            // instance's running event keeps its scope (bit us: every
            // keyboard Cancel tripped the input watchdog).
            var pressSfx = bt.sfx_press;
            if (bt.onClick != -4)
            {
                var fn = bt.onClick;
                fn();
            }
            sfx_start_ext(pressSfx, 0, 1, 0, 0, 1);
        })
    });
    return skey;
}

// oMenuElement slider: label in leftLabel, value in rightLabel (the game's
// Step refreshes it every frame). Left/right arrows adjust via the
// per-object mirror below.
function vwa_widget_add_slider(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "slider",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.leftLabel;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                return self.inst.rightLabel;
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onAdjust: method({ inst: inst }, function(sign, large)
        {
            vwa_widget_slider_adjust(self.inst, sign, large);
        })
    });
    return skey;
}

// The volume sliders' only pointer-free adjustment path is the mouse-wheel
// handler, whose body reads live mouse state, so this mirrors its exact
// effect per slider object: the same clamp and the same update call
// (mouseWheelToSlide in oSettings_volume_music Create). The increments are
// OUR keyboard granularity, Rashad's choice: 0.01 per arrow step and 0.1
// per Ctrl+arrow large step (the game's wheel uses 0.05; the effect path
// is what's mirrored, not the wheel's coarseness). A slider without a
// mirror logs loudly: extending this dispatch is the documented
// generic-builder exception for new sliders.
function vwa_widget_slider_adjust(inst, sign, large)
{
    var inc = large ? 0.1 : 0.01;
    var objIdx = inst.object_index;
    if (objIdx == oSettings_volume_music)
    {
        global.currVolume_BGM = clamp(global.currVolume_BGM + sign * inc, 0, 1);
        music_volume_update();
        return;
    }
    if (objIdx == oSettings_volume_sound)
    {
        global.volumeMax_SFX = clamp(global.volumeMax_SFX + sign * inc, 0, 1);
        master_volume_update();
        return;
    }
    vwa_log("ERROR: slider " + object_get_name(objIdx) + " has no adjust mirror");
}

// oMenuElement dropdown, closed state: a combo box. Label in leftLabel,
// value in centerText (centerTextOverride wins when set - fullscreen /
// custom size on the window-size element). Activation mirrors the game's
// dropdown-button click (draw_dropdownButton in init_dropdownVariables):
// refuse while another dropdown is open, the click sound, then open. The
// open list becomes the vwa-dropdown child screen.
function vwa_widget_add_combo(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "combo",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.leftLabel;
            }), false),
            vwa_part_fn("value", method({ inst: inst }, function()
            {
                var el = self.inst;
                return (el.centerTextOverride != "") ? el.centerTextOverride
                    : el.centerText;
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            var el = self.inst;
            if (dropdown_any_open())
            {
                vwa_log("ERROR: opening a dropdown while another is open"
                    + " - screen stack out of sync?");
                return;
            }
            sfx_start(global.sfx_click, 0, 1, 0, 0);
            el.toggleDropdown = true;
        })
    });
    return skey;
}

// oMenuElement that is neither slider nor dropdown: a plain labeled row.
function vwa_widget_add_element_label(bd, inst)
{
    var skey = object_get_name(inst.object_index) + "#" + string(inst.id);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "label",
        parts: [vwa_part_fn("label", method({ inst: inst }, function()
        {
            var el = self.inst;
            if (el.leftLabel != "")
            {
                return el.leftLabel;
            }
            return (el.centerTextOverride != "") ? el.centerTextOverride
                : el.centerText;
        }), false),
            vwa_widget_tooltip_part(inst)]
    });
    return skey;
}

// The oButton family's activation mirror, shared by the generic widget
// adapter and the main menu's social buttons: update_hover's guards plus
// click_to_trigger_button (oButton Create), in the game's order.
// Confirmation dialogue and open dropdowns block; drawConditionsMet blocks
// (oButton Step_0 gates the whole click path on it - an invisible button
// is unclickable); hoverConditionsMet blocks; an inactive buttonActive
// refuses with audible feedback; then onPress, the press sound, and
// triggerButton = true (the child object's Step does the real work off
// that flag).
function vwa_obutton_activate(bt)
{
    if (instance_exists(oUIConfirmationDialogue) || dropdown_any_open())
    {
        vwa_log("ERROR: button " + object_get_name(bt.object_index)
            + " blocked by an overlay - screen stack out of sync?");
        return;
    }
    if (bt.drawConditionsMet != -4)
    {
        var dc = bt.drawConditionsMet;
        if (!dc())
        {
            vwa_log("ERROR: button " + object_get_name(bt.object_index)
                + " is not drawn - screen stack out of sync?");
            return;
        }
    }
    if (bt.hoverConditionsMet != -4)
    {
        var hc = bt.hoverConditionsMet;
        if (!hc())
        {
            vwa_log("ERROR: button " + object_get_name(bt.object_index)
                + " hover conditions refuse activation"
                + " - screen stack out of sync?");
            return;
        }
    }
    var act = bt.buttonActive;
    if (!act())
    {
        vwa_speak([vwa_t("vwa--state-disabled")], false);
        return;
    }
    // Sound id read before onPress for the same dying-instance reason as
    // oButton_menus; skip triggerButton if onPress destroyed the button
    // (nothing left to trigger).
    var pressSfx = bt.sfx_press;
    if (bt.onPress != -4)
    {
        var fp = bt.onPress;
        fp();
    }
    sfx_start_ext(pressSfx, 0, 1, 0, 0, 1);
    if (instance_exists(bt))
    {
        bt.triggerButton = true;
    }
}

// oButton family (Configure Keybinds): label in centerText, activation via
// the shared oButton mirror above.
function vwa_widget_add_obutton(bd, inst)
{
    var skey = object_get_name(inst.object_index);
    vwa_gb_add(bd, vwa_id_ref(inst, skey), {
        typeKey: "button",
        parts: [
            vwa_part_fn("label", method({ inst: inst }, function()
            {
                return self.inst.centerText;
            }), false),
            vwa_part_fn("enabled", method({ inst: inst }, function()
            {
                var bt = self.inst;
                if (bt.buttonActive == -4)
                {
                    return "";
                }
                var act = bt.buttonActive;
                return act() ? "" : vwa_t("vwa--state-disabled");
            }), true),
            vwa_widget_tooltip_part(inst)
        ],
        onActivate: method({ inst: inst }, function()
        {
            vwa_obutton_activate(self.inst);
        })
    });
    return skey;
}

// ---- the dropdown child screen's guts ----

function vwa_find_open_dropdown()
{
    var cnt = instance_number(oMenuElement);
    for (var i = 0; i < cnt; i++)
    {
        var el = instance_find(oMenuElement, i);
        if (el.enableDropdown && el.toggleDropdown)
        {
            return el;
        }
    }
    return undefined;
}

// One node per entry; identity is the list index (a dropdown's entries are
// fixed while it is open). The current selection carries the "selected"
// part, which is also what lands focus there on entry. Disabled entries
// read as unavailable and have no activation ("No action").
function vwa_dropdown_build(bd)
{
    var dd = vwa_find_open_dropdown();
    if (dd == undefined)
    {
        return; // closed this same frame; empty build, screen pops next tick
    }
    var entries = dd.dropdownEntries;
    for (var i = 0; i < array_length(entries); i++)
    {
        var disabled = (i < array_length(dd.dropdownEntry_disabled))
            && dd.dropdownEntry_disabled[i];
        var def = {
            typeKey: "option",
            parts: [
                vwa_part_fn("label", method({ dd: dd, idx: i }, function()
                {
                    return self.dd.dropdownEntries[self.idx];
                }), false),
                vwa_part_fn("selected", method({ dd: dd, idx: i }, function()
                {
                    return (self.dd.dropdown_currSelectedIndex == self.idx)
                        ? vwa_t("vwa--state-selected") : "";
                }), true)
            ]
        };
        if (disabled)
        {
            array_push(def.parts, vwa_part("enabled", vwa_t("vwa--state-disabled")));
        }
        else
        {
            def.onActivate = method({ dd: dd, idx: i }, function()
            {
                vwa_dropdown_choose(self.dd, self.idx);
            });
        }
        vwa_gb_add(bd, vwa_id("opt:" + string(i)), def);
    }
}

// Mirror of the game's entry-click commit (oMenuElement Step_0): blocked by
// a confirmation dialogue, the select sound, the index, then the element's
// stored select_dropdownEntry. One deliberate divergence: the mouse flow
// leaves the list open after a click; the keyboard flow closes it (choose =
// commit + close, combo-box convention) - closing is exactly what clicking
// the dropdown button again does, so no game state is invented.
function vwa_dropdown_choose(dd, idx)
{
    if (instance_exists(oUIConfirmationDialogue))
    {
        vwa_log("ERROR: dropdown choose while a confirmation dialogue is open"
            + " - screen stack out of sync?");
        return;
    }
    sfx_start_ext(global.sfx_selectDropdownEntry, 0, 1, 0, 0, 0);
    dd.dropdown_currSelectedIndex = idx;
    if (dd.select_dropdownEntry != -4)
    {
        var fn = dd.select_dropdownEntry;
        fn();
    }
    // A select that closes its own menu (destroying the element) is
    // legitimate game behavior; only close the list if it survived.
    if (instance_exists(dd))
    {
        dd.toggleDropdown = false;
    }
}

// ---- the auto-paging list pattern (session 12) ----
// Paged game lists are surfaced WHOLE: every row of every page goes into
// the graph, so arrows walk the full list, type-ahead spans pages with no
// search changes (candidates are the focused stop's nodes), and the
// auto-stamped position is a global "n of m". NO pager button nodes are
// emitted. What keeps the game's own view honest is this ensure-visible
// tick, called from the screen's build (the vwa_commander_badge_tick
// pattern: impure per-frame work driven from build): when the focused
// node's row is not on the game widget's current page, the game's OWN
// page-step methods run - shortest wrapping direction - until it is, so
// hover-badge clears, page badges, and whatever a sighted helper sees all
// track focus. The flip happens inside the build that follows a focus
// change, before parts resolve, so the announcement always reads the
// settled page. Idempotent (already visible = no-op), bounded by the page
// count, converges or logs. cfg fields:
//   focusPage  fn(skey) -> 0-based page holding the focused node's row,
//              or -1 when the focused node is not a paged row
//   curPage    fn() -> the widget's 0-based current page
//   pageCount  fn() -> total pages
//   stepNext / stepPrev  fn() - the game's own page-step methods
function vwa_pages_ensure_visible(scr, cfg)
{
    if (scr == undefined || scr.navState.curId == undefined)
    {
        return;
    }
    var fPage = cfg.focusPage;
    var target = fPage(scr.navState.curId.skey);
    if (target < 0)
    {
        return;
    }
    var fCount = cfg.pageCount;
    var n = fCount();
    var fCur = cfg.curPage;
    if (n <= 1 || fCur() == target)
    {
        return;
    }
    var guard = 0;
    while (fCur() != target && guard < n)
    {
        var diff = ((target - fCur()) % n + n) % n;
        var fStep = (diff <= n / 2) ? cfg.stepNext : cfg.stepPrev;
        fStep();
        guard += 1;
    }
    if (fCur() != target)
    {
        vwa_log("ERROR: ensure-visible stuck on page " + string(fCur())
            + " wanting " + string(target) + " of " + string(n));
    }
}
