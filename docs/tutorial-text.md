# Void War tutorial text

Every player-facing string in the game's tutorial, extracted from the
decompile (`decompiled/code/gml_GlobalScript_scrTutorial.gml` and the
`oTxtTutorial*` encounter objects). The text is hardcoded English in the
game code; it does not go through the lang CSVs.

The tutorial is delivered as a linear sequence of "plates": small dialog
boxes attributed to a commando named Lyceus (his portrait is drawn on
every plate and on every encounter popup). A plate either shows a
Continue button (label is the game's localized `global.label_continue`)
or auto-advances when the player performs the instructed action. Some
plates hand off to an encounter popup (the story beats below), which
returns to the plate sequence via its own Continue choice.

Plates are listed in sequence order. Encounter popups are inserted where
the sequence triggers them. Auto-advance plates are marked; everything
else waits for Continue.

## Opening

1. "The God-King has fallen. The Empire is in despair. The time is nigh
   for you to be our instrument for salvation. You will now be
   familiarized with the basics of void warfare."
2. "This is your ship."

## Crew selection and movement

3. (auto-advances when the player selects themselves) "As the commander
   of this vessel, you may select any crewmember of the ship, including
   yourself, by clicking their portrait frame. You may also select them
   by clicking on them directly or dragging a box around them. Select
   yourself now."
4. (auto-advances on arrival in the marked room) "While crewmembers are
   selected you may issue commands by right-clicking any of the rooms on
   your ship. Move yourself to the designated room."
5. "The selected crewmember will move to the destination and
   automatically perform any required tasks upon arrival."

## Systems and the reactor

6. "The system control interface allows you to control your ship's
   SYSTEMS. Each system has an icon that corresponds with one on your
   ship."
7. "All of your systems are powered by the ship's REACTOR, which is
   shown here. Each bar represents 1 unit of reactor power. The more
   power a system draws from your reactor, the more effective it
   becomes."
8. "You may hover over any system for more detail. While hovering, a
   reticle appears on your ship showing you the location of each
   system."
9. "These are your ship's SUBSYSTEMS. Subsystems are different from
   normal systems in that they are automatically powered and do not
   consume reactor power."
10. (auto-advances; the count in parentheses live-updates as arrows are
    cleared) "To proceed, hover over each of your ship's systems and
    subsystems. (Remaining: 8)"
11. "This is your ship's hull strength. When this reaches zero, your
    ship will explode, and everyone aboard it will die."

Encounter popup, new crew: "A pair of Imperial Enforcers have joined
your crew." (choice: Continue)

Encounter popup, first fire: "They have arrived in time to assist you
with the fire that has broken out on your ship." (choice: Continue)

## Command mode and firefighting

12. "Time is precious when confronted by hazards like fire. Thankfully,
    you have access to COMMAND MODE."
13. "The COMMAND MODE indicator shows when you are in COMMAND MODE. When
    in COMMAND MODE, all of the action is paused, giving you time to
    carefully examine the situation and queue up any commands you might
    have."
14. "COMMAND MODE represents your ability to think on your feet. It
    allows you to set weapon targets, issue crew orders, allocate
    reactor power, and vent airlocks, all at the same time."
15. (auto-advances when all crew are selected) "The fire needs to be
    extinguished. Select all of the crew on your ship by dragging a box
    around them."
16. (auto-advances when the order is queued) "Send your crew to
    extinguish the fire by right-clicking the designated room. A
    destination marker will appear, but your crew will not begin moving
    yet."
17. (auto-advances when the game unpauses) "Press SPACEBAR to leave
    COMMAND MODE. Your crew will move to extinguish the fire."
18. (Continue button enables once the fire is out) "Sending multiple
    crewmembers will let them accomplish their tasks faster, which helps
    reduce any injuries they might sustain."
19. "You have successfully extinguished the fire."

Encounter popup, second fire: "Unfortunately another fire has broken out
on your ship. This time, instead of sending crew to extinguish the fire,
use your ship's door control system to open an airlock and vent out the
room." (choice: Continue)

## Venting

20. (auto-advances when the game is paused) "First, enter COMMAND MODE
    by pressing SPACEBAR."
21. (auto-advances when the airlock opens) "All doors and airlocks
    aboard your ship can be opened and closed by clicking on them, as
    long as your door control system is powered. Click on the airlock to
    vent out the room and extinguish the fire. Note that doors and
    airlocks will open instantly, even in COMMAND MODE."
22. (auto-advances when the game unpauses) "Leave COMMAND MODE
    (SPACEBAR) and allow the room to vent."
23. "Notice how the room will slowly turn PINK as the oxygen is vented
    out of the room."
24. "A fully vented room will appear with diagonal HAZARD STRIPES. Crew
    inside a fully vented room will lose a portion of their health every
    second as they SUFFOCATE. Suffocation will hurt high HP units more
    than low HP units."

## The command throne and engines

25. (auto-advances when the commander mans the throne) "It is time to
    prepare for subspace translation. Move the COMMANDER to the command
    throne."
26. "Notice how you automatically man the command throne when you
    arrive."
27. (auto-advances when engines receive power) "You will need to power
    your engines before you can engage the subspace drive. Left-clicking
    a system icon will add power. Right-clicking a system icon will
    remove power. Power your engines now."
28. "Notice how power has been removed from your reactor and transferred
    to your engines."
29. "With your engines powered, your subspace drives are now active. It
    is time to engage the drives."

Encounter popup, engines destroyed: "As you prepare to initiate subspace
translation, a sudden energy spike surges through your vessel,
destroying your engines." (choice: Continue)

## Repair

30. (auto-advances when engines are fully repaired) "Your engines are
    now RED, showing they have been fully DESTROYED. You will need to
    repair your engines before you can engage your subspace drives. Send
    someone to the engine room to begin repairing your engine system."
31. "Notice how your engines have automatically powered themselves.
    Repaired systems will automatically power themselves up to their
    last power state, provided there is enough free reactor power."
32. "Now that your engines are powered, you are ready to engage your
    subspace drive."
33. "As the COMMANDER of this ship, you MUST be present aboard the ship
    to engage the subspace drive. You can always identify the COMMANDER
    of a ship by hovering over them and looking for the COMMANDER
    keyword."
34. (auto-advances when the star map opens) "Ensure the COMMANDER is
    manning the COMMAND THRONE, then press the WARP button."

## The star map

35. "This is the star map. It contains all of the jump nodes in the
    current sector. Hovering over a node will display basic information
    about that node."
36. "You can use these controls to navigate the map. You may also use
    your MOUSE WHEEL to scroll the map."
37. (auto-advances when the HOME button is clicked) "When you are ready,
    press the HOME button to center the map on your current location."
38. (auto-advances when the warp begins) "Select a jump node to engage
    your subspace drive."

Encounter popup, combat begins: "The galaxy is filled with hostile
threats. These servo-husks have gone rogue and are threatening to
destroy your ship." (choice: Continue)

Encounter popup, combat continued: "Fortunately their ship's weapons do
not have the strength to penetrate your shields. You will show them the
error of their ways." (choice: Continue)

## Weapons

39. (auto-advances when the game is paused) "Enter COMMAND MODE
    (SPACEBAR)."
40. (auto-advances when the weapon is powered) "Power your weapon by
    clicking on it. You may need to depower other systems (by
    right-clicking them) to free up reactor power for your weapon."
41. (auto-advances when the weapon is armed) "Now that your weapon is
    powered, click on it again to activate it."
42. (auto-advances when the enemy shields room is targeted) "Your weapon
    is armed. Set a target by clicking a room on the enemy ship."
43. (auto-advances when the game unpauses) "Leave COMMAND MODE
    (SPACEBAR) to resume combat."
44. (auto-advances after the shot lands and enemy shields drop) "Your
    weapon will fire as soon as it finishes charging."
45. "The two shots from your cannon cannot penetrate the enemy's two
    shield layers. You will need some help to overcome the enemy."

## Boarding

46. "Your ship is equipped with a launch bay system, which will allow
    you to conduct boarding operations against the enemy ship."
47. "Crew loaded into this system will be delivered in an assault sled.
    The assault sled is designed to penetrate all enemy shielding before
    crashing into the enemy ship."
48. (auto-advances when crew reach the launch bay) "Send your crew to
    the launch bay."
49. (auto-advances when the game is paused) "Launching an assault sled
    is multi-step task, so it is a good idea to enter COMMAND MODE
    (SPACEBAR)." [sic, "is multi-step task" is the game's own typo]
50. (auto-advances when crew are loaded) "Click the LOAD CREW button to
    send your crew into the launch bay."
51. "Crew loaded into the launch bay are hidden from view inside the
    ship. They are shown in the small counter at the top of the launch
    bay system."
52. (auto-advances when the sled launches) "Click the launch button, and
    target the enemy's shields room to launch the assault sled."
53. (auto-advances when the game unpauses) "Leave COMMAND MODE
    (SPACEBAR)."
54. (auto-advances when the enemy shields system takes damage) "Your
    crew will now attack the shields room."
55. "Your crew has killed an enemy and damaged the enemy shields system.
    Notice that the enemy shields icon has turned ORANGE. This indicates
    that the system has been DAMAGED. Alternatively, when an enemy
    system is DESTROYED its icon will turn RED."
56. "Your crew will instantly damage an enemy system anytime they kill a
    non-temporary enemy crew in the same room. This is a great way to
    quickly damage enemy systems. Your crew will also attack enemy
    systems if there are no enemies to fight in the room."
57. (auto-advances when all crew are back aboard) "Your boarding action
    has degraded the enemy's defenses. Return your crew to your ship
    using the Recall Crew button. Remember, you risk losing any crew
    aboard the enemy ship if the enemy ship explodes or successfully
    flees."
58. "With a damaged shields system, the enemy can now only recharge up
    to 1 layer of shields."
59. (auto-advances when the enemy ship is destroyed; ends this plate
    block) "Now your cannons will be able to punch through their shields
    and damage their hull. Continue firing at the enemy ship until it is
    destroyed."

Encounter popup, victory (enemy ship destroyed): "The corsair vessel
breaks apart. You salvage some material from the remains. You can hover
over any of your salvaged items for more info." (choice: Continue)

Alternate victory popup (all enemy crew killed instead): "The enemy crew
has perished. You salvage some material from the remains. You can hover
over any of your salvaged items for more info." (choice: Continue)

Both victory popups grant the same rewards (repair drone, cannon, scrap)
and resume the plate sequence at the loadout section below.

## Loadout and equipment

60. (auto-advances when the loadout menu opens) "To view your new
    equipment, click the LOADOUT button."
61. "You have acquired a REPAIR DRONE, which is a piece of crew
    equipment. Crew equipment offers powerful bonuses that can greatly
    enhance the effectiveness of your crew."
62. (auto-advances when the drone is equipped) "Crew equipment can only
    be equipped in slots that match their type. Since your REPAIR DRONE
    is a TOOL, it must be equipped in a TOOL slot. Equip your REPAIR
    DRONE by clicking it and placing it in the appropriate slot."
63. (auto-advances when the second weapon is slotted) "You have also
    acquired a new starship weapon. To equip it, click the weapon in
    your cargo and place it in one of your empty armament slots."
64. (auto-advances when the menu closes) "Close the LOADOUT panel by
    clicking anywhere outside the interface."
65. "Note the total power capacity of your weapons system is not enough
    to power all of your weapons. Your weapons system has a capacity of
    2 power bars, while your two weapons require a total of 3 power to
    operate."
66. "If you want to power both of your weapons, you will need to upgrade
    your weapons system."

## Upgrades

67. (auto-advances when the upgrade menu opens) "Press the UPGRADE
    button."
68. "This is your UPGRADE PANEL. You can spend scrap here to upgrade
    your ship's systems, subsystems, and reactor. Left-clicking a system
    will upgrade it. Right-clicking it will undo any unconfirmed
    upgrades."
69. "It is crucial to keep your systems upgraded as you journey through
    the void."
70. (auto-advances when a weapons upgrade is queued) "Now upgrade your
    weapons system."
71. (auto-advances when the menu closes) "Press the UPGRADE button to
    confirm your upgrades."
72. (auto-advances when both weapons are powered) "Now you should have
    enough weapons system capacity to power all of your weapons. Power
    them up now. If necessary, depower other systems (by right-clicking
    them) to free up power for your weapons."
73. "Your weapons are now fully powered."

Encounter popup, life support destroyed: "A sudden energy spike has
destroyed your life support system. This could be dangerous. Without
life support, the oxygen in your ship will gradually deplete and
eventually suffocate your crew." (choice: Continue)

## Active abilities and the translocator

74. "You can use the REPAIR DRONE you equipped earlier to repair your
    life support system remotely."
75. (auto-advances when life support is fully repaired) "Certain pieces
    of crew equipment such as consumables and psychic powers will also
    grant an ACTIVE ABILITY. These abilities will appear on the portrait
    of the crew they are attached to. Click the REPAIR DRONE ability,
    then target your LIFE SUPPORT system room to repair it."
76. "Your life support system has been repaired."
77. (auto-advances when the commander translocates) "One last thing.
    Your translocator has been enabled. You can use it to board enemy
    ships, escape from a difficult situation, or simply to get around
    your ship faster. Try it."

## Closing

78. "This concludes your training."
79. "As you set out, be on guard against the craven pirate, the dread
    cultist, and the Imperial who yet clings to his fallen deity."
80. "Let none bar your path to the Vault of Souls, for only within its
    argent flames lie our destined salvation from this forsaken realm."
81. (auto-advances when the star map opens; final plate) "When you are
    ready, ensure you are manning the COMMAND THRONE, then press the
    WARP button to continue on with your journey."

## Other tutorial strings

Player death during the tutorial (`oTxtPlayerDeathTutorial`): "You
died." (choice: Main Menu)

Unused in the current sequence but present in the data
(`oTxtTutorialSpawnFire2`): "As you continue to your attack on the enemy
vessel, you hear an explosion echo across your ship. Another fire has
broken out on your ship." (choice: Continue)

An unreferenced lance reward popup (`oTxtTutorialGainLance`): "An energy
lance has been installed on your ship." (choice: Continue)
