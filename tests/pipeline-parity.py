#!/usr/bin/env python3
"""Large-file differential cases exercising buffered reads and carry.

Checks every count-flag subset around the pipeline threshold and four-block
reuse boundaries. The macOS path also compares the original assembly pipeline;
Linux checks its native buffered reader against unmodified upstream.
"""
import itertools
import json
from pathlib import Path
import platform
import subprocess
import tempfile

from support import BIN_DIR, RESULTS_DIR


def run(binary, args, folder):
    result = subprocess.run(['asmwc', *args], executable=str(binary), cwd=folder,
                            capture_output=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def main():
    binaries = [BIN_DIR/'asmwc']
    if platform.system() == 'Darwin' and (BIN_DIR/'asmwc-before').exists():
        binaries.append(BIN_DIR/'asmwc-before')
    oracle = BIN_DIR/'asmwc-rust'
    records = []
    mib = 1024 * 1024
    with tempfile.TemporaryDirectory(prefix='asmwc-pipeline-') as temporary:
        folder = Path(temporary)
        block = (b'a \n\x00b\t\r\xff\v\f' * 104858)[:mib]
        for length in (8*mib-1, 8*mib, 8*mib+1, 13*mib+17):
            path = folder/'large'
            path.write_bytes((block*(length//len(block)+1))[:length])
            with path.open('r+b') as stream:
                for position in range(mib, length, mib):
                    stream.seek(position-2)
                    stream.write(b'xxx\n')
            for count in range(1, 6):
                for flags in itertools.combinations('clwmL', count):
                    args = ['-'+''.join(flags), 'large']
                    expected = run(oracle, args, folder)
                    for binary in binaries:
                        actual = run(binary, args, folder)
                        assert actual == expected, (length, args, str(binary), actual, expected)
                    records.append({'length': length, 'flags': args[0], 'passed': True})
    report = RESULTS_DIR/'pipeline-parity.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({'status': 'passed', 'cases': len(records),
                                 'binaries': [str(path) for path in binaries],
                                 'results': records}, indent=2)+'\n')
    print(f'Large-file parity: {len(records)} cases passed against Rust; {len(binaries)} assembly executable(s)')


if __name__ == '__main__':
    main()
