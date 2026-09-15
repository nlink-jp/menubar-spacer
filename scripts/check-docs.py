#!/usr/bin/env python3
"""Checks the documents can be trusted: links resolve, and withdrawn mechanisms
stay withdrawn.

Prose does not compile, so a feature removed from the code can live on in the
documents indefinitely. Every retired name below was a real mechanism that was
built, measured, and then withdrawn; a reappearance means either the mechanism
came back without its documents, or a document was never swept.
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
}

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


def main():
    problems = []

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
