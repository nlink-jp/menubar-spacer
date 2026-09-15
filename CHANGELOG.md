# Changelog

## [Unreleased]

- Implement the preference writer, the on-disk backup and the apply/restore
  coordinator: the way back is stored before the first write, every write is
  verified by reading it back, a restore is refused when someone else changed
  the keys in between, and an unreadable backup blocks every preset except the
  return to the OS default. 26 new tests.
- Add opt-in hardware tests, the only ones that touch the real preference
  domain: they refuse to run unless both keys are absent and delete both keys
  in teardown. They cover the single-key write the measurement probe never
  performed.

- Measure the spacing behaviour on macOS 27.0: every preset value is now
  observed (unset 37, 4 → 25, 8 → 29, 24 → 45), the value proves to be latched
  per process rather than per status item, and read-back after each write
  matched. Two identical runs, preferences restored exactly both times.
- Add the development-only measurement probe and its coordinator, with an exact
  two-key backup, an external watchdog, serialised mutations and 20 guard cases.
- Settle the preview design on a child process, since items created in the
  running app after a write keep the old spacing.

- Scaffold the project: Swift Package Manager layout, signing and notarization
  wiring, bilingual README, and the RFP in both languages.
- Add the pure model layer — spacing keys, absent-aware stored values, minimal
  write plans, the four presets, and the restore decision that refuses to
  overwrite an external change or write from a corrupt backup — with 19 tests.
- Add a read-only preference reader for the current-host and any-host scopes,
  and a window shell that describes the live state. Nothing is written yet.
