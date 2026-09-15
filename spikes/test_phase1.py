"""Coordinator guards for the Phase 1 hardware checks.

These run before any preference is touched: a bug in the analysis or in the
restoration guard must not be discovered while the live settings are changed.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phase1 as coordinator  # noqa: E402


def items(widths, kinds=("variable_text", "square_symbol", "fixed_32")):
    return [
        {"kind": kind, "bounds": [0, 0, width, 22], "window_frame": [0, 0, width + 2, 24],
         "intrinsic_width": width, "has_window": True}
        for kind, width in zip(kinds, widths)
    ]


def samples(phase, group, *width_sets):
    return [{"phase": phase, group: items(w)} for w in width_sets]


class RestorationGuardTests(unittest.TestCase):
    def test_accepts_an_empty_scope(self):
        self.assertEqual(coordinator.restoration_values({"current_host": {}}), {})

    def test_accepts_the_two_spacing_keys(self):
        snapshot = {"current_host": {"NSStatusItemSpacing": 4, "NSStatusItemSelectionPadding": 4}}
        self.assertEqual(coordinator.restoration_values(snapshot), snapshot["current_host"])

    def test_refuses_a_scope_holding_anything_else(self):
        # A foreign key means the backup would not describe what we are about to
        # overwrite, so the experiment must not start at all.
        with self.assertRaises(ValueError):
            coordinator.restoration_values({"current_host": {"AppleInterfaceStyle": "Dark"}})

    def test_refuses_a_malformed_snapshot(self):
        with self.assertRaises(ValueError):
            coordinator.restoration_values({"current_host": []})


class WidthTests(unittest.TestCase):
    def test_reads_three_items(self):
        self.assertEqual(
            coordinator.widths(items((21, 22, 32))),
            {"variable_text": (21, 23, 21), "square_symbol": (22, 24, 22), "fixed_32": (32, 34, 32)},
        )

    def test_rejects_a_missing_item(self):
        with self.assertRaises(ValueError):
            coordinator.widths(items((21, 22)))

    def test_rejects_an_item_without_a_window(self):
        broken = items((21, 22, 32))
        broken[1]["has_window"] = False
        with self.assertRaises(ValueError):
            coordinator.widths(broken)

    def test_rejects_a_nonpositive_width(self):
        broken = items((21, 0, 32))
        with self.assertRaises(ValueError):
            coordinator.widths(broken)

    def test_rejects_an_unexpected_fixture(self):
        with self.assertRaises(ValueError):
            coordinator.widths(items((21, 22, 32), kinds=("a", "b", "c")))


class SettledTests(unittest.TestCase):
    def test_requires_the_last_two_samples_to_agree(self):
        unsettled = samples("sample", "before_group", (21, 22, 32), (25, 22, 32))
        with self.assertRaises(ValueError):
            coordinator.settled(unsettled, "sample", "before_group")

    def test_returns_the_settled_widths(self):
        stable = samples("sample", "before_group", (21, 22, 32), (21, 22, 32))
        self.assertEqual(
            coordinator.settled(stable, "sample", "before_group")["variable_text"],
            {"button_width": 21, "window_width": 23, "intrinsic_width": 21},
        )

    def test_requires_at_least_two_samples(self):
        with self.assertRaises(ValueError):
            coordinator.settled(samples("sample", "before_group", (21, 22, 32)), "sample", "before_group")

    def test_ignores_other_phases(self):
        mixed = samples("other", "before_group", (9, 9, 9), (9, 9, 9))
        mixed += samples("sample", "before_group", (21, 22, 32), (21, 22, 32))
        self.assertEqual(coordinator.settled(mixed, "sample", "before_group")["variable_text"]["button_width"], 21)


class AnalysisTests(unittest.TestCase):
    def stage(self, widths_, value, write_status=0):
        return {
            "requested_value": value,
            "write_status": write_status,
            "probe": {
                "effective_at_launch": {"cfpreferences": {} if value is None else
                                        {k: value for k in coordinator.KEYS}},
                "samples": samples("sample", "before_group", widths_, widths_),
            },
        }

    def base_report(self):
        return {"stages": {
            "baseline": self.stage((37, 38, 48), None),
            "value_4": self.stage((25, 26, 36), 4),
            "value_8": self.stage((29, 30, 40), 8),
            "value_24": self.stage((45, 46, 56), 24),
            "restored": self.stage((37, 38, 48), None),
        }}

    def test_reports_each_stage_and_restoration(self):
        result = coordinator.analyse(self.base_report())
        self.assertNotIn("geometry_error", result)
        self.assertTrue(result["all_stages_distinct"])
        self.assertTrue(result["baseline_geometry_restored"])
        self.assertTrue(result["write_read_back_ok"])
        self.assertEqual(result["window_width_variable_text"]["value_8"], 31)

    def test_notices_when_restoration_did_not_reproduce_the_baseline(self):
        report = self.base_report()
        report["stages"]["restored"] = self.stage((29, 30, 40), None)
        self.assertFalse(coordinator.analyse(report)["baseline_geometry_restored"])

    def test_notices_a_failed_write_read_back(self):
        report = self.base_report()
        report["stages"]["value_8"]["write_status"] = 4
        self.assertFalse(coordinator.analyse(report)["write_read_back_ok"])

    def test_notices_two_values_producing_the_same_geometry(self):
        report = self.base_report()
        report["stages"]["value_8"] = self.stage((25, 26, 36), 8)
        self.assertFalse(coordinator.analyse(report)["all_stages_distinct"])

    def test_same_process_detects_new_items_picking_up_the_value(self):
        report = self.base_report()
        report["same_process"] = {"stage_name": "value_4", "probe": {
            "requested_value": 4, "write_status": 0,
            "samples": (samples("before_write", "before_group", (37, 38, 48), (37, 38, 48))
                        + samples("existing_items_after_write", "before_group", (37, 38, 48), (37, 38, 48))
                        + samples("new_items_after_write", "after_group", (25, 26, 36), (25, 26, 36))),
        }}
        same = coordinator.analyse(report)["same_process"]
        self.assertFalse(same["existing_items_changed"])
        self.assertTrue(same["new_items_changed"])
        self.assertTrue(same["new_items_match_fresh_process"])

    def test_same_process_detects_new_items_keeping_the_old_value(self):
        report = self.base_report()
        report["same_process"] = {"stage_name": "value_4", "probe": {
            "requested_value": 4, "write_status": 0,
            "samples": (samples("before_write", "before_group", (37, 38, 48), (37, 38, 48))
                        + samples("existing_items_after_write", "before_group", (37, 38, 48), (37, 38, 48))
                        + samples("new_items_after_write", "after_group", (37, 38, 48), (37, 38, 48))),
        }}
        same = coordinator.analyse(report)["same_process"]
        self.assertFalse(same["new_items_changed"])
        self.assertFalse(same["new_items_match_fresh_process"])

    def test_incomplete_geometry_is_reported_not_guessed(self):
        report = self.base_report()
        report["stages"]["value_8"]["probe"]["samples"] = samples(
            "sample", "before_group", (29, 30, 40), (31, 30, 40))
        result = coordinator.analyse(report)
        self.assertIn("geometry_error", result)
        self.assertNotIn("all_stages_distinct", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
