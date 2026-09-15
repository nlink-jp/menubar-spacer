# RFP: menubar-spacer

> Generated: 2026-09-15
> Status: Draft (Phase 1 hardware checks complete — [results](phase1-results.md))

## 1. Problem Statement

macOS 27 exposes no public setting for menu bar icon spacing. As icons accumulate
they exhaust the available width, and on notched Macs they collide with the
application menus on the left until items become unreachable. Changing two
undocumented keys in the global preference domain — `NSStatusItemSpacing` and
`NSStatusItemSelectionPadding` — does change the spacing; this was measured on
hardware (see the spacing experiment in `_wip/menu-bar-feasibility`: machine-read
width changes plus the user's visual confirmation). menubar-spacer applies a
preset to **those two keys only**, records the prior state exactly — including
"the key was absent" — and restores it completely. It is a non-resident macOS app
for ordinary users: no terminal, no permission grants.

## 2. Functional Specification

### Commands / API Surface

A GUI-only app (no CLI). A non-resident window app: launch → pick a preset →
apply → quit.

| UI element | Content |
|---|---|
| Current state | Current value of both keys ("OS default" when absent), and whether menubar-spacer set it |
| Preset picker | Minimum (4) / Narrow (8) / OS default / Wide (24) |
| Sample | Draws every preset at once — six sample icons each, shared left edge, measured widths — marking the one in effect. Clicking a row chooses it |
| Apply | Writes the preset, then reads the effective values back to verify the result |
| Restore | Returns to the recorded prior state, including absence |
| Guidance | States that a target app must be relaunched — or the user logged out — before the change shows |

The "OS default" preset is implemented as **deleting** both keys, taking the same
code path as restore. The app never quits or restarts other applications.

### Input / Output

- Input: GUI interaction only. No stdin, no arguments.
- Output: GUI only. No machine-readable output on stdout.
- Persisted data: one backup record of the prior state, as JSON, at
  `~/Library/Application Support/jp.nlink.menubar-spacer/backup.json`. The type
  distinguishes "absent" from any value, and writes are atomic.

### Configuration

The app has no settings of its own. The selected preset is derived from the
current OS values, so its own state cannot drift from what the OS actually holds.

### Write scope

CFPreferences **current user / current host / any application**
(`kCFPreferencesCurrentUser` / `kCFPreferencesCurrentHost` /
`kCFPreferencesAnyApplication`) only. The any-host scope is read for display and
never written. This is the same scope the feasibility study validated.

### External Dependencies

None. No network traffic, no credentials, no external services, and no
third-party libraries.

## 3. Design Decisions

**Language / framework: Swift 6, SwiftUI + AppKit, Swift Package Manager.**
The exact CFPreferences scopes must be addressed directly, and the app draws
status-item geometry. util-series already has an established GUI-only Swift/SPM
shape — share-mounter, load-spinner, url-shelf, instant-translate, grid-edit,
zip-porter — and instant-translate is the reference project.

**Why no CLI.** The util-series pattern "a GUI is a thin frontend over a signed
CLI" applies where the CLI is valuable on its own. Here the entire operation is
reading and writing two preference keys: there is no data to pipe and no other
tool to compose with. A separate CLI would double the signing, notarization and
distribution surface with no benefit to the user.

**Complements.** Nothing; the tool stands alone. Its evidence base is the
`_wip/menu-bar-feasibility` study (measured values and restoration procedure).

**Explicitly out of scope.**

- Hiding and revealing menu bar icons (the study's adoption gate was not met; held as a separate problem)
- Reordering icons
- Residency, login items, hotkeys
- Quitting or relaunching other applications on the user's behalf
- Setting the two keys independently (they were only ever validated changed together)
- The any-host scope, other user accounts, other hosts
- Multiple profiles, themes, icon imagery

## 4. Development Plan

### Phase 1: Core

1. Preference layer: read, write and delete in the current-user/current-host/
   any-application scope. A type that distinguishes "absent" from a value.
   Read-only access to the any-host scope for display.
2. Backup layer: record and restore the prior state. Atomic writes. Detection of
   changes made outside the app.
3. Hardware checks (macOS 27.0, Apple Silicon) — **done, see [results](phase1-results.md)**:
   - Presets 4, 8 and 24 are all measured now (widths 25 / 29 / 45; unset is 37).
   - **The value is latched per process.** Items created in the same process after
     a write do not pick it up; a child process spawned by that process does.
   - Read-back after every write matched what was written.
4. Unit tests: state transitions (absent → value → absent), backup round trips,
   external-change detection, rejection of out-of-range and malformed values.

**Independently reviewable.** This layer writes preferences destructively, so a
review is mandatory.

### Phase 2: Features

5. The SwiftUI window, preset picker, and current-state display.
6. An in-window sample drawn to the measured geometry, showing every preset at
   once on a shared left edge. It is also the picker. Replaces the menu bar
   preview (below).
7. Relaunch guidance, a path back to OS defaults before uninstalling, app icon.

**Independently reviewable.**

### Phase 3: Release

8. README.md / README.ja.md / CHANGELOG.md / AGENTS.md.
9. Developer ID signing, notarization, stapling, and `make verify-release`.
10. GitHub release and a Homebrew cask (`BREW_MACOS_FLOOR` set for macOS 27).
11. Add as a util-series submodule, update the org profile, run `check-org.sh`,
    and feed reusable findings back to `nlink-jp/knowledge`.

## 5. Required API Scopes / Permissions

**None.**

- No TCC grants (Accessibility, Screen Recording, Full Disk Access). Reading and
  writing its own preference domain and creating its own status items is enough.
- No administrator rights, no SIP changes, no privileged helper.
- No network access, no credentials.
- Hardened Runtime only; native Swift/AppKit needs no special entitlement.

Requiring no permission at all is a deliberate property of this tool and is
treated as a requirement to preserve.

## 6. Series Placement

Series: **util-series**

Reason: a general local utility. util-series already contains six GUI-only
Swift/SPM apps (share-mounter, load-spinner, url-shelf, instant-translate,
grid-edit, zip-porter). cli-series is for authenticated clients of external
services, lite-series for LLM tooling, cybersecurity-series for threat
intelligence and IR — none of which fit.

## 7. External Platform Constraints

1. **It depends on undocumented OS settings.** Apple documents nothing and
   supports nothing here; an OS update may change or disable the behavior. The
   app reads the effective values back after applying and reports "no effect"
   when they do not match.
2. **Only newly launched processes are affected.** The value is latched per
   process, so a running app's status items do not change even if that app
   recreates them. Restarting Finder or logging out was never shown to be
   necessary, but a fresh launch was shown to be sufficient.
3. **The two keys were only ever validated changed together.** Individual effects
   are unknown, so the product changes them together as well.
4. **Compatibility with all apps is unverified.** Only our own AppKit fixture was
   measured. Apple's own items, multiple displays and overflow layouts are untested.
5. **App Store distribution is not possible.** A sandboxed app cannot write the
   global preference domain. Direct distribution (Developer ID + notarization) only.
6. **macOS 27 and later, Apple Silicon.** Measurements come from 27.0 (26A428)
   only. macOS 26 and earlier were not tested and are out of scope.
7. **Current user and current host only.** Other accounts and other Macs are unaffected.

---

## Discussion Log

- The starting point was the `_wip/menu-bar-feasibility` study. Its primary
  candidate — hide/reveal through the private `MBAssessmentModeAssertion` API —
  failed the adoption gate: fixture B, which was explicitly allowed, disappeared
  along with an audio/video system identifier. Only the spacing result held up
  under measurement, so that is what gets productized.
- The name follows the util-series "target + agent" pattern (share-mounter,
  zip-porter, load-spinner). `spacing-lens` was rejected because the lens family
  is about measurement and visualization, not changing settings.
- The deliverable is GUI-only. The "GUI is a thin frontend over a CLI" pattern
  applies where a standalone CLI is valuable, which is not the case here; six
  existing GUI-only Swift apps are the precedent.
- Presets were chosen over a numeric slider: not every value can be validated, so
  a slider would need an "unverified range" indicator that undercuts the point of
  a single-purpose tool.
- Basis for the preset values: measured text-item window widths against an
  intrinsic width of 21pt were 37 when absent, 25 at 4/4 and 45 at 24/24, which
  reads as `width ≈ intrinsic + N`, putting the OS default near N ≈ 16. Only two
  points were measured, so 8 is an interpolation to be confirmed in Phase 1.
- "Guidance only" was chosen for the relaunch problem, because quitting other
  apps on the user's behalf can destroy unsaved work.
- A preview in the real menu bar was built in Phase 2 and then **withdrawn**.
  It worked — a child process does pick up a freshly written value — but it can
  only run *after* a write, and one strip of icons seen once, with nothing to
  compare it against, turned out to be unjudgeable in practice: the user tried
  it and could not tell whether anything had changed. The photographs in
  [preset-appearance](preset-appearance.md) are legible only because four strips
  share a left edge.
- The replacement is an **in-window sample**: every preset drawn at once, six
  icons each, on a shared left edge — the arrangement that makes the
  photographs legible — before applying anything. It doubles as the picker. It
  is a scale drawing, and its geometry is pinned by tests to the widths
  measured on hardware, so it cannot drift away from what it depicts.
- Supported OS is limited to macOS 27+. A macOS 26 Apple Silicon machine was
  available to test on, but the chosen policy is to promise only what has been
  measured rather than widen the verification surface.
- Distribution is GitHub Release plus a Homebrew cask, the same route as the
  other Swift GUI apps.
