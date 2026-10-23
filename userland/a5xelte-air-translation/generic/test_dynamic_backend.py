#!/usr/bin/env python3
"""Check the actual dynamic backend against private known and unseen stages."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
from dynamic_abi import build_manifest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--backend', type=Path, required=True)
    p.add_argument('--known-dir', type=Path, required=True)
    p.add_argument('--unknown-dir', type=Path, required=True)
    a = p.parse_args()
    with tempfile.TemporaryDirectory(prefix='a5-dynamic-backend-', dir='/private/tmp') as tmp:
        out = Path(tmp)
        counter = 0
        def run(folder, stage, manifest=None, ok=True):
            nonlocal counter
            counter += 1
            meta = json.loads((folder / 'reflection.json').read_text())
            abi = build_manifest(meta, stage) if manifest is None else manifest
            text = out / f'{counter}.abi'
            code = out / f'{counter}.midgard'
            info = out / f'{counter}.json'
            text.write_text(abi)
            suffix = 'vert' if stage == 'vertex' else 'frag'
            with (out / f'{counter}.log').open('w') as log:
                result = subprocess.run([str(a.backend), '--dynamic-stage', stage,
                    str(folder / f'shader.{suffix}.spv'), str(code), str(text), str(info)],
                    stdout=log, stderr=subprocess.STDOUT)
            if not ok:
                assert result.returncode and not code.exists() and not info.exists()
                return None
            assert result.returncode == 0
            j = json.loads(info.read_text())
            assert j['schema'] == 1 and j['stage'] == stage
            assert j['native_info']['bytes'] == code.stat().st_size
            assert not j['native_info']['tls'] and not j['native_info']['wls']
            return code.read_bytes(), j
        # A caller may compile a previously unknown module using only its
        # reflected ABI; no generated kStages fingerprint is consulted.
        for stage, suffix in (('vertex', 'vert'), ('fragment', 'frag')):
            code, info = run(a.known_dir, stage)
            assert code == (a.known_dir / f'{suffix}.midgard').read_bytes()
            other, _ = run(a.unknown_dir, stage)
            if stage == 'fragment':
                assert hashlib.sha256(other).digest() != hashlib.sha256(code).digest()
                assert any(x == {'native_index': 3, 'min_bytes': 128} for x in info['live_ubos'])
            else:
                assert any(x['location'] == 12 and x['components'] == 1 for x in info['outputs'])
        manifest = build_manifest(json.loads((a.known_dir / 'reflection.json').read_text()), 'fragment')
        cases = [manifest.replace('uniform 168', 'uniform 127'),
                 manifest.replace('stage fragment', 'stage vertex'),
                 manifest + 'spec 0 0\n',
                 manifest.replace('texture 5 0', 'texture 5 1'),
                 manifest.replace('push_bytes 76', 'push_bytes 84'),
                 manifest.replace('binding 3 uniform 8\n', ''),
                 manifest.replace('binding 2 uniform 168', 'binding 2 storage 168'),
                 manifest.replace('texture 5 0', 'texture 4294967301 0'),
                 manifest.replace('texture 5 0', 'texture -4294967291 0'),
                 manifest + ('spec 77 0\n' * 70),
                 manifest.rstrip('\n')]
        for value in cases:
            run(a.known_dir, 'fragment', value, False)
        # A valid module with its ColorWriteRule moved into unimplemented
        # UBO0 space must fail actual native-liveness validation, even though
        # dynamic compilation intentionally has no module-hash allowlist.
        altered = out / 'unimplemented-sysval'
        altered.mkdir()
        (altered / 'reflection.json').write_bytes((a.known_dir / 'reflection.json').read_bytes())
        blob = (a.known_dir / 'shader.frag.spv').read_bytes()
        words = list(struct.unpack('<%dI' % (len(blob) // 4), blob))
        cursor, changed = 5, 0
        while cursor < len(words):
            count, opcode = words[cursor] >> 16, words[cursor] & 0xffff
            assert count
            # OpMemberDecorate(type, member, Offset, 72).
            if opcode == 72 and count == 5 and words[cursor + 3:cursor + 5] == [35, 72]:
                words[cursor + 4] = 96
                changed += 1
            cursor += count
        assert changed == 1
        (altered / 'shader.frag.spv').write_bytes(struct.pack('<%dI' % len(words), *words))
        run(altered, 'fragment', manifest, False)
        # Old pair mode remains byte-identical after adding dynamic support.
        with (out / 'pair.log').open('w') as log:
            subprocess.run([str(a.backend), str(a.known_dir / 'shader.vert.spv'),
                str(a.known_dir / 'shader.frag.spv'), str(out / 'pair.vert'),
                str(out / 'pair.frag')], stdout=log, stderr=subprocess.STDOUT, check=True)
        for stage in ('vert', 'frag'):
            assert (out / f'pair.{stage}').read_bytes() == (a.known_dir / f'{stage}.midgard').read_bytes()
        print('dynamic backend: 4 actual stages, 11 bounded-ABI negatives, actual unknown-sysval rejection and preserved static pair PASS')


if __name__ == '__main__':
    main()
