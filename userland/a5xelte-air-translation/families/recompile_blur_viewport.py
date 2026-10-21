#!/usr/bin/env python3
"""Recompile authenticated blur SPIR-V with real UBO viewport sysvals.

Keeps all legacy artifacts intact. The fragment machine code must stay byte
identical; only the shared DS4/blur vertex program changes. No Apple bytes here.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import translate_blur as compiler


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--spirv-root', type=Path, required=True)
    p.add_argument('--ds4-vertex', type=Path, required=True)
    p.add_argument('--validator', type=Path, required=True)
    p.add_argument('--mesa-build', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    source = json.loads(a.manifest.read_text())
    a.output.mkdir(parents=True, exist_ok=True)
    backend = a.output.resolve() / 'blur-pair-midgard'
    compiler.build_backend(a.mesa_build.resolve(), backend)
    records = []
    for item in source['pairs']:
        if item['status'] != 'compiled':
            raise ValueError('uncompiled source profile')
        suffix = '_RGBA16Float' if item['attachment_format'] == 'RGBA16Float' else ''
        directory = a.spirv_root / (item['fragment'] + suffix)
        dest = a.output.resolve() / directory.name
        dest.mkdir(exist_ok=True)
        paths = [directory / ('pair.' + st + '.spv') for st in ('vert', 'frag')]
        for st, path in zip(('vert', 'frag'), paths):
            info = item[st + '_spirv']
            if compiler.sha(path) != info['sha256'] or path.stat().st_size != info['bytes']:
                raise ValueError('changed authenticated ' + st + ' SPIR-V')
            subprocess.run([str(a.validator), '--target-env', 'vulkan1.2', '--uniform-buffer-standard-layout', str(path)], check=True)
        if compiler.sha(a.ds4_vertex) != item['vert_spirv']['sha256']:
            raise ValueError('DS4 vertex must be the exact same validated module')
        cmd = [str(backend), *map(str, paths), str(dest / 'pair.vert.midgard'),
               str(dest / 'pair.frag.midgard'), compiler.fnv(paths[0]), compiler.fnv(paths[1]),
               str(item['native_binding']['ubo3_fragment_buffer1_bytes'])]
        if suffix: cmd.append('rgba16f')
        cmd.append('--dynamic-viewport')
        result = subprocess.run(cmd, text=True, capture_output=True)
        (dest / 'compile.log').write_text(result.stdout + result.stderr)
        result.check_returncode()
        reports = re.findall(r'Midgard bytes=(\d+) first_tag=(\d+) textures=(\d+) work_regs=(\d+) tls=(\d+) wls=(\d+) attributes=(\d+) ubos=(\d+) samplers=(\d+)', result.stdout)
        if len(reports) != 2: raise ValueError('missing real compiler metadata')
        record = {'vertex': item['vertex'], 'fragment': item['fragment'],
                  'attachment_format': item['attachment_format']}
        for st, report in zip(('vert', 'frag'), reports):
            path = dest / ('pair.' + st + '.midgard')
            info = dict(zip(('bytes','first_tag','textures','work_regs','tls','wls','attributes','ubos','samplers'), map(int, report)))
            if path.stat().st_size != info['bytes']: raise ValueError('invalid compiler size')
            record[st + '_midgard'] = {**info, 'path': str(path), 'sha256': compiler.sha(path), 'fnv1a64': compiler.fnv(path)}
        if record['frag_midgard']['sha256'] != item['frag_midgard']['sha256']:
            raise ValueError('viewport change altered fragment machine code')
        record['vert_spirv_sha256'] = item['vert_spirv']['sha256']
        records.append(record)
    if len(records) != 9 or len({r['vert_midgard']['sha256'] for r in records}) != 1:
        raise ValueError('expected nine profiles sharing one genuine vertex program')
    manifest = {'scope': 'host compilation, not on-device execution proof',
        'source_manifest': str(a.manifest.resolve()), 'source_manifest_sha256': compiler.sha(a.manifest),
        'backend_source_sha256': compiler.sha(Path(compiler.__file__).with_name('blur_pair_midgard.c')),
        'backend_sha256': compiler.sha(backend), 'validator_sha256': compiler.sha(a.validator),
        'viewport_sysval': {'stage': 'Vertex', 'ubo': 0, 'scale_offset': 512,
            'offset_offset': 528, 'record_bytes': 16, 'ubo_bytes': 576},
        'base_vertex': 0, 'profile_ids': list(range(99,109)), 'pairs': records}
    (a.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('PASS 9 real validated pairs: dynamic viewport VS, unchanged FS; DS4 exact input module matches')
    print(json.dumps(records[0]['vert_midgard'], sort_keys=True))


if __name__ == '__main__': main()
