#!/usr/bin/env python3
"""Reproducible end-to-end warm-cache asmwc and ripwc comparison.

Default: 128 MiB text/binary files, 64 files totalling 128 MiB, 12 measured
invocations of each executable per case. --quick uses 64 MiB and five cases,
but retains 12 repetitions. --runs 2 is available for a diagnostic smoke run.
--before adds a preserved assembly executable for a three-way comparison;
use a multiple of six runs (for example 24) to balance every execution order.
No third-party Python modules are needed. Run after builds and tests finish.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
MIB = 1024 * 1024
UPSTREAM_COMMIT = "de1a12e8e2d7c031404370773e5099b23ef01e95"
SEED = 0x5249505743

# Reuse the exact invocation/environment and comparison contract from parity.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("asmwc_parity", ROOT / "tests/parity.py")
PARITY = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PARITY
SPEC.loader.exec_module(PARITY)


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(MIB):
            hasher.update(block)
    return hasher.hexdigest()


def write_pattern(path, pattern, length):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        while length:
            portion = pattern[:min(length, len(pattern))]
            stream.write(portion)
            length -= len(portion)


def prepare_corpus(root, size_mib):
    config = {"version": 1, "seed": SEED, "size_mib": size_mib, "many_count": 64}
    expected_sizes = {"text.dat": size_mib * MIB, "binary.dat": size_mib * MIB, "small.txt": 4096}
    expected_sizes.update({f"many/file-{index:03d}.dat": size_mib * MIB // config["many_count"]
                           for index in range(config["many_count"])})
    manifest_path = root / "manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("config") == config:
            actual_many = {str(path.relative_to(root)) for path in (root / "many").rglob("*")
                           if path.is_file()}
            expected_many = {name for name in expected_sizes if name.startswith("many/")}
            valid = (set(manifest.get("files", {})) == set(expected_sizes)
                     and actual_many == expected_many
                     and all((root / name).is_file()
                        and (root / name).stat().st_size == info["bytes"] == expected_sizes[name]
                        and digest(root / name) == info["sha256"]
                        for name, info in manifest["files"].items()))
            if valid:
                return manifest
    root.mkdir(parents=True, exist_ok=True)
    if not manifest_path.is_file() and any(root.iterdir()):
        raise RuntimeError(f"corpus directory is nonempty without a generated manifest: {root}")
    # This dedicated directory is owned by the corpus generator. A manifest is
    # required before replacing an existing generated many-file dataset.
    many = root / "many"
    if many.exists():
        shutil.rmtree(many)
    text_line = (b"The quick brown fox jumps over 13 lazy dogs.\t"
                 b"Tabs, CR\r, punctuation; and UTF-8: caf\xc3\xa9 \xe4\xb8\x96\xe7\x95\x8c.\n")
    text_block = (text_line * ((MIB + len(text_line) - 1) // len(text_line)))[:MIB]
    rng = random.Random(SEED)
    binary_block = rng.randbytes(MIB)
    total = size_mib * MIB
    write_pattern(root / "text.dat", text_block, total)
    write_pattern(root / "binary.dat", binary_block, total)
    write_pattern(root / "small.txt", text_line, 4096)
    for index in range(config["many_count"]):
        block = text_block if index % 2 == 0 else binary_block
        write_pattern(many / f"file-{index:03d}.dat", block, total // config["many_count"])
    files = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and (path.name in ("text.dat", "binary.dat", "small.txt")
                               or path.parent == many):
            files[str(path.relative_to(root))] = {"bytes": path.stat().st_size, "sha256": digest(path)}
    manifest = {"config": config, "files": files}
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def machine_info():
    information = {"platform": platform.platform(), "machine": platform.machine(),
                   "python": platform.python_version(), "available_logical_cpus": os.cpu_count(),
                   "affinity": "all inherit the benchmark process CPU availability; no per-executable restriction"}
    if hasattr(os, "sched_getaffinity"):
        information["cpu_affinity"] = sorted(os.sched_getaffinity(0))
    if sys.platform == "darwin":
        for key in ("hw.model", "hw.memsize", "hw.physicalcpu", "hw.logicalcpu", "machdep.cpu.brand_string"):
            result = subprocess.run(["/usr/sbin/sysctl", "-n", key], capture_output=True, check=False)
            if result.returncode == 0:
                information[key] = result.stdout.decode().strip()
    return information


def build_info():
    info = {"recipes": {}, "toolchains": {}}
    for relative in ("build-rust.sh", "upstream/Cargo.toml", "Makefile"):
        path = ROOT / relative
        if path.is_file():
            info["recipes"][relative] = {"sha256": digest(path), "text": path.read_text()}
    for tool in ("rustc", "cargo", "clang"):
        executable = shutil.which(tool)
        if executable:
            result = subprocess.run([executable, "--version"], capture_output=True, check=False)
            if result.returncode == 0:
                info["toolchains"][tool] = result.stdout.decode(errors="replace").splitlines()[0]
    return info


def workload_cases(quick, size_mib, extended=False):
    modes = {"default": (), "lines": ("-l",), "words": ("-w",),
             "chars": ("-m",), "max-line": ("-L",), "byte-metadata": ("-c",)}
    if extended:
        modes["all-counts"] = ("-lwmcL",)
    cases = []
    for corpus in ("text", "binary"):
        for mode, flags in modes.items():
            cases.append({"name": f"{corpus}/{mode}", "argv": [*flags, corpus + ".dat"],
                          "input_bytes": size_mib * MIB, "files": 1,
                          "kind": "metadata" if mode == "byte-metadata" else "scan"})
    for mode in ("default", "chars"):
        cases.append({"name": f"many/{mode}", "argv": ["-r", *modes[mode], "many"],
                      "input_bytes": size_mib * MIB, "files": 64, "kind": "scan"})
    for mode in ("default", "byte-metadata"):
        cases.append({"name": f"startup/{mode}", "argv": [*modes[mode], "small.txt"],
                      "input_bytes": 4096, "files": 1, "kind": "startup"})
    if quick:
        selected = {"text/default", "binary/default", "text/byte-metadata", "many/default", "startup/default"}
        cases = [case for case in cases if case["name"] in selected]
    return cases


def stats(values):
    return {"runs": len(values), "median_seconds": statistics.median(values),
            "mean_seconds": statistics.mean(values), "min_seconds": min(values),
            "max_seconds": max(values),
            "stdev_seconds": statistics.stdev(values) if len(values) > 1 else 0.0}


def execution_orders(implementations, runs, rng):
    """Seeded complete permutation blocks, followed by at most one partial block."""
    permutations = list(itertools.permutations(implementations))
    orders = []
    while len(orders) < runs:
        block = permutations.copy()
        rng.shuffle(block)
        orders.extend(block[:runs - len(orders)])
    return orders


def paired_median_ratio_ci(before, after, resamples, seed=SEED):
    """Percentile 95% CI, resampling matched repetitions together."""
    rng = random.Random(seed)
    ratios = []
    for _ in range(resamples):
        indices = rng.choices(range(len(before)), k=len(before))
        ratios.append(statistics.median(before[index] for index in indices)
                      / statistics.median(after[index] for index in indices))
    ratios.sort()

    def percentile(fraction):
        offset = (len(ratios) - 1) * fraction
        lower = int(offset)
        upper = min(lower + 1, len(ratios) - 1)
        return ratios[lower] + (ratios[upper] - ratios[lower]) * (offset - lower)

    return [percentile(0.025), percentile(0.975)]


def summarize_case(case, values, bootstrap_resamples=5000):
    case["statistics"] = {name: stats(samples) for name, samples in values.items()}
    medians = {name: summary["median_seconds"] for name, summary in case["statistics"].items()}
    case["rust_over_assembly_median"] = medians["rust"] / medians["assembly"]
    if "previous_assembly" in values:
        case["previous_over_assembly_median"] = medians["previous_assembly"] / medians["assembly"]
        case["assembly_time_reduction_percent"] = 100 * (1 - medians["assembly"] / medians["previous_assembly"])
        if bootstrap_resamples:
            case["previous_over_assembly_median_ci95"] = paired_median_ratio_ci(
                values["previous_assembly"], values["assembly"], bootstrap_resamples)


def write_results(output, report):
    output.mkdir(parents=True, exist_ok=True)
    (output / "benchmark.json").write_text(json.dumps(report, indent=2) + "\n")
    with (output / "benchmark.csv").open("w", newline="") as stream:
        fields = ["case", "implementation", "kind", "input_bytes", "files", "runs",
                  "median_seconds", "mean_seconds", "min_seconds", "max_seconds", "stdev_seconds",
                  "scan_mib_per_second", "rust_over_assembly_median",
                  "previous_over_assembly_median", "assembly_time_reduction_percent",
                  "previous_over_assembly_median_ci95_low", "previous_over_assembly_median_ci95_high"]
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for case in report["cases"]:
            if "statistics" not in case:
                continue
            for implementation, summary in case["statistics"].items():
                row = {"case": case["name"], "implementation": implementation,
                       "kind": case["kind"], "input_bytes": case["input_bytes"], "files": case["files"],
                       **summary, "rust_over_assembly_median": case["rust_over_assembly_median"]}
                for field in ("previous_over_assembly_median", "assembly_time_reduction_percent"):
                    row[field] = case.get(field, "")
                interval = case.get("previous_over_assembly_median_ci95", ("", ""))
                row["previous_over_assembly_median_ci95_low"], row["previous_over_assembly_median_ci95_high"] = interval
                row["scan_mib_per_second"] = (case["input_bytes"] / MIB / summary["median_seconds"]
                                               if case["kind"] == "scan" else "")
                writer.writerow(row)
    with (output / "benchmark-samples.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=("case", "repetition", "position", "implementation", "seconds",
                                                   "stdout_sha256", "stderr_sha256", "returncode"))
        writer.writeheader()
        for case in report["cases"]:
            for sample in case.get("samples", []):
                writer.writerow({"case": case["name"], **sample})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rust", type=Path, default=ROOT / "bin/asmwc-rust")
    parser.add_argument("--asm", type=Path, default=ROOT / "bin/asmwc")
    parser.add_argument("--before", type=Path, help="preserved assembly executable to compare against --asm")
    parser.add_argument("--quick", action="store_true", help="five cases, 64 MiB unless overridden; keep 12 repetitions")
    parser.add_argument("--extended", action="store_true", help="also benchmark all five counting flags together")
    parser.add_argument("--size-mib", type=int, choices=(64, 128, 256), help="per large file and total many-file bytes")
    parser.add_argument("--runs", type=int, default=12, help="measured invocations per executable/case (default: 12)")
    parser.add_argument("--warmups", type=int, default=2, help="untimed invocations per executable/case (default: 2)")
    parser.add_argument("--bootstrap-resamples", type=int, default=5000,
                        help="paired bootstrap samples for before/assembly 95%% interval; 0 disables (default: 5000)")
    parser.add_argument("--case", action="append", default=[], help="select case substring (repeatable)")
    parser.add_argument("--list", action="store_true", help="list cases without creating corpus or running binaries")
    parser.add_argument("--corpus", type=Path, default=ROOT / ".build/benchmark-corpus")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "results")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    if args.runs < 1 or args.warmups < 1:
        parser.error("--runs and --warmups must be positive")
    if args.bootstrap_resamples < 0:
        parser.error("--bootstrap-resamples must be nonnegative")
    size_mib = args.size_mib or (64 if args.quick else 128)
    cases = workload_cases(args.quick, size_mib, args.extended)
    if args.case:
        cases = [case for case in cases if any(part in case["name"] for part in args.case)]
    if not cases:
        parser.error("no cases selected")
    if args.list:
        print("\n".join(case["name"] for case in cases))
        return 0
    binaries = {"rust": args.rust.resolve(), "assembly": args.asm.resolve()}
    if args.before:
        binaries["previous_assembly"] = args.before.resolve()
    for path in binaries.values():
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f"missing/non-executable binary: {path}")
    report = {
        "status": "running", "upstream_commit": UPSTREAM_COMMIT,
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "machine": machine_info(), "build": build_info(),
        "runs_per_implementation": args.runs, "warmup_pairs": args.warmups,
        "diagnostic_only": args.runs < 10, "order_seed": SEED,
        "order_permutations": list(itertools.permutations(binaries)),
        "order_fully_balanced": args.runs % (6 if args.before else 2) == 0,
        "bootstrap": {"resamples": args.bootstrap_resamples if args.before else 0, "seed": SEED,
                      "confidence_level": 0.95,
                      "method": "paired repetition percentile bootstrap of previous/assembly ratio of medians"},
        "methodology": [
            "End-to-end subprocess wall-clock time, including startup, path traversal, output capture and shutdown.",
            "Deterministic on-disk files; parity preflight before timing every selected workload.",
            "Warm filesystem cache after preflight and warmups; no cache flushing or cold-disk claim.",
            "Same inherited CPU availability for all processes; no affinity restriction.",
            "One-file cases have one scanner in each implementation; upstream Rust still creates its global thread pool.",
            "Seeded shuffled complete execution-permutation blocks; measured order is fully balanced when runs is divisible by the permutation count.",
            "Before/assembly confidence intervals resample matched measured repetitions; they describe observed timing variation, not machine-to-machine variation.",
            "Metadata-only byte counts are reported separately from scanning throughput.",
            "Compare these executable implementations/builds on this machine, not language performance in general.",
            "Run sequentially without concurrent tests/builds or other benchmark processes.",
        ],
        "binaries": {name: {"path": str(path), "sha256": digest(path)} for name, path in binaries.items()},
        "environment": {key: os.environ.get(key) for key in ("RAYON_NUM_THREADS", "OMP_NUM_THREADS")},
        "cases": cases,
    }
    print(f"Preparing/verifying deterministic {size_mib} MiB corpus (outside timed region)...", flush=True)
    corpus = args.corpus.resolve()
    try:
        report["corpus"] = {"path": str(corpus), **prepare_corpus(corpus, size_mib)}
    except (OSError, RuntimeError, ValueError) as error:
        report.update(status="failed", error=f"corpus preparation: {error}")
        write_results(args.output_dir, report)
        print(f"Benchmark failed: {report['error']}", file=sys.stderr)
        return 1
    print(f"Preflighting {len(cases)} workloads before timing...", flush=True)
    try:
        # Complete all preflight comparisons before any measurements. A failure
        # makes the benchmark invalid; no mismatching output is timed.
        for case in cases:
            results = {name: PARITY.run(path, tuple(case["argv"]), corpus, args.timeout)
                       for name, path in binaries.items()}
            rust = results["rust"]
            if rust.returncode or any(not PARITY.equivalent(rust, result) for result in results.values()):
                case["preflight"] = {"passed": False,
                                     **{name: PARITY.result_data(result) for name, result in results.items()}}
                raise RuntimeError(f"parity preflight failed: {case['name']}")
            case["preflight"] = {"passed": True, "stdout_sha256": hashlib.sha256(rust.stdout).hexdigest(),
                                 "stderr_sha256": hashlib.sha256(rust.stderr).hexdigest(), "returncode": 0,
                                 "validated_implementations": list(binaries)}
        rng = random.Random(SEED)
        for index, case in enumerate(cases, 1):
            warmup_orders = execution_orders(binaries, args.warmups, rng)
            measured_orders = execution_orders(binaries, args.runs, rng)
            values = {name: [] for name in binaries}
            case["samples"] = []
            for repetition, order in enumerate(warmup_orders + measured_orders, -args.warmups):
                for position, implementation in enumerate(order):
                    started = time.perf_counter_ns()
                    result = PARITY.run(binaries[implementation], tuple(case["argv"]), corpus, args.timeout)
                    elapsed = (time.perf_counter_ns() - started) / 1e9
                    # Check output on each measurement too, without timing its hash.
                    stdout_hash = hashlib.sha256(result.stdout).hexdigest()
                    stderr_hash = hashlib.sha256(result.stderr).hexdigest()
                    if (result.returncode or stdout_hash != case["preflight"]["stdout_sha256"]
                            or stderr_hash != case["preflight"]["stderr_sha256"]):
                        raise RuntimeError(f"output changed during {case['name']} ({implementation})")
                    if repetition >= 0:
                        values[implementation].append(elapsed)
                        case["samples"].append({"repetition": repetition + 1, "position": position + 1,
                                                "implementation": implementation, "seconds": elapsed,
                                                "stdout_sha256": stdout_hash, "stderr_sha256": stderr_hash,
                                                "returncode": result.returncode})
            summarize_case(case, values, args.bootstrap_resamples)
            ratio = case["rust_over_assembly_median"]
            rust_ms = 1000 * case["statistics"]["rust"]["median_seconds"]
            asm_ms = 1000 * case["statistics"]["assembly"]["median_seconds"]
            comparison = f"Rust {rust_ms:.3f} ms, assembly {asm_ms:.3f} ms, Rust/assembly {ratio:.3f}x"
            if args.before:
                previous_ms = 1000 * case["statistics"]["previous_assembly"]["median_seconds"]
                comparison += (f", previous assembly {previous_ms:.3f} ms, previous/assembly "
                               f"{case['previous_over_assembly_median']:.3f}x "
                               f"({case['assembly_time_reduction_percent']:+.2f}% time reduction)")
                if "previous_over_assembly_median_ci95" in case:
                    low, high = case["previous_over_assembly_median_ci95"]
                    comparison += f", paired 95% CI [{low:.3f}, {high:.3f}]x"
            print(f"[{index}/{len(cases)}] {case['name']}: {comparison}", flush=True)
            write_results(args.output_dir, report)
        report["status"] = "passed"
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        report.update(status="failed", error=str(error))
        print(f"Benchmark failed: {error}", file=sys.stderr)
    write_results(args.output_dir, report)
    print(f"Benchmark {report['status']}; JSON/summary CSV/raw sample CSV: {args.output_dir}")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
