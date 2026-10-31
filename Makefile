CC = clang
CPU ?= apple-m3
ASFLAGS = -arch arm64 -mcpu=$(CPU) -O3 -g
PYTHON ?= python3
PREFIX ?= /usr/local
DESTDIR ?=
INSTALL ?= install
BENCH_ARGS ?= --extended --runs 24
SOURCES = src/main.S src/cli.S src/count.S src/pipeline.S
ORIGINAL_SOURCES = history/original-src/main.S history/original-src/cli.S history/original-src/count.S
RUST_SOURCES = upstream/Cargo.toml upstream/Cargo.lock $(wildcard upstream/src/*.rs)

.PHONY: all baselines rust test check check-platform bench install clean FORCE
all: bin/ripwc

check-platform:
	@./scripts/check-platform.sh

# Keep ordinary make incremental while honoring CPU/compiler/flag overrides.
.build/assembly-config: FORCE | check-platform
	@mkdir -p .build
	@printf '%s\n' "$(CC) $(CPPFLAGS) $(ASFLAGS) $(LDFLAGS)" > "$@.tmp"
	@if cmp -s "$@.tmp" "$@"; then rm "$@.tmp"; else mv "$@.tmp" "$@"; fi

FORCE:

bin/ripwc: $(SOURCES) Makefile .build/assembly-config FORCE | check-platform
	@mkdir -p bin
	@if [ ! -f "$@" ] || [ -n "$(filter-out FORCE .build/assembly-config,$?)" ] || ! cmp -s .build/assembly-config .build/ripwc-config; then \
		echo "Building $@ with $(CC) ($(CPU))"; \
		$(CC) $(CPPFLAGS) $(ASFLAGS) $(LDFLAGS) $(SOURCES) -o "$@" && \
		cp .build/assembly-config .build/ripwc-config; \
	fi

bin/ripwc-before: $(ORIGINAL_SOURCES) Makefile .build/assembly-config FORCE | check-platform
	@mkdir -p bin
	@if [ ! -f "$@" ] || [ -n "$(filter-out FORCE .build/assembly-config,$?)" ] || ! cmp -s .build/assembly-config .build/ripwc-before-config; then \
		echo "Building $@ with $(CC) ($(CPU))"; \
		$(CC) $(CPPFLAGS) $(ASFLAGS) $(LDFLAGS) $(ORIGINAL_SOURCES) -o "$@" && \
		cp .build/assembly-config .build/ripwc-before-config; \
	fi

bin/ripwc-rust: $(RUST_SOURCES) build-rust.sh rust-toolchain.toml | check-platform
	./build-rust.sh

rust: bin/ripwc-rust

baselines: bin/ripwc-rust bin/ripwc-before

check:
	$(PYTHON) scripts/check.py
	$(PYTHON) tools/check_evidence.py
	$(PYTHON) -m unittest discover -s tests -p '*_test.py'

test: all baselines check
	mkdir -p results
	./tests/kernel.sh
	$(PYTHON) tests/parity.py
	$(PYTHON) tests/cli-parity.py
	$(PYTHON) tests/io-boundaries.py
	$(PYTHON) tests/pipeline-parity.py
	./tests/pipeline_resources.sh

bench: all baselines
	$(PYTHON) bench.py --before bin/ripwc-before $(BENCH_ARGS)

install: all
	$(INSTALL) -d "$(DESTDIR)$(PREFIX)/bin"
	$(INSTALL) -m 755 bin/ripwc "$(DESTDIR)$(PREFIX)/bin/ripwc"

clean:
	rm -f bin/ripwc bin/ripwc-before bin/ripwc-rust bin/ripwc-rust.tmp
	rm -rf .build
