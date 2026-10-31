#!/bin/sh
# Failure injection is confined to test executables and their child process.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if [ "$(uname -s)" = Linux ]; then
  exec python3 "$project_dir/tests/linux-thread-fallback.py"
fi
if [ "$(uname -s)" != Darwin ]; then
  echo 'SKIP native resource tests: unsupported operating system'
  exit 0
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/asmwc-pipeline.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
${CC:-cc} -O2 "$project_dir/tests/pipeline_resources.c" "$project_dir/src/pipeline.S" \
  "$project_dir/src/count.S" -o "$build_dir/resource-test"
"$build_dir/resource-test"
cat > "$build_dir/group-null.c" <<'EOF'
#include <dispatch/dispatch.h>
static dispatch_group_t fail_group(void) { return 0; }
__attribute__((used)) static struct { const void *replacement; const void *replacee; }
interpose __attribute__((section("__DATA,__interpose"))) = { (const void*)fail_group, (const void*)dispatch_group_create };
EOF
${CC:-cc} -dynamiclib "$build_dir/group-null.c" -o "$build_dir/group-null.dylib"
python3 - "$project_dir" "$build_dir" <<'PY'
import os, pathlib, subprocess, sys
project, temporary = map(pathlib.Path, sys.argv[1:])
bin_dir=pathlib.Path(os.environ.get('ASMWC_BIN_DIR', project/'bin')).expanduser().resolve()
path=temporary/'eight-mib'
with path.open('wb') as stream: stream.truncate(8*1024*1024)
env=os.environ.copy(); env['DYLD_INSERT_LIBRARIES']=str(temporary/'group-null.dylib')
def run(binary, environment):
    result=subprocess.run(['asmwc','-w',str(path)], executable=str(binary), env=environment,
                          capture_output=True, timeout=30)
    return result.returncode,result.stdout,result.stderr
expected=run(bin_dir/'asmwc-rust',os.environ.copy())
assert run(bin_dir/'asmwc',env)==expected, 'pipeline setup failure did not fall back correctly'
print('PASS real executable falls back to buffered reads after injected group allocation failure')
PY
