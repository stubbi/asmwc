#!/usr/bin/env python3
"""Validate committed evidence integrity and independently recompute medians."""
from __future__ import annotations

from collections import Counter
import hashlib
import itertools
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "benchmarks/results/apple-m3-2026-10-31"


def close(actual, expected, name):
    if not math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-15):
        raise ValueError(f"incorrect {name}: {actual} != {expected}")


def verify(directory: Path = EVIDENCE):
    manifest = json.loads((directory / "PUBLICATION.json").read_text())
    for relative, expected in manifest["files"].items():
        path = directory / relative
        if not path.resolve().is_relative_to(directory.resolve()):
            raise ValueError(f"evidence path escapes publication: {relative}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"evidence checksum mismatch: {relative}")
        content = path.read_text()
        if "/Users/" in content or ".local " in content or "/var/folders/" in content:
            raise ValueError(f"local identifying path/hostname in publication: {relative}")
    report = json.loads((directory / "benchmark.json").read_text())
    if report["status"] != "passed" or report["runs_per_implementation"] != 24:
        raise ValueError("expected the captured successful 24-run comparison")
    names = tuple(report["binaries"])
    if len(names) != 3 or len(report["cases"]) != 18:
        raise ValueError("expected three executables and 18 workloads")
    for case in report["cases"]:
        if not case["preflight"]["passed"]:
            raise ValueError(f"failed preflight: {case['name']}")
        samples = case["samples"]
        for name in names:
            values = [sample["seconds"] for sample in samples if sample["implementation"] == name]
            if len(values) != 24 or not all(value > 0 for value in values):
                raise ValueError(f"invalid samples: {case['name']}/{name}")
            close(case["statistics"][name]["median_seconds"], statistics.median(values), "median")
        orders = Counter(tuple(sample["implementation"] for sample in samples[offset:offset+3])
                         for offset in range(0, len(samples), 3))
        if orders != Counter({order: 4 for order in itertools.permutations(names)}):
            raise ValueError(f"unbalanced execution order: {case['name']}")
        for sample in samples:
            if any(sample[key] != case["preflight"][key] for key in ("stdout_sha256", "stderr_sha256")):
                raise ValueError(f"output changed in measured sample: {case['name']}")
        medians = {key: item["median_seconds"] for key, item in case["statistics"].items()}
        close(case["rust_over_assembly_median"], medians["rust"] / medians["assembly"], "Rust speed ratio")
        close(case["previous_over_assembly_median"], medians["previous_assembly"] / medians["assembly"], "assembly speed ratio")
        close(case["assembly_time_reduction_percent"], 100 * (1 - medians["assembly"] / medians["previous_assembly"]), "time reduction")
    parity = json.loads((directory / "parity.json").read_text())
    for key, name in (("asm", "assembly"), ("rust", "rust")):
        if parity["binaries"][key]["sha256"] != report["binaries"][name]["sha256"]:
            raise ValueError(f"measured/tested executable hash mismatch: {name}")
    for relative in ("parity.json", "io-boundaries.json", "pipeline-parity.json"):
        if json.loads((directory / relative).read_text())["status"] != "passed":
            raise ValueError(f"recorded test failure: {relative}")
    return len(report["cases"]), sum(len(case["samples"]) for case in report["cases"])


if __name__ == "__main__":
    cases, samples = verify()
    print(f"Published evidence verified: {cases} workloads, {samples} samples, checksums and output hashes.")
