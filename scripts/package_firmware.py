"""Verify local Vivado BIT/BIN/MCS outputs and package them for user delivery.

No network, hardware access, source upload or repository mutation.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bit_payload(path):
    data = path.read_bytes()
    magic_length = int.from_bytes(data[:2], 'big')
    position = 2 + magic_length
    if data[position:position + 2] != b'\x00\x01':
        raise ValueError('Invalid Xilinx BIT header')
    position += 2
    fields = {}
    for expected_key in b'abcde':
        if data[position] != expected_key:
            raise ValueError('Unexpected BIT header field')
        position += 1
        width = 4 if expected_key == ord('e') else 2
        length = int.from_bytes(data[position:position + width], 'big')
        position += width
        value = data[position:position + length]
        if len(value) != length:
            raise ValueError('Truncated BIT file')
        position += length
        fields[chr(expected_key)] = value
    if position != len(data) or b'7s50' not in fields['b'].lower():
        raise ValueError('BIT length/target part mismatch')
    return fields['e']


def verify_images(bit, binary, mcs):
    payload = bit_payload(bit)
    image = binary.read_bytes()
    reverse_bits = bytes(int(f'{value:08b}'[::-1], 2) for value in range(256))
    if payload == image:
        encoding = 'BIT payload unchanged'
    elif payload.translate(reverse_bits) == image:
        encoding = 'BIT payload with each byte bit-reversed'
    else:
        raise ValueError('BIN does not match BIT payload')
    if not 0 < len(image) <= 16 * 1024 * 1024:
        raise ValueError('Image exceeds MT25QL128 capacity')
    reconstructed = bytearray(b'\xff') * len(image)
    base, eof, data_records, first_address = 0, False, 0, None
    for line_number, line in enumerate(mcs.read_text(encoding='ascii').splitlines(), 1):
        if not line.startswith(':') or eof:
            raise ValueError(f'Invalid MCS record at line {line_number}')
        record = bytes.fromhex(line[1:])
        if len(record) < 5 or len(record) != record[0] + 5 or sum(record) & 255:
            raise ValueError(f'MCS checksum/length error at line {line_number}')
        address, kind, value = int.from_bytes(record[1:3], 'big'), record[3], record[4:-1]
        if kind == 0:
            start = base + address
            if first_address is None:
                first_address = start
            if start + len(value) > len(image):
                raise ValueError('MCS addresses exceed BIN length')
            reconstructed[start:start + len(value)] = value
            data_records += 1
        elif kind == 1 and len(value) == 0:
            eof = True
        elif kind in (2, 4) and len(value) == 2:
            base = int.from_bytes(value, 'big') << (4 if kind == 2 else 16)
        else:
            raise ValueError(f'Unsupported MCS record type {kind}')
    if not eof or first_address != 0 or not data_records or reconstructed != image:
        raise ValueError('MCS/BIN contents, start address or EOF mismatch')
    return {'bit_to_bin_encoding': encoding, 'mcs_data_records': data_records,
            'mcs_bin_equal': True, 'image_bytes': len(image)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-log', required=True, type=Path)
    parser.add_argument('--program-log', required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    identity_source = repo / 'flexray-interceptor-vivado.srcs/sources_1/new/flexray_log_can_diagnostics.vhd'
    text = identity_source.read_text(encoding='utf-8')
    version = [int(re.search(rf'constant FW_{field} .*?:= (\d+);', text).group(1)) for field in ('MAJOR', 'MINOR', 'PATCH')]
    build_id = int(re.search(r'constant BUILD_ID .*?:= x"([0-9A-Fa-f]+)";', text).group(1), 16)
    version_text = '.'.join(map(str, version))
    name = f'bendbeam_fw_{version_text}_build{build_id}'
    paths = [output / f'{name}.{suffix}' for suffix in ('bit', 'bin', 'mcs')]
    image_validation = verify_images(*paths)
    verification = args.verify_log.read_text(encoding='utf-8', errors='replace')
    match = re.search(r'VERIFY_RESULT telemetry=false diagnostics=true CAN_ID=0x1FA WNS=([\d.-]+) WHS=([\d.-]+)', verification)
    if match is None or min(map(float, match.groups())) < 0 or 'SPI_CDC_RESULT stages=4' not in verification:
        raise ValueError('Missing successful release timing/CDC verification')
    if 'PROGRAMMING_FILES_PASS' not in args.program_log.read_text(encoding='utf-8', errors='replace'):
        raise ValueError('Programming file generation did not complete')

    def git(*arguments):
        return subprocess.check_output(['git', '--no-optional-locks', *arguments], cwd=repo, text=True).strip()

    source_names = git('ls-files', '--', 'flexray-interceptor-vivado.srcs/sources_1',
                       'flexray-interceptor-vivado.srcs/constrs_1', 'scripts/verify_design.tcl',
                       'scripts/check_spi_paths.tcl', 'scripts/generate_programming_files.tcl').splitlines()
    source_names = [p for p in source_names if Path(p).suffix.lower() in ('.vhd', '.xdc', '.bd', '.xci', '.tcl')]
    dirty_names = git('diff', '--name-only', 'HEAD', '--', *source_names)
    if dirty_names:
        raise ValueError('Uncommitted build inputs: ' + dirty_names)
    info = {'firmware': version_text, 'build_id': build_id, 'git_commit': git('rev-parse', 'HEAD'),
            'branch': git('branch', '--show-current'), 'packaged_utc': datetime.now(timezone.utc).isoformat(),
            'working_tree_status': git('status', '--porcelain=v1').splitlines(),
            'build_uses_saved_xpr': False, 'vivado': '2024.2', 'part': 'xa7s50csga324-1Q',
            'frame_telemetry': False, 'diagnostics': True, 'can_id': '0x1FA',
            'identity_hex': (bytes([0x2f, *version]) + build_id.to_bytes(4, 'little')).hex().upper(),
            'source5_original_ids': ['0x1F', '0x31', '0x0D'], 'source5_cycles': 'all',
            'TEST_LCA': False, 'flash': 'MT25QL128', 'interface': 'SPIx4', 'flash_capacity_MiB': 16,
            'start_address': '0x00000000', 'WNS_ns': float(match[1]), 'WHS_ns': float(match[2]),
            'hardware_programmed': False, 'external_io_timing': 'NOT_VALIDATED',
            'image_validation': image_validation,
            'files': {p.name: {'bytes': p.stat().st_size, 'sha256': sha256(p)} for p in paths},
            'source_sha256_at_package_time': {p: sha256(repo / p) for p in source_names}}
    metadata = output / 'build_info.json'
    metadata.write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8')
    readme = output / 'README.txt'
    readme.write_text(
        f'FlexRay Interceptor firmware {version_text} / build {build_id}\n'
        f'Source commit: {info["git_commit"]}\n'
        f'Target: {info["part"]}; MT25QL128, SPIx4, flash address 0x00000000\n'
        'BIT: FPGA configuration image. BIN/MCS: equivalent external-flash images.\n'
        'Source4=BCM-side output; source5=selected DADC original; source6=DADC output.\n'
        'Source5 IDs 0x1F/0x31/0x0D, every cycle, independent of actual modification.\n'
        'Host must support CA90/source5. Host changes are maintained separately.\n'
        f'CAN identity (0x1FA, DLC8): {info["identity_hex"]}\n'
        f'Timing: WNS {info["WNS_ns"]:+.3f} ns / WHS {info["WHS_ns"]:+.3f} ns.\n'
        'Frame telemetry OFF; logging diagnostics ON; TEST_LCA=false.\n'
        'No hardware/flash was programmed. Physical I/O/USB/vehicle validation not performed.\n'
        'Check SHA256SUMS.txt before use. build_info.json records source provenance.\n', encoding='utf-8')
    paths += [metadata, readme]
    sums = output / 'SHA256SUMS.txt'
    sums.write_text(''.join(f'{sha256(p)}  {p.name}\n' for p in paths), encoding='ascii')
    paths.append(sums)
    archive = output / f'{name}.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p in paths:
            z.write(p, p.name)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None or sorted(z.namelist()) != sorted(p.name for p in paths):
            raise ValueError('ZIP integrity check failed')
        for p in paths:
            if hashlib.sha256(z.read(p.name)).hexdigest() != sha256(p):
                raise ValueError('ZIP member checksum mismatch')
    archive.with_suffix('.zip.sha256').write_text(f'{sha256(archive)}  {archive.name}\n', encoding='ascii')
    print(json.dumps({'result': 'FIRMWARE_PACKAGE_PASS', 'zip': str(archive),
                      'sha256': sha256(archive), 'bytes': archive.stat().st_size, **image_validation}))


if __name__ == '__main__':
    main()
