#!/bin/sh
# Apple Silicon/macOS. Run './tests/kernel.sh bench' for a diagnostic
# in-memory throughput measurement; it is not an end-to-end IO benchmark.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ripwc-kernel.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cc -O2 -Wall -Wextra "$project_dir/tests/kernel.c" \
  "$project_dir/tests/kernel-abi.S" "$project_dir/src/count.S" \
  -o "$build_dir/kernel-test"
"$build_dir/kernel-test" "$@"
