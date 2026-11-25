#!/usr/bin/env python3
"""Checks the documents can be trusted: links resolve, and withdrawn mechanisms
stay withdrawn.

Prose does not compile, so a feature removed from the code can live on in the
documents indefinitely. Every retired name below was a real mechanism that was
built, measured, and then withdrawn; a reappearance means either the mechanism
came back without its documents, or a document was never swept.

The oldest supported macOS is stated in five places — Package.swift, Info.plist,
the cask floor in the Makefile and both READMEs — and none of them reads another,
so they are checked against Package.swift here.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# name -> why it is retired, printed when it reappears
RETIRED = {
    "PreviewSession": "the menu bar preview was withdrawn in Phase 2 (see docs/en/preset-appearance.md)",
    "PreviewLauncher": "the menu bar preview was withdrawn in Phase 2",
    "--preview": "the preview process and its launch flag were withdrawn in Phase 2",
    "previewNote": "the preview message was withdrawn with the preview",
    "isMeasured": "every preset value is measured now; the provenance flag was removed",
    "isPlausible": "values read from a Mac are never range-checked (ADR-0001 §3)",
    # Drafts of the 2026-09-21 amendment that never shipped (ADR-0001, Rejected alternatives).
    "ProcessTrust": "no state is kept for a write in doubt; the premise was measured false",
    "processInDoubt": "no state is kept for a write in doubt; the premise was measured false",
    "isInDoubt": "no state is kept for a write in doubt; the premise was measured false",
    "failureLands": "the stub models what the API reports, not a flush that half-lands",
    "savedOnDisk": "the plist is not read to verify a write: it lags a real one by seconds",
    "currentHostFile": "the plist is not read to verify a write: it lags a real one by seconds",
    "writesAreNotSaved": "an unsaved write is invisible at write time; it is a documented limit",
}

# Homebrew's names for the macOS majors this app may declare as its floor.
# A major missing here is a problem, not a guess: add its name from Homebrew's
# MacOSVersion::SYMBOLS when the floor moves.
BREW_MACOS = {"26": ":tahoe", "27": ":golden_gate"}

SEARCHED = [ROOT / "Sources", ROOT / "Tests", ROOT / "docs", ROOT / "spikes"]
SEARCHED += [ROOT / name for name in ("README.md", "README.ja.md", "AGENTS.md", "CLAUDE.md")]


def files():
    for target in SEARCHED:
        if target.is_file():
            yield target
        elif target.is_dir():
            for path in sorted(target.rglob("*")):
                if path.is_file() and path.suffix in {".swift", ".md", ".py"}:
                    yield path


def floor_problems():
    """Every place that states the oldest supported macOS, against Package.swift."""
    def read(name):
        return (ROOT / name).read_text(encoding="utf-8")

    found = re.search(r'\.macOS\("(\d+)\.0"\)', read("Package.swift"))
    if not found:
        return ['Package.swift: no .macOS("NN.0") platform found']
    major = found.group(1)
    problems = []

    plist = re.search(r"<key>LSMinimumSystemVersion</key>\s*<string>([^<]*)</string>", read("Info.plist"))
    if not plist or plist.group(1) != f"{major}.0":
        problems.append(f"Info.plist: LSMinimumSystemVersion is {plist and plist.group(1)!r}, Package.swift says {major}.0")

    cask = re.search(r"^BREW_MACOS_FLOOR := (\S+)", read("Makefile"), re.MULTILINE)
    if major not in BREW_MACOS:
        problems.append(f"scripts/check-docs.py: no Homebrew name for macOS {major} in BREW_MACOS")
    elif not cask or cask.group(1) != BREW_MACOS[major]:
        problems.append(f"Makefile: BREW_MACOS_FLOOR is {cask and cask.group(1)!r}, macOS {major} is {BREW_MACOS[major]}")

    for name, phrase in (("README.md", f"macOS {major} or later"), ("README.ja.md", f"macOS {major} 以降")):
        if phrase not in read(name):
            problems.append(f"{name}: does not state {phrase!r} (Package.swift says {major}.0)")
    return problems


def main():
    problems = floor_problems()

    for path in files():
        text = path.read_text(encoding="utf-8")
        for name, reason in RETIRED.items():
            for number, line in enumerate(text.splitlines(), 1):
                if name in line:
                    problems.append(f"{path.relative_to(ROOT)}:{number}: retired name {name!r} — {reason}")

    for path in ROOT.rglob("*.md"):
        if ".build" in path.parts:
            continue
        for label, target in re.findall(r"!?\[([^\]]*)\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if target.startswith(("http", "#", "mailto:")):
                continue
            if not (path.parent / target.split("#")[0]).resolve().exists():
                problems.append(f"{path.relative_to(ROOT)}: broken link [{label}]({target})")

    for problem in problems:
        print(problem)
    if problems:
        print(f"\ncheck-docs: {len(problems)} problem(s)")
        return 1
    print("check-docs: links resolve, no retired name in use")
    return 0


if __name__ == "__main__":
    sys.exit(main())
