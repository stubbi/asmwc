#!/usr/bin/env python3
"""Fast benchmark-contract tests; no benchmark corpus or performance trials."""

from __future__ import annotations

from collections import Counter
import contextlib
import csv
import importlib.util
import io
import json
from pathlib import Path
import random
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ripwc_bench_test_subject", ROOT / "bench.py")
BENCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCH)


class BenchmarkTests(unittest.TestCase):
    def test_three_way_orders_cover_every_permutation_and_position_equally(self):
        names = ("rust", "assembly", "previous_assembly")
        orders = BENCH.execution_orders(names, 24, random.Random(123))
        self.assertEqual(Counter(orders), {
            ("rust", "assembly", "previous_assembly"): 4,
            ("rust", "previous_assembly", "assembly"): 4,
            ("assembly", "rust", "previous_assembly"): 4,
            ("assembly", "previous_assembly", "rust"): 4,
            ("previous_assembly", "rust", "assembly"): 4,
            ("previous_assembly", "assembly", "rust"): 4,
        })
        for position in range(3):
            self.assertEqual(Counter(order[position] for order in orders),
                             {"rust": 8, "assembly": 8, "previous_assembly": 8})
        self.assertEqual(orders, BENCH.execution_orders(names, 24, random.Random(123)))
        self.assertNotEqual(orders, BENCH.execution_orders(names, 24, random.Random(456)))

    def test_two_way_orders_remain_balanced_with_partial_final_block(self):
        orders = BENCH.execution_orders(("rust", "assembly"), 13, random.Random(12))
        self.assertEqual(len(orders), 13)
        self.assertEqual(sorted(Counter(orders).values()), [6, 7])

    def test_comparison_uses_medians_and_reports_time_saved_relative_to_before(self):
        case = {}
        BENCH.summarize_case(case, {"rust": [10, 100, 14], "assembly": [5, 1, 4],
                                    "previous_assembly": [6, 12, 24]}, bootstrap_resamples=0)
        self.assertEqual(case["statistics"]["assembly"]["median_seconds"], 4)
        self.assertEqual(case["rust_over_assembly_median"], 3.5)
        self.assertEqual(case["previous_over_assembly_median"], 3)
        self.assertAlmostEqual(case["assembly_time_reduction_percent"], 200 / 3)
        self.assertNotIn("previous_over_assembly_median_ci95", case)

    def test_paired_bootstrap_preserves_matched_samples_and_is_reproducible(self):
        # Every matched observation has exactly the same ratio, despite a large
        # timing range. Resampling implementations independently breaks this.
        before = [2, 20, 200, 2000]
        after = [1, 10, 100, 1000]
        interval = BENCH.paired_median_ratio_ci(before, after, 200, seed=9)
        self.assertEqual(interval, [2.0, 2.0])
        varied = BENCH.paired_median_ratio_ci([2, 3, 8, 11], [1, 2, 3, 5], 200, seed=9)
        self.assertEqual(varied, BENCH.paired_median_ratio_ci(
            [2, 3, 8, 11], [1, 2, 3, 5], 200, seed=9))
        self.assertLess(varied[0], varied[1])

    def fake_binary(self, root, name, *, fail_on=0, failure="stdout"):
        binary = root / name
        counter = root / (name + ".calls")
        # These programs run through the real parity subprocess helper. Only
        # corpus generation and host metadata are replaced in the test harness.
        binary.write_text(
            f"#!{sys.executable}\n"
            "from pathlib import Path\n"
            "import sys\n"
            f"counter = Path({str(counter)!r})\n"
            "count = int(counter.read_text()) + 1 if counter.exists() else 1\n"
            "counter.write_text(str(count))\n"
            f"bad = count == {fail_on}\n"
            f"print('wrong' if bad and {failure!r} == 'stdout' else 'same')\n"
            f"print('wrong' if bad and {failure!r} == 'stderr' else 'same-error', file=sys.stderr)\n"
            f"sys.exit(1 if bad and {failure!r} == 'returncode' else 0)\n"
        )
        binary.chmod(0o755)
        return binary

    def run_tiny_benchmark(self, root, *, before_failure=None, failures=None, runs=6,
                           include_before=True, bootstrap_resamples=0):
        failures = failures or {}
        rust = self.fake_binary(root, "rust", **failures.get("rust", {}))
        assembly = self.fake_binary(root, "assembly", **failures.get("assembly", {}))
        before = self.fake_binary(root, "previous", **(before_failure or failures.get("previous_assembly", {})))
        output = root / "report"
        argv = ["bench.py", "--rust", str(rust), "--asm", str(assembly),
                "--runs", str(runs), "--warmups", "1", "--output-dir", str(output),
                "--corpus", str(root), "--bootstrap-resamples", str(bootstrap_resamples)]
        if include_before:
            argv.extend(("--before", str(before)))
        case = {"name": "tiny/default", "argv": ["fixture"], "input_bytes": 4,
                "files": 1, "kind": "scan"}
        with patch.object(sys, "argv", argv), \
                patch.object(BENCH, "prepare_corpus", return_value={"files": {}}), \
                patch.object(BENCH, "workload_cases", return_value=[case]), \
                patch.object(BENCH, "machine_info", return_value={}), \
                patch.object(BENCH, "build_info", return_value={}), \
                contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            status = BENCH.main()
        return status, json.loads((output / "benchmark.json").read_text()), output

    def test_three_way_report_records_all_binaries_and_balanced_raw_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            status, report, output = self.run_tiny_benchmark(Path(directory), bootstrap_resamples=100)
            self.assertEqual(status, 0)
            self.assertEqual(report["status"], "passed")
            self.assertEqual(set(report["binaries"]), {"rust", "assembly", "previous_assembly"})
            case = report["cases"][0]
            self.assertTrue(case["preflight"]["passed"])
            self.assertEqual(set(case["statistics"]), {"rust", "assembly", "previous_assembly"})
            self.assertIn("previous_over_assembly_median", case)
            self.assertIn("assembly_time_reduction_percent", case)
            interval = case["previous_over_assembly_median_ci95"]
            self.assertLessEqual(interval[0], interval[1])
            with (output / "benchmark-samples.csv").open(newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(Counter(row["implementation"] for row in rows),
                             {"rust": 6, "assembly": 6, "previous_assembly": 6})
            orders = [tuple(row["implementation"] for row in rows[offset:offset + 3])
                      for offset in range(0, len(rows), 3)]
            self.assertEqual(len(set(orders)), 6)
            for sample in case["samples"]:
                self.assertEqual(sample["stdout_sha256"], case["preflight"]["stdout_sha256"])
                self.assertEqual(sample["stderr_sha256"], case["preflight"]["stderr_sha256"])
            with (output / "benchmark.csv").open(newline="") as stream:
                summaries = list(csv.DictReader(stream))
            self.assertEqual(len(summaries), 3)
            for row in summaries:
                self.assertIn("rust_over_assembly_median", row)
                self.assertEqual(float(row["previous_over_assembly_median"]),
                                 case["previous_over_assembly_median"])
                self.assertEqual(float(row["previous_over_assembly_median_ci95_low"]), interval[0])
                self.assertEqual(float(row["previous_over_assembly_median_ci95_high"]), interval[1])

    def test_before_is_optional_and_existing_two_way_report_still_works(self):
        with tempfile.TemporaryDirectory() as directory:
            status, report, _ = self.run_tiny_benchmark(Path(directory), runs=2, include_before=False)
            self.assertEqual(status, 0)
            self.assertEqual(set(report["cases"][0]["statistics"]), {"rust", "assembly"})
            self.assertNotIn("previous_over_assembly_median", report["cases"][0])

    def test_previous_assembly_preflight_failure_prevents_all_measurements(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status, report, _ = self.run_tiny_benchmark(root, before_failure={"fail_on": 1})
            self.assertEqual(status, 1)
            self.assertFalse(report["cases"][0]["preflight"]["passed"])
            self.assertNotIn("samples", report["cases"][0])
            self.assertEqual((root / "rust.calls").read_text(), "1")
            self.assertEqual((root / "assembly.calls").read_text(), "1")

    def test_each_implementation_output_or_status_change_rejects_timing_results(self):
        for implementation in ("rust", "assembly", "previous_assembly"):
            for failure in ("stdout", "stderr", "returncode"):
                with self.subTest(implementation=implementation, failure=failure), \
                        tempfile.TemporaryDirectory() as directory:
                    # Call 1 is preflight; call 2 is warmup; call 3 is measured.
                    status, report, _ = self.run_tiny_benchmark(Path(directory), failures={
                        implementation: {"fail_on": 3, "failure": failure}})
                    self.assertEqual(status, 1)
                    self.assertEqual(report["status"], "failed")
                    self.assertIn(implementation, report["error"])
                    self.assertNotIn("statistics", report["cases"][0])


if __name__ == "__main__":
    unittest.main()
