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
| Minimum (4) | 174 px | −72 px (−29%) |
| Narrow (8) | 198 px | −48 px (−20%) |
| macOS default | 246 px | — |
| Wide (24) | 294 px | +48 px (+20%) |

The widths are the sum of the six items' own windows (`item_window_widths` in
`evidence/screenshots/capture.json`). An earlier version of this table gave the
width of each photograph's crop, which adds a 12 px margin — 186 / 210 / 258 /
306 — and took its percentages from those.

Per icon that is 12, 8, and −8 points respectively, which matches the geometry
measured in [phase1-results](phase1-results.md): `width ≈ intrinsic + N`.

On a menu bar carrying a dozen third-party icons, Minimum reclaims roughly 145
points — about the width of two application menus.

## Why it is hard to see live

A single row is hard to judge. The app's first attempt showed exactly that — one
strip of real icons in the menu bar, once, with nothing beside it — and it was
tried and found unjudgeable. The difference is obvious in the image above only
because four strips are stacked and share a left edge.

This is a limitation of showing one row, not of the mechanism. The spacing does
change, visibly, by a fifth to a quarter of the width — but a person cannot hold
the previous row in their head accurately enough to see it in isolation. The app
therefore draws the comparison in its own window, to these same widths.

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

## What it does not reach

Using the app on a real Mac turned up two limits that no measurement of our own
fixture could have shown:

- **macOS's own icons keep their spacing.** Wi-Fi, battery, the clock, Control
  Center and the input menu did not move, before or after a sign out.
- **A sign out and back in is what applies it everywhere.** Quitting and
  reopening one app moves that app's icon; most of the rest belong to helpers
  that cannot be quit individually.

Corroborating measurement, taken in one frame with the spacing set to 8 and
every process restarted by a sign in: our own six fresh icons sat at a 29–30 px
pitch, third-party icons at 26–33 px (mean ≈ 29), and the cluster of macOS's own
icons at 34–38 px (mean ≈ 36) — the pitch the default produces. That is
consistent with the observation rather than proof of it: glyph widths differ
between icons, and only a before-and-after across a sign out settles it. The
before-and-after is the operator's own observation above.

## Limits

- Six icons of our own making, not a real menu bar's mixture of widths.
- One display, one scale factor, one wallpaper.
- Point widths as AppKit reports them; the captures are the pixels that resulted.
- Nothing here says a preset is comfortable to click at 4, only how wide it is.
