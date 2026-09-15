# Phase 1 hardware checks

2026-09-15; macOS 27.0 (26A428), Apple Silicon.

**All three open questions are answered, and both the preset values and the
preview design are settled.** Two complete runs produced identical numbers, and
the preferences were restored to their original absent state after each.

## Method

`spikes/run_phase1.py` captures an exact backup of both keys before any write,
arms an external watchdog that restores it if the coordinator dies, serialises
every mutation behind a lock, and refuses any further experimental write once
recovery has begun. Only `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`
in the current-user / current-host / any-application domain were written.

`Sources/SpacingProbe` creates three status items matching the feasibility
study's fixture — variable-length text, square symbol, fixed width 32 — and
records their AppKit geometry at three moments, requiring the last two samples to
agree before a measurement counts. Twenty coordinator guard cases run before any
preference is touched.

The numbers below are **AppKit-reported widths in points, not measured pixel gaps
between icons**, and they come from our own fixture, not from other applications.

## 1. What each preset value does

Status-item window width, by stage. The text item's intrinsic width is 21pt.

| Stage | Variable text | Square symbol | Fixed width 32 |
|---|---:|---:|---:|
| Keys absent (OS default) | 37 | 38 | 48 |
| Both keys 4 | 25 | 26 | 36 |
| **Both keys 8** | **29** | **30** | **40** |
| Both keys 24 | 45 | 46 | 56 |
| Restored (absent) | 37 | 38 | 48 |

`width ≈ intrinsic + N` holds at every measured point: 8 produced exactly 29 as
the two-point hypothesis predicted, so `narrow` is now a measured value rather
than an interpolation. Every stage is distinct, and the built-in default behaves
like N ≈ 16.

Each stage's probe read back the values it was supposed to see
(`{spacing: 4, padding: 4}` and so on), and the restored stage reproduced the
baseline geometry exactly.

## 2. Same process vs. child process

A single process created three items, wrote `4` to both keys from an unset start,
then created three more items.

| Observation | Result |
|---|---|
| Items that already existed | Unchanged (37 / 38 / 48) |
| **New items in the same process** | **Unchanged (37 / 38 / 48)** |
| **A child process launched by that same process** | **25 / 26 / 36 — matches a fresh process exactly** |

So the value is latched per process, not per status item: a process keeps
whatever spacing was in effect when it started, no matter when its items are
created. Writing the preference and spawning a short-lived child is enough — the
app does not need to relaunch itself.

**Consequence for the product.** The preview is a child process: apply the value,
spawn the same executable in a preview mode, let it show its own status items,
and let it exit. The relaunch-the-app fallback named in the RFP is not needed.

## 3. Read-back after a write

Every write returned a verified read-back: the current-host scope held exactly
what was written, and the deletion path left both keys absent in both the
current-host and any-host scopes. The probe reports a mismatch as an error code
rather than assuming success, and no mismatch occurred in either run.

## What this does not establish

- Other applications' menu bar items, Apple's own items, multiple displays and
  overflow layouts remain unmeasured. Only our fixture was observed.
- These are AppKit geometry values, not rendered pixel gaps, and not a judgement
  about whether a compact value stays comfortable to click.
- Nothing here says the behaviour survives a macOS update; these preferences stay
  undocumented.
- The individual effect of each key is still unknown — they were changed together
  throughout, as the product will.

## Reproduce

```bash
swift build -c release
python3 spikes/test_phase1.py                       # 20 coordinator guards
python3 spikes/run_phase1.py run /absolute/out.json
```

The runner prints a private temporary directory. If anything is left changed,
`python3 spikes/run_phase1.py restore /absolute/printed-directory` puts the two
backed-up keys back. Do not run two spacing experiments at once.

Evidence: [phase1-hardware-checks.json](../../evidence/phase1-hardware-checks.json)
(second run, process ids removed).
