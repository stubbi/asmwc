#!/bin/sh
# Native macOS/ARM64 or Linux/AArch64/x86-64. Run './tests/kernel.sh bench' for a diagnostic
# in-memory throughput measurement; it is not an end-to-end IO benchmark.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/asmwc-kernel.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64|Darwin/aarch64)
    count_source="$project_dir/src/count.S"
    abi_source="$project_dir/tests/kernel-abi.S" ;;
  Linux/aarch64|Linux/arm64)
    count_source="$project_dir/src/linux/aarch64/count.S"
    abi_source="$project_dir/tests/kernel-abi.S" ;;
  Linux/x86_64|Linux/amd64)
    count_source="$project_dir/src/linux/x86_64/count.S"
    abi_source="$project_dir/tests/kernel-abi-x86_64.S" ;;
  *) echo "Unsupported native kernel test target: $(uname -s)/$(uname -m)" >&2; exit 2 ;;
esac
${CC:-cc} -O2 -Wall -Wextra -Werror "$project_dir/tests/kernel.c" \
  "$abi_source" "$count_source" \
  -o "$build_dir/kernel-test"
"$build_dir/kernel-test" "$@"
