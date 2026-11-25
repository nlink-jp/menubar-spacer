# macOS 26 — measurements of 2026-11-25 (macOS 26.7.1)

What lowering the floor from macOS 27 to macOS 26 rests on. Commit `ca58e6e`
was copied aside, `Package.swift` and `Info.plist` were changed to 26.0 — no
source or test was touched — and the copy was built, tested and measured on
macOS 26.7.1 (25G241), Apple Silicon, with Xcode 27.2 / SDK 27.2.

| Question | File | Result |
|---|---|---|
| Does it build for 26.0, and do the tests pass there? | `01-build-and-unit-tests.txt` | Release build with no error or warning; both binaries carry `minos 26.0` / `sdk 27.2`. 112 of 117 Swift tests pass, the 5 hardware tests skip without opt-in; the probe self-test, `spikes/test_phase1.py` and `scripts/check-docs.py` pass |
| Do the hardware tests pass against the real preference domain? | `02-hardware-e2e-tests.txt` | 5 of 5 pass; both keys absent before and after |
| Do the spacing keys behave as on 27.0? | `03-…-run1.json`, `04-…-run2.json`, `05-phase1-three-way-diff.txt` | `spikes/run_phase1.py`, run twice: every `result` equals [the 27.0 record](../phase1-hardware-checks.json) — all 15 widths, the same-process and child-process behaviour. `pid` and `child_output` were removed so the schema matches that record |
| Does the app launch? | `06-app-launch-and-single-instance.txt` | Ad-hoc signed bundles: the 27.0 build is refused by LaunchServices (`-10825`, `kLSIncompatibleSystemVersionErr`); the 26.0 build launches, and a second copy exits with "already running" |
| Does the real-domain plist still lag a write (ADR-0001 §2)? | `07-timing-real-domain-26.txt` | Yes: a set reached the plist after 0.8–1.8 s, a delete after up to 58 ms, while the API answered at once. Shorter than on 27.0, still not immediate — the read-back stays on the API |

Not covered: the window was not looked at nor driven by hand,
`spikes/capture_spacing.py` was not run, other apps' items were not observed
after a sign-out, `probe-unwritable-file.swift` and the throwaway-domain probe
were not re-run, and the signed, notarized, Homebrew-installed build was not
tried. Only 26.7.1 was measured; 26.0–26.6 were not.

The `swift` commands ran with `--disable-sandbox` and a throwaway `HOME`, which
is where the SwiftPM cache warnings in `01` come from; the home path in them is
replaced by `<HOME>`, and the host UUID in `07` by `<host uuid>`.
