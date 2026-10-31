#!/bin/sh
# Failure injection is confined to test executables and their child process.
set -eu
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ripwc-pipeline.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cc -O2 "$project_dir/tests/pipeline_resources.c" "$project_dir/src/pipeline.S" \
  "$project_dir/src/count.S" -o "$build_dir/resource-test"
"$build_dir/resource-test"
cat > "$build_dir/group-null.c" <<'EOF'
#include <dispatch/dispatch.h>
static dispatch_group_t fail_group(void) { return 0; }
__attribute__((used)) static struct { const void *replacement; const void *replacee; }
interpose __attribute__((section("__DATA,__interpose"))) = { (const void*)fail_group, (const void*)dispatch_group_create };
EOF
cc -dynamiclib "$build_dir/group-null.c" -o "$build_dir/group-null.dylib"
python3 - "$project_dir" "$build_dir" <<'PY'
import os, pathlib, subprocess, sys
project, temporary = map(pathlib.Path, sys.argv[1:])
path=temporary/'eight-mib'
with path.open('wb') as stream: stream.truncate(8*1024*1024)
env=os.environ.copy(); env['DYLD_INSERT_LIBRARIES']=str(temporary/'group-null.dylib')
def run(binary, environment):
    result=subprocess.run(['ripwc','-w',str(path)], executable=str(binary), env=environment,
                          capture_output=True, timeout=30)
    return result.returncode,result.stdout,result.stderr
expected=run(project/'bin/ripwc-rust',os.environ.copy())
assert run(project/'bin/ripwc',env)==expected, 'pipeline setup failure did not fall back correctly'
print('PASS real executable falls back to buffered reads after injected group allocation failure')
PY
