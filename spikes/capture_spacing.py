"""Photograph the menu bar at each preset, so the difference can be judged by eye.

The measurements in docs/en/phase1-results.md say the widths change. They do not
say whether a person can see it. This captures the same fixture icons at each
preset value and crops each shot to exactly the fixture's own items, so nothing
of the operator's real menu bar ends up in the record.

Same safety as the Phase 1 harness: an exact backup of both keys before any
write, an external watchdog, every mutation serialised behind a lock, and no
further experimental write once recovery has begun.

    python3 spikes/capture_spacing.py run /absolute/output-directory
    python3 spikes/capture_spacing.py restore /absolute/printed-directory
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_phase1 import (  # noqa: E402  — one backup/restore implementation, not two
    KEYS, PROBE, mutation_lock, read_preferences, restore, restoration_values, set_values, watch,
)

# Two groups of three items: enough repetitions that a per-item difference adds
# up to something the eye can judge, without filling the bar.
GROUPS = 2
HOLD_SECONDS = 6.0
STAGES = [("default", None), ("minimum", 4), ("narrow", 8), ("wide", 24)]


def capture(rect, destination):
    """`screencapture -R` measures from the top-left; AppKit from the bottom-left."""
    subprocess.run(["screencapture", "-x", "-R", ",".join(str(round(v)) for v in rect),
                    str(destination)], check=True, timeout=20)


def crop_rectangle(report, margin=6):
    """The box around the fixture's own items, in screencapture coordinates."""
    items = report["items"]
    if not items:
        raise ValueError("the fixture reported no items")
    frames = [i["window_frame"] for i in items]
    if any(f[2] <= 0 or f[3] <= 0 for f in frames):
        raise ValueError("nonpositive item geometry")
    left = min(f[0] for f in frames) - margin
    right = max(f[0] + f[2] for f in frames) + margin
    top_in_appkit = max(f[1] + f[3] for f in frames)
    bottom_in_appkit = min(f[1] for f in frames)
    screen_height = report["screen_frame"][3]
    top = screen_height - top_in_appkit - margin
    height = (top_in_appkit - bottom_in_appkit) + margin * 2
    return (left, top, right - left, height)


def stage(directory, name, value, output_directory):
    if value is not None:
        set_values(directory, {key: value for key in KEYS})
    else:
        set_values(directory, {})

    report_path = directory / f"hold-{name}.json"
    report_path.unlink(missing_ok=True)
    holder = subprocess.Popen([str(PROBE), "hold", str(report_path), str(GROUPS), str(HOLD_SECONDS)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and not report_path.exists():
            time.sleep(0.2)
        if not report_path.exists():
            raise RuntimeError(f"the fixture never reported for stage {name}")
        report = json.loads(report_path.read_text())
        rectangle = crop_rectangle(report)
        image = output_directory / f"menu-bar-{name}.png"
        capture(rectangle, image)
    finally:
        holder.terminate()
        try:
            holder.wait(timeout=5)
        except subprocess.TimeoutExpired:
            holder.kill()

    return {
        "requested_value": value,
        "effective": report["effective"]["cfpreferences"],
        "crop": [round(v) for v in rectangle],
        "item_window_widths": [i["window_frame"][2] for i in report["items"]],
        "image": image.name,
    }


def run(output_directory):
    if not PROBE.exists():
        raise SystemExit(f"probe not built: {PROBE} (run `swift build -c release`)")
    output_directory.mkdir(parents=True, exist_ok=True)

    import tempfile
    directory = Path(tempfile.mkdtemp(prefix="menubar-spacer-capture-", dir="/private/tmp"))
    print(str(directory), flush=True)

    import plistlib
    original = read_preferences(directory, "original")
    restoration_values(original)
    (directory / "original.plist").write_bytes(plistlib.dumps(original))

    watcher = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve().parents[0] / "run_phase1.py"),
         "watch", str(directory)],
        start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    record = {"test": "menubar-spacer preset screenshots", "original": original,
              "groups_of_three_items": GROUPS, "stages": {}}
    try:
        for name, value in STAGES:
            print(f"{name} …", flush=True)
            record["stages"][name] = stage(directory, name, value, output_directory)
    except Exception as exc:
        record["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            record["restored"] = restore(directory)
            (directory / "done").write_text("restored\n")
            watcher.wait(timeout=5)
        except Exception as exc:
            record["restoration_error"] = f"{type(exc).__name__}: {exc}"
        (output_directory / "capture.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({k: v.get("item_window_widths", [None])[0]
                      for k, v in record["stages"].items()}, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["run", "restore"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    if not args.path.is_absolute():
        parser.error("absolute path required")
    if args.mode == "run":
        run(args.path)
    else:
        restore(args.path)
