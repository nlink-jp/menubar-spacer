# menubar-spacer

A non-resident macOS app that changes menu bar icon spacing through two
undocumented global preferences and restores the prior state exactly.
Swift / SwiftUI + AppKit, Swift Package Manager, macOS 27+, Apple Silicon.

**Scaffold stage.** The preference reader, the preset and plan model, the restore
decision logic and their tests exist. Applying, preview and restore are not
implemented. The app writes nothing yet — keep it that way until the Phase 1
hardware checks below are done.

## Build and test

```sh
make test        # swift test (19 cases)
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
- `Sources/MenubarSpacer/SpacingPreset.swift` — the four presets and
  `isMeasured`, which marks 8 as interpolated rather than observed. Pure.
- `Sources/MenubarSpacer/BackupRecord.swift` — the one backup record and
  `RestorePlanner.decide`, which refuses to write over an external change or from
  a corrupt record. Pure.
- `Sources/MenubarSpacer/SpacingPreferences.swift` — `SpacingPreferenceReading`
  protocol, the CFPreferences-backed reader, and a stub for tests.
- `Sources/MenubarSpacer/{App,ContentView}.swift` — the window shell.
- `Tests/MenubarSpacerTests/` — plan, preset and restore-decision cases.

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

## Phase 1 hardware checks (not yet done)

1. The effect of each preset (4 / 8 / 24) on macOS 27.0. Only 4 and 24 are
   measured; 8 is interpolated from `width ≈ intrinsic + N`.
2. Whether a status item created in the **same process** after a write picks up
   the new value. The preview feature depends on it; the feasibility study only
   ever observed a freshly launched process. If it does not, the preview has to
   relaunch the app instead.
3. That reading the effective values back after a write reflects what was written.

## Gotchas

- A change reaches an app only when that app next launches. The app must say so
  and must never quit other applications.
- `SpacingPreset.matching` returns nil for a state we did not produce (a
  hand-edited `defaults` write). The UI has to describe that state, not assume it.
- App Store distribution is impossible: a sandboxed app cannot write the global
  preference domain. Direct distribution with Developer ID + notarization only.
- The cask floor must be set for macOS 27 before the first `make brew`; the
  template default `:big_sur` would advertise unsupported systems.

## Design reference

- RFP: `docs/ja/menubar-spacer-rfp.ja.md` (`docs/en/menubar-spacer-rfp.md`)
- Evidence for every measured claim: the spacing experiment in the
  `menu-bar-feasibility` study, including the two trials and the restoration check.
