#!/bin/sh
set -eu
cd "$(dirname "$0")"
./scripts/check-platform.sh
if ! command -v rustup >/dev/null 2>&1; then
    echo 'error: rustup is required for the pinned Rust comparison baseline. Install rustup, then run make baselines.' >&2
    exit 1
fi
# rust-toolchain.toml selects the measured compiler; Cargo.lock fixes dependencies.
rust_toolchain="$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)"
if [ -z "$rust_toolchain" ]; then
    echo 'error: could not read the pinned Rust channel from rust-toolchain.toml.' >&2
    exit 1
fi
export RUSTFLAGS='-C target-cpu=native'
export CARGO_INCREMENTAL=0
export CARGO_TARGET_DIR="$PWD/.build/rust-target"
rustup run --install "$rust_toolchain" cargo build --release --locked --manifest-path upstream/Cargo.toml
mkdir -p bin
cp "$CARGO_TARGET_DIR/release/ripwc" bin/ripwc-rust.tmp
mv -f bin/ripwc-rust.tmp bin/ripwc-rust
