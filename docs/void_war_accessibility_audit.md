# Void War: Comprehensive Accessibility Audit

## Every User-Facing Mechanic and Interface Element

*Ordered by Encounter Sequence*

> **Note:** This document catalogues every screen, panel, popup, HUD element,
> and interactive mechanic a player encounters in Void War (verified against
> the decompiled 1.4.0c data; GameMaker 2023.8). It is organized in the order
> a player first encounters each element, from launch through a full run. The
> goal is to identify every component that must be made accessible for a
> blind player using a screen reader. It describes what exists in the game,
> not how to make it accessible. Object and script names from the decompile
> are cited so future work can find the code fast.

> **Status key:** DONE = fully accessible via the mod, PARTIAL = accessible
> with gaps, NOT STARTED = no coverage, N/A = not applicable.

> **Interaction baseline.** The game has no focus concept and no menu
> keyboard navigation. Almost every control is mouse hover + left click over
> either an `oButton`/`oMenuButton`/`oMenuElement` widget or raw drawn text
> backed by an invisible `scrCollisionBox` hit region. The game's own
> keyboard support, in total: Escape (back/close/pause, hardcoded, not
> rebindable), number keys 1-9 on encounter choice popups, Left/Right to
> cycle hulls on ship select, Up/Down to scroll the announcements popup and
> credits, text entry in four name fields, and the ~44 rebindable combat
> actions in `scrKeybinds` (pause, map, menus, doors, system/weapon power,
> control groups - full list in Phase 12). Everything spatial - picking a
> crew, a room, a weapon target, a map node, an item slot - is mouse-only.

---

# Phase 1: Application Launch and Main Menu

## 1.1 Boot and Loading - N/A

`rmPreload` (`oInitGlobals`) and `rmLoading` (`oAssetLoader`) are
non-interactive boot rooms. No text, no input. The mod's boot announcement
fires here.

## 1.2 Main Menu - DONE

Room `rmMainMenu`, controller `oMainMenuControls`. The menu is raw
`draw_text_color` entries with per-item collision boxes (no button objects),
built into `buttonList`. Entries are conditional:

- **Continue** - only when an autosave exists. Loads it and resumes the run.
- **New Game** - to Commander Select; on a brand-new profile it instead
  force-starts the tutorial via Ship Select.
- **Tutorial** - replay; only after the tutorial has been completed once.
- **Archives** - only when at least one finished run is recorded.
- **Achievements**, **Settings**, **Exit**.
- Top-right corner entries (same list): **Credits** (only after any
  victory) and **Announcements**.

Game keyboard: Escape opens Settings. Everything else is mouse-only.
The mod walks `buttonList` live, so all conditional entries and the corner
entries are covered; activation mirrors the game's overlay guards.

## 1.3 Social Button Bar - DONE

`oSocialButtonBar` + `oSocialButton`, bottom right: two buttons opening the
Steam store page and the Discord invite in a browser (`url_open`), each with
a hover tooltip. Not in `buttonList`; the mod surfaces them as a second Tab
stop on the main-menu screen (a "Social links" row, labels from the game's
own localized tooltip globals). Activation runs the game's oButton path
(`triggerButton`, whose Step calls `url_open`); visibility mirrors
`drawConditionsMet` (hidden while credits are up). The bar's "Thank you for
playing" string is dead code - its Draw event sets up fonts but never draws
text - so it is not surfaced.

## 1.4 Announcements Popup (Patch Notes) - DONE

`oGameStartMessage`, an overlay. Auto-spawns once per profile when a new
announcement exists, and manually from the corner button. Content is a
hardcoded array of title + body entries (`scrAnnouncementsText`), drawn as
raw text. Game keyboard: mouse wheel or Up/Down scroll, left-click or Escape
dismiss. Quirk (handled by the mod and its dev helper): the first-ever
dismissal on a profile respawns the popup once.

## 1.5 Version Info Line - N/A

`oGlobal` Draw GUI, gated on the Show Version Info setting: release/build
line bottom-left, plus sector/node fields in-run. Raw `draw_mini_text`,
decorative diagnostics.

---

# Phase 2: Settings Family

## 2.1 Settings Screen - DONE

`oMenuSettings` overlay (menuToggle 9), reachable from the main menu, Escape
at the main menu, and the pause menu. Widgets are real objects, enumerated
live by the mod's generic widget adapter:

- **Checkboxes** (`oSettings_checkbox_*`): Fullscreen, Borderless, Windowed
  (a side-by-side trio the mod treats as one group), Texture Filtering,
  Precise Crew Movement, Auto-Pause while in background, Mute while in
  background, Highlight Commander, Show Version Info, Enable Clean Font.
  (An Ambient Sounds checkbox exists in the assets but is not in the
  screen's element list, so it never shows.)
- **Sliders**: Music Volume, Sound Volume (game: click-drag or mouse wheel;
  mod: arrow keys, Ctrl for large steps, via the sanctioned wheel-path
  mirror).
- **Dropdowns** (`oMenuElement`): Window Size, Language (English + three
  BETA languages; picking a beta one raises a confirmation dialogue with
  the warning text, so the unsurfaced per-entry hover tooltip loses
  nothing).
- **Buttons**: Configure Keybinds, Back.

## 2.2 Configure Keybinds Screen - NOT STARTED

`oMenuConfigureKeybinds` (menuToggle 15), from Settings. Spawns one
`oKeybindSetter` row per action (~44, in columns of 14): current key name +
localized action label, raw text. Rebind flow: click a row to enter edit
mode, press any key or middle mouse to capture (Escape/Alt/Ctrl cannot be
bound), conflict raises `oUIConfirmationDialogue_keybindConfirmOverride`.
Bottom buttons: Back, Reset Keybinds (confirmation-guarded). Row selection
is mouse-only; Escape exits edit mode, then the screen. Currently a
name-only placeholder in the mod; the rows are widget objects, so the
generic adapter path applies.

## 2.3 Confirmation Dialogues - DONE

Base `oUIConfirmationDialogue` (menuToggle 14): dims screen, body question as
raw text, Confirm/Cancel as `oMenuButton`s, Escape = cancel. The mod's
generic confirm screen keys on the base object, so every variant is covered:
main menu / restart / reset-to-ship-select (from pause), reset keybinds,
keybind override, skip tutorial, beta language, commander purchase, ship
purchase, dismiss crew, jump-with-boarders.

## 2.4 Standalone Language Menu - DONE

`oMenuLanguage` (menuToggle 10). Dead code in 1.4.0c (the settings dropdown
replaced it) but covered by one generic-builder call as insurance.

---

# Phase 3: Out-of-Run Meta Screens

## 3.1 Run Archives - NOT STARTED

Room `rmRunArchives`, controller `oScoreArchive`; from the main menu
Archives entry. One archived run at a time, newest first:

- Panels (`oRunArchive_*`, raw text + sprites, hover tooltips): hull sprite
  and name + class, score, difficulty, run end (Victory / Commander Killed /
  Hull Destroyed), crew grid (12 per page, hover tooltip per crew),
  commander, 3 module slots, armament icons, system power boxes.
- A 3-page stats sheet ("Summary") of label:value lines: scrap acquired,
  max sector, ships destroyed/decrewed/surrendered, surrenders refused,
  minibosses, node-type visit counts, crew gained/lost by cause, healing,
  enemy crew slain by cause, repairs, fires extinguished, breaches
  repaired, creatures summoned, consumables spent.
- Nav buttons (mouse-only `oMenuButton`): previous/next entry, next stats
  page, next crew page. Filter dropdowns (`oMenuElement`): hull class, hull
  variant, difficulty, win/loss, plus a time-entry dropdown that IS the run
  selector.
- Back (also Escape) to main menu; Rankings button to Leaderboards.

## 3.2 Rankings (Local Leaderboard) - NOT STARTED

Room `rmLeaderboards`, `oLeaderboard`. A local top-10 of the player's own
runs (not a Steam online board), drawn as a raw-text table: rank, hull
sprite, name, class, variant, max sector, difficulty, victory yes/no,
score. Hovering highlights a row ("Click to view archive entry");
left-click deep-links into Run Archives. Same four filter dropdowns.
Mouse-only except Escape.

## 3.3 Achievements - NOT STARTED

Room `rmAchievements`: title + seven `oAchievementsGroup` rows (Dominion,
Exalted Feats, Voidcraft, Hosts of War, Massacre, Covenants, Stratagems).
Each group is a header + a row of achievement icons; locked ones are
greyscale with a lock overlay. Name + description + "(COMPLETED)" and
difficulty tier reached exist ONLY in the mouse-hover tooltip. No text
list. Back/Escape to main menu.

## 3.4 Credits - NOT STARTED

`oCredits` (room `rmCredits`), from the corner button after a victory, and
auto-played before the victory score screen. Auto-scrolling raw text (dev
credits + a backer list from a CSV, in a 3-column grid); mouse wheel or
Up/Down scroll manually, left-click or Escape dismisses.

## 3.5 Unlock Toasts - NOT STARTED

`oToastBox`: transient slide-in notifications ("Ship Unlocked" + hull name,
"Task Complete: ..."), about 8 seconds, raw text, click to dismiss, never
announced anywhere else. The only feedback for ship/difficulty unlocks.

---

# Phase 4: New Run Setup

## 4.1 Commander Select - NOT STARTED

Room `rmCommanderSelect` (menuToggle 13), controller `oUICommanderList`;
also spawned as an overlay on top of Ship Select. 17 commanders, 4 per page:

- Each grid entry (collision box, not an object) draws portrait + name;
  hidden ones show "???", locked ones a lock sprite + Resonance cost, won
  ones a max-difficulty star. Click selects; click on a locked, affordable
  one opens the purchase confirmation ("Confirm unlock?", name, Resonance
  cost).
- Page controls, a Resonance counter (hover tooltip), a commander name text
  box (click to focus, type) + randomize button, Confirm button.
- Game keyboard: Escape only. Grid selection is mouse-only. "New" badges
  clear silently on hover.

## 4.2 Ship Select - NOT STARTED

Room `rmShipSelectUI` (menuToggle 12), the richest setup screen. Structural
fact: each hull is a whole GameMaker room (12 hulls x A/B/C variants);
cycling ships is a room change with the live interior shown behind the UI.

- **Hull selector** (`oShipMenu_shipSelector`): the one keyboard control in
  the flow - Left/Right cycle hulls (skipping unavailable ones). Locked
  hulls draw a lock + quest-unlock description + a "Purchase" button
  (hardcoded English) opening the purchase confirmation.
- **Variant selector**: A/B/C buttons, mouse-only.
- **Ship list overlay** (`oShipListMenu`, menuToggle 11): all 12 hulls as a
  4x3 grid of buttons + variant selector; click picks; Escape or click
  outside closes.
- **Commander button**: portrait + name; click re-opens commander select
  as an overlay.
- **Crew display**: 3x2 paged grid of starting crew, hover tooltip each;
  page arrows (click or wheel), a toggle-crew-names button, click a crew to
  rename inline (text field).
- **Loadout readouts** (all hover-tooltip only): weapons/ordnance slots,
  3 module slots, systems with upgrade bars, "Additional Equipment:" items
  (label hardcoded English), highest Torment beaten, commander-wins count.
- **Ship name**: click-to-edit text field + randomize button.
- **Difficulty selector**: the Torment dropdown, tiers 1-21, unlocked
  progressively; rich per-entry hover tooltips. The run's only modifier -
  no seed entry, no daily/challenge modes.
- **Buttons**: View Exterior, Randomize Hull, Main Menu, Launch (inactive
  with a tooltip when the hull is locked).

Game keyboard: Left/Right, Escape (back to commander select), the two text
fields. Everything else mouse.

## 4.3 Tutorial - NOT STARTED

Forced on the first-ever New Game (fixed hull, auto-launch); replayable
from the main menu. Controller `oTutorial` with ~70 ordered steps
(`scrTutorial`); the visible step box `oTutorialPlate` draws body text,
the tutor's portrait/name, and a "Continue" hit-box - advancing is
mouse-click or the step's auto-advance condition; no keyboard. Decorative
arrows/brackets/highlight boxes point at UI. Skip is only via the pause
menu's Skip Tutorial button (confirmation-guarded). Some steps hand off to
normal encounter popups (`oTxtTutorial*`), which do have number-key choice
support.

## 4.4 Run Start Transition - NOT STARTED

Launch calls `VS_start_run()`: room change to the first node, then the
intro encounter chain (`oTxtGameStart` and successors) through the standard
popup system (Phase 7). `global.initialPopupSpawned` is the "run is now
interactive" gate.

---

# Phase 5: The Combat Screen (Ship View)

The core gameplay surface: both ship interiors side by side (player left,
enemy right in `oEnemyBox`), the systems bar below, weapons row, crew
portraits, and top-bar chrome. Real-time with a hard pause. This is the
sonification-grade design problem flagged in the backlog. Everything below
is NOT STARTED unless noted.

## 5.1 Ship Interior Spatial Model - NOT STARTED

- A ship = one `oHull` instance (hull HP `currHP`/`maxHP`, reactor
  `maxPsi`/`availablePsi`, `allied` flag; `global.playerHull` /
  `global.enemyHull`) + the `oCell` tiles overlapping it. Cells come in
  1/2/4-slot sizes with per-slot occupancy arrays.
- **Rooms have no names in data.** A cell's identity is the system instance
  sitting in it (`cell.system.name`, e.g. "Shields", "Life Support",
  "Launch Bay") or nothing for empty cells. Spoken room labels must be
  synthesized from the system plus position. Enumerating the ship =
  iterating `oCell` over the hull and reading system, crew, hazards.
- **Edges**: `oWall`, `oDoor`, `oAirlock` (`oCellSide`). Each cell holds
  `doorsList`, `adjCellList`, and `connectedCellList` (adjacency through
  doors) - the graph that fire spread, oxygen flow, and crew pathing use.
  Doors have open/closed/destroyed states and HP (boarders chew through
  them); airlocks vent to space. Click a door to toggle it; Z/X (bound)
  open/close all.
- Weak-point cells (`isWeakPoint`) accept crew deployment via the
  deployment queue.

## 5.2 Per-Room Hazard State - NOT STARTED

What a sighted player reads at a glance, per cell:

- **Oxygen is per-cell** (`currOxygen` 0-100): red tint deepens as it
  falls, distinct sprite when lethally low. Refilled by the oxygen
  system, drained by open airlocks/breaches along door paths (flood-fill
  recheck on every door change).
- **Fire** (`oFire`): burns a slot, spreads through connected cells,
  consumes oxygen, damages the room's system.
- **Hull breach** (`oBreach`): permanent vacuum source; sprite tiers show
  repair progress.
- **Poison clouds** mirror into `cell.isPoisoned`.
- **Boarders**: no per-cell marker - enemy crew sprites just stand there;
  a ship-level flashing "intruders" warning (`oUIWarningFlasher`) fires
  when hostiles are aboard.
- All of it is drawn only where the player has vision (5.9).

## 5.3 Crew: Selection, Orders, Stations - NOT STARTED

- Crew (`oCrew`/`oCrewPlayer`) live in cell slots; state machine covers
  idle/move/manning/extinguish/repair/melee/ranged/stunned/boarding
  states. HP bar above each sprite; status keywords appear as floating
  icons (5.8). A selected crew's details show in the side panel
  (`oUICrewPanel`) and the portrait bar (`oCrewPortrait*`).
- **Selection is mouse-only**: click or drag a marquee box; Shift adds,
  Ctrl toggles. **Movement is mouse-only**: right-click a destination cell
  (crew paths there, taking the manning console slot if one is free).
- **Keyboard that exists**: control groups - plain 1-9,0,minus,equals
  recall a saved group, Ctrl+number assigns one (rebindable
  `crew_management1..12`); F1 selects the commander; Backslash saves all
  crew positions as "stations" and Enter sends everyone back to them
  (`oUIStationsSave`/`oUIStationsReturn`).
- Manning: a crew in a system's console slot mans it (throne manning
  matters for evasion and the jump drive).

## 5.4 Systems Bar and Reactor - NOT STARTED

Power is "psi". A vertical reactor pip bar shows unallocated power (name
and description in a hover tooltip). Each installed system/subsystem gets
an icon button (`oSysUI*`) showing psi pips, a manned/unmanned pin where
relevant, a fire icon when its room burns, an ion-lock icon with a numeric
cooldown when ionized, and grey-out when unpowered.

- **Click model**: left-click adds 1 psi, right-click removes 1 (shields
  cost 2 per step). Insufficient power = error sound only.
- **Bound keys mirror the click**: A/S/D/F/G for the first five systems,
  and per-exotic keys (T/Y missile bays, I siege beam, O siege bombard,
  J hull reaper, M terror amplifier, H husk rack, P thrall pit, B shield
  charger, N graviton, K auto-surgeon); Shift+key removes power.
- Systems carry up to 4 sub-buttons (left-click only) with tooltips and
  inline error strings: medbay activate (+charge counter), door control
  open/close all, launch bay load/unload/recall/launch, hull reaper and
  terror amplifier fire + autofire, etc. Counters (medbay charges, sensor
  level, thrall/husk counts) are raw drawn numbers with their own
  tooltips.
- Damage model: fewer pips when damaged, greyed when destroyed, ion lock
  with countdown; repair just restores the display.

## 5.5 Weapons, Ordnance, Artillery, Targeting - NOT STARTED

- Each equipped weapon is a wide button (`oUIWeaponButton`, slots keyed
  Q/W/E/R): art, truncated name, psi-cost pips, a charge bar, an autofire
  toggle, and a target button. Hotkey or click powers the weapon and arms
  targeting; **the target itself is always a mouse click on an enemy
  room**. Right-click depowers. Weapon stats live in the hover tooltip
  (`generate_weapon_description`: shots, charge time, damage types,
  munitions cost, shield piercing, fire chance and so on).
- Missile bays (`oUIWeaponButton_ordnance`, keys T/Y): same shape plus a
  Load button opening `oLoadOrdnancePanel` to pick a missile template;
  consumes the munitions stock.
- Artillery (siege beam/bombard, keys I/O): one activate button, gated on
  power, charges, and a hostile target.
- Evasion is a drawn number per ship (`oUIEvasionCounter`, tooltip); a
  miss shows a floating "Miss" + sound.

## 5.6 Shields and Hull - NOT STARTED

- Shields render as a bubble sprite whose animation frame encodes layer
  count and recharge - **the layer count exists nowhere as text**; the
  shield system's psi pips (2 per layer) are the only numeric proxy.
- Hull HP for both ships is a row of blocks (`oUIHullHP`); the number is
  only in the hover tooltip ("Hull Strength: curr/max"). Flashes red when
  low.

## 5.7 Boarding - NOT STARTED

Via the Launch Bay system (`oSysBoarding`), not a teleporter: load crew
(V), launch an assault sled (C) - launching enters a cursor mode where
valid enemy cell edges get indicators and **the landing spot is a mouse
click**. The sled flies as a projectile; on impact crew disembark into the
enemy cell and fight with normal crew AI. Recall is another cursor-click
mode (or automatic if the enemy dies first); a jump with crew still aboard
the enemy raises the confirm-jump dialogue. Enemies board you the same
way. A crew's ship affiliation is recomputed from whichever hull is under
it.

## 5.8 Abilities and Status Effects - NOT STARTED

- Crew abilities (psychic spells, tools, consumables - `oAbilityPsychic`,
  `oAbilityEquipment`) appear as up to 2 icon buttons on the crew's
  portrait: cooldown seconds replace the icon while cooling, charge pips,
  a targeting overlay. Left-click casts or arms a **mouse-picked target**;
  right-click cancels. No mana - gating is cooldown/charges/crew state
  (some cost caster HP). Ability names and full stats are hover-tooltip
  only; error feedback ("Charges depleted!", "Cannot use while
  moving"...) is floating text, hardcoded English.
- Status effects on a crew are floating sprite icons with **no text, no
  duration, no hover**; names and remaining seconds appear only inside
  the crew's hover tooltip ("Stunned (3)").

## 5.9 Enemy Ship Presentation and Sensors - NOT STARTED

Sensor level gates interior vision: level 1+ shows your own cell
contents; matching the enemy's sensor level reveals theirs. A cell with
your crew in it is always visible (boarders grant local vision).
Obscured cells draw as dark grey rectangles hiding crew and hazards. With
vision, the enemy interior reads exactly like yours (systems, crew with
HP bars, fires). Enemy cells vanish entirely when the enemy is destroyed
or fleeing.

## 5.10 Weather and Boss Attacks - NOT STARTED

Sector weather (`oWeather*`: fire, plague, ion, warp breaches, asteroids,
defense batteries) pulses on a timer. About five seconds before each
pulse a flashing warning triangle + text banner appears
(`oUIWarningFlasher`: "Warning!" / "Extreme Heat Detected!" etc.) with a
sound cue - except asteroids and defense batteries, which give no warning
at all. Boss set-pieces telegraph with the generic "Extreme Energy
Detected!" flasher plus pure-visual expanding rings/arcs and radial
volleys. No weather name is shown outside the encounter intro prose.

## 5.11 Feedback Channels and the Absent Combat Log - NOT STARTED

All moment-to-moment feedback is floating drawn text and sprites
(`oVFXPopup` family): damage numbers, "+N/-N" HP, "Miss", "Rest",
skull-on-death. Alert sounds exist for weather, hull warning, and misses.
**The game has no combat log or event feed**: `oShipLog`, despite the
name, is a silent statistics logger for the score system (its only
rendering is a debug overlay). Any review-buffer/event-feed the mod wants
must be built from the underlying events, not read from an existing feed.

## 5.12 Pause / Command Mode - NOT STARTED

Space (rebindable; middle mouse alternate) toggles a hard freeze -
projectiles, crew, hazards, AI, and warp charging all stop; UI, hover
tooltips, targeting, and power allocation stay interactive. This is the
natural anchor for the mod's combat interaction model. No game speed
controls exist beyond pause.

## 5.13 Top Bar Chrome - NOT STARTED

`oUITopBarButton` children, each an icon + hover tooltip, disabled during
active threats ("Cannot open while active threats are present"): Loadout
(L), Upgrade (U), Encyclopedia/descriptions toggle (Backspace; adds lore
sections to tooltips), pause-menu button (Escape does the same), plus the
jump button and drive-charge widget (Phase 9), scrap and Resonance
counters, ordnance count, hull/evasion frames, and the music toggle
(click + wheel, mouse-only). Persistent between fights as well.

## 5.14 Fight End - NOT STARTED

Enemy flee (drive-charging warning popup, then "The target has jumped
out."), surrender at low HP (accept/refuse choice popup with rewards),
victory (`oTxtEnemyDestroyed`/`oTxtEnemyCrewKilled` reward popups), and
player death (Phase 11) all route through the standard encounter popup
system - number keys work for choices, reward tiles do not (Phase 7).

---

# Phase 6: In-Run Management Menus

All four are game-pausing overlays (`menu_create`), pure pointer
interfaces: no focus, no arrow keys, no keyboard activation; Escape closes
(and the bound toggles reopen). Item manipulation is click-to-pick-up /
click-to-drop via a cursor-following `oUIDraggedCargo`; hit-testing is
invisible collision boxes. Numbers, names, and bars are raw drawn text.

## 6.1 Crew Menu (menuToggle 1) - NOT STARTED

`oMenuCrew`: portrait bar (paged; wheel or arrows cycle; press-hold-drag
reorders), and a detail card per selected crew: editable name box (the
game's one real text field family), HP/DPS/TYPE stats, a color-bucketed
effects/keywords text block, four typed equipment slots (armor, weapon,
tool, psychic). Right-click a portrait opens the armament menu;
right-click a slot unequips; a Dismiss button (confirmation-guarded)
deletes the crew and their items. No XP/leveling system exists - crew are
stats + equipment + innate keywords.

## 6.2 Cargo Menu (menuToggle 2) - NOT STARTED

`oMenuCargo`: cargo row (4 slots, ship weapons + missile templates) and
equipment row (8 slots, crew items) from `oPlayerInfo`. Drag to move/swap;
drag onto the discard box **permanently deletes with no confirmation**;
right-click equips onto the selected crew. New-item badges clear silently
on hover. When loot arrives with full cargo, a modal red overflow grid
(`oUIOverflowGrid`) forces drag-or-discard resolution - drag-only.

## 6.3 Armament Menu (menuToggle 7) - NOT STARTED

`oMenuArmament`: hardpoint row (slot order = combat hotkeys, letters drawn
on the slots), 3 module slots, and - via the missile toggle button - the
active missile-template row. Equip/swap by drag; right-click unequips
(sells when a shop is open).

## 6.4 Upgrade Menu (menuToggle 4) - NOT STARTED

`oMenuUpgrade`: buttons per installed system/subsystem with stacked level
bars and next-level scrap cost ("MAX" at cap), plus the reactor grid.
Left-click queues a level, right-click refunds, Confirm applies, Undo
zeroes; Escape auto-undoes. All in Draw events, pure mouse.

## 6.5 Items, Keywords, and the Tooltip System - NOT STARTED

Items (`oItemWeapon/Armor/Tool/Psychic`, ship weapons, modules) expose
name, description, type, prices, charges, and lore through
`item_get_info`/`ability_get_info`/`keyword_get_info` and the description
generators - all flat, markup-free strings, reconstructable without
scraping the draw layer (the same pattern the mod already relies on).
Tooltips are hover-spawned panels (`oUITooltip`, sectioned
`oUITooltipSection` children) and are the ONLY place most names, stats,
prices, and keyword text surface. Keywords (184 `oKW*` objects) appear as
colored description lines inside crew tooltips; they have no drill-in.

## 6.6 Currencies - NOT STARTED

Scrap Metal (run currency) and munitions/missiles as top-bar counters
(raw text + icon, red at zero, hover tooltip); Resonance as the
meta-currency counter. No fuel resource exists.

---

# Phase 7: Encounters, Rewards, and Mid-Run Popups

## 7.1 The Encounter Popup - NOT STARTED

The single presentation frame for all text events, fight intros/ends,
surrenders, tutorials, story triggers, and confirmations-in-prose:
`oPopup`/`oPopupGroup` rendering a data-only `oEncounter` instance
(~3,300 `oTxt*` objects; queue owned by `oPopupManager`).

- Body text (optionally centered/italic, optional commander/NPC
  portrait), then a numbered choice list ("1. ...", "2. ..."). All raw
  drawn text over invisible hit boxes.
- **Native keyboard exists here**: number keys 1-9 pick choices, honoring
  requirement gating. Mouse hover + click equally works. Escape does NOT
  dismiss - it opens the pause menu.
- Choice states carried in data: removed entirely (unmet condition),
  greyed (unmet grey-condition or unaffordable scrap cost), bonus-colored.
  Every encounter has at least a "Continue".
- Choices chain to follow-up encounters; text is localized flat strings
  with only pre-resolved placeholders (no markup - confirmed for speech).

## 7.2 Reward Panels - NOT STARTED

`oPopupRewardPanel`/`oPopupRewardEntry` tiles under the popup: fixed
rewards (granted automatically, informational tiles) or choose-one
rewards - **picking a reward tile is mouse-only**, unlike the choice
list. Tiles are icon + raw label ("3x Scrap", "Module: ...", "Crew lost:
..." for negative outcomes in red), details hover-only. Weapon/item
overflow opens the drag-only overflow grid (6.2); module overflow becomes
a replace/discard encounter with the module list drawn for selection.

## 7.3 Story Triggers and Vaults - NOT STARTED

`oPopupTrigger`/`oTrg*` are invisible state-watchers (commander HP
thresholds, crew death, first boarding...) that queue ordinary encounter
popups - nothing extra to surface beyond the popup itself. Vaults
(`oSysVault*`) are enemy-ship subsystems looted by crew contact,
destruction, or teleport; the loot arrives as a standard reward popup.

## 7.4 The Shop (menuToggle 3) - NOT STARTED

`oMenuShop` overlay at merchant nodes, merchant-typed stock (Weapons
Dealer, Ordnance Expert, Shaman, Mercenary Broker, Mechanic): a paginated
3x3 grid, one category per row with raw-text divider labels. Each entry
(`oUIShopEntry`) shows icon + price + stock count; full name/description
hover-only; dimmed with a reason string when unbuyable. Left-click while
hovering buys. Fixed side buttons: Repair 1 / Repair Maximum / Munitions /
Replenish Artillery / Medkit, each with price, tooltip, stock, and inline
error strings. Selling = Left-Alt + right-click on inventory items, or
right-click unequip while the shop is open. **Entirely mouse-driven.**

---

# Phase 8: Shipyard and Special Nodes - NOT STARTED

Shipyard nodes run through encounter popups (`oTxtShipyard_*`: hull
repair, services) rather than a dedicated screen; faction shrines and
planet nodes likewise. Merchant "Current Stock" summaries appear in the
map-node hover tooltip before jumping (Phase 9).

---

# Phase 9: Run Navigation (Maps and Jumping)

## 9.1 Jump Button and Drive Charge - NOT STARTED

`oUIJumpButton` (top bar) is the single entry to the map flow and has a
bound key (`toggle_map`, Tab). Gated on drive charge full, a manned
command throne, powered engines, commander aboard, no popup open, not at
the final boss. Every blocking reason and the charge percentage exist
ONLY in its hover tooltip ("Subspace Drive Charging... Charge Progress:
N%", "Command Throne Unmanned", "You cannot escape fate."). The drive
charge widget flashes red icons when the throne/engines block it.
Jumping with crew on the enemy ship raises a covered confirmation
dialogue. No fuel, no per-jump cost, no pursuing fleet.

## 9.2 Local Map (menuToggle 5) - NOT STARTED

`oWMNodeGen`: a left-to-right column graph of nodes for the current
sector. Node types: hostile/neutral/empty fights, Miniboss ("Major
Threat Detected"), Shipyard, five Merchant flavors (tooltip lists current
stock), planets, shrines, the Stargate exit, and the final-boss "Vault of
Souls". Current position, connections, visited marks, weather-warning
icons, and quest labels are all sprites; **every node identity and
weather warning lives in the hover tooltip only**. Jump = click a
connected next-column node. Panning: wheel, drag, or arrow buttons;
close/center/go-to-end buttons; Escape closes. Sector name is drawn on
the map. No keyboard node navigation of any kind.

## 9.3 Sector Map (menuToggle 6) - NOT STARTED

`oWMGalaxyGen`: six columns of sector nodes (a run is 6 sectors), factions
bucketed into Neutral / Warzone / Exclusion Zone (legend drawn as raw
text). Unvisited sectors show only their category; names and descriptions
appear on hover for reachable next sectors. Choosing the next sector =
click, only from the sector's last column. The final column is always the
boss sector.

## 9.4 Warp, Rest, and Autosave - NOT STARTED

On jump: warp VFX, then automatic rest-heal ("Rest" floating text;
"Cannot rest" when blocked by boarders/hazards/keywords) and oxygen
replenish, the next encounter fires, and the game silently autosaves
(single slot, no indicator; the save blanks at the moment of death).
Sector number/jump count are never displayed anywhere in-run.

---

# Phase 10: In-Game Pause Menu - DONE

`oMenuPause` (menuToggle 8), via Escape or the top-bar button: Resume,
Hangar (reset to ship select), Restart, Settings, Main Menu - plus Skip
Tutorial during the tutorial. All spawned `oButton_menus` widgets; the
destructive ones raise covered confirmation dialogues. The mod covers the
menu; the confirmations are covered by the generic confirm screen.

---

# Phase 11: Run End - NOT STARTED

- **Defeat**: "You died." / "Your ship has been destroyed." encounter
  popup (number-key "Continue" works); the autosave is already deleted at
  that point. Continue opens `oEndGameStats`.
- **Victory**: credits roll first, then `oScoreScreen` ("Victory",
  score, surviving crew portraits with hover-only score tooltips;
  left-click continues).
- **End-game stats** (`oEndGameStats`): multi-page raw-text summary
  (score breakdown + the full run-stats sheet), mouse-only page controls,
  and Hangar / Main Menu / Restart buttons.
- Resonance earned, unlock toasts (3.5), and archive write-out happen
  here.

---

# Phase 12: The Input Layer (Reference)

What the game itself provides, for the mod's suppression and binding
design (`scrKeybinds`; all rebindable; keyboard binds self-suppress
during text entry, mouse binds do not):

- Space pause/command mode (middle-mouse alternate), Tab map, L loadout,
  U upgrade, Backspace descriptions/encyclopedia, Z/X open/close all
  doors, Backslash save stations, Enter return to stations, F1 select
  commander.
- A/S/D/F/G power systems 1-5; Q/W/E/R power+arm weapons 1-4; T/Y missile
  bays; I/O siege beam/bombard; J hull reaper; M terror amplifier; H husk
  rack; P thrall pit; B shield charger; N graviton; K auto-surgeon;
  Shift+key removes power.
- 1-9,0,minus,equals crew control groups (Ctrl+key assigns).
- Escape (hardcoded everywhere): back/close/pause-menu; number keys 1-9 on
  encounter choices; Up/Down scroll on announcements and credits;
  Left/Right hull cycling on ship select.
- Text fields (click-to-focus only): crew rename x2, commander name, ship
  name. `global.textFieldInputEnabled` gates keybinds while typing.
- Gamepad/Steam Input: vestigial demo code only; no real controller
  support.

Mouse-only interaction classes with no keyboard path (the mod's core
work): all spatial picks (crew selection/movement, weapon/ability/boarding
targets, map nodes, door clicks), all item manipulation (pickup/drop/swap/
discard/overflow), shop buying, reward-tile picking, menu/button clicking
outside the covered screens, hover tooltips as sole information carriers,
scroll surfaces (map pan, portrait bar, shop pages, volume), and text-field
focusing.

---

# Phase 13: Consolidated Inventory

## 13.1 Full-Screen or Modal Surfaces

Main menu (DONE), announcements popup (DONE), settings (DONE), configure
keybinds, confirmation dialogues (DONE), language menu (DONE), run
archives, rankings, achievements, credits, commander select, ship select,
ship list overlay, tutorial plates, pause menu (DONE), crew/cargo/armament/
upgrade menus, shop, local map, sector map, encounter popup + reward
panels, overflow grid, load-ordnance panel, end-game stats, score screen.

## 13.2 Persistent HUD

Top bar (jump button, drive charge, scrap/Resonance/ordnance counters,
hull HP + evasion for both ships, menu buttons, music control), systems
bar + reactor pips, weapons row, crew portrait bar with ability buttons,
warning flashers, unlock toasts, floating combat text.

## 13.3 The Ship World

Cells (system identity, oxygen, fire, breach, poison, vision), doors and
airlocks, crew sprites with HP bars and status icons, shield bubbles,
projectiles, boarding sleds, weather effects, boss telegraphs.

## 13.4 Cross-Cutting Facts for the Mod

- Raw drawn text + invisible hit boxes is the norm; real widget objects
  exist only for the settings family, menu buttons, keybind rows, and
  dropdowns (the generic adapter's home turf).
- Hover tooltips are the sole carrier of most names, numbers, and
  reasons; several values (shield layers) exist nowhere as text.
- Native keyboard islands worth reusing: encounter number keys, the
  rebindable action set, Escape semantics, control groups, stations.
- There is no combat log to read - an event feed must be synthesized.
- Localization gaps in the game itself: ship purchase dialogue,
  "Additional Equipment:", ability error floaters and tooltip
  instruction lines are hardcoded English.
- Rooms are nameless in data; room speech must be synthesized from
  `cell.system.name` plus position.
- Silent-by-design behaviors to watch: hover clears "new" badges, the
  discard box deletes without confirmation, autosave is invisible,
  unlock toasts time out.

---

*End of Document*
