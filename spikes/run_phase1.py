"""Phase 1 hardware checks for menubar-spacer.

Answers the three questions the feasibility study left open:

1. What does each preset value (4 / 8 / 24) actually do? Only 4 and 24 were ever
   measured; 8 is an interpolation.
2. Does a status item created in the *same process*, after the write, pick up the
   new value? The preview feature depends on it; the study only ever launched a
   fresh process per value.
3. Does reading the effective values back after a write reflect what was written?

Safety, mirroring the design validated in the feasibility study: an exact backup
of both keys is written before any mutation; every experimental write takes a
lock and is refused once recovery has begun; an external watchdog restores the
backup if this process dies. Only NSStatusItemSpacing and
NSStatusItemSelectionPadding in the current-user/current-host global domain are
ever written.

    python3 spikes/run_phase1.py run /absolute/output.json
    python3 spikes/run_phase1.py restore /absolute/printed-directory   # manual recovery
"""

import argparse
import fcntl
import json
import plistlib
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / ".build/release/SpacingProbe"
KEYS = ("NSStatusItemSpacing", "NSStatusItemSelectionPadding")
WATCHDOG_SECONDS = 150
MUTATION_DEADLINE_SECONDS = 120


# --- preference access (always through the probe, never through `defaults`) ---

def read_preferences(directory, name):
    path = directory / (name + ".plist")
    subprocess.run([str(PROBE), "read", str(path)], check=True, timeout=10)
    return plistlib.loads(path.read_bytes())


@contextmanager
def mutation_lock(directory):
    with (directory / "mutation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def _write_values(directory, values):
    with tempfile.NamedTemporaryFile(dir=directory, suffix=".plist", delete=False) as payload:
        path = Path(payload.name)
    path.write_bytes(plistlib.dumps(values))
    subprocess.run([str(PROBE), "write", str(path)], check=True, timeout=10)


def set_values(directory, values):
    with mutation_lock(directory):
        if (directory / "recovery-started").exists():
            raise RuntimeError("experiment closed for restoration")
        _write_values(directory, values)


def restoration_values(snapshot):
    values = snapshot["current_host"]
    if not isinstance(values, dict) or set(values) - set(KEYS):
        raise ValueError("unexpected preference scope")
    return dict(values)


def restore(directory):
    with mutation_lock(directory):
        (directory / "recovery-started").write_text("no further experimental writes\n")
        original = plistlib.loads((directory / "original.plist").read_bytes())
        _write_values(directory, restoration_values(original))
        restored = read_preferences(directory, "restored")
        if restored != original:
            raise RuntimeError("preference restoration mismatch")
        (directory / "restoration-ok").write_text("exact host values, absence and any-host values match\n")
        return restored


def watch(directory):
    deadline = time.monotonic() + WATCHDOG_SECONDS
    while time.monotonic() < deadline:
        if (directory / "done").exists():
            return
        time.sleep(0.2)
    restore(directory)
    (directory / "watchdog-restored").write_text("restored after watchdog deadline\n")


# --- measurement ---

def run_probe(directory, name, mode, value=None):
    path = directory / (name + ".json")
    path.unlink(missing_ok=True)
    command = [str(PROBE), mode, str(path)]
    if value is not None:
        command.append(str(value))
    subprocess.run(command, check=True, timeout=30 if mode == "same-process" else 20)
    return json.loads(path.read_text())


def widths(items):
    """kind -> (button width, window width, intrinsic width)."""
    if len(items) != 3 or any(not i["has_window"] for i in items):
        raise ValueError("missing own-item windows")
    if {i["kind"] for i in items} != {"variable_text", "square_symbol", "fixed_32"}:
        raise ValueError("fixture identity mismatch")
    if any(i["bounds"][2] <= 0 or i["window_frame"][2] <= 0 for i in items):
        raise ValueError("nonpositive width")
    return {i["kind"]: (i["bounds"][2], i["window_frame"][2], i["intrinsic_width"]) for i in items}


def settled(samples, phase, group):
    """The widths of `group` in `phase`, requiring the last two samples to agree."""
    matching = [s for s in samples if s["phase"] == phase and group in s]
    if len(matching) < 2:
        raise ValueError("incomplete samples for " + phase)
    last, previous = widths(matching[-1][group]), widths(matching[-2][group])
    if last != previous:
        raise ValueError("geometry not settled in " + phase)
    return {kind: {"button_width": b, "window_width": w, "intrinsic_width": i}
            for kind, (b, w, i) in last.items()}


def analyse(report):
    """Turn the recorded stages into the three answers, or say why not."""
    result = {}

    # Q1 / Q3 — per-value geometry from a freshly launched process.
    try:
        geometry = {name: settled(stage["probe"]["samples"], "sample", "before_group")
                    for name, stage in report["stages"].items()}
        result["geometry_by_stage"] = geometry
        result["window_width_variable_text"] = {
            name: g["variable_text"]["window_width"] for name, g in geometry.items()
        }
        result["all_stages_distinct"] = len({
            tuple(sorted((k, v["window_width"]) for k, v in g.items()))
            for name, g in geometry.items() if name != "restored"
        }) == len([n for n in geometry if n != "restored"])
        result["baseline_geometry_restored"] = geometry.get("baseline") == geometry.get("restored")
    except (ValueError, KeyError, TypeError) as exc:
        result["geometry_error"] = f"{type(exc).__name__}: {exc}"

    result["write_read_back_ok"] = all(
        stage.get("write_status", 0) == 0 for stage in report["stages"].values()
    )
    result["effective_values_loaded"] = {
        name: stage["probe"]["effective_at_launch"]["cfpreferences"]
        for name, stage in report["stages"].items()
    }

    # Q2 — same process.
    same = report.get("same_process")
    if same:
        try:
            samples = same["probe"]["samples"]
            before_write = settled(samples, "before_write", "before_group")
            existing_after = settled(samples, "existing_items_after_write", "before_group")
            new_after = settled(samples, "new_items_after_write", "after_group")
            fresh = result.get("geometry_by_stage", {}).get(same["stage_name"])
            result["same_process"] = {
                "requested_value": same["probe"].get("requested_value"),
                "write_status": same["probe"].get("write_status"),
                "existing_items_changed": existing_after != before_write,
                "new_items_changed": new_after != before_write,
                "new_items_match_fresh_process": fresh is not None and new_after == fresh,
                "before_write": before_write,
                "existing_items_after_write": existing_after,
                "new_items_after_write": new_after,
                "fresh_process_same_value": fresh,
            }
            # A child spawned by the very process that wrote the preference —
            # the shape the preview feature would take.
            child = same.get("child_probe")
            if child:
                child_widths = settled(child["samples"], "sample", "before_group")
                result["same_process"]["child_process"] = {
                    "launched": same["probe"].get("child_launched"),
                    "effective_at_launch": child["effective_at_launch"]["cfpreferences"],
                    "widths": child_widths,
                    "matches_fresh_process": fresh is not None and child_widths == fresh,
                    "differs_from_parent": child_widths != new_after,
                }
            else:
                result["same_process"]["child_process"] = {
                    "launched": same["probe"].get("child_launched"),
                    "error": same["probe"].get("child_error", "no child report"),
                }
        except (ValueError, KeyError, TypeError) as exc:
            result["same_process_error"] = f"{type(exc).__name__}: {exc}"

    return result


def run(output):
    if not PROBE.exists():
        raise SystemExit(f"probe not built: {PROBE} (run `swift build -c release`)")

    directory = Path(tempfile.mkdtemp(prefix="menubar-spacer-phase1-", dir="/private/tmp"))
    print(str(directory), flush=True)

    original = read_preferences(directory, "original")
    restoration_values(original)  # refuse to start if the scope holds anything unexpected
    (directory / "original.plist").write_bytes(plistlib.dumps(original))

    watcher = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "watch", str(directory)],
        start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )

    report = {
        "test": "menubar-spacer Phase 1 hardware checks",
        "original": original,
        "stages": {},
    }
    deadline = time.monotonic() + MUTATION_DEADLINE_SECONDS
    try:
        for name, value in [("baseline", None), ("value_4", 4), ("value_8", 8), ("value_24", 24)]:
            if time.monotonic() > deadline:
                raise RuntimeError("mutation deadline exceeded")
            if value is not None:
                set_values(directory, {key: value for key in KEYS})
            print(name + " starting", flush=True)
            report["stages"][name] = {
                "requested_value": value,
                "preferences": read_preferences(directory, name),
                "probe": run_probe(directory, name, "sample"),
            }
            print(name + " sampled", flush=True)

        # Same-process check: start from the untouched state so the delta is large,
        # then let one process write and create new items afterwards.
        set_values(directory, {})
        print("same-process starting", flush=True)
        with mutation_lock(directory):
            if (directory / "recovery-started").exists():
                raise RuntimeError("experiment closed for restoration")
            probe = run_probe(directory, "same-process", "same-process", value=4)
        child_path = Path(probe["child_output"]) if probe.get("child_output") else None
        report["same_process"] = {
            "stage_name": "value_4",
            "probe": probe,
            "child_probe": json.loads(child_path.read_text()) if child_path and child_path.exists() else None,
            "preferences_after": read_preferences(directory, "same-process-after"),
        }
        print("same-process sampled", flush=True)
    except Exception as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            report["restored_preferences"] = restore(directory)
            (directory / "done").write_text("restored\n")
            watcher.wait(timeout=5)
            report["stages"]["restored"] = {
                "requested_value": None,
                "preferences": read_preferences(directory, "after"),
                "probe": run_probe(directory, "restored", "sample"),
            }
        except Exception as exc:
            report["restoration_error"] = f"{type(exc).__name__}: {exc}"
        report["result"] = analyse(report)
        if (directory / "watchdog-restored").exists():
            report["error"] = "watchdog restored during experiment"
        if "error" in report or "restoration_error" in report:
            report["result"]["outcome"] = "inconclusive"
        output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["result"].get("same_process", {}), indent=2), flush=True)
    print(json.dumps(report["result"].get("window_width_variable_text", {}), indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["run", "watch", "restore"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    if not args.path.is_absolute():
        parser.error("absolute path required")
    if args.mode == "run":
        run(args.path)
    elif args.mode == "watch":
        watch(args.path)
    else:
        restore(args.path)
