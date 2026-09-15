# menubar-spacer

A non-resident macOS app that changes menu bar icon spacing through two
undocumented global preferences and restores the prior state exactly.
Swift / SwiftUI + AppKit, Swift Package Manager, macOS 27+, Apple Silicon.

**Phase 1 complete.** The three hardware questions are answered
(`docs/en/phase1-results.md`), and the preference layer, the backup layer and the
apply/restore coordinator are implemented and tested — including against the real
preference domain. Phase 2 is the UI: nothing in the shipped app calls the
coordinator yet, so launching the app still writes nothing.

## Build and test

```sh
make test        # swift test (44 cases; the hardware tests skip)
python3 spikes/test_phase1.py   # 20 measurement-coordinator guards

# The only tests that touch the real preference domain. They refuse to run
# unless both keys are absent, and delete both keys in teardown.
MENUBAR_SPACER_HARDWARE_TEST=1 swift test --filter HardwareEndToEndTests
make run         # swift run (debug)
make build-app   # signed .app into dist/
make package     # notarized + stapled + zipped
make verify-release
```

Never run `swift build` for a deliverable — `make build` / `make build-app` own
the output location and the signing.

## Structure

- `Sources/MenubarSpacer/SpacingSettings.swift` — `SpacingKey` (the only two keys
  that may be written), `StoredValue` (absent vs. value), `SpacingSettings`, and
  `SpacingPlan.operations` which emits the minimal write/delete list. Pure.
- `Sources/MenubarSpacer/SpacingPreset.swift` — the four presets, all four
  values measured on hardware. Pure.
- `Sources/MenubarSpacer/BackupRecord.swift` — the one backup record and
  `RestorePlanner.decide`, which refuses to write over an external change or from
  a corrupt record. Pure.
- `Sources/MenubarSpacer/SpacingPreferences.swift` — the reading and writing
  protocols, the CFPreferences-backed implementation (every write verified by a
  read-back), and an in-memory stub for previews and tests.
- `Sources/MenubarSpacer/BackupStore.swift` — the one backup record on disk,
  written atomically; an unreadable file throws instead of reading as "no backup".
- `Sources/MenubarSpacer/SpacingCoordinator.swift` — apply, restore and the
  state the UI displays. Owns the ordering rules below.
- `Sources/MenubarSpacer/{App,ContentView}.swift` — the window shell.
- `Tests/MenubarSpacerTests/` — plan, preset, restore-decision, coordinator and
  file-store cases, plus the opt-in hardware tests.
- `Sources/SpacingProbe/` — development-only measurement probe. Never copied into
  the `.app`; owns its own preference access so a measurement meant to inform the
  product does not depend on the product's assumptions.
- `spikes/run_phase1.py` — the measurement coordinator: exact backup before any
  write, external watchdog, serialised mutations, manual `restore` mode.
  `spikes/test_phase1.py` guards its analysis before anything is written.

## Non-negotiable rules

- **Only `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` may be written**,
  and only in the current-user / current-host / any-application scope. The
  any-host scope is read for display and never written. Widening this is a
  product decision, not an implementation detail.
- **"Absent" is a state, not a default value.** Restoring an untouched Mac means
  deleting both keys, never writing the number that looks like the OS default.
- **The two keys always move together.** Only that combination was measured.
- **Tests are mandatory** — the model layer is pure precisely so it can be tested
  without touching the preference domain. Only `HardwareEndToEndTests` may touch
  it, and only behind its environment variable.
- **The backup is durable before the first write, never after it.** If a write
  fails, the way back must already be on disk.
- **An unreadable backup blocks every value preset**, because overwriting it
  would destroy the only record of what this Mac held beforehand. Returning to
  the OS default stays available: it needs no record and cannot make recovery
  worse.
- **Requesting no TCC permission is a requirement, not an accident.** Do not add
  Accessibility or any other grant without a deliberate scope decision.
- Docs in sync: `README.md` and `README.ja.md` in the same commit.

## Phase 1 hardware checks (done 2026-09-15, two identical runs)

Full numbers in `docs/en/phase1-results.md`; evidence in
`evidence/phase1-hardware-checks.json`.

1. Every preset is now measured. Status-item window width for a 21pt text item:
   unset 37, value 4 → 25, value 8 → 29, value 24 → 45. `width ≈ intrinsic + N`
   holds throughout, so the OS default behaves like N ≈ 16.
2. **The value is latched per process, not per item.** Items created in the same
   process after a write do not change, and neither do existing ones. A child
   process spawned by that same process gets the new value and matches a fresh
   process exactly.
3. Read-back after every write matched what was written, and the deletion path
   left both keys absent in both scopes.

## Gotchas

- A change reaches an app only when that app next launches. The app must say so
  and must never quit other applications.
- **The preview must be a child process.** Applying and then creating status
  items in the running app shows the old spacing — measured, not assumed. Spawn
  the same executable in a preview mode and let it exit; do not relaunch the app.
- `SpacingPreset.matching` returns nil for a state we did not produce (a
  hand-edited `defaults` write). The UI has to describe that state, not assume it.
- **"There is a backup" means "something of ours is in effect".** The coordinator
  drops the record once the Mac is back at its original state, so the UI can read
  that flag directly.
- **A restore is refused when someone else changed the keys after our write**
  (`refusedExternalChange`), rather than silently discarding their change.
- **A write that does not take is `noEffect`, not success.** These keys are
  undocumented; a future macOS may accept the write and ignore it.
- App Store distribution is impossible: a sandboxed app cannot write the global
  preference domain. Direct distribution with Developer ID + notarization only.
- The cask floor must be set for macOS 27 before the first `make brew`; the
  template default `:big_sur` would advertise unsupported systems.

## Design reference

- RFP: `docs/ja/menubar-spacer-rfp.ja.md` (`docs/en/menubar-spacer-rfp.md`)
- Phase 1 results: `docs/ja/phase1-results.ja.md` (`docs/en/phase1-results.md`)
- Evidence for every measured claim: `evidence/phase1-hardware-checks.json`, and
  the spacing experiment in the `menu-bar-feasibility` study that preceded it.
