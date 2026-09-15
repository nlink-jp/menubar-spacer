# Changelog

All notable changes to menubar-spacer are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

### Added

- The window: pick a preset, apply it, undo it. Applying shows the result at
  once with three sample icons in the menu bar, because the change is invisible
  in every app that is already running.
- A single-instance guard, so a second copy exits instead of opening a second
  window onto the same setting. The preview child is exempt.

- The preference layer for the two spacing keys, an on-disk backup of the state
  this Mac held beforehand, and the apply/restore coordinator that orders the
  two safely. See [ADR-0001](docs/en/adr/0001-backup-and-restore-model.md).
- Presets: minimum (4), narrow (8), OS default, wide (24). Every value measured
  on macOS 27.0; see [the measurements](docs/en/phase1-results.md).
- A development-only measurement probe and its coordinator, with an exact
  two-key backup, an external watchdog and serialised mutations.
- Opt-in hardware tests, the only ones that touch the real preference domain.

### Fixed

Findings from the independent review of the write layer, all pre-release:

- A value someone had set by hand outside 0…64 was recorded faithfully and then
  rejected as corrupt on every restore, leaving no way back. There is no
  plausibility range any more: whatever a Mac holds is what gets restored.
- A value that is not a plain integer — what `defaults write -g … 8` stores
  without `-int` — read as "absent", so a restore would have deleted a key the
  user had set. Such values are now preserved verbatim and written back unchanged.
- A write that landed on one key only left the record describing the requested
  state rather than the Mac, so the next restore blamed an outsider and refused.
  The record is now re-saved from what was actually read back.
- Two running copies could race between reading the record and saving it, and
  the second could record a state the app itself produced as the user's
  original. Every mutating path now runs under an exclusive lock and reads the
  live state inside it.
- An unreadable backup was deleted even when nothing had been written. It is now
  moved aside rather than deleted, and only after a write actually happened.
- Applying over a change made outside the app is now reported
  (`appliedOverExternalChange`) instead of passing silently.
- A failure to delete the bookkeeping file no longer reports a completed write
  as a failure.
- The project scaffold: Swift Package Manager layout, signing and notarization
  wiring, bilingual README and RFP.
