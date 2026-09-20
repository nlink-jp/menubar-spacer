# Changelog

All notable changes to menubar-spacer are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

### Fixed

- **If macOS reports that a change could not be saved, the saved record is put
  back as it was.** The app records the new spacing before it writes, and used to
  leave that record in place when the write failed: the Mac stayed on your
  earlier spacing, the record no longer mentioned it, and Undo declined it as
  someone else's change. (A save that fails *without* a report cannot be seen at
  all — see Limits in the README.)
- **A damaged saved original was set aside even when returning to the macOS
  default did not work.** If macOS ignored that change, the app's spacing stayed
  in effect while the file that might have undone it was moved away. It is now
  moved only once the Mac is back at the default.
- A change that took effect for only one of the two settings was described as
  "still a setting made outside this app". It now says only part of it took
  effect.
- **A change that did nothing could make Undo remove someone else's setting.**
  When macOS ignored a change made over a value that had been set outside the
  app, the app recorded that value as its own. If nothing changed, the record now
  stays exactly as it was.
- **A saved original that cannot be decoded no longer locks the app.** With the
  spacing already at the macOS default, choosing the default wrote nothing, so
  the unusable file was never moved aside: every other spacing refused from then
  on, Undo could not use the file either, and the message said that choice would
  clear it. It is now moved aside (never deleted) when you choose the default,
  and the message says so instead of "nothing was changed". A file that merely
  could not be read is still left alone — that may pass — and its message no
  longer promises a clearing. Two files set aside within one second no longer
  collide.
- **A spacing set for every Mac was invisible.** `defaults write -g
  NSStatusItemSpacing …` without `-currentHost` — the widely copied recipe — sets
  a value this app does not write but the menu bar does use. The window called
  that "the macOS default" and marked the default row "in effect". It now shows
  the spacing actually in effect, keeps a note on screen while such a value
  exists, and says which spacing applies whenever a change leaves this Mac
  without a setting of its own — because "macOS default" then returns to that
  value, not to Apple's.

### Changed

- Release builds are linked against the current macOS SDK and `make
  verify-release` checks it: since the Xcode 27 toolchain a plain build records
  the deployment target instead, and macOS then draws the window with the
  previous design. No published build was affected.

### Documentation

- The README now says what the read-back cannot tell: a Mac that cannot save its
  preferences at all reports success and reverts within a minute.
- The README said uninstalling takes the saved original with it. It does not:
  the record stays in `~/Library/Application Support/jp.nlink.menubar-spacer/`
  through a Trash or a `brew uninstall --zap`, so reinstalling brings Undo back.
- "Six icons occupy 186 / 210 / 258 / 306 px" were the widths of the photographs'
  crops, which add a 12 px margin. The icons occupy 174 / 198 / 246 / 294 px;
  the percentages are corrected with them.
- `AGENTS.md` still described the app as unreleased with no UI wired. The bundle's
  copyright line said "All rights reserved"; the licence is MIT.

## [0.1.0] - 2026-09-16

### Added

- The window states what the setting does not reach: macOS's own icons keep
  their spacing, and applying it everywhere takes a sign out and back in. Both
  were found by using the app on hardware.

- Photographs of every preset, with the measured widths, and a comparison image
  stacking them on one canvas: six icons occupy 186px at Minimum against 258px
  at the macOS default. See docs/en/preset-appearance.md.

- The window: pick a preset, apply it, undo it. It draws all four presets at
  once — six sample icons each, on a shared left edge, to the widths measured on
  this version of macOS — marks the one in effect, and doubles as the picker, so
  the choice can be compared before anything is written.
- A single-instance guard, so a second copy exits instead of opening a second
  window onto the same setting.

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
