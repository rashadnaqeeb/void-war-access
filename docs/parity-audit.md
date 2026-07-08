# Parity audit against the references (session 8)

Systematic comparison of Void War Access against WotR Access (UI
architecture donor) and Tangledeep/Tanglebeep (dev-driver contract donor),
run 2026-07-08 as seven parallel review passes: one per subsystem (input,
screens/navigator, graph/announcer, speech chain, dev driver), one walking
the WotR audit invariant checklist against this codebase, and one
inventorying WotR's UI infrastructure for the completeness backlog.
Everything below was verified against source on both sides (file:line
evidence gathered during the audit); live-game claims were verified over
the dev driver the same day.

Verdict up front: the foundation is a faithful port. Every load-bearing
mechanism - two-tier identity, reconciliation ladder, poll-and-diff stack,
path-diff composition, focus-first category liveness, shadowing, typematic
repeat, the speech chokepoint, the dev-driver threading model - matches the
references mechanism-for-mechanism. The audit found eight unintended
foundation-level divergences, all fixed this session (list below), plus a
set of deliberate divergences now documented here, and a backlog.

## Fixed this session (was unintended)

1. Home/End were missing. WotR binds ui.home/ui.end to jump to the
   first/last item. Added `vwa_graph_move_ends` (first/last control of the
   focused Tab stop, declaration order) on Home/End, localized in all four
   languages. This was the gap Rashad reported.
2. Tab / Shift+Tab did not repeat while held. WotR marks both Repeating();
   ours passed repeats=false. Flipped.
3. One binding per action. WotR actions carry a binding LIST (AddBinding
   chains); ours stored exactly one chord struct. The registry now stores a
   bindings array (register accepts a struct or an array), dispatch and the
   /state dump iterate it. No action uses a second binding yet; the shape
   is what rebinding UI and any future alternate keys sit on.
4. No synchronous value feedback on adjust/activate (the WotR StateText
   behavior). A slider value or toggled state was spoken only by the NEXT
   tick's live-part watch, non-interrupting - under typematic key repeat
   the queued values read behind the slider's actual position. Added
   `vwa_nav_state_feedback`: after a successful adjust or activate, the
   changed live part speaks immediately with interrupt, and the live cache
   rebaselines so the watch does not double-speak. Guarded for activations
   that close their own screen (isActive check before the rerender). The
   interrupt-policy invariant in CLAUDE.md was widened to name this case.
5. Dropdown list entries had no role word (typed "label"). WotR types
   choice options with a role ("radio button"). Added the "option" control
   type (localized role word) to the dropdown child screen's entries.
6. Disabled and selected state parts were not live. WotR marks both LIVE so
   a control graying out or a selection moving under focus re-announces.
   Flipped the enabled parts (oButton_menus, oButton) and the dropdown
   selected part to live.
7. The live-part watch compared by index even when the part COUNT changed,
   which could speak a positionally wrong part for a frame. It now
   rebaselines silently on a count change (WotR does the same).
8. The generic group word was "Radio group" (vwa--group-radio), which also
   labeled button rows like the confirmation dialogue's Confirm/Cancel.
   Renamed to the neutral "group" (vwa--group-generic). The window-mode
   trio now reads "group, 2 of 14, Fullscreen, checkbox, ..., 1 of 3" -
   also more honest, since the game-truth trio is independent toggles, not
   real radios. Rashad can veto the wording.

Also new: F10 "read current control" (`vwa_nav_read_current`), the WotR
AnnounceCurrent primitive as a user key - re-composes the focused node's
full path fresh from live state (unlike F11, which replays the last spoken
line verbatim). WotR has the primitive wired to internal callers only; we
expose it because a menu-only mod has no focus-mode toggle to hang it on.

Housekeeping from the invariant walk, same session: the CLAUDE.md
swallow-and-log list now names all five sanctioned spots (dev pump
watchdog, input tick watchdog, screen-callback quarantine, part-resolve
guard, shim-init degrade); a "session-5+6" version label was stripped from
a shipped log line.

## Deliberate divergences (kept, with reasons)

Input layer:
- Tooltip key is F9, not WotR's Space/F1: the game itself binds Space and
  F1; mod chords avoid every game-bound key.
- Categories are strings, not an enum: cross-entry enum visibility is not
  guaranteed under the UTMT importer.
- textSafe speech controls stay live while a game text field is focused
  (WotR stands down entirely while typing). Strictly safer - the chosen
  chords cannot type a character - and required by never-strand.
- No focus-mode toggle: the poll-and-diff screen stack IS the focus-mode
  equivalent. The UI category is live exactly while a mod screen is
  focused; there is nothing to toggle. (Revisit when in-run screens need
  an explicit "mod owns the keyboard" mode over live gameplay.)
- Plain-Ctrl binding (speech stop) via the modifier-is-main-key exemption:
  ours-only enhancement, no WotR equivalent.

Screens / navigator:
- Tab always wraps between stops. WotR consumes at the end unless a screen
  opts into Wrap, because tabbing off the end of an unfocused screen blurs
  into exploration - a concept we do not have yet. Wrap is the friendlier
  default for menu-only screens; revisit with the in-run phase.
- Enter on a node with no action speaks "No action"; WotR consumes
  silently. Ours is deliberately more informative (session 4, smoke-covered).
- Dropdowns are a registered child SCREEN going live through poll-and-diff
  (toggleDropdown), not WotR's imperative ActiveChild chain. Same felt
  behavior (Escape closes just the list, focus restores); fits the GML
  poll model.
- The keyboard dropdown flow closes the list on commit (combo convention);
  the game's mouse flow leaves it open (session 6, documented there).
- Boot announcement speaks directly from the patched oInitGlobals Create:
  a one-shot boot confirmation, not a per-frame hook; sanctioned.

Graph / announcer:
- A multi-item row IS a group (synthesized context node, one vertical
  entry, group word + two-axis "n of m"). WotR excludes multi-item rows
  from the vertical count entirely and speaks no group word - which is
  exactly the bare-"1 of 3" bug Rashad reported in session 7. Ours is a
  deliberate superset of the reference.
- No expandable tree groups, no FlowSheet regions (Ctrl+Up/Down), no
  menu/raw mode-boundary stitching: nothing in the foundation screens
  needs them (scrVwaGraph.gml header documents all three). Trees and
  regions move to the backlog below - the settings-style long lists of the
  in-run phase will want them.

Speech chain:
- Parts-array composition joined once at the chokepoint (vs WotR Message
  objects resolved at output boundaries): the GML form of the same rule.
  Parts hold resolved strings, but every build re-resolves per frame from
  live state, so language changes are picked up next frame.
- Capture-only speech gate in dev launches (unattended runs must not drive
  the screen reader); /speech taps upstream so nothing is lost.
- Persistent per-line speech log and F11 repeat-last: both EXCEED the
  reference (WotR has no spoken-line log and no repeat key at all).
- Panic reset re-runs the shim's tier selection rather than "force back to
  Prism": equivalent, since we have no user handler choice to reset.

Dev driver:
- /cmd eval-lite interpreter instead of /eval: GML cannot compile at
  runtime (the founding constraint, build-plan session 2).
- `call` invokes methods directly with a 4-arg cap: script_execute_ext on
  a method value silently runs an unrelated script (session-5 bit-us).
- /gui/raw enumerates known widget families instead of walking a scene
  graph: GameMaker has no scene graph.
- Single command in flight: a second game-touching request while one is
  pending gets an explicit HTTP 429 (the references queue and drain all
  jobs per pump). DOCUMENTED HERE AS DELIBERATE: the pump runs one command
  per frame by design, /health and /speech are shim-side and always
  answer, and the 429 is loud, not silent. Rule for drivers (including
  this project's agent): serialize game-touching calls. Revisit only if a
  long-blocking command (the /loadsave equivalent) arrives.
- Ours-only additions beyond the references: /state (input-layer dump),
  pumpAgeMs and bgKeepalive in /health, explicit dropped-line counts in
  /speech, real 504 on pump timeout (references return 200 with a sentinel
  string), PID-lock launcher discipline stricter than WotR's.

## Verified non-gaps (checked because they looked like gaps)

- Tooltip reading works on every control that has a game tooltip (verified
  live on all 16 settings controls). The settings buttons (Configure
  Keybinds, Back) have NO tooltip in game state - oButton_menus has no
  tooltipStr variable at all and oButton defaults it to 0 - so F9's "No
  tooltip" there is game truth, per surface-only-what's-visible. What
  Rashad likely hit is the key divergence (WotR reads tooltips on Space/F1;
  ours is F9) - see deliberate divergences.
- Numpad Enter activates: GameMaker maps both Return and numpad Enter to
  vk_enter (13), so WotR's explicit KeypadEnter second binding is covered
  by the platform. (Multi-binding now exists regardless.)
- Help system: WotR defines Screen.GetHelpMessages() but nothing consumes
  it - no help key exists there either. Not a divergence; an unbuilt
  feature on both sides (backlog).
- Rich-text stripping: WotR strips TMP markup before speaking. Void War's
  text files carry no markup - the only bracket tokens are substitution
  placeholders ([FACTION], [hullName]) replaced before display (verified
  against the shipped lang files 2026-07-08). No stripper needed.
- The game's own event-order dependency: our input tick runs in Begin Step
  before every game Step/Draw read; keyboard_clear as the consume
  mechanism is the game's own idiom (oUIConfirmationDialogue does it).

## Missing, does not matter yet (post-foundation backlog)

UI infrastructure, roughly by everyday-navigation value (this is the
UI-completeness list vs WotR, excluding its overworld/exploration/audio
layer, which is a different game):

1. Type-ahead search: type letters to jump within the focused Tab stop;
   WotR has 6-tier matching (word start > prefix > mid-word > substring >
   abbreviation), repeated-letter cycling, Up/Down through results,
   Home/End to first/last hit, Escape clears. The single biggest everyday
   feature for long lists (ship log, encyclopedia, shops). The engine
   (TypeAheadSearch.cs) is pure and ports cleanly; the glue needs a
   text-input feed the input layer does not have yet.
2. Tooltip drill-in reader: WotR opens a tooltip as a navigable document
   (headings, lines, links that push further child screens; Back pops one
   level). Ours speaks tooltipStr flat on F9 - adequate while Void War
   tooltips are plain strings; becomes real work if encounter/encyclopedia
   text needs structured reading.
3. Expandable tree groups (BeginGroup): focusable headers whose children
   emit only while expanded, left/right expand/collapse/descend/ascend.
   NOT the same thing as our row groups (a multi-item row counting as one
   vertical entry). Needed for a mod-settings tree and any long
   categorized list.
4. Secondary action (Backspace, OnSecondary vtable slot): nothing to bind
   it to until vendor/loot-style screens.
5. FlowSheet regions + Ctrl+Up/Down region jumps, and the GraphSheet
   table emitter (rows/columns, column-header announcements, sparse
   cells): needed for tabular in-run screens (cargo, crew).
6. Review buffers: Alt+Up/Down scrub through named text lists (event log,
   status) independent of focus. The likely frame for the oShipLog work
   in the in-run phase.
7. Text entry echo (game fields and a mod single-line editor): no
   editable field in any foundation screen; the input layer already has
   the text-field awareness (textSafe) the feature will sit on.
8. Settings model + mod settings screen: persisted tree of typed settings
   (bool/int/choice/binding) with dotted-path keys, auto-save, reset;
   per-kind/per-type announcement verbosity (PartFilter) and presets;
   inherit-aware nodes. The per-part announcement settings are the
   gate for inline tooltip parts (see 10).
9. Key rebinding UI + persisted bindings: capture screen, conflict
   steal/reject, append vs replace; BindingSetting persistence. The
   bindings-array registry from this session is the substrate. The game's
   own Configure Keybinds menu (menuToggle 15) is also still a name-only
   placeholder - cover it via the generic widget adapter when this lands.
10. Inline tooltip/description part in announcements (WotR speaks tooltips
    inline after value/enabled, user-togglable): gated on per-part
    settings (8); chatty without them. F9 covers the need meanwhile.
11. Mod menu launcher (Ctrl+M style), help screen, log review screen:
    WotR conveniences; the mod menu becomes worthwhile once settings (8)
    exist.
12. UI earcons (hover/activate sounds; WotR plays the game's hover sound
    on every move): a design decision for Rashad - speech-first may not
    want them; the game's own click sounds already fire on activation
    mirrors.
13. Clipboard last-resort speech backend (WotR's terminal fallback when
    Prism AND SAPI fail): SAPI is effectively always present on Windows,
    so low priority.
14. Announce-current internal wiring (focus-mode toggle, text-entry
    return): we ship it as F10 instead; the internal callers arrive with
    their features.
15. KeepStateOnPop, InitialFocusStop, pending-focus-with-retry,
    StartUnfocused/Wrap flags: screen-struct affordances with no
    foundation consumer; add per-flag when a real screen needs one.
16. Dev-driver niceties: compound (array/struct) literals for call/set,
    an enumerate-globals/scripts discovery command, a /log tail, the
    /loadsave state jump (documented post-foundation since session 0).

## Next-phase backlog (game coverage, from the build plan's "after the
foundation" plus this audit)

- In-run menus: crew, cargo, shop, upgrade, armament, maps (GraphSheet
  and regions land here).
- The ship/combat screen: sonification-grade feedback; the hardest design
  problem, plan first.
- Text encounters (oEncounter family; likely wants the drill-in reader).
- The oShipLog event feed piped to speech (Tanglebeep's biggest early
  win; review buffers are the frame).
- Meta screens: ship/commander select, archives, achievements.
- The keybinds menu (menuToggle 15) via the generic adapter.
- /loadsave equivalent for the dev loop.
- Localization QA pass over de/es/fr once strings settle (the vwa-- rows
  are machine-authored so far).

## Post-audit simplification (same day, Rashad's direction)

After reviewing the bindings list, Rashad cut three keys as unnecessary:

- F9 tooltip-on-demand is GONE; tooltips are now an inline announcement
  part. Any widget with a game tooltipStr speaks it as part of its normal
  announcement (after state, before position); widgets without one append
  nothing. This diverges from WotR deliberately: Pathfinder tooltips are
  layered documents needing a drill-in reader, while Void War tooltips are
  verified flat strings (draw_label panels; sections/double panels are
  visual composition, no links or nesting), so inline reading covers the
  entire surface. The graph's onTooltip plumbing was removed with it.
  Backlog items 2 (drill-in reader) and 10 (inline tooltip part) are
  RESOLVED by this design; a per-part verbosity toggle (item 8) remains
  the future lever if inline tooltips get chatty.
- F10 read-current-control: removed (added this session, cut same day).
- F11 repeat-last: removed, along with the last-spoken tracking in the
  chokepoint. The speech-parity note that we "exceed the reference" here
  no longer applies; WotR has no repeat key either.

Ctrl (stop speech) and Shift+F11 (panic reset) remain the only global
keys; the UI category is arrows, Enter, Tab/Shift+Tab, Home/End, Escape,
plus Ctrl+Left/Right as large adjust steps (added right after the cut:
the slider mirror's reserved large flag, 0.2 per step). Ctrl+Up/Down stay
unbound - in WotR they are FlowSheet region jumps, which wait for grid
screens (backlog item 5).

## Standing rule going forward

`.claude/commands/audit.md` (created this session) encodes the project's
invariants as the recurring architectural-health check; run it after any
multi-session stretch of feature work. This document records point-in-time
parity; the audit command keeps the invariants enforced.
