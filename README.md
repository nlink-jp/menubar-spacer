# menubar-spacer

Adjust the spacing between macOS menu bar icons, and put it back exactly as it was.

macOS has no setting for this. When icons fill the bar — especially on a notched
Mac, where they collide with the application menus — the only lever is a pair of
undocumented global preferences. menubar-spacer changes those two, records what
they held beforehand, and restores that state on demand.

## Requirements

- macOS 27 or later, Apple Silicon. Signed with Developer ID and notarized.
- No permissions. The app needs no Accessibility, Screen Recording or Full Disk
  Access grant, no administrator rights, and no network access.

## What it does

| | |
|---|---|
| Presets | Minimum (4), Narrow (8), OS default, Wide (24) — [what each looks like](docs/en/preset-appearance.md) |
| Compare before choosing | The window draws all four presets at once — six sample icons each, on a shared left edge, to the widths measured on this version of macOS — and marks the one in effect |
| Restore | Returns both keys to the state recorded before the first change, including "unset" |
| Residency | None — launch it, choose, quit |

The spacing value applies to `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`
together, in the current user's global preferences for this Mac only. Nothing
else is written.

Measured on macOS 27.0 with a test app whose status item is 21pt wide:

| Setting | unset (OS default) | 4 | 8 | 24 |
|---|---:|---:|---:|---:|
| Item width | 37pt | 25pt | 29pt | 45pt |

Roughly `width ≈ icon + value`, which puts the built-in default near 16. Six
icons side by side occupy 186px at Minimum against 258px at the default — see
[the photographs](docs/en/preset-appearance.md).

## Limits

- **macOS's own icons do not follow it.** Wi-Fi, battery, the clock, Control
  Center and the input menu keep their spacing whatever this is set to, and a
  sign out does not change that. Only other applications' icons move.
- **A change reaches an app only when that app next launches.** The spacing is
  fixed when an app starts, so a running app keeps its old spacing until you quit
  and reopen it. **Sign out and back in to apply it everywhere at once** — many
  menu bar icons belong to helpers you cannot quit individually. menubar-spacer
  never quits anything for you.
- **Not every app is known to follow the setting.** It was measured with an
  AppKit test app; multiple displays and overflow layouts have not been checked.
- **These preferences are undocumented.** Apple does not support them, and a
  macOS update may change or ignore them. The app reads the values back after
  writing and tells you when they did not take effect.
- The two keys are always changed together; their individual effects are unknown.
- Settings apply to the current user on the current Mac only.

## Before you uninstall

**Click "Undo my changes" first.** Removing the app does not undo the spacing —
the setting belongs to macOS, not to the app — and uninstalling takes the record
of what your Mac held beforehand with it. If that has already happened, the
command below still returns you to the macOS default.

## Undoing it without the app

If the app is gone and the spacing is still changed, this restores the built-in
default:

```bash
defaults -currentHost delete -g NSStatusItemSpacing; defaults -currentHost delete -g NSStatusItemSelectionPadding
```

Then quit and reopen the affected apps, or log out and back in.

## Build from source

```bash
make test        # unit tests
make run         # debug build
make build-app   # signed .app in dist/
```

## How it was measured

See [the measurements](docs/en/phase1-results.md).

## License

MIT — see [LICENSE](LICENSE).

[日本語版 README](README.ja.md)
