#!/usr/bin/env python3
"""I/O regression coverage for buffer-sized candidates; no timing results.

Catches early EOF after a short read, lost cross-read word/current-line state,
incorrect finalization, and allocation/read-length mismatches. Expected output is
independently obtained from the pinned Rust executable. Every named FIFO has a
fresh real writer and a nonempty final write before EOF.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

from support import BIN_DIR, RESULTS_DIR


def run(binary, flags, path):
    result = subprocess.run(['asmwc', *flags, str(path)], executable=str(binary),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            stdin=subprocess.DEVNULL, timeout=30)
    return result.returncode, result.stdout, result.stderr


def fifo_run(binary, flags, path, chunks):
    errors = []
    def write():
        try:
            with path.open('wb', buffering=0) as output:
                for chunk in chunks:
                    output.write(chunk)
                    time.sleep(0.002)
        except Exception as error:
            errors.append(error)
    writer = threading.Thread(target=write, daemon=True)
    writer.start()
    result = run(binary, flags, path)
    writer.join(timeout=5)
    assert not writer.is_alive(), 'FIFO writer remained blocked'
    assert not errors, errors
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binaries', nargs='*', type=Path, default=[BIN_DIR/'asmwc'])
    parser.add_argument('--oracle', type=Path, default=BIN_DIR / 'asmwc-rust')
    parser.add_argument('--report', type=Path, default=RESULTS_DIR/'io-boundaries.json')
    args = parser.parse_args()
    records = []
    with tempfile.TemporaryDirectory(prefix='asmwc-io-boundaries-') as tmp:
        root = Path(tmp)
        cases = []
        # Breaks are one byte before/on/after every proposed boundary. The
        # nonseparator spans that break; a long final line spans several reads.
        for boundary in (16*1024, 64*1024, 128*1024, 256*1024, 1024*1024):
            for delta in (-1, 0, 1):
                length = boundary + delta
                data = bytearray((b'a \x00\xff\n\t\r\v\f' * ((length+8)//9))[:length])
                data[max(0, boundary-12):min(length, boundary+12)] = b'x' * (min(length,boundary+12)-max(0,boundary-12))
                data += b'x' * (2 * boundary + 7) + b' last\x00word'
                path = root / f'boundary-{boundary}-{delta}'
                path.write_bytes(data)
                for flags in (('-lwmcL',), ('-wL',), ('-l',), ('-m',), ('-c',)):
                    cases.append((f'{path.name}/{flags[0]}', flags, path))
        path = root / 'empty'
        path.touch()
        for flags in (('-lwmcL',), ('-c',), ('-L',)):
            cases.append((f'empty/{flags[0]}', flags, path))
        for path in (Path('/dev/null'), root):
            for flags in (('-lwmcL',), ('-c',)):
                cases.append((f'special/{path.name}/{flags[0]}', flags, path))
        for name, flags, path in cases:
            expected = run(args.oracle, flags, path)
            for binary in args.binaries:
                actual = run(binary, flags, path)
                assert actual == expected, (name, str(binary), expected, actual)
                records.append({'case': name, 'binary': str(binary), 'passed': True})
        fifo = root / 'short-reads.fifo'
        os.mkfifo(fifo)
        chunks = [b'word' + b'x' * 20000, b'\x00tail ', b'a\nb\r', b'\tlast' + b'y' * 270000, b'\nfinal']
        for flags in (('-lwmcL',), ('-wL',), ('-l',), ('-m',)):
            expected = fifo_run(args.oracle, flags, fifo, chunks)
            for binary in args.binaries:
                actual = fifo_run(binary, flags, fifo, chunks)
                assert actual == expected, ('fifo', flags, str(binary), expected, actual)
                records.append({'case': f'fifo/{flags[0]}', 'binary': str(binary), 'passed': True})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'status':'passed','cases':len(records),'results':records}, indent=2)+'\n')
    print(f'I/O boundaries: {len(records)} comparisons passed; {args.report}')


if __name__ == '__main__':
    main()
