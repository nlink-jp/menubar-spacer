# menubar-spacer

Adjust the spacing between macOS menu bar icons, and put it back exactly as it was.

macOS has no setting for this. When icons fill the bar — especially on a notched
Mac, where they collide with the application menus — the only lever is a pair of
undocumented global preferences. menubar-spacer changes those two, records what
they held beforehand, and restores that state on demand.

> **Status: in development.** The preference reader, the preset model and their
> tests are in place, and the spacing behaviour is measured on hardware;
> applying, preview and restore are not implemented yet. There is no release to
> install.

## Requirements

- macOS 27 or later, Apple Silicon.
- No permissions. The app needs no Accessibility, Screen Recording or Full Disk
  Access grant, no administrator rights, and no network access.

## What it does

| | |
|---|---|
| Presets | Minimum (4), Narrow (8), OS default, Wide (24) |
| Preview | Shows real status items at the new spacing before you commit to it |
| Restore | Returns both keys to the state recorded before the first change, including "unset" |
| Residency | None — launch it, choose, quit |

The spacing value applies to `NSStatusItemSpacing` and `NSStatusItemSelectionPadding`
together, in the current user's global preferences for this Mac only. Nothing
else is written.

Measured on macOS 27.0 with a test app whose status item is 21pt wide:

| Setting | unset (OS default) | 4 | 8 | 24 |
|---|---:|---:|---:|---:|
| Item width | 37pt | 25pt | 29pt | 45pt |

Roughly `width ≈ icon + value`, which puts the built-in default near 16.

## Limits

- **A change reaches an app only when that app next launches.** The spacing is
  fixed when an app starts, so a running app keeps its old spacing until you quit
  and reopen it, or log out and back in. menubar-spacer never quits other
  applications for you.
- **Not every app is known to follow the setting.** It was measured with an
  AppKit test app. Apple's own menu bar items, multiple displays and overflow
  layouts have not been checked.
- **These preferences are undocumented.** Apple does not support them, and a
  macOS update may change or ignore them. The app reads the values back after
  writing and tells you when they did not take effect.
- The two keys are always changed together; their individual effects are unknown.
- Settings apply to the current user on the current Mac only.

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

Every number above comes from a bounded experiment that backs up both keys before
writing, restores them afterwards, and verifies the restoration — twice, with
identical results. See [the results](docs/en/phase1-results.md).

## License

MIT — see [LICENSE](LICENSE).

[日本語版 README](README.ja.md)
