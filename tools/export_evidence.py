#!/usr/bin/env python3
"""Export captured reports without publishing personal paths or hostnames.

Usage: python3 tools/export_evidence.py results NEW_DESTINATION
Timing values, sample order, summary statistics and checksums are preserved.
The exporter deliberately refuses to overwrite an existing publication.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

REPORTS = (
    "benchmark.json", "benchmark.csv", "benchmark-samples.csv", "build-info.json",
    "parity.json", "io-boundaries.json", "pipeline-parity.json", "verification.txt",
)


def redact_text(text: str, repository: Path) -> str:
    text = text.replace(str(repository.resolve()), "$REPO")
    text = re.sub(r"(?:/private)?/var/folders/[^/\s]+/[^/\s]+/T/[^/'\"\s]+", "$TMP", text)
    text = re.sub(r"/Users/[^\s\"']+", "$LOCAL_PATH", text)
    text = re.sub(r"\bDarwin\s+\S+\s+(\d+\.\d+)", r"Darwin benchmark-host \1", text)
    return text


def redact(value, repository: Path):
    if isinstance(value, str):
        return redact_text(value, repository)
    if isinstance(value, list):
        return [redact(item, repository) for item in value]
    if isinstance(value, dict):
        return {key: redact(item, repository) for key, item in value.items()}
    return value


def number_tree(value):
    """Identify every numeric/boolean value and its location in a report."""
    if isinstance(value, dict):
        return {key: number_tree(item) for key, item in value.items()
                if not isinstance(item, str)}
    if isinstance(value, list):
        return [number_tree(item) if not isinstance(item, str) else None for item in value]
    return value


def export(source: Path, destination: Path) -> dict:
    if destination.exists():
        raise FileExistsError(f"refusing to overwrite published evidence: {destination}")
    if not (source / "benchmark.json").is_file():
        raise FileNotFoundError(f"missing captured benchmark: {source / 'benchmark.json'}")
    destination.mkdir(parents=True)
    manifest = {
        "schema_version": 1,
        "experiment_date": "2026-10-31",
        "description": "Captured Apple M3 experiment, with local paths and hostname redacted.",
        "redactions": {"$REPO": "local project directory", "$LOCAL_PATH": "other local path",
                       "$TMP": "temporary directory", "benchmark-host": "local hostname"},
        "preserved": ["all numeric values", "sample order", "summary statistics",
                      "corpus checksums", "measured executable hashes", "compiler settings"],
        "binary_hash_note": "Hashes identify the measured executables. Rebuilds can differ because of compiler versions, debug paths and signing.",
        "files": {},
    }
    for prefix in ("", "original-run/"):
        for name in REPORTS:
            relative = prefix + name
            path = source / relative
            if not path.is_file():
                continue
            if path.suffix == ".json":
                original = json.loads(path.read_text())
                published = redact(original, source.resolve().parent)
                if number_tree(original) != number_tree(published):
                    raise ValueError(f"redaction changed numeric evidence: {relative}")
                content = json.dumps(published, indent=2, ensure_ascii=True) + "\n"
            else:
                content = redact_text(path.read_text(), source.resolve().parent)
            output = destination / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(content)
            manifest["files"][relative] = hashlib.sha256(output.read_bytes()).hexdigest()
    (destination / "PUBLICATION.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    manifest = export(args.source, args.destination)
    print(f"Exported {len(manifest['files'])} reports; numeric evidence and checksums preserved.")


if __name__ == "__main__":
    main()
