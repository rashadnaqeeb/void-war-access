# Backlog - future work to consider

The foundation (speech, input, screens, graph, announcer, dev driver, main
menu + settings family) is built and smoke-covered; this is what remains.
Ordered lists are rough priority. History lives in git; invariants and
verified facts live in CLAUDE.md.

## Game coverage (the next phase)

- In-run menus: crew, cargo, shop, upgrade, armament, maps.
- The ship/combat screen: sonification-grade feedback; the hardest design
  problem - plan it before building.
- Text encounters (the `oEncounter` family).
- The `oShipLog` event feed piped to speech (the references' biggest early
  gameplay win; review buffers below are the likely frame).
- Meta screens: ship/commander select, archives, achievements.
- The keybinds menu (menuToggle 15, `oMenuConfigureKeybinds`) - currently a
  name-only placeholder; cover via the generic widget adapter.
- The `/loadsave` dev-driver equivalent (cold start to in-run in one call).

## UI infrastructure not built yet (menu features)

1. Type-ahead search: type letters to jump within the focused Tab stop.
   Tiered matching (word start > prefix > mid-word > substring >
   abbreviation, repeated-letter cycling); needs a text-input feed the
   input layer doesn't have yet.
3. Secondary action (Backspace vtable slot) - nothing to bind until
   vendor/loot-style screens.
4. Grid screens: regions with Ctrl+Up/Down region jumps (reserved) and a
   table emitter (rows/columns, column-header announcements) - for
   cargo/crew.
5. Review buffers: scrub named text lists (event log, status) independent
   of focus.
7. Settings model: persisted typed settings tree, per-kind/per-type
   announcement verbosity (the lever if inline tooltips get chatty),
   verbosity presets.
8. Key rebinding UI + persisted bindings (the bindings-array registry is
   the substrate); capture screen with conflict handling.
9. Mod menu launcher, help screen, log review screen (worth it once the
   settings model exists).
12. Screen-struct affordances with no consumer yet: KeepStateOnPop,
    InitialFocusStop, pending-focus-with-retry, StartUnfocused/Wrap flags.

## Standing questions

- Localization QA over de/es/fr once strings settle (the vwa-- rows are
  machine-authored so far).
- Whether the WndProc bg keepalive is strictly load-bearing was never
  proven (Windows' foreground lock blocked the reproduction); it installs
  cleanly and is kept as a cheap safeguard.
