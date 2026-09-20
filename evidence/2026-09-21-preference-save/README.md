# Whether a preference write was saved — measurements of 2026-09-21 (macOS 27.0)

What ADR-0001 §2 (amended) rests on. Three questions, three probes.

| Question | Probe | Result |
|---|---|---|
| What does CFPreferences report when a write cannot be saved? | `probe-unwritable-file.swift` on a throwaway ByHost domain whose plist was made immutable (`chflags uchg`), driven by hand | `result-unwritable-file.txt`: `CFPreferencesSynchronize` returns true; the API — new processes included — reports the unsaved value for 15 s to about a minute, then the old one; the plist keeps the old value throughout |
| How soon does the plist show a write, in a throwaway domain? | `probe-timing-throwaway-domain.swift` | `result-timing-throwaway-domain.txt`: 0 ms for a saved write; never for an unsaved one |
| How soon does it show one in the real domain (`.GlobalPreferences`, current host)? | `probe-timing-real-domain.swift` under `run-real-domain-guarded.sh` | `result-timing-real-domain.txt`: **4–8 s** after `Synchronize` returns, for a set and for a delete |

The second result does not carry over to the third, and a draft that read the
plist to verify a write failed every successful write in the hardware tests.

`run-real-domain-guarded.sh DIR` writes the real `NSStatusItemSpacing` key. It
sets the Mac's two values aside first, puts them back on every exit path, and
prints what it restored. The same guard runs the hardware tests on a Mac whose
keys are set: `scripts/hardware-test-guarded.sh`.
