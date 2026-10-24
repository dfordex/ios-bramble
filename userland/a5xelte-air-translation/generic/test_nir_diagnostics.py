#!/usr/bin/env python3
"""Check actual compiler code equivalence and bounded default NIR diagnostics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--input-dir', type=Path, required=True,
                        help='private directory containing shader.vert.spv/shader.frag.spv')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    results = []
    reference = None
    # Only the literal 1 enables a full dump; ordinary values are not truthy.
    for value in (None, '0', 'yes', '1'):
        label = 'unset' if value is None else value
        env = dict(os.environ)
        env.pop('A5_MIDGARD_DUMP_NIR', None)
        if value is not None:
            env['A5_MIDGARD_DUMP_NIR'] = value
        prefix = out / label
        log = prefix.with_suffix('.log')
        with log.open('w') as stream:
            subprocess.run([str(args.backend.resolve()),
                str(args.input_dir.resolve() / 'shader.vert.spv'),
                str(args.input_dir.resolve() / 'shader.frag.spv'),
                str(prefix.with_suffix('.vert')), str(prefix.with_suffix('.frag'))],
                stdout=stream, stderr=subprocess.STDOUT, env=env, check=True)
        native = [prefix.with_suffix('.' + stage).read_bytes() for stage in ('vert', 'frag')]
        if reference is None:
            reference = native
        assert native == reference, 'NIR verbosity changed native code'
        text = log.read_text()
        assert text.count('validation=enabled dump=') == 2
        assert text.count('Midgard bytes=') == 2
        if value == '1':
            assert log.stat().st_size > 4096 and 'shader: MESA_SHADER_' in text
            assert 'validation=enabled dump=1' in text
        else:
            assert log.stat().st_size < 2048 and 'shader: MESA_SHADER_' not in text
            assert 'validation=enabled dump=1' not in text
        results.append({'setting': value, 'log_bytes': log.stat().st_size,
                        'native_sha256': [hashlib.sha256(x).hexdigest() for x in native]})
    (out / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
    print('NIR diagnostics: four actual compiler runs retain identical native code; default bounded and explicit dump available PASS')


if __name__ == '__main__':
    main()
