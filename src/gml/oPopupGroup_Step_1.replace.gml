// Replaces oPopupGroup's Begin Step (build-mod.csx QueueReplace, asserted
// post-import): the game's original also called keyboardShortcut_choiceExecute
// here - a raw number-key read that EXECUTES a dialogue choice with no
// feedback, which for a blind player is a silent commit. The mod removes it;
// number keys instead move the mod cursor to the choice (scrVwaMenuEncounter,
// enc-choice-N). The mouse click path stays the game's own.
if (!instance_exists(oMenuPause) && !instance_exists(oUIConfirmationDialogue) && !hideAllChoices && !txtObj.disableChoices)
{
    detect_choice_click_and_execute();
}
