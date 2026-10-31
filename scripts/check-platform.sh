#!/bin/sh
# The executable uses Darwin system interfaces and the Apple arm64 ABI.
set -eu
system="$(uname -s)"
architecture="$(uname -m)"
if [ "$system" != Darwin ] || [ "$architecture" != arm64 ]; then
    printf 'error: ripwc-asm requires macOS on Apple Silicon (Darwin arm64); found %s %s.\n' "$system" "$architecture" >&2
    echo 'The portable repository checks are available with make check.' >&2
    exit 1
fi
