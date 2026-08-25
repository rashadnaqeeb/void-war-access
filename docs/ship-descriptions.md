# Ship descriptions (working draft)

Source drafts for the ship-description feature. These are English masters;
they become `vwa--` lang rows (all four languages) when the feature ships.
Derived from `decompiled\ships.json` (tile grids) and the hull sprites in
`data.win` (flavor), sessions 2026-07-26 through 2026-08-08.

## Conventions

- Each entry is two parts, spoken map-first: the map sentence (interior
  tile grid: width, height, symmetry, overall shape), then the flavor
  sentence (hull art: concrete visible features only).
- Orientation is player-relative and authored in bow/stern vocabulary.
  The player's ship sits horizontal, bow-right toward the enemy. Current
  enemy ships sit vertical, nose-up (verified: prow hardpoints above the
  top cell row, thrusters below the bottom row) - enemy entries use
  nose (top) / engines (bottom), and their symmetry axis is side to
  side. Screen directions are derived live at speak time, never stored.
- Symmetry tiers: "symmetrical" (exact top-bottom mirror), "nearly
  symmetrical" (one or two tiles off), "not symmetrical".
- Flavor wording tiers, kept distinct so the listener knows the claim:
  "is X" only when the art literally depicts X (a bone ship's ribs);
  "shaped like X" / "looks like X" for resemblance; otherwise plain
  structure nouns. No "all X, Y, and Z" triads. Every phrase must
  survive "what would I literally see."
- Map facts (width, height, symmetry, connectivity) are derivable live
  from cell instances; when the feature ships, derive them at speak time
  rather than baking numbers into strings (never-cache rule). The shape
  words ("a dumbbell", "twin decks") are authored.
- Disconnected layouts (rare; one live case, the small demon ruin): the
  map sentence becomes "N separate structures", each with size and a
  player-relative position ("nearest you" / "farthest"), top/bottom
  unchanged.

## Player ships

The used roster is the 29 hulls `playerShip_isPlayable` enables (Ship 9C,
11A-C, 12A-C are disabled with placeholder names). Within a family the
variant art is largely a recolor; similar flavor lines reflect that.

### Empire Cruiser

**Triumph of Heaven (A)** - `rmStart_EMCruiserA_gunBoarding`
Map: 14 wide, 6 tall, nearly symmetrical; widest at the stern, tapering
to a point at the bow.
Flavor: The point is an armored ram, gun turrets line the top and bottom
edges, and a tall bridge tower stands over the stern.

**Sunhammer (B)** - `rmStart_EMCruiserB_gunLance`
Map: 14 wide, 4 tall, nearly symmetrical; two solid decks run the full
length, with a block at the stern and scattered single rooms along the
top and bottom edges.
Flavor: Sand-colored plating, a three-pronged lance at the bow, gun
turrets along both edges, a tall tower at the stern.

**Damnatio (C)** - `rmStart_EMCruiserC`
Map: 14 wide, 7 tall, nearly symmetrical; a tall cross of rooms at the
stern, then three parallel decks running to the bow.
Flavor: Dark red and black, with rows of actual carved skulls along both
gun decks and a rounded bow bearing a large skull.

### Raider Arrow

**Mongrel (A)** - `rmStart_RDArrowA_huskRack`
Map: 11 wide, 6 tall, nearly symmetrical; a full-height block at the
stern, twin decks along the top and bottom edges, a solid nose block
between them.
Flavor: Built from welded scrap; the nose is a flat plow blade, and
spikes and scaffolding trail off the stern.

**Pugilist (B)** - `rmStart_RDArrowB_eliteVacuum`
Map: 11 wide, 6 tall, nearly symmetrical; twin full-length decks with
room blocks above and below, and a solid mass at the bow.
Flavor: Welded scrap in dark green, a blunt plow nose, jagged spikes off
the stern, two long guns mounted on top.

**Arm of Gold (C)** - `rmStart_RDArrowC_squishySonic`
Map: 12 wide, 7 tall, symmetrical; two long decks over a broken center
row, with single-room stubs on the outer edges.
Flavor: Welded scrap dressed in gold plate, a blunt plow nose, a comb of
spikes at the stern.

### Plague Ribcage

**Grasp of Ruin (A)** - `rmStart_PLRibcageA_chaosRiftKnight`
Map: 14 wide, 6 tall, nearly symmetrical; a dumbbell, one cluster at the
bow, one at the stern, a thin waist between.
Flavor: Part of the hull is actual bone: pale ribs arch over the waist,
the bow cluster is a rounded bone mass, and the stern cluster is
mechanical engines.

**Corpsemother (B)** - `rmStart_PLRibcageB_spellPoison`
Map: 12 wide, 6 tall, nearly symmetrical; a full-height wall at the
stern, two solid decks running the full length, small blocks at the bow
corners.
Flavor: A boxy armored head at the bow, actual pale ribs across the
midship, machinery at the stern.

**Bonespire (C)** - `rmStart_PLRibcageC_poisonBeam`
Map: 13 wide, 5 tall, symmetrical; one full-length central deck with
short rib rooms paired above and below along it, and a taller stern
cluster.
Flavor: Rust-orange plate with a rounded blunt bow; bare bone and red
growths show through amidships.

### War Freighter

**Cruel Tempest (A)** - `rmStart_WRFreighterA_missileBoat`
Map: 11 wide, 8 tall, symmetrical; compact and blocky, two full-width
decks with short stubs of rooms above and below.
Flavor: Thick angular armor plate in dark red, a short ram at the bow, a
vertical rack of pods behind it.

**Godless Carnage (B)** - `rmStart_WRFreighterB_spellship`
Map: 12 wide, 7 tall, symmetrical; roughly diamond-shaped, widest along
the center row which runs the full length, shrinking toward the top and
bottom.
Flavor: Thick copper-brown armor plate, a short ram bow, a stacked pod
rack behind it.

**Kynagidas (C)** - `rmStart_WRFreighterC_houndBoarding`
Map: 12 wide, 9 tall, nearly symmetrical; a tall middle column of rooms
crossed by two long decks, thinning to single rooms at the top and
bottom points.
Flavor: Thick dark red-brown armor plate, a short ram bow, a pod rack
behind it.

### Raider Long

**Bastard Star (A)** - `rmStart_RDLongA_ionBeamArtillery`
Map: 14 wide, 6 tall, nearly symmetrical; a chain of room blocks from
stern to bow linked by the upper and lower decks.
Flavor: A long industrial barge in layered grey and brown plate, antenna
spikes along the top edge, blunt at the bow.

**Fortressbane (B)** - `rmStart_RDLongB_beamConsumables`
Map: 14 wide, 6 tall, symmetrical; twin decks at the stern leading into
a solid midship block, then a separate bow block joined only by the
middle rows.
Flavor: A long barge in tan and grey plate, antenna spikes along both
edges, a large round port on the stern block.

**Outrider (C)** - `rmStart_RDLongC`
Map: 15 wide, 5 tall, symmetrical; the stern half is repeated
full-height columns of rooms, the bow half two parallel decks meeting at
a single-tile tip.
Flavor: A long barge in steel blue, antenna spikes along both edges.

### Techno Trilobite

**Trilobite (A)** - `rmStart_TCTrilobiteA_abductor`
Map: 12 wide, 9 tall, symmetrical; a rounded block of rooms at the bow,
with a single-tile tail corridor running all the way back to the stern.
Flavor: Looks like a horseshoe crab: smooth shell forward, a segmented
tail covered in long spines.

**Fieldpiercer (B)** - `rmStart_TCTrilobiteB_energistSniper`
Map: 9 wide, 7 tall, symmetrical; a compact block of three full-width
decks with single rooms along the top and bottom edges.
Flavor: One smooth domed shell covers nearly the whole hull, with a thin
needle probe at the bow.

**Null Perception (C)** - `rmStart_TCTrilobiteC`
Map: 8 wide, 9 tall - taller than it is long - symmetrical; three
full-width decks crossed by short connector rooms.
Flavor: A rounded shell studded all over with sensor domes, with needle
probes at both ends.

### Blood Overseer (Ship 7)

**Excrucior (A)** - `rmStart_ship07A`
Map: 13 wide, 9 tall, symmetrical; a full-height mast of rooms near the
stern, a compact midbody, and short spurs at the top and bottom bow
corners.
Flavor: Deep crimson; a thin lance projects from an oval pod at the bow,
and rows of spines run both edges.

**Fleshtyrant (B)** - `rmStart_ship07B`
Map: 13 wide, 7 tall, symmetrical; a tall stern column, a center deck,
and two long arms running to the bow above and below.
Flavor: Crimson and grey; two curved claw slabs close around an oval pod
at the bow, with spine rows along both edges.

**Profane Ecstacy (C)** - `rmStart_ship07C`
Map: 12 wide, 8 tall, nearly symmetrical; a dense oval - two long decks
around an almost solid middle.
Flavor: Pale pink and crimson; curved claws wrap an oval pod at the bow,
and long spikes project fore and aft.

### Ancient (Ship 8)

**Petraglyph (A)** - `rmStart_ship08A`
Map: 15 wide, 5 tall, nearly symmetrical; a single center spine from the
stern with lone rooms alternating above and below, swelling into a solid
block at the bow.
Flavor: Olive-green; the bow is a broad faceted slab studded in rows
like a carved stone tablet, with four turret domes amidships and long
blade masts raking back.

**Carrion Engine (B)** - `rmStart_ship08B`
Map: 13 wide, 7 tall, symmetrical; twin decks running from the stern
into a solid bow cluster, with a short center block midway.
Flavor: Rust-brown; a thin lance runs forward from midship, four turret
domes around it, two long fins swept back from the stern.

**Apocalypso (C)** - `rmStart_ship08C`
Map: 14 wide, 6 tall, not symmetrical; a stern block on the middle rows,
with offset upper and lower decks overlapping toward the bow.
Flavor: Near-black and covered in long raking spikes, with orange embers
glowing across the hull.

### Demon Oblivion (Ship 9)

**Kadkaziel (A)** - `rmStart_ship09A`
Map: 11 wide, 6 tall, nearly symmetrical; a stern block feeding two
solid center decks that run to the bow, with lone single rooms spaced
along the outer edges.
Flavor: The bow half is overgrown with flesh and curved tusks; the stern
half is bare grey machinery.

**Rex Voratores (B)** - `rmStart_ship09B`
Map: 11 wide, 6 tall, not quite symmetrical; the center rows form stern,
midship, and bow blocks in a row, with scattered singles above and
below.
Flavor: Purple-grey; the bow is a scaled, fleshy mass sprouting large
curved horns, with machinery and more horns behind.

### Ship 10

**Ultima Ratio (A)** - `rmStart_ship10A`
Map: 12 wide, 7 tall, symmetrical; two long parallel decks joined by
cross-rooms, thicker toward the stern.
Flavor: Plain industrial plating with hazard stripes; exposed machinery
runs down the centerline.

**Lantern of Ash (B)** - `rmStart_ship10B`
Map: 13 wide, 7 tall, symmetrical; stern corner blocks joined to twin
decks that run out to the bow, with a broken center row between them.
Flavor: Pale grey slab plating with red-painted sections, blocky end to
end.

**Bellerophon (C)** - `rmStart_ship10C`
Map: 13 wide, 7 tall, not symmetrical; full at the stern across all
rows, thinning to an upper deck that runs out to the bow while the lower
half drops away past midship.
Flavor: Blue-grey slabs with yellow gantry scaffolding exposed along the
lower edge.

## Enemy ships

The used enemy set is every room that contains its own placed `oHull*`
instance (the current generation pipeline requires it), excluding
`_oldLayout`, `_MEMTEST`, and the `rmRD_small1_bk` backup duplicate.
The hull-less named rooms (rmWRCruiser, rmEMCutter, ...) are legacy and
excluded. Display names are the game's own `hullName` lang rows. Enemy
ships read nose at the top, engines at the bottom; forts and ruins are
static structures described in screen terms.

### Kromic (War)

**Ruinous Scout** - `rmWR_small2`, model oHullWR_S1
Map: 2 wide, 6 tall; a plain solid rectangle.
Flavor: A narrow brown tower of stacked armor bands, small fins at the
engine end, a red war glyph low on the hull.

**Kromic Interceptor** - `rmWR_small1`, model oHullWR_S2
Map: 3 wide, 4 tall; a ring of rooms around one enclosed empty tile,
with a single tile trailing below.
Flavor: Two large angular wing plates spread upward in a V from a squat
dark body.

**Kromic Corvette** - `rmWR_small3`, model oHullWR_S3
Map: 3 wide, 8 tall; a single-tile spine with a short crossbar near the
engines.
Flavor: A brown armored tower, side pods low on the hull, a red glyph at
the base.

**Kromic Destroyer** - `rmWR_medium1`, model oHullWR_M1
Map: 5 wide, 6 tall; two side columns and a center column tied together
by one full-width row near the engines.
Flavor: Two huge swept wing slabs rise like raised shoulders around a
small central body, lamps at their tips.

**Kromic Cruiser** - `rmWR_large1`, model oHullWR_L1
Map: 6 wide, 6 tall; a solid block with a few interior holes and
notched corners.
Flavor: A broad diamond of layered brown armor, rows of segments down
the middle, a pointed keep at the nose.

**Kromic Monitor** - `rmWR_large2`, model oHullWR_L2
Map: 11 wide, 4 tall - a wide ship; one full-width deck with room
clusters above it and a short tail below the middle.
Flavor: Two huge angled wing slabs flank a central keel, red war glyphs
on their inner faces.

### Imperial (Empire)

**Imperial Corvette** - `rmEM_small1`, model oHullEM_S1
Map: 3 wide, 8 tall; a single-tile spine with a two-row crossbar near
the engines.
Flavor: A pale grey armored tower, stacked gun bands down its length,
flared at the engine base.

**Imperial Strike Craft** - `rmEM_small2`, model oHullEM_S2
Map: 3 wide, 9 tall; one long single-tile spine, a crossbar one row
above the engines.
Flavor: A slim pale tower, twin rails down the spine, side pods at the
flared base.

**Imperial Scout** - `rmEM_small3`, model oHullEM_S3
Map: 3 wide, 8 tall; a single-tile spine ending in a full-width engine
row.
Flavor: A pale keep-like tower over a wider skirted base, fins at the
engines.

**Imperial Destroyer** - `rmEM_medium1`, model oHullEM_M1
Map: 5 wide, 7 tall; a solid midbody flaring from a single-tile nose,
waisted before a full-width engine row.
Flavor: A grey slab-sided warship, gun racks down both sides, a spired
nose.

**Imperial Cruiser** - `rmEM_large1`, model oHullEM_M2
Map: 5 wide, 8 tall; twin single-tile prongs at the nose joining a
solid lower body, one tile centered at the engines.
Flavor: A massive grey block of a hull, stacked deck bands at the nose,
heavy sponson pods along the sides.

### Technocult

**Technocult Scout** - `rmTC_small1`, model oHullTC_S1
Map: 3 wide, 5 tall; a solid nose block over an alternating single-tile
tail.
Flavor: A rounded shell body, twin antenna masts at the nose, two long
fins swept down and outward.

**Technocult Probe** - `rmTC_small2`, model oHullTC_S2
Map: 3 wide, 4 tall; a near-solid block with one enclosed empty tile.
Flavor: Two smooth grey lobes at the center of a dense mechanical
frame, racks jutting from both sides.

**Technocult Hunter-Killer** - `rmTC_medium1`, model oHullTC_M1
Map: 10 wide, 3 tall - a wide ship; one full-width deck with a two-tile
nub on top and rooms at each end below.
Flavor: Two broad shell lobes spread to the sides of a small central
head - wider than it is long.

**Technocult Destroyer** - `rmTC_large1`, model oHullTC_L1
Map: 4 wide, 7 tall; stacked full-width decks separated by narrower
connector rows.
Flavor: A tall oval carapace, smooth shell wrapping the nose, segmented
plates stacked down the body.

**Technocult Freighter** - `rmTC_large2`, model oHullTC_L2
Map: 5 wide, 8 tall; two solid blocks joined by a single-tile neck,
ragged at the engines.
Flavor: A stack of rounded cargo pods like an insect's abdomen, a thin
machine spine down the middle.

**Technocult Cruiser** - `rmTC_large3`, model oHullTC_L3
Map: 3 wide, 9 tall; a solid column with enclosed empty tiles
alternating down its center.
Flavor: A tall shell of two smooth lobes covering the upper body, bare
machinery below.

### Corsair (Raider)

**Corsair Scout** - `rmRD_small1`, model oHullRD_S1
Map: 2 wide, 6 tall; a two-wide column with single-tile bites taken
from each side near the nose.
Flavor: A narrow riveted hull, rounded at the nose, short spars down
both sides.
(The tutorial's **Hijacked Frigate**, `rmRD_small_tutorial`, is this
same layout and art.)

**Corsair Frigate** - `rmRD_medium1`, model oHullRD_M1
Map: 4 wide, 5 tall; a ring of rooms around two enclosed empty tiles.
Flavor: A rounded dome nose over a boxy riveted body, red script
painted down the centerline.

**Corsair Destroyer** - `rmRD_medium2`, model oHullRD_M2
Map: 4 wide, 8 tall; a two-wide spine swelling to a ring of rooms
amidships around two empty tiles.
Flavor: A domed nose, a narrow waist, spars down both edges of the
engine body.

**Corsair Assault Barge** - `rmRD_large1`, model oHullRD_L1
Map: 5 wide, 7 tall; a single-tile nose over a full-width row, a
two-wide waist, and a broken engine block.
Flavor: A broad hull, ribbed sponsons at the shoulders, a flared lower
body ending in prongs.

**Corsair Cruiser** - `rmRD_large2`, model oHullRD_L2
Map: 5 wide, 7 tall; a near-solid block with a single-tile nose and
scattered interior holes.
Flavor: A huge rounded hulk of layered riveted plates, a dome at the
nose - nearly as wide as it is long.

### Gorgothian (Plague)

**Gorgothian Frigate** - `rmPL_small1`, model oHullPL_S1
Map: 4 wide, 5 tall, lopsided; a solid nose block shrinking to a
one-tile waist and a small tail.
Flavor: A boxy hull, its upper corner corroded and streaked with brown
rot.

**Gorgothian Scout** - `rmPL_small2`, model oHullPL_S2
Map: 3 wide, 9 tall; a single-tile spine with a small offset dogleg at
the engines.
Flavor: A tall grimy tower, gun racks down both sides, a flared engine
base.

**Gorgothian Destroyer** - `rmPL_large2`, model oHullPL_M1
Map: 5 wide, 6 tall, lopsided; a solid block on the right with one
full-width row and a ragged tail.
Flavor: A patched, blotchy hulk, a scaffold platform jutting from one
side, a wide engine skirt.

**Corrupt Cruiser** - `rmPL_large1`, model oHullPL_L1
Map: 5 wide, 8 tall, lopsided; a single-tile column up the left edge, a
full row at its foot, and the body massed low on the right.
Flavor: A mismatched pile of hull sections, a dark barred block on one
side, rot streaks down the plating, a wide skirted stern.

### Ariokine (Blood)

**Ariokine Frigate** - `rmBL_small1`, model oHullBL_S1
Map: 2 wide, 5 tall; a plain solid rectangle.
Flavor: A narrow dark red hull, dense rib fins down both sides.

**Ariokine Corvette** - `rmBL_small2`, model oHullBL_S2
Map: 3 wide, 8 tall; a single-tile spine over a solid engine block.
Flavor: A dark red tower, twin turrets at the nose, two spiked wings
flaring from the lower body.

**Ariokine Scout** - `rmBL_small3`, model oHullBL_S3
Map: 3 wide, 8 tall; a single-tile spine with a crossbar near the
engines.
Flavor: A slim red-brown tower, paired gun racks down the sides.

**Ariokine Destroyer** - `rmBL_medium1`, model oHullBL_M1
Map: 4 wide, 5 tall; a solid block with two enclosed empty tiles behind
the nose and a two-tile tail.
Flavor: A broad hull flanked by dense red rib racks, spikes crowning
the nose.

**Ariokine Cruiser** - `rmBL_large1`, model oHullBL_L1
Map: 8 wide, 5 tall - a wide ship; one full-width deck under two lone
corner rooms, narrowing to twin single-tile tails.
Flavor: A central pod with two horns at the nose, flanked by two tall
weapon pylons - wider than it is tall.

### Possessed (Demon)

**Possessed Scout** - `rmDMsmall1`, model oHullDM_S1
Map: 3 wide, 8 tall; a single-tile spine ending in a full-width engine
row.
Flavor: A corroded tower with a single giant horn curling over its
nose.

**Possessed Frigate** - `rmDMmedium1`, model oHullDM_M1
Map: 3 wide, 8 tall, lopsided; a ragged two-wide spine that staggers as
it descends.
Flavor: A rotting hull studded with growths, short horns jutting from
both sides.

**Possessed Cruiser** - `rmDMlarge1`, model oHullDM_L1
Map: 5 wide, 7 tall; a narrow body opening into a full-width engine row
with rooms at both corners below it.
Flavor: A rusted red hulk, two great curved horns at its shoulders,
bone spurs breaking through the lower plating.

### Independents

**Merchant Vessel** - `rmMC_medium1`, model oHullMC_M1
Map: 4 wide, 7 tall; a solid upper body narrowing to a two-wide tail.
Flavor: A rounded nose over a body stacked with wide cargo racks
jutting out on both sides.

**Vanguard Trident** - `rmSDF_small1`, model oHullSDF_S1
Map: 3 wide, 8 tall; a spine swelling to full width twice, behind the
nose and at the engines.
Flavor: Overlapping green scale plates down its length, a pointed crest
at the nose with two red lights.

**Vanguard Interceptor** - `rmSDF_small2`, model oHullSDF_S2
Map: 4 wide, 6 tall; a solid nose block over a two-wide tail.
Flavor: Layered blue fins around a round core, woven lattice plating on
the lower body.

**Vanguard Destroyer** - `rmSDF_medium1`, model oHullSDF_M1
Map: 3 wide, 9 tall, slightly lopsided; a narrow nose opening into a
near-solid lower body.
Flavor: A purple hull, a tall crest at the nose lined with white
serrations, gold studs down the swept flanks.

### Forts and ruins (static structures)

**Imperial Bastion** - `rmEM_fort_medium1`, model oHullEM_fort_M1
Map: 9 wide, 6 tall, one connected structure; two offset blocks, upper
left and lower right, joined at the corner.
Flavor: Two rectangular fort blocks with plank-brown roofs, their edges
ringed by dense battlements.

**Frontier Bastion** - `rmEM_fort_medium2`, model oHullEM_fort_M2
Map: 10 wide, 5 tall; a long low compound, full-width through the
middle, ragged top and bottom edges.
Flavor: A staggered cluster of flat fort blocks in red-brown paneling,
battlements along every edge.

**Imperial Stronghold** - `rmEM_fort_large1`, model oHullEM_fort_L1
Map: 13 wide, 9 tall, 74 tiles; a solid mass on the right with one
full-width row running out to the left edge.
Flavor: A sprawling fortress, a great roofed hall with radiating beams,
smaller wings, battlements on every outer wall.

**Cult Refinery** - `rmPL_fort_medium1`, model oHullPL_fort_M1
Map: 11 wide, 6 tall; a central mass with arms reaching left and right
along the middle rows.
Flavor: A fort compound with two round tank domes on the roof and a
mass of rot clinging to one end.

**Cult Outpost** - `rmPL_fort_medium2`, model oHullPL_fort_M2
Map: 10 wide, 5 tall; two long full-width rows with scattered rooms
above and below.
Flavor: A flat-roofed compound in pale green paneling, patched with
rust, a round vent on the roof.

**Cult Sanitarium** - `rmPL_fort_large1`, model oHullPL_fort_L1
Map: 14 wide, 8 tall, 74 tiles; a dense compound filling most of its
rectangle, pierced by scattered holes.
Flavor: A sprawl of green-roofed halls, round tanks sunk into the roof,
rot creeping over the edges.

**Ruined Fortification** - `rmDM_ruin_small1`, model oHullDM_ruin_S1
Map: 11 wide, 9 tall overall, in four separate structures: one at the
top center, one at the upper right, and two along the bottom.
Flavor: Broken fragments of a fortress, walls torn open, rubble
scattered between them.

**Infested Techno-crypt** - `rmDM_ruin_large1`, model oHullDM_ruin_L1
Map: 14 wide, 10 tall, 81 tiles in one connected maze, riddled with
holes, no symmetry.
Flavor: A dark labyrinth of thick broken walls, edges crumbled to
rubble.

**Antediluvian Crypt** - `rmJW_ruin_small1`, model oHullJW_ruin_S1
Map: 12 wide, 9 tall; a winding connected lattice of corridors, widest
in the middle, trailing to a single tile at the bottom.
Flavor: A flat slab of dark stone, stepped angular edges, long slot
openings cut through it.

**Shrouded Temple** - `rmJW_ruin_large1`, model oHullJW_ruin_L1
Map: 14 wide, 10 tall, 81 tiles; a dense block pierced by small holes,
a notch splitting the bottom edge.
Flavor: A vast flat stone slab, stepped edges, pierced by rows of small
openings, a deep cleft in its lower edge.

### Minibosses

**Voltaic Cruiser** - `rmMinibossTechno01`, model oHullTC_miniboss01
Map: 10 wide, 8 tall; a narrow column at the nose spreading into a wide
three-lobed base.
Flavor: A great domed oval body over two clawed arm masses, gun stalks
at the shoulders.

**Imperial Battle Ark** - `rmMinibossEmpire01`, model oHullEM_miniboss01
Map: 9 wide, 7 tall; a diamond over a full-width base row.
Flavor: A vast tiered bone-white facade, spires at the crown, a
heraldic shield at its base, a fringe of teeth below.

**Core Miner** - `rmMinibossRaider01`, model oHullRD_miniboss01
Map: 10 wide, 8 tall; a wide upper mass narrowing step by step to a
two-tile tip at the bottom, a funnel.
Flavor: Two huge domed tanks flank a central grated silo, orange hazard
trim across the works.

**Giant Necrophage** - `rmMinibossDemon02`, model oHullDM_miniboss02
Map: 10 wide, 7 tall; a full-width band near the top, thinning to a
ragged lower edge.
Flavor: A mound of pink-red flesh fused into machinery, pale tusks
jutting in every direction.

### Bosses

Normal and torment fights use separate rooms; where the grids differ
both are given. Art differences between the two are minor (extra gun
pods) except where noted.

**Doom Engine** - `rmBossWar_normal` / `rmBossWar`, models
oHullWR_boss_normal / oHullWR_boss
Map (normal): 8 wide, 8 tall, symmetrical side to side; a cross-shaped
core over a full-width base of engine blocks.
Map (torment): 12 wide, 8 tall, symmetrical side to side; the same core
widened by wing arms on the middle rows.
Flavor: Two massive angled wing slabs around a segmented brown iron
core, over a wide skirted base; the torment version adds gun pods on
the outer edges.

**Ariokine Starflayer** - `rmBossBlood_normal` / `rmBossBlood`, models
oHullBL_boss_normal / oHullBL_boss
Map: 13 wide, 9 tall, symmetrical side to side (both fights); two tall
wing columns rising from a wide middle band, the core massed low at the
center.
Flavor: Two enormous dark red sails spread like bat wings, spired
towers between them, the hull itself small at their base.

**Necropolis Barge** - `rmBossPlague_normal` / `rmBossPlague`, models
oHullPL_boss_normal / oHullPL_boss
Map: 12 wide, 9 tall, not symmetrical; room clusters strung diagonally
from the upper left down to a full-width engine row near the bottom
(the torment fight fills a few more tiles).
Flavor: A city-block slab of grey iron, towers and vents across its
surface, bone tusks around the rim, rot boiling over its left half.

**Hyperion Shard** - `rmBossEmpire_normal` / `rmBossEmpire`, model
oHullEM_boss (same art both fights)
Map (normal): 8 wide, 7 tall, symmetrical side to side; a diamond core
over a full-width base row.
Map (torment): 8 wide, 8 tall; the same with an extra solid block at
the nose.
Flavor: A pale cathedral fortress, a tall central keep, crenellated
towers up both sides, red heraldic shields on the flanking bastions.

**Demon boss** - `rmBossDemon` (no standard hull model or hullName)
Map: 6 wide, 8 tall, symmetrical side to side; a solid column with a
two-hole waist and a notched base.
Flavor: TODO - this fight has no standard hull sprite (only
provisional art assets exist in data.win); verify what it looks like in
a live fight before authoring.
