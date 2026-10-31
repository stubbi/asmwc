#!/bin/sh
# Only native builds are supported: libc layouts are measured on the build host.
set -eu
system="$(uname -s)"
architecture="$(uname -m)"
case "$system:$architecture" in
    Darwin:arm64)
        ;;
    Linux:aarch64|Linux:x86_64)
        libc="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
        case "$libc" in
            'glibc '*) ;;
            *)
                printf 'error: the Linux assembly ports require native glibc; found %s %s without a glibc runtime (musl is not supported).\n' "$system" "$architecture" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        printf 'error: unsupported native platform %s %s; supported targets are macOS arm64 and Linux glibc aarch64/x86_64.\n' "$system" "$architecture" >&2
        echo 'The portable repository checks are available with make check.' >&2
        exit 1
        ;;
esac
