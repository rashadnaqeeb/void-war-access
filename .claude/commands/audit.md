Perform a full codebase audit of the Void War Access mod.

## Your Role

You are auditing the entire codebase against the project's standing
invariants, not reviewing a diff. Focus on invariant violations,
architectural drift, abstraction quality, and long-term maintainability.
Speech is the player's only interface: a silent failure or a stale readout
is invisible to the user, so correctness findings outrank style findings.

## Instructions

1. Read CLAUDE.md (invariants, sanctioned exceptions, and the deliberate
   divergences from the WotR reference - do NOT re-report those as
   findings) and docs/backlog.md (known future work is not a finding).
2. Scan all of src/gml/, src/shim/, src/lang/, tools/, and scripts/.
3. Where a check needs game truth, look it up in decompiled/ or verify
   over the dev driver against a live game - never from memory.
4. Report per the output format at the bottom.

## Audit Areas

### Speech correctness (the reason the mod exists)

**One chokepoint:**
- Every spoken string flows through `vwa_speak(parts, interrupt)` with a
  parts ARRAY. Flag any call passing a pre-joined concatenation of
  localized pieces (composition freezing), and any direct shim call
  outside the sanctioned set: scrVwaCore's own speech path, the input
  layer's keyDelay/keyRate reads, the dev pump's poll/reply, the Game End
  teardown (`vwa_shim_shutdown`).

**Localization:**
- Every user-facing string is a `vwa--` row read through `vwa_t`, or the
  game's own (already localized) live text. Dev-driver and log text
  exempt. Flag English literals in parts arrays or screen names.
- Cross-check src/lang/: keys referenced in GML but missing from any of
  the four CSVs, rows present in one language but not the others, and
  dead rows no longer referenced (action labelKeys are alive even though
  only dumped by /state today - the rebind UI will speak them).

**Never cache game state:**
- Every part closure and build function must read live instance/global
  state at resolve time. Flag any closure capturing a resolved label or
  state value at build time. The only acceptable capture is a live
  instance reference whose variables are read on demand.

**Interrupt policy:**
- Interrupt only on: genuine focus movement within a screen, direct
  user-caused state feedback (`vwa_nav_state_feedback`), and the panic
  reset's confirmation. Screen names, initial landings, and live-part
  watch changes never interrupt. Flag any other `vwa_speak(_, true)`.

**Hooks never speak:**
- Patched game events (`*.append.gml`) set state or enqueue; speech
  happens once per frame from the tick's observe/diff. Sanctioned
  exception: the one-shot boot announcement in oInitGlobals Create.

**Surface only what's visible:**
- Readouts mirror the game's own visibility/sort/filter rules. Flag any
  announcement invented from state a sighted player cannot currently see.
  (Mod-authored structure words - "n of m", the group word - are the
  sanctioned verbalized-visible-structure class.)

### Failure discipline

**No silent failures:**
- Every guarded failure path logs via `vwa_log`. Early returns on
  expected-absent values (no focused screen, no node) are control flow,
  not failures. The ONLY sanctioned swallow-and-log spots: the dev pump
  watchdog, the input tick watchdog (which must clear
  `global.vwaSuppressGameKeys`), the screen-callback quarantine in
  `vwa_screens_tick` (once-per-activation via faultLogged), the
  part-resolve guard in scrVwaAnnounce, and `vwa_shim_init`'s
  log-only-speech degrade. A NEW try/catch anywhere else is a finding.
- The suppression flag must be un-settable by any error path: verify the
  watchdog still clears it and nothing else sets it without a restore
  path (including on throw - try/finally is unverified under UTMT, use
  restore-and-rethrow).

**Never strand the user:**
- Shim: Prism -> SAPI fallback intact; no DLL still writes the speech
  log. Shift+F11 panic path reaches `vw_reset_speech`. The textSafe
  speech controls must dispatch while `global.textFieldInputEnabled`.

### Activation and input contracts

- Every onActivate calls the game's OWN stored callback and mirrors the
  real handler's guards, order, and sounds; press-sound ids are read
  BEFORE the callback (a destroyed button's dead id crashes post-callback
  reads). Sanctioned reimplementation: the volume-slider wheel-path
  mirror (`vwa_widget_slider_adjust`); a new slider object must extend
  that dispatch, and an unhandled widget family must log.
- Raw `keyboard_check*`/`keyboard_key`/`io_clear`/`keyboard_clear` only
  in scrVwaInput (the sanctioned home) and scrVwaDev diagnostics. All
  user-facing hotkeys are registered actions (bindings arrays).
- Escape consumption (`vwa_input_consume_escape`) only when a screen's
  onBack claimed the press.
- The dev driver drives real code paths (stored callbacks, real action
  dispatch), never OS synthetic input; game-touching driver calls are
  serialized (the single-command 429 is deliberate).

### Framework health

- scrVwaGraph and scrVwaAnnounce stay PURE: no instance, global, or game
  references (announcer hooks carry localized words in). Flag any leak.
- Screen structs follow the contract (key/layerNum/isActive/name/build/
  categories/exclusive; optional onBack); screens never mutate focus
  directly - the navigator owns it. All screens gated on
  `!global.gameIsLoading` where menuToggle is read (nonzero during boot).
- Node identity: stable structural keys (indexes added where game data
  can duplicate); tier-1 refs are the entry struct or instance id.
- Zero build warnings (shim -Wall -Wextra -Werror and UTMT import), never
  suppressed. Shim exports take/return only doubles and C strings.
- Host-side protocol tests and the five smoke scripts still cover their
  subsystems; a behavior change without a smoke expectation update is a
  finding.

### Code quality (secondary to the above)

- Missed abstractions: logic repeated across 3+ sites that wants a
  helper; over-abstraction: indirection with a single user.
- Comments describe current state, never change history (no "was",
  "previously", no session numbers in shipped log strings; "bit us"
  rationale lives in docs, a brief why-comment citing the constraint is
  fine).
- Dead code, dead lang rows, TODO/FIXME inventory, leftover debug output.
- Files or functions grown past easy comprehension (the widget adapter
  and dev interpreter are the watch candidates).

### Docs currency

- CLAUDE.md invariants match the code's actual sanctioned exceptions.
- README keys section matches the registered actions; CLAUDE.md's verified
  facts, sanctioned-exception lists, and deliberate-divergence section
  match the code; docs/backlog.md doesn't list anything already built.

## Output Format

### Summary
- **Critical**: [count] - invariant violations that will produce silent
  failures, stale speech, stranded users, or game-state corruption
- **Improvements**: [count] - refactoring or hardening opportunities
- **Notes**: [count] - minor observations

### Findings (grouped by severity)
For each: Area, File(s):line, what the issue is, why it matters for a
blind player or for maintainability, and a concrete suggestion. Verify
each finding against the code before reporting; do not report documented
deliberate divergences from CLAUDE.md's divergence section.
