# menubar-spacer

A non-resident macOS app that changes menu bar icon spacing through two
undocumented global preferences and restores the prior state exactly.
Swift / SwiftUI + AppKit, Swift Package Manager, macOS 27+, Apple Silicon.

**Scaffold stage, Phase 1 measurements done.** The preference reader, the preset
and plan model, the restore decision logic and their tests exist, and the three
hardware questions are answered (`docs/en/phase1-results.md`). Applying, preview
and restore are still unimplemented: the app writes nothing yet.

## Build and test

```sh
make test        # swift test (18 cases)
python3 spikes/test_phase1.py   # 20 measurement-coordinator guards
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
- `Sources/MenubarSpacer/SpacingPreferences.swift` — `SpacingPreferenceReading`
  protocol, the CFPreferences-backed reader, and a stub for tests.
- `Sources/MenubarSpacer/{App,ContentView}.swift` — the window shell.
- `Tests/MenubarSpacerTests/` — plan, preset and restore-decision cases.
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
  without touching the preference domain.
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
- App Store distribution is impossible: a sandboxed app cannot write the global
  preference domain. Direct distribution with Developer ID + notarization only.
- The cask floor must be set for macOS 27 before the first `make brew`; the
  template default `:big_sur` would advertise unsupported systems.

## Design reference

- RFP: `docs/ja/menubar-spacer-rfp.ja.md` (`docs/en/menubar-spacer-rfp.md`)
- Phase 1 results: `docs/ja/phase1-results.ja.md` (`docs/en/phase1-results.md`)
- Evidence for every measured claim: `evidence/phase1-hardware-checks.json`, and
  the spacing experiment in the `menu-bar-feasibility` study that preceded it.
