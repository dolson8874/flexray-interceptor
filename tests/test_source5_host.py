"""Offline test of the actual native decoder patch and Python envelope mapper.

Copies only required source files to an ignored build tree; never edits HostRepo.
No cereal/import of the full application and no connection to a vehicle/device.
"""
import argparse
import ast
import ctypes
import os
from pathlib import Path
import re
import subprocess
import time
from types import SimpleNamespace


def crc_bits(crc, value, count, width, poly):
    for bit in range(count - 1, -1, -1):
        feedback = ((crc >> (width - 1)) ^ (value >> bit)) & 1
        crc = (crc << 1) & ((1 << width) - 1)
        if feedback:
            crc ^= poly
    return crc


def frame(marker, identifier, cycle, words):
    flags = 3
    hc = crc_bits(26, (flags << 18) | (identifier << 7) | words, 20, 11, 0x385)
    header = bytes([(flags << 3) | (identifier >> 8), identifier & 255,
                    (words << 1) | (hc >> 10), (hc >> 2) & 255, ((hc & 3) << 6) | cycle])
    payload = bytes((i * 17 + 0x90) & 255 for i in range(words * 2))
    if len(payload) >= 6:
        payload = b'\xca\x80\xca\x90\xca\xa0' + payload[6:]
    crc = 0xfedcba
    for b in header + payload:
        crc = crc_bits(crc, b, 8, 24, 0x5d6dcb)
    return b'\xca' + bytes([marker]) + header + bytes([flags, cycle]) + payload + crc.to_bytes(3, 'big')


def main():
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('--host-repo', type=Path, default=repo / 'docs/sunnypilot-source5-host')
    parser.add_argument('--host-base', default='97efb304e81f60fe8f9b8c23da5579807d8f2ca3')
    parser.add_argument('--gcc-bin', type=Path, default=Path('C:/Xilinx/Vivado/2024.2/tps/mingw/10.0.0/win64.o/nt/bin'))
    args = parser.parse_args()
    build = repo / 'tests/source5_host.sim'
    destination = build / 'host/openpilot/system/flexray_logd'
    destination.mkdir(parents=True, exist_ok=True)
    patch = repo / 'host-patches/source5-native.patch'
    # Reconstruct the pinned baseline, so this also verifies clean patch application
    # after the separate working host clone has been edited/committed.
    for name in re.findall(r'^\+\+\+ b/(.+)$', patch.read_text(encoding='utf-8'), re.MULTILINE):
        target = build / 'host' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        content = subprocess.check_output(['git', '-C', str(args.host_repo), 'show', f'{args.host_base}:{name}'])
        target.write_bytes(content)
    # git apply only changes the copied files, never the reference host clone.
    prefix = (build / 'host').relative_to(repo).as_posix()
    subprocess.run(['git', 'apply', '--check', '--directory=' + prefix, str(patch)], cwd=repo, check=True)
    subprocess.run(['git', 'apply', '--directory=' + prefix, str(patch)], cwd=repo, check=True)
    env = dict(os.environ, PATH=str(args.gcc_bin) + os.pathsep + os.environ['PATH'])
    gcc = args.gcc_bin / 'gcc.exe'
    dll = build / 'source5_decoder.dll'
    subprocess.run([str(gcc), '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-shared',
                    str(destination / 'flexray_decoder.c'), '-o', str(dll)], env=env, check=True)
    native_test = build / 'test_decoder.exe'
    subprocess.run([str(gcc), '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-I' + str(destination), str(destination / 'tests/test_decoder.c'),
                    str(destination / 'flexray_decoder.c'), '-o', str(native_test)], env=env, check=True)
    subprocess.run([str(native_test)], env=env, check=True)
    library = ctypes.CDLL(str(dll))
    decode = library.decode_flexray_buffer
    decode.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p, ctypes.c_size_t]
    decode.restype = ctypes.c_size_t
    tree = ast.parse((destination / 'flexrayd.py').read_text(encoding='utf-8'))
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'unpack_frames')
    namespace = {'FLEXRAY_SOURCE_OFFSET': 4}
    exec(compile(ast.Module(body=[function], type_ignores=[]), str(destination / 'flexrayd.py'), 'exec'), namespace)
    unpack = namespace['unpack_frames']
    cases = 0

    def decode_chunks(wire, split):
        pending = bytearray()
        captured = bytearray()
        for chunk in (wire[:split], wire[split:]):
            pending.extend(chunk)
            raw = ctypes.create_string_buffer(bytes(pending), max(1, len(pending)))
            count = ctypes.c_size_t(len(pending))
            output = ctypes.create_string_buffer(4096)
            n = decode(raw, ctypes.byref(count), output, len(output))
            pending[:] = raw.raw[:count.value]
            captured.extend(output.raw[:n])
        return pending, captured

    for marker, expected_src in ((0x80, 4), (0x90, 5), (0xa0, 6)):
        for identifier in (13, 31, 49, 0x7ff):
            for cycle in (0, 1, 63):
                for words in (0, 1, 13, 127):
                    wire = frame(marker, identifier, cycle, words)
                    for split in range(len(wire) + 1):
                        pending, captured = decode_chunks(wire, split)
                        assert not pending
                        rows = unpack(captured)
                        assert not captured and len(rows) == 1
                        assert rows[0] == {'address': identifier, 'src': expected_src, 'dat': wire[7:]}
                        cases += 1
        # A corrupt source5 candidate must not hide the following record.
        wire = bytearray(frame(marker, 31, 0, 13))
        wire[-1] ^= 1
        good = frame(marker, 13, 1, 13)
        pending, captured = decode_chunks(bytes(wire) + good, 5)
        assert not pending
        assert unpack(captured) == [{'address': 13, 'src': expected_src, 'dat': good[7:]}]
    wire = b''.join(frame(m, 31, 63, 13) for m in (0x80, 0x90, 0xa0))
    mixed_splits = len(wire) + 1
    for split in range(len(wire) + 1):
        pending, captured = decode_chunks(wire, split)
        assert not pending and [row['src'] for row in unpack(captured)] == [4, 5, 6]
    # Other marker values remain rejected (do not reinterpret bus 3 as source7).
    wire = frame(0xb0, 31, 0, 13) + frame(0x90, 13, 1, 13)
    _, captured = decode_chunks(wire, len(wire))
    assert [row['src'] for row in unpack(captured)] == [5]
    # Execute the actual patched status class, without importing cereal/native deps.
    tree = ast.parse((destination / 'status.py').read_text(encoding='utf-8'))
    status_class = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'CaptureStatus')
    namespace = {'time': time, 'FRAME_FRESH_SECONDS': 2.0}
    exec(compile(ast.Module(body=[status_class], type_ignores=[]), 'status.py', 'exec'), namespace)
    status = namespace['CaptureStatus'](None, clock=lambda: 10.0)
    status.received([{'src': 5}, {'src': 5}])
    snapshot = status.snapshot()
    assert snapshot['state'] == 'receiving' and snapshot['src4Frames'] == snapshot['src6Frames'] == 0
    assert status.counts[5] == status.arrival_counts[5] == 2
    # Execute the actual startup submit method to verify source5 survives buffering.
    tree = ast.parse((destination / 'startup.py').read_text(encoding='utf-8'))
    startup_class = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'LoggerStartup')
    submit = next(n for n in startup_class.body if isinstance(n, ast.FunctionDef) and n.name == 'submit')
    submit.name = 'startup_submit'
    message = SimpleNamespace(to_bytes=lambda: b'buffered-cereal-placeholder')
    namespace = {'messaging': SimpleNamespace(new_message=lambda *a: message)}
    exec(compile(ast.Module(body=[submit], type_ignores=[]), 'startup.py', 'exec'), namespace)
    startup = SimpleNamespace(clock=lambda: 10.0, telemetry=status, ready=False, queue=[],
                              buffered_bytes=0, buffered_frames=0, capacity=4096)
    rows = [{'src': 4}, {'src': 5}, {'src': 6}]
    namespace['startup_submit'](startup, rows)
    assert message.can == rows and startup.queue[0][1] == {4: 1, 5: 1, 6: 1}
    assert startup.buffered_frames == 3 and status.arrival_counts[5] == 3
    print(f'TEST_SUMMARY source5_host failures=0 split_cases={cases} mixed_splits={mixed_splits}')


if __name__ == '__main__':
    main()
