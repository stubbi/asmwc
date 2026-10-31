SYSTEM := $(shell uname -s)
ARCH := $(shell uname -m)

# Select native sources and baseline ISA flags. Command-line/environment compiler
# overrides remain available; do not inherit make's built-in CC=cc on macOS.
ifeq ($(origin CC),default)
ifeq ($(SYSTEM),Darwin)
CC = clang
else
CC = cc
endif
endif

ifeq ($(SYSTEM),Darwin)
CPU ?= apple-m3
ASFLAGS ?= -arch arm64 -mcpu=$(CPU) -O3 -g
SOURCES = src/main.S src/cli.S src/count.S src/pipeline.S
BASELINES = bin/asmwc-rust bin/asmwc-before
BENCH_BASELINE_ARGS = --before bin/asmwc-before
else ifeq ($(SYSTEM),Linux)
ifneq ($(filter $(ARCH),aarch64 x86_64),)
ifeq ($(ARCH),aarch64)
CPU ?= generic
ASFLAGS ?= -mcpu=$(CPU) -O3 -g
else
CPU ?= x86-64
ASFLAGS ?= -march=$(CPU) -O3 -g
endif
SOURCES = src/linux/$(ARCH)/main.S src/linux/$(ARCH)/cli.S src/linux/$(ARCH)/count.S
TARGET_CPPFLAGS = -I.build/linux
TARGET_ASFLAGS = -fPIE -pthread
TARGET_LDFLAGS = -pie -pthread -Wl,-z,noexecstack,-z,relro,-z,now,-z,defs
ABI_HEADER = .build/linux/abi.h
BASELINES = bin/asmwc-rust
endif
endif

PYTHON ?= python3
PREFIX ?= /usr/local
DESTDIR ?=
INSTALL ?= install
BENCH_ARGS ?= --extended --runs 24
ORIGINAL_SOURCES = history/original-src/main.S history/original-src/cli.S history/original-src/count.S
RUST_SOURCES = upstream/Cargo.toml upstream/Cargo.lock $(wildcard upstream/src/*.rs)

.PHONY: all baselines rust test check check-platform bench install clean FORCE
all: bin/asmwc

check-platform:
	@./scripts/check-platform.sh

# Keep ordinary make incremental while honoring CPU/compiler/flag overrides.
.build/assembly-config: FORCE | check-platform
	@mkdir -p .build
	@printf '%s\n' "$(SYSTEM) $(ARCH) $(CC) $(TARGET_CPPFLAGS) $(CPPFLAGS) $(CFLAGS) $(TARGET_ASFLAGS) $(ASFLAGS) $(TARGET_LDFLAGS) $(LDFLAGS)" > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi

FORCE:

# Query the native libc's layouts/constants rather than guessing architecture-
# specific offsets. The probe is a build tool, never an application input.
.build/linux/abi.h: tools/linux_abi.c Makefile .build/assembly-config FORCE | check-platform
	@mkdir -p .build/linux
	@if [ ! -f "$@" ] || [ -n "$(filter-out FORCE .build/assembly-config,$?)" ] || ! cmp -s .build/assembly-config .build/linux/abi-config; then \
		echo "Probing native Linux glibc ABI with $(CC)"; \
		$(CC) $(CPPFLAGS) $(CFLAGS) -std=c11 -O2 -Wall -Wextra tools/linux_abi.c -o .build/linux/abi-probe && \
		.build/linux/abi-probe > "$@.tmp" && \
		mv "$@.tmp" "$@" && \
		cp .build/assembly-config .build/linux/abi-config; \
	fi

bin/asmwc: $(SOURCES) $(ABI_HEADER) Makefile .build/assembly-config FORCE | check-platform
	@mkdir -p bin
	@if [ ! -f "$@" ] || [ -n "$(filter-out FORCE .build/assembly-config,$?)" ] || ! cmp -s .build/assembly-config .build/asmwc-config; then \
		echo "Building $@ with $(CC) ($(CPU))"; \
		$(CC) $(TARGET_CPPFLAGS) $(CPPFLAGS) $(TARGET_ASFLAGS) $(ASFLAGS) $(SOURCES) $(LDFLAGS) $(TARGET_LDFLAGS) -o "$@" && \
		cp .build/assembly-config .build/asmwc-config; \
	fi

ifeq ($(SYSTEM),Darwin)
bin/asmwc-before: $(ORIGINAL_SOURCES) Makefile .build/assembly-config FORCE | check-platform
	@mkdir -p bin
	@if [ ! -f "$@" ] || [ -n "$(filter-out FORCE .build/assembly-config,$?)" ] || ! cmp -s .build/assembly-config .build/asmwc-before-config; then \
		echo "Building $@ with $(CC) ($(CPU))"; \
		$(CC) $(CPPFLAGS) $(ASFLAGS) $(LDFLAGS) $(ORIGINAL_SOURCES) -o "$@" && \
		cp .build/assembly-config .build/asmwc-before-config; \
	fi
else
.PHONY: bin/asmwc-before
bin/asmwc-before: | check-platform
	@echo 'error: the preserved assembly baseline is available only on macOS arm64; use make baselines for the native Rust comparison.' >&2
	@exit 1
endif

bin/asmwc-rust: $(RUST_SOURCES) build-rust.sh rust-toolchain.toml | check-platform
	./build-rust.sh

rust: bin/asmwc-rust

baselines: $(BASELINES) | check-platform

check:
	$(PYTHON) scripts/check.py
	$(PYTHON) tools/check_evidence.py
	$(PYTHON) -m unittest discover -s tests -p '*_test.py'

test: all baselines check
	mkdir -p results
	./tests/kernel.sh
	$(PYTHON) tests/parity.py
	$(PYTHON) tests/cli-parity.py
	$(PYTHON) tests/cli-identity.py
	$(PYTHON) tests/io-boundaries.py
	$(PYTHON) tests/pipeline-parity.py
	./tests/pipeline_resources.sh

bench: all baselines
	$(PYTHON) bench.py $(BENCH_BASELINE_ARGS) $(BENCH_ARGS)

install: all
	$(INSTALL) -d "$(DESTDIR)$(PREFIX)/bin"
	$(INSTALL) -m 755 bin/asmwc "$(DESTDIR)$(PREFIX)/bin/asmwc"

clean:
	rm -f bin/asmwc bin/asmwc-before bin/asmwc-rust bin/asmwc-rust.tmp
	rm -rf .build
