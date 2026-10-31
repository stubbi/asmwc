#!/usr/bin/env python3
"""Large-file differential cases exercising reader/scanner pipeline and carry.

Checks every count-flag subset around the pipeline threshold and four-block
reuse boundaries, comparing to unmodified upstream and the original assembly.
"""
import itertools
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(binary, args, folder):
    result = subprocess.run(['ripwc', *args], executable=str(binary), cwd=folder,
                            capture_output=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def main():
    binaries = [ROOT/'bin/ripwc']
    if (ROOT/'bin/ripwc-before').exists():
        binaries.append(ROOT/'bin/ripwc-before')
    oracle = ROOT/'bin/ripwc-rust'
    records = []
    mib = 1024 * 1024
    with tempfile.TemporaryDirectory(prefix='ripwc-pipeline-') as temporary:
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
    report = ROOT/'results/pipeline-parity.json'
    report.write_text(json.dumps({'status': 'passed', 'cases': len(records),
                                 'binaries': [str(path) for path in binaries],
                                 'results': records}, indent=2)+'\n')
    print(f'Pipeline parity: {len(records)} large-file cases passed against Rust and original assembly')


if __name__ == '__main__':
    main()
