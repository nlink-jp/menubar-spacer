# What each preset looks like

2026-09-15; macOS 27.0 (26A428), Apple Silicon.

The same six fixture icons, photographed at each preset. Nothing is redrawn or
scaled: each row is the captured pixels, left-aligned on one canvas, with an
orange tick at the right edge of each row so the difference can be measured by
eye.

![The four presets compared](../../evidence/screenshots/menu-bar-comparison.png)

## What the six icons occupy

| Preset | Six icons | Against the default |
|---|---:|---:|
| Minimum (4) | 186 px | −72 px (−28%) |
| Narrow (8) | 210 px | −48 px (−19%) |
| macOS default | 258 px | — |
| Wide (24) | 306 px | +48 px (+19%) |

Per icon that is 12, 8, and −8 points respectively, which matches the geometry
measured in [phase1-results](phase1-results.md): `width ≈ intrinsic + N`.

On a menu bar carrying a dozen third-party icons, Minimum reclaims roughly 145
points — about the width of two application menus.

## Why it is hard to see live

A single row is hard to judge, and the app's own preview shows exactly that: one
row, once, with nothing to compare it against. The difference is obvious in the
table above only because four rows are stacked and share a left edge.

This is a real limitation of the current preview, not a limitation of the
mechanism. The spacing does change, visibly, by a fifth to a quarter of the
width — but a person cannot hold the previous row in their head accurately
enough to see it in isolation.

## How these were taken

`spikes/capture_spacing.py` backs up both keys, walks the presets, launches a
fixture holding six status items at each one, and photographs **only the
fixture's own items** — the crop rectangle is computed from the geometry the
fixture reports, so none of the operator's real menu bar is captured. The keys
are restored to exactly what they held before, verified by a fresh read.

```bash
swift build -c release
python3 spikes/capture_spacing.py run /absolute/output-directory
```

Raw captures and the per-stage record are in
[evidence/screenshots](../../evidence/screenshots).

## Limits

- Six icons of our own making, not a real menu bar's mixture of widths.
- One display, one scale factor, one wallpaper.
- Point widths as AppKit reports them; the captures are the pixels that resulted.
- Nothing here says a preset is comfortable to click at 4, only how wide it is.
