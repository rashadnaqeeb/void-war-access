# Ship layer accessibility plan

The plan for making the in-run ship screen playable: how a blind player
perceives the two ships, selects crew, and issues orders. This is the
build-to document for the ship layer; each piece below is built one at a
time, in the order given at the end. Once a piece is built, its script
header becomes the authoritative spec and this document's section for it
is history.

Out of scope for now, deliberately: the top-bar buttons and their menus
(upgrade, loadout, encyclopedia, escape - the overlay-menu framework will
cover them later), the local/sector map screens, weapon targeting, and
the audio/earcon implementation (interface stubbed here, library chosen
later).

## Verified game model (what everything below builds on)

All verified against the decompile; identifiers are real.

The ship is a graph the game already maintains. Rooms are `oCell`
instances (subclasses Single 1x1, Wide 2x1, Tall 1x2, Large 2x2 on a
36px grid). Each tile of a cell is one crew slot; slot world coordinates
are `slot1x/slot1y..slot4x/slot4y`, and each slot holds a length-2
occupancy array `occupantNID` - index 0 the allied channel, index 1 the
hostile channel, so a boarder and a defender share one slot. Each cell
caches, built once at room init and never changed mid-run:

- `sideData`: one struct per edge - the edge instance (`oWall`, `oDoor`,
  or `oAirlock`) and the neighboring cell across it, or -4 for none.
- `connectedCellList`: neighbors reachable through a door (the
  traversable graph); `adjCellList`: all touching neighbors; `doorsList`:
  doors and airlocks on this cell.
- `system`: the overlapping `oSysGroup` (0 = empty room), with
  `sysConsoleSlot` (0 = none) naming the manning slot.

Topology is immutable for the whole run - nothing creates or destroys a
cell, door, or airlock mid-run. State changes only: doors have `state`
(0 open, 1 closed, 2 battered open at 0 HP until repaired) and `cell1`/
`cell2` refs; per-room state is `currOxygen`/`maxOxygen`, `vacuum`,
`lethalVacuum`, `isPoisoned`; fire and breach are per-slot instances
(`oFire`, `oBreach`, capped one each per slot) with `onFire`/`breached`
as cell rollups. Live crew per cell: `crewInCell_player/enemy/all`
ds_lists, rebuilt every ~10 steps; accessors in `scrShipCells`. That
throttle means occupant-reporting sections and backends prefer direct
queries (crew instance positions, the `occupantNID` arrays) over the
lists wherever a ~10-step lag could speak stale.

Two UI-instance traps recorded for later pieces (toolbar work, not this
plan): the system power icons (`oSysUI`) are destroyed and recreated on
every jump re-init, and crew portrait instances are rebuilt on page
changes - those instance ids are never stable; re-resolve from
`oUISystemPower.systemList` / `oUICrewPortraitManager` at speak time.

Both hulls share the screen (player left, enemy right) but have separate
lattices. Player-ship instances are persistent and survive jumps (a jump
is a literal `room_goto`); the enemy hull is fresh instances every
encounter. `get_hull(1)` is the player hull, `get_hull(0)` the enemy;
`global.drawEnemyBox` says whether an enemy is engaged.

Visibility is strictly per room, on `cell.playerHasVision`, recomputed
every step from two globals: own rooms need own sensor level >= 1,
enemy rooms need sensor parity (`sensorLevel_matches_enemy()`), and a
room holding your own crew is always visible. Enemy geometry, and which
room holds which enemy system (with damage state), are visible whenever
the enemy is engaged - `cell_object_visible` checks only
`enemyCellsVisible`, not parity. Only room interiors (crew, fire,
breach, poison) sit behind `playerHasVision`.

Orders: the destination IS the order. A movement order carries only a
target cell and reserved slot; on arrival crew drop to idle, and idle
re-evaluates a fixed priority ladder against where they stand: melee if
an enemy shares the slot, ranged if hostiles share the room, extinguish
if the own-side room burns, attack the system if standing in an enemy
room with a living system, repair if the own room's system is damaged or
the room breached, man the console (or throne) if standing on the
console slot. Extinguish, repair, and manning fire only at the ordered
destination (`crew_has_reached_destination`). Door battering triggers
automatically when a closed enemy door blocks a path. The functions:
`crew_move_set_target(crew, cell)` (auto-picks nearest vacant slot),
`crew_move_set_target_slot(crew, cell, slot, clearOld)` (precise), then
the game starts the walk - deferred automatically while paused, which is
how order queueing under command mode works. Selection truth is
`oUICursor.currSelected` (a ds_list), fed by `select_crew(crew)` /
`deselect_all_crew()`, eligibility allied and not friendly-AI.

The game's own ship-layer keyboard is extensive - the full verified
inventory is its own section below. The input layer's default-deny
game-key gate (scrVwaInput) has every one of these defaults off; the
inventory documents what each binding did, so the functions worth
keeping can come back rebound - a mod action on a key of our choosing
that calls the game's own built-in function (the same code path the
original binding ran), never a reimplementation and never a gate
allowance.

## Game key inventory (verified against the decompile)

Everything the game reads at the ship layer, from
`keybinds_init_default` in `scrKeybinds` plus the raw reads outside the
registry. All registered bindings are rebindable in the game's own
keybind menu and flow through `input_check*` (which returns false while
a game text field is up or `global.menuToggle == 14`, the keybind
screen). Default keys given; the mod action list mimics these actions
whatever keys they end up on.

Pause and screens:

- Space (`toggle_command_mode`) and middle mouse
  (`toggle_command_mode2`): toggle pause / command mode
  (`oGlobal.manage_pressSpaceToPause`; gated during tutorial and warp).
- Tab (`toggle_map`): opens the local map, but ONLY while the jump
  button is active (drive charged and `global.playerDriveActive`);
  while a map is open (`menuToggle` 5 or 6) Tab closes it. Otherwise
  the key does nothing.
- L (`toggle_loadout_panel`) / U (`toggle_upgrade_panel`): open, close,
  or cycle to the loadout / upgrade menus
  (`oUITopBarButton.keybind_to_openMenu`).
- Backspace (`toggle_descriptions`): toggles encyclopedia mode
  (`global.enableEncyclopediaMode`). Shipped-game quirk, verified: the
  escape button (`oUIEscapeButton_Step_0`) listens to this SAME binding
  and opens the pause menu, so one Backspace press does both.
- Escape: raw `vk_escape` in `oPopupManager.manage_escape_popup` opens
  the pause menu (guarded on no popup/menu/warp); menus and popups have
  their own Escape handling.
- F1 (`select_commander`): deselect all, select the commander crew
  (`oCrewPortraitPlayer`).

Crew and doors:

- Enter (`return_to_stations`): send all crew to saved stations
  (`oUIStationsReturn`, active only when stations are saved).
- Backslash (`save_stations`): save current stations (`oUIStationsSave`).
- Z (`open_doors`) / X (`close_doors`): open/close ALL allied doors
  (`oSysDoorControl`). Individual door toggling is mouse-only (click,
  guarded by door control powered OR allied crew nearby; calls
  `door_open`/`door_close`).
- 1-0, minus, equals (`crew_management1..12`): control groups. Plain
  press selects the stored group (deselects all first; a group is a
  single crew, a crew array, or a crew ABILITY - selecting an ability
  group triggers it through its portrait button). Ctrl+key with crew
  selected assigns the current selection to that key
  (`oUICursor.controlGroup_assignMultiple`). Hovering a portrait's
  ability button and pressing a key binds that ability
  (`oCrewPortraitButton.assign_shortcuts`). Assign wins over select
  within a frame (`global.controlGroupAssignedThisFrame`).

Power and weapons (all in `oSysUI.detect_shortcut_keys`,
`oUIWeaponButton_Draw_0`, and `scrQueueWeapon`; for every key here,
holding Shift REMOVES power instead of adding):

- A (`power_shields`), S (`power_engines`), D (`power_oxygen`): add one
  power bar to that system.
- F (`power_system4`), G (`power_system5`): add power to the systems at
  tray positions 4 and 5, whatever they are on this hull
  (`sysPositionNumber`), not fixed systems.
- Q/W/E/R (`power_target_weapon1..4`): weapon slot keys. Unpowered
  weapon: powers it. Already powered: starts targeting
  (`hull.clickWeapon[i]`). Shift+key: unpowers.
- T (`power_target_missile_bay`) / Y (`power_target_missile_bay2`):
  same power-or-target pattern for the first/second ordnance bay.
- I (`power_target_siege_beam`), O (`power_target_siege_bombard`),
  J (`power_target_hull_reaper`), M (`power_target_terror_amplifier`):
  power-or-target for those siege/special weapons.
- H (`power_husk_rack`), P (`power_thrall_pit`),
  B (`power_activate_shield_charger`), N (`power_activate_graviton`):
  power/activate those systems.
- C (`launch_bay_launch_sled`) / V (`launch_bay_load`): boarding system
  - launch the assault sled / load selected crew into the launch bay
  (fire the system UI's own buttons, only while those are active).
- K (`auto_surgeon_activate`): fire the medbay's auto-surgeon button.

Held modifiers (raw reads, not rebindable):

- Shift: unpower variant of every power key, as above.
- Ctrl: control-group assign, as above.
- Left Alt: inverts crew-movement precision mode while held
  (`oUICursor_Step_1`: the `global.togglePreciseCrewMovement` setting
  picks the default, Alt flips it; precision mode is slot-precise vs
  room-level move orders) and suppresses system-icon hover tooltips.

Everything else `keyboard_check` touches in gameplay objects is behind
`global.enableDebugKeys` / dev-mode guards - not player-facing.

Mouse verbs (the action vocabulary our tools must cover, not keys to
rebind): left click / drag-box selects crew; left click activates UI
buttons, toggles a door, adds power to a system icon, powers or targets
a weapon; right click issues the move order for the selection
(`oUICursor_Step_0`) and removes power on system/weapon icons; middle
click is the alternate pause bind. There is no additive
shift-click selection and no mouse-wheel action at the ship layer.

## General status surfaces (verified against the decompile)

Every ship-global or run-global status the sighted player can see on
the in-run screen - the inventory a status-review facility must cover.
Per-crew, per-weapon-detail, and per-room surfaces are out of scope
here (the crew sheet and cursor sections carry those). How these get
exposed - dedicated status keys vs a review ring vs a status screen -
is an open decision below. Architecture note: most of these draw in
Draw_0 via a `draw()` method defined in their Create event; there is no
single HUD controller object. Player and enemy readouts are the SAME
objects instantiated per hull, switched on `hull.allied`.

Player ship:

- Reactor power: `scrDrawTotalPsi` (called from `oUISystemPower`
  Draw_0) - `hull.availablePsi` filled of `hull.maxPsi` pips.
- Hull integrity: `oUIHullHP` inside the `oUIHullFrame` container -
  `currHP` of `maxHP` blocks, warning flash at or below 33 percent.
- Shields: `oUIShieldCounter` - `currShieldStrength` bubble pips of
  `floor(maxShieldHP/2)`, plus a regen progress bar
  (`regenTimer/regenTime`). Exists only when the shields system does.
- Evasion: `oUIEvasionCounter` - `hull.evasion` percent; red/flashing
  when engines are destroyed.
- Jump drive charge: `oUIDriveCharge` over the jump button -
  `currDriveCharge` 0 to 1, with red-flash states for throne unmanned
  and engines unpowered; hidden once charged and active.
- System power icons: `oUISystemPower` spawning one `oSysUI` per
  installed system (the known re-created-every-jump instance trap).
- Boarding capacity: `oPassengerCounter` - loaded crew n of
  `crewCapacity`, only when a boarding system exists.
- There is NO ship-global oxygen readout: `oUIOxygenCounter` exists in
  the object table but is never instantiated (dead). Oxygen surfaces
  only per room and through the warning flashers.

Enemy ship (all only while `global.drawEnemyBox`):

- `oEnemyBox`: enemy hull name plus hostility state - Friendly /
  Hostile / Disabled from `hull.currEnemyState` (Disabled doubles as
  the surrender state; there is no separate surrender banner). Fort
  enemies add an infiltrator status line (none deployed / undetected /
  detected).
- Enemy hull HP, shields, evasion: the same `oUIHullFrame` /
  `oUIHullHP` / `oUIShieldCounter` / `oUIEvasionCounter` objects with
  `hull.allied` false; hidden when the enemy is destroyed or fled.
- Enemy system tray: `oUIEnemySystemTray` spawning
  `oUIEnemySystemIcon` per enemy system; gated on sensor visibility
  and `global.toggleEnemySystemTray`.
- Enemy jump charge: `oUIEnemyDriveChargeCounter`, spawned only while
  the enemy drive is charging
  (`oPopupManager.enemyWarpDriveChargeTime/Max`) - the "they are about
  to escape" bar.
- Enemy weapon bar: `oUIEnemyWeaponBar` - incoming weapon charge
  icons. Borderline per-weapon; listed because it is the only warning
  of incoming fire.

Resources and run status (top bar):

- Scrap: `oCounterScrap` - `oPlayerInfo.currScrap`.
- Missiles/munitions: `oCounterMissiles` - `oPlayerInfo.playerMissileCt`,
  drawn red at zero.
- Sensor status: `oCounterSensor` - active / jammed / disabled text
  (the thing that drives enemy interior visibility), with own-vs-enemy
  sensor strength in its tooltip.
- Meta currency: `oCounterMetaCurrency` - `global.currMetaCurrency`.
- Crew log counter: `oCounterLog` - niche, conditional.
- Verified absences: no fuel resource exists; no sector/beacon,
  difficulty, or score readout on the ship screen (those live on the
  map screens).

Alerts and banners:

- `oUIWarningFlasher`, one instance per active condition, `type`
  strings verified: `hull` (crossing 75/50/25 percent and critical),
  `boarders` (intruders detected), `oxygen` / `oxygenUnpowered`,
  `shields` (shields destroyed), and the weather hazards `fire`,
  `warpFire`, `poison`, `ion`, `demon`, `boss` (spawned from
  `scrWarningFlashers`, `oUIShieldCounter`, and `oWeather`/
  `oBossWeather`). These are the game's own model of "what deserves an
  interrupt" - the natural seed list for spoken alerts.
- Command mode banner: `oUICommandMode` - flashing COMMAND MODE text
  while paused with an enemy present.

Top-bar controls (buttons, for completeness; their menus are the
overlay-menu framework's job): loadout (`oUIArmamentButton`, with a
new-item badge), upgrade (`oUIUpgradeButton`), game menu
(`oUIEscapeButton`), encyclopedia toggle
(`oUIEncyclopediaModeButton`), jump (`oUIJumpButton`), and the missile
autofire toggle (`oButton_missileToggle`) - that last one is a
gameplay control, not a menu.

## The substrate: ship-layer mode and per-ship focus

BUILT (piece 1): the authoritative spec is now scrVwaShipLayer's header
(mode predicate, per-hull containers, geometry index, focus toggle) plus
the mode-provider model in scrVwaInput's header. The hull containers are
where pieces 4-5 add their per-ship state (scanner position, pending
selection corners). This section is history.

## Tool 1: the cursor

BUILT (pieces 2-3: movement, edge rules, the section composer, the full
section set, visibility gating, and the where-am-I / details keys;
scrVwaShipLayer's header is the authoritative spec, vwa_dev_shipwalk the
live sweep). Decisions settled at build: spoken coordinates are signed
x/y from the hull's bounding-box center (x right, y UP, bare values
with a localized minus word - "minus 4, 1"); the door-speech interim is
every door state speaking its own short token (open/closed/battered);
where-am-I is K and details R (letters are status keys in this mode;
piece 7's key map decides around them); oxygen speaks only when below
full, with vacuum/venting/poisoned state tokens; the dark-room token is
a bare "unknown", speaking at cell granularity (entering a dark room,
not every step inside it); the selection-marker section shipped here,
reading oUICursor.currSelected live. The spoken order was settled in
play with Rashad (criticality behind the name anchor): system name
first as the room's identity, then hostile count, hazards, air, shape,
own-crew count, then the slot facts with hostiles before own crew, and
coordinates always last - empty sections are silent, so alarms cost
nothing in calm rooms. The full section list, movement and edge rules,
composer contract, and visibility gate live in the script header. This
section is history.

## Tool 2: the scanner

BUILT (piece 4: backends, snapshot, category/item/instance browsing,
jump, orient, pre-jump return, and Ctrl+F search; scrVwaShipScan's
header is the authoritative spec, vwa_dev_shipscan the live check).
Decisions settled at build: keys are Ctrl+PageUp/PageDown for
categories, PageUp/PageDown for items, Alt+PageUp/PageDown for
instances, Home jump, End orient, Backspace pre-jump return, Ctrl+F
search (chosen with Rashad); the four v1 categories shipped
(doors/airlocks as a fifth stays an in-play decision below); instance
position "n of m" speaks only when an item has more than one instance;
the category cycle skips empty categories (revised in play: nothing in
them means not discoverable; a category that empties mid-browse still
answers "empty"); offsets speak as one phrase, always vertical then
horizontal ("2 up 1 right"). The refresh model (revised with Rashad
at build): every browse key rebuilds the snapshot from live backends
and re-seats the browse on the same entity by a stable per-entry key
with the sort origin preserved, so new and dead things are always
current and a resort never moves the browse; the category cycle is the
explicit reorient. Ctrl+F search: a committed query filters the live
entry list through the scrVwaSearch tiered matcher into a frozen
single-category snapshot the normal keys browse, exited by the
category cycle. The backend contract
(identity-only scan, resolve as the one source of location/detail),
visibility gating, deterministic sorting, and the speak-time staleness
pruning live in the header. This section is history.

## Tool 3: selection

A pure rectangle module plus a thin application layer.

The rectangle machinery: two presses of the corner key define a
rectangle in tile space; multiple rectangles accumulate (two separate
clumps of crew); a single-cell select exists for the degenerate case;
excluding a cell decomposes its containing rectangle into up to four
sub-rectangles; a clear-at-cursor removes the last rectangle covering
the cursor; clear-all resets. No hollow rectangles - that served
another game's build tools. This module is pure geometry over tile
coordinates: no game reads, fully unit-testable on fixtures.

Application: on completion, rectangles are an input method, not a
parallel selection model. We walk the focused hull's crew, test each
crew's world position quantized to a tile against the rectangles
(mirroring the game's own drag-box, which rectangle-tests crew sprites -
a mid-walk crew occupies no slot and must still be selectable), and call
the game's own
`select_crew` for each eligible one (allied, not friendly-AI - the
game's own predicate), after `deselect_all_crew()` unless adding. The
authoritative selected set remains `oUICursor.currSelected`; the game's
portraits and order paths stay in sync for free, and there is nothing to
cache. The cursor's slot-level selection-marker section reads
`currSelected` live, so browsing tiles reports "selected" truthfully.

Selection works identically on the enemy ship view: your boarders are
allied crew standing in enemy rooms, and the same rectangle - and the
same order functions, which check same-hull between crew and target -
manage them there.

Selection-adjacent gestures (select whole room's crew, select crew at
cursor slot, additive modifiers) are an open decision, settled together
with the order keys.

## Orders (thin dispatch layer)

Because arrival behavior is automatic, ordering reduces to:

- Send, with the governing principle: fine-grain slot order when the
  game allows it, room order when it doesn't. A single selected crew
  sends to the cursor's exact slot via `crew_move_set_target_slot` when
  that slot is vacant, falling back to `crew_move_set_target` (room,
  auto-slot) otherwise; a multi-crew selection always sends room-level -
  the exact flow the game's right-click runs, including per-crew
  reachability checks and slot reservation.
- Send-to-console ("man this"): `crew_move_set_target_slot(crew, cell,
  sysConsoleSlot, ...)` when the cursor's room has a mannable system.
  Explicit variant, not an auto-preference - auto-preferring the console
  would make "park a second crewman in the engine room" awkward.
- Door toggle at the cursor's edge: `door_open`/`door_close` behind the
  game's own operational guard (door control powered, or allied crew
  nearby for manual operation), with the guard's failure spoken.
- Everything else (all-doors, stations, power keys, control groups)
  stays the game's own function underneath, rebound as a mod action on
  a mod-chosen key that calls the same built-in the original binding
  ran, documented in the help layer. Which functions earn a key is a
  per-function decision at build time.

All order paths mirror the game's guard order and produce spoken
feedback through the chokepoint (what was ordered, or why it refused).
Orders queue under pause exactly as the game queues them - "pause,
survey, order, unpause" is the intended rhythm of the whole layer.

## Earcon layer

Named audio events through one chokepoint (`vwa_earcon(name)` shape),
failures logged, never silent. Any event whose information exists
nowhere else keeps a spoken fallback so the player is never stranded.

Event sounds, chosen by Rashad from the game's own sound assets (all
six verified present in the game data by asset name):

- wall-block: `vs_ui_click2` - REPLACES the spoken "wall" token.
- airlock-block:
  `clickHiss03b_filtered_EXOSKELETONBluezone_SmartSoundFXPOND5` -
  REPLACES the spoken "airlock" token.
- door-cross, per state: open `sfxDoorOpen_crop`, closed
  `sfxDoorClose_crop`, battered `Metlimpt_Ji_B_03_soundbits` -
  REPLACE the spoken door state tokens (the door channel goes
  audio-only; that open decision is settled).
- scanner wrap: `buttonSmall_doubleClick1_SmartSoundFXPOND5` -
  additive; wrap had no speech, and the scanner's spoken "n of m"
  position stays.
- scanner direction: the ONI-style synthesized tone sequence
  (vertical-then-horizontal, pan and volume coded), AUGMENTING the
  spoken offsets, never replacing them.
- ship toggle: dropped for now.
- selection corner set / rectangle complete: join when piece 6 lands.

Settings-forward shape: the scanner-direction earcon toggle and the
general earcon volume live as mod state written so a future settings
screen (not yet built) can bind them; until then they hold defaults.

Audio path DECIDED (verified live, `vwa_dev_earcon_probe`): native
GameMaker audio, no external library. Tones are synthesized at runtime
in GML - stereo s16 PCM at 48kHz written with `buffer_write`, turned
into a sound asset by `audio_create_buffer_sound` - and played through
the game's own audio system; per-play volume and pitch use the same
`audio_sound_gain`/`audio_sound_pitch` calls the game's `sfx_start`
uses, and pan is baked into the stereo samples as constant-power
left/right amplitudes (the game has no pan function; emitters are not
needed). The probe proved the whole path under the UTMT importer and
this runner: asset length sample-accurate, playback live, free and
re-create clean. Multi-segment earcons (the ONI-style direction
sequence) are baked as one buffer per sequence or scheduled frame-based
from the pump - an implementation choice at build, not a library
question. Earcon volume is NOT multiplied by `global.volumeMax_SFX` by
default (the game's SFX slider must not be able to silence navigation
audio); the earcon volume is its own settings-forward variable, per the
shape above.

## Testing

Pure fixtures in `vwa_dev_selftest`, per the testing rules (behavior,
never content snapshots; expectations derived live).

BUILT (pieces 1-3, in `vwa_test_shiplayer` plus the live
`vwa_dev_shipwalk`): geometry-index building, the focus decision,
movement and edge rules, edge classification, the composer (granularity
dampening, quarantine-on-throw, the visibility gate and token
placement), count wording, the where-am-I read order, and the live
sweep - every tile of the focused hull by real arrow moves, spoken
content verified against a fresh independent resolve, coverage derived
live from the geometry index, cross-checked against the game's own
connectivity lists.

BUILT (piece 4, in `vwa_test_shipscan` plus the live `vwa_dev_shipscan`):
snapshot grouping, sorting and tie-breaks, offset wording, prune
behavior, locate-by-key, and search-group filtering on synthetic
entries; live, a full category lap through the real handlers with every
utterance verified against a fresh compose, every snapshot entry
re-resolved through its own backend right after the rebuild, the vision
gate and per-category totals cross-checked against direct live
enumeration, an identity-preserving refresh check, a verified jump with
Backspace return, and a live search apply and exit.

Still to build with their pieces:

- Rectangle geometry (piece 6): corners, accumulation,
  exclude-decompose, area membership. Live: a rect over known crew
  fixture positions lands exactly those crew in `currSelected`.

All new assertion logic in GML (`scrVwaTest`); the existing three
smokes still gate any framework-touching change.

## Build order

Each piece lands with its selftest fixtures and walker/smoke coverage
before the next starts.

1. DONE - Substrate: mode detection, per-hull state containers, geometry
   index, Tab focus toggle, input category. Deliverable: Tab speaks
   ship names and a stub position; mode suspends/resumes correctly
   around menus, popups, and jumps. (scrVwaShipLayer; verified live
   in-run.)
2. DONE - Cursor core: movement with edge rules, minimal sections (room
   identity, system, plus an every-move position stub). Deliverable: full
   sweep of the player ship by arrows, walls block, doors pass.
   (scrVwaShipLayer; vwa_dev_shipwalk is the live sweep.)
3. DONE - Sections complete: hazards, air, occupants, crew and selection
   markers, console, visibility gating, where-am-I (K) and details (R)
   keys. (scrVwaShipLayer; fixture gating tests in vwa_dev_selftest,
   live coverage via vwa_dev_shipwalk.)
4. DONE - Scanner: backends, snapshot, category/item/instance keys,
   jump and orient. (scrVwaShipScan; fixtures in vwa_dev_selftest, live
   check vwa_dev_shipscan.)
5. Earcon layer: wiring for the events that exist (door-cross,
   wall/airlock block, scanner wrap; ship toggle dropped for now) with
   the chosen sounds, the scanner direction tones, spoken tokens
   removed where audio replaces them (audio path and sound choices are
   in the earcon layer section).
   Pulled ahead of selection and orders (Rashad's call): a
   lot of their decisions rest on what the audio channel can carry.
   Selection events join when piece 6 lands.
6. Selection: pure rect module + application to `select_crew`.
7. Orders: send, send-to-console, door toggle; the key overwrite map
   decided here, alongside the game-hotkey help layer.

## Open decisions

- Key map: which game functions earn a rebound key and where each
  lands (notably return-to-stations, formerly Enter, vs our
  send/activate key). Decided per key during pieces 1 and 7; the full
  inventory to decide over is the key inventory section above. Already
  taken on the ship category: Tab (focus toggle), arrows (cursor),
  K (where am I), R (details), Ctrl/plain/Alt+PageUp/PageDown (scanner
  categories/items/instances), Home (scanner jump), End (scanner
  orient), Backspace (scanner pre-jump return), Ctrl+F (scanner search;
  while its capture is armed, Enter/Escape/Backspace belong to it).
- Status review shape: how the general status surfaces (their own
  section above) get spoken - dedicated keys per status family, a
  single review ring cycled with one key pair, or a status screen on
  the existing screen framework - and which warning flasher types
  earn a spoken interrupt versus review-only. Decided alongside the
  key map.
- DECIDED - Door information channel: audio-only; the per-state door
  sounds replace the piece-2 spoken tokens (earcon layer section).
- Fine selection gestures: room-select, slot-select, additive modifiers
  (piece 6/7 debate).
- Whether doors/airlocks become a fifth scanner category.
- Whether the scanner gets an auto-move option (cursor follows each
  announced entry) in addition to explicit jump; cheap, but changes how
  distance announcements read, so decided in play.
- DECIDED - Audio path for pitch+pan earcons: native GameMaker audio
  with runtime PCM synthesis, no external library (details in the
  earcon layer section above).
