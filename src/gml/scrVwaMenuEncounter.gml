// scrVwaMenuEncounter - Void War Access encounter dialogue family: the
// game's popup system, which is the entire in-run narrative layer. One
// persistent oPopup (child of oPopupGroup) displays an oEncounter-child
// "oTxt*" instance as txtObj: body text, up to 10 numbered choices with
// outcome callbacks, optional commander/NPC portrait, optional reward
// panel. Every story encounter, boss intro, module prompt, the in-run
// pause popup (oTxtPauseMenu), and the new-run intro after ship select's
// Begin flow through it. Registered from vwa_menus_init via
// vwa_menu_encounter_init.
// Imported by tools/build-mod.csx as a new global script. Ships in release.
//
// Player model:
// - The screen ("Dialogue") activates when oPopup has a live, initialized
//   txtObj (conditionalChoicesRemoved - text and the choice set are final
//   only after txtInit_initText's localization + conditional removal). The
//   popup is NOT a menu: global.menuToggle stays 0 (or keeps the underlying
//   in-run menu's value, e.g. the upgrade menu under oTxtUpgradeConfirm),
//   so activation keys off the instances, and the layer sits between the
//   generic menu fallback (39) and the pause/settings menus (40): the game
//   allows oMenuPause and oUIConfirmationDialogue OVER a popup and freezes
//   the popup's own input while they exist - those screens must cover this
//   one, while a popup over an in-run menu must cover the fallback.
// - One control list: the body (one node, one spoken line per text
//   paragraph, portrait line last), reward entries when the panel is up,
//   then the choices exactly as the game numbers them ("1. Continue").
// - Number keys 1-9 (top row and numpad; category "encounter", live only
//   while this screen is focused) move the mod cursor to that choice and
//   speak it - they NEVER activate. The game's own number shortcut, which
//   executed the choice with no feedback (a silent commit for a blind
//   player), is removed at build time (oPopupGroup_Step_1.replace.gml via
//   build-mod.csx, asserted post-import). The game numbers by choice INDEX
//   - an empty slot keeps its successors' numbers - so key n maps to index
//   n-1 directly, and a number with no choice speaks "no choice n".
// - Enter activates through the popup's own stored choice_execute (real
//   dispatch: encounter log, outcome callback, response chain), mirroring
//   the click path's guards and click sound; a greyed choice (unmet grey
//   condition or scrap requirement) speaks the disabled state instead, and
//   its announcement carries "unavailable" plus the scrap cost.
// - A choice resolving swaps txtObj (all structural keys change, focus
//   falls to the new body node and the tick announces it) or destroys the
//   popup (the screen pops silently; the run continues). Escape stays the
//   game's own - the mod claims nothing here.
// - Reward entries speak the exact text the game drew: each entry stores
//   its final rendered label in rewardText (game truth - the 700-line
//   branch soup in oPopupRewardEntry Draw_64 needs no mirror). On an
//   entry's first frame the text is not yet stored and the node is
//   silently empty for that frame.
//
// Walker note: this screen only exists over a live run (reaching it in a
// smoke means starting a run, which touches the player's autosave), so
// scripts/smoke.ps1 does not cover it; walk it manually after Begin via
// `call vwa_dev_walk_start encounter`. The pure paragraph splitter is
// covered by vwa_dev_selftest.

function vwa_menu_encounter_init()
{
    vwa_screen_register({
        key: "encounter",
        layerNum: 39.5,
        categories: ["encounter", "ui"],
        exclusive: true,
        isActive: function()
        {
            if (!instance_exists(oPopup))
            {
                return false;
            }
            var p = instance_find(oPopup, 0);
            return objInst_exists(p.txtObj) && p.txtObj.conditionalChoicesRemoved;
        },
        name: function() { return vwa_t("vwa--screen-dialogue"); },
        build: function(bd) { vwa_encounter_build(bd); }
    });

    // The choice jumps. Registered once at boot; live only while the
    // encounter screen contributes its "encounter" category (i.e. focused -
    // an exclusive screen above kills it). Top row and numpad both bind.
    for (var n = 1; n <= 9; n++)
    {
        vwa_action_register("enc-choice-" + string(n), "vwa--action-enc-choice",
            "encounter",
            [vwa_bind(ord(string(n)), false, false, false),
             vwa_bind(vk_numpad0 + n, false, false, false)],
            false,
            method({ n: n }, function() { vwa_enc_choice_jump(self.n); }));
    }
}

// Immediate-mode build from the live popup (never cache game state). Node
// identity: every structural key embeds the txtObj instance, so the next
// dialogue in a chain invalidates the whole render and focus falls to its
// body node (announced by the tick). Only the body node carries a ref (the
// txtObj) - the graph reconciles by ref BEFORE structural key, so a shared
// ref would snap focus off the choices every frame.
function vwa_encounter_build(bd)
{
    var p = instance_find(oPopup, 0);
    var txt = p.txtObj;
    var base = "enc:" + string(txt);

    // The body: paragraph 1 is the summary line, each further paragraph its
    // own line (alt-arrow steppable), the portrait line last. The paragraph
    // COUNT is fixed per build, but builds rerun every frame, so dynamic
    // text (module overflow relabeling) stays current.
    var paras = vwa_enc_split_paragraphs(txt.text);
    var parts = [vwa_part_fn("label", method({ txt: txt }, function()
    {
        if (!instance_exists(self.txt))
        {
            return "";
        }
        var ps = vwa_enc_split_paragraphs(self.txt.text);
        return (array_length(ps) > 0) ? ps[0] : "";
    }), false)];
    for (var i = 1; i < array_length(paras); i++)
    {
        array_push(parts, vwa_part_fn("tooltip", method({ txt: txt, idx: i }, function()
        {
            if (!instance_exists(self.txt))
            {
                return "";
            }
            var ps = vwa_enc_split_paragraphs(self.txt.text);
            return (self.idx < array_length(ps)) ? ps[self.idx] : "";
        }), false));
    }
    if (txt.drawEnemyCommanderPortrait || txt.drawTempNPCPortrait != -1)
    {
        array_push(parts, vwa_part_fn("tooltip", method({ txt: txt }, function()
        {
            var nm = vwa_enc_portrait_name(self.txt);
            if (nm == "")
            {
                return "";
            }
            return string_replace(vwa_t("vwa--enc-portrait"), "{name}", nm);
        }), false));
    }
    vwa_gb_add(bd, vwa_id_ref(txt, base + ":body"), {
        typeKey: "label",
        parts: parts
    });

    vwa_encounter_rewards_build(bd, base);

    // The choices, exactly as drawn (draw_choices: non-empty entries,
    // numbered by index+1, hidden wholesale by hideAllChoices /
    // disableChoices).
    if (!p.hideAllChoices && !txt.disableChoices)
    {
        for (var i = 0; i < array_length(txt.choice); i++)
        {
            var c = txt.choice[i];
            if (!is_string(c) || c == "")
            {
                continue;
            }
            vwa_gb_add(bd, vwa_id(base + ":choice:" + string(i)), {
                typeKey: "button",
                parts: [
                    vwa_part_fn("label", method({ txt: txt, idx: i }, function()
                    {
                        if (!instance_exists(self.txt)
                            || self.idx >= array_length(self.txt.choice))
                        {
                            return "";
                        }
                        var s = self.txt.choice[self.idx];
                        if (!is_string(s) || s == "")
                        {
                            return "";
                        }
                        return string(self.idx + 1) + ". " + s;
                    }), false),
                    vwa_part_fn("enabled", method({ txt: txt, idx: i }, function()
                    {
                        return vwa_enc_choice_blocked_text(self.txt, self.idx);
                    }), false)
                ],
                onActivate: method({ idx: i }, function()
                {
                    vwa_enc_choice_activate(self.idx);
                })
            });
        }
    }
}

// Reward panel entries, in on-screen order (the panel lays them out
// left to right). Spoken text is the entry's own rewardText - the final
// string its Draw_64 rendered and stored (game truth, no mirror); absent
// until the entry's first draw. Draw_64 hides entries while oMenuPause or
// oUIOverflowGrid is up, but both put an exclusive screen over this one,
// so presence here mirrors visibility.
function vwa_encounter_rewards_build(bd, base)
{
    var list = [];
    var cnt = instance_number(oPopupRewardEntry);
    for (var i = 0; i < cnt; i++)
    {
        var e = instance_find(oPopupRewardEntry, i);
        if (e.data != -1)
        {
            array_push(list, e);
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
    vwa_gb_push_context(bd, vwa_t("vwa--group-rewards"));
    for (var i = 0; i < array_length(list); i++)
    {
        vwa_gb_add(bd, vwa_id_ref(list[i], base + ":reward:" + string(i)), {
            typeKey: "label",
            parts: [vwa_part_fn("label", method({ inst: list[i] }, function()
            {
                if (!instance_exists(self.inst)
                    || !variable_instance_exists(self.inst, "rewardText"))
                {
                    return "";
                }
                var t = self.inst.rewardText;
                return is_string(t) ? t : "";
            }), false)]
        });
    }
    vwa_gb_pop_context(bd);
}

// Split popup body text into non-empty trimmed lines, one spoken line each
// (the game authors paragraphs with blank lines; leading/trailing runs
// vanish). PURE - fixture-tested in vwa_dev_selftest.
function vwa_enc_split_paragraphs(text)
{
    if (!is_string(text))
    {
        return [];
    }
    var out = [];
    var lines = string_split(text, "\n");
    for (var i = 0; i < array_length(lines); i++)
    {
        var ln = string_trim(lines[i]);
        if (ln != "")
        {
            array_push(out, ln);
        }
    }
    return out;
}

// Mirror of oPopupGroup draw_commanderPortrait's name resolution, same
// precedence: enemy commander (truncatedName over the base name unless a
// custom display name is set), the last-commander fallback, the
// oCommanderAdder override, the temp-NPC override; visible only when both
// the sprite and the name resolve, like the draw. Speech skips only the
// visual 60-pixel truncation - same entity, full name. crew_get_info
// selectors: 37 = portrait sprite, 31 = base name.
function vwa_enc_portrait_name(txt)
{
    if (!instance_exists(txt))
    {
        return "";
    }
    var spr = -4;
    var nm = -4;
    var hull = get_hull(0);
    var commander = enemyCrew_get_commander();
    if (hull && commander)
    {
        spr = commander.sprite_portrait;
        nm = crew_get_name(commander);
        if (!is_string(commander.customCommanderDisplayName)
            && commander.truncatedName != "")
        {
            nm = commander.truncatedName;
        }
    }
    else if (global.lastEnemyCommander_index != -1)
    {
        spr = crew_get_info(global.lastEnemyCommander_index, 37);
        nm = global.lastEnemyCommander_name;
    }
    if (instance_exists(oCommanderAdder))
    {
        var crewIndex = oCommanderAdder.crewIndex;
        spr = crew_get_info(crewIndex, 37);
        nm = crew_get_info(crewIndex, 31);
        if (is_string(oCommanderAdder.name))
        {
            nm = oCommanderAdder.name;
        }
    }
    if (txt.drawTempNPCPortrait != -1)
    {
        spr = txt.drawTempNPCPortrait;
        nm = txt.drawTempNPCPortrait_name;
    }
    if (!sprite_exists(spr) || !is_string(nm))
    {
        return "";
    }
    return nm;
}

// The spoken blocked-state for choice i: "" when activatable, else the
// disabled word, plus the scrap cost when that is what blocks (mirrors
// choiceGreyCondition_requirementsMet / choiceMetalRequirement_requirementsMet
// on oPopupGroup - resolved here without the popup so the part stays
// readable even mid-teardown).
function vwa_enc_choice_blocked_text(txt, i)
{
    if (!instance_exists(txt))
    {
        return "";
    }
    var greyBlocked = i < array_length(txt.choiceGreyConditionMet)
        && !txt.choiceGreyConditionMet[i];
    var metalReq = (i < array_length(txt.choiceMetalRequirement))
        ? txt.choiceMetalRequirement[i] : -1;
    var metalBlocked = metalReq != -1 && oPlayerInfo.currScrap < metalReq;
    if (!greyBlocked && !metalBlocked)
    {
        return "";
    }
    var out = vwa_t("vwa--state-disabled");
    if (metalBlocked)
    {
        var req = string_replace(vwa_t("vwa--enc-requires-scrap"), "{n}",
            string(metalReq));
        out += ", " + string_replace(req, "{currency}", string(global.currencyName));
    }
    return out;
}

// Number key n: move the mod cursor to the game's visibly numbered choice
// n and speak it - never commit (Enter does that). A number with no choice
// behind it answers audibly instead of dying silently.
function vwa_enc_choice_jump(n)
{
    var scr = global.vwaFocusedScreen;
    if (scr == undefined || scr.key != "encounter")
    {
        // The "encounter" category is only live while this screen is
        // focused (it is exclusive and everything above it is too), so
        // this is a stack bug worth seeing.
        vwa_log("ERROR: enc-choice-" + string(n)
            + " fired without encounter focus");
        return;
    }
    var p = instance_find(oPopup, 0);
    var skey = "enc:" + string(p.txtObj) + ":choice:" + string(n - 1);
    if (!vwa_nav_focus_speak(scr, skey))
    {
        vwa_speak([string_replace(vwa_t("vwa--enc-no-choice"), "{n}",
            string(n))], true);
    }
}

// Mirror of the game's own choice click path (oPopupGroup Step_1 ->
// choice_execute): the same overlay guards, the same grey/scrap checks,
// the same click sound, then the popup's own stored choice_execute (real
// dispatch: encounter log, outcome callback, response chain; the popup's
// End Step advances the queue once the outcome finishes). A blocked
// requirement speaks the disabled state (the widget-adapter precedent); an
// overlay guard firing means our stack is out of sync - log loudly.
function vwa_enc_choice_activate(i)
{
    if (!instance_exists(oPopup))
    {
        vwa_log("ERROR: encounter activation with no oPopup");
        return;
    }
    var p = instance_find(oPopup, 0);
    var txt = p.txtObj;
    if (!objInst_exists(txt) || i >= array_length(txt.choice)
        || !is_string(txt.choice[i]) || txt.choice[i] == "")
    {
        vwa_log("ERROR: encounter activation of missing choice " + string(i));
        return;
    }
    if (instance_exists(oMenuPause) || instance_exists(oUIConfirmationDialogue))
    {
        vwa_log("ERROR: encounter activation blocked by an overlay the game"
            + " guards against - screen stack out of sync?");
        return;
    }
    if (p.hideAllChoices || txt.disableChoices)
    {
        vwa_log("ERROR: encounter activation while choices are hidden");
        return;
    }
    var greyOk = p.choiceGreyCondition_requirementsMet;
    var metalOk = p.choiceMetalRequirement_requirementsMet;
    if (!greyOk(i) || !metalOk(i))
    {
        vwa_speak([vwa_t("vwa--state-disabled")], false);
        return;
    }
    sfx_start(global.sfx_click, 0, 1, 0, 0);
    var fn = p.choice_execute;
    fn(i);
}
