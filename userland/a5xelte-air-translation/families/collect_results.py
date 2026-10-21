#!/usr/bin/env python3
"""Verify local family outputs and collect row-preserving host coverage.

Reads the three recipes' private manifests. Does not install, submit GPU jobs,
or equate a compiled shader with verified rendering. Output belongs outside Git.
"""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
COMPILED = ('compiled', 'compiled_empty_fragment', 'compiled_native_ordered_fetch')
VK_FORMATS = {'R8Unorm': 9, 'RG8Unorm': 16, 'BGRA8Unorm': 44,
              'RGBA16Float': 97, 'R32Float': 100}


def checked(path, expected):
    data = path.read_bytes()
    if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
        raise ValueError(f'output disagrees with compiler manifest: {path}')
    return {'bytes': len(data), 'sha256': expected['sha256'], 'path': str(path)}


def collect(blur, path, misc):
    targets = json.loads((HERE / 'targets.json').read_text())
    target_rows = {r['row']: r for group in targets['groups'].values() for r in group}
    rows = {}
    identities = set()
    source_profiles = set()
    results = []
    for group, manifest_path in [('blur', blur), ('path', path), ('misc', misc)]:
        doc = json.loads(manifest_path.read_text())
        for entry in doc.get('pairs', doc.get('profiles', [])):
            selected = entry.get('warmup_rows', entry.get('rows', [entry.get('row')]))
            fmt = entry.get('attachment_format', entry.get('color_format'))
            status = entry['status']
            render_target = entry.get('render_target')
            output_format = entry.get('output_color_format', fmt)
            result = {'group': group, 'vertex': entry['vertex'], 'fragment': entry['fragment'],
                      'color_format': fmt, 'rows': selected, 'status': status,
                      'runtime_verified': False, 'stages': {},
                      'render_target': render_target, 'output_color_format': output_format,
                      'execution': entry.get('execution', 'native_profile'),
                      'source_manifest': str(manifest_path)}
            for key in ('requires', 'native_ordered_contract', 'runtime_blocker',
                        'resource_abi', 'native_binding', 'graphics', 'layout',
                        'full_air_output_targets', 'native_output_packing',
                        'native_ordered_tilebuffer_contract'):
                if key in entry:
                    result[key] = entry[key]
            if status in COMPILED:
                if group == 'blur':
                    suffix = '' if fmt == 'BGRA8Unorm' else '_' + fmt
                    stem = manifest_path.parent / (entry['fragment'] + suffix) / 'pair'
                    descriptions = {s: entry[s + '_midgard'] for s in ('vert', 'frag')}
                    spirv = {s: entry[s + '_spirv'] for s in ('vert', 'frag')}
                elif group == 'path':
                    stem = manifest_path.parent / entry['pair']
                    descriptions, spirv = entry['midgard'], entry['spirv']
                else:
                    stem = manifest_path.parent / (entry['family'] + '_' + entry['variant'])
                    descriptions, spirv = entry['midgard'], entry['spirv']
                spirv_stem = stem
                native_stem = Path(str(stem) + '_rt' + str(render_target)) if render_target is not None else stem
                for stage in ('vert', 'frag'):
                    result['stages'][stage] = {
                        'spirv': checked(Path(str(spirv_stem) + '.' + stage + '.spv'), spirv[stage]),
                        'midgard': checked(Path(str(native_stem) + '.' + stage + '.midgard'), descriptions[stage]),
                        'compiler_info': descriptions[stage]}
                if not result['stages']['vert']['midgard']['bytes']:
                    raise ValueError('empty vertex executable')
                empty_fragment = not result['stages']['frag']['midgard']['bytes']
                if empty_fragment != (status == 'compiled_empty_fragment'):
                    raise ValueError('empty fragment incorrectly classified')
            else:
                result['reason'] = entry.get('reason', entry.get('error', 'unspecified'))
            for row in selected:
                target = target_rows[row]
                if target not in targets['groups'][group]:
                    raise ValueError(f'incorrectly grouped row: {row}')
                for field in ('vertex', 'fragment', 'color_format'):
                    if result[field] != target[field]:
                        raise ValueError(f'row {row} {field} disagrees with audited target')
                # A source pipeline may have several explicitly selected SFBD outputs.
                # Keep all of them; repeated identical variants are still an error.
                identity = (row, render_target, output_format, result['execution'])
                if identity in identities:
                    raise ValueError(f'duplicate execution variant: {identity}')
                identities.add(identity)
                rows.setdefault(row, []).append(len(results))
                if group == 'misc':
                    graphics = entry['graphics']
                    attachments = graphics['color_attachments']
                    outputs = entry['full_air_output_targets']
                    if graphics['color_outputs'] != sum(1 << n for n in outputs):
                        raise ValueError(f'row {row}: AIR output mask disagrees')
                    if render_target not in outputs or render_target >= len(attachments):
                        raise ValueError(f'row {row}: selected target is not an AIR output')
                    secondary = 'RG8Unorm' if fmt == 'R8Unorm' else fmt
                    expected_formats = {0: fmt, 1: secondary}
                    expected_formats.update({a['index']: a['color_format']
                                             for a in target['additional_color_attachments']})
                    for index, attachment in enumerate(attachments):
                        if attachment['format'] != VK_FORMATS[expected_formats[index]]:
                            raise ValueError(f'row {row}: attachment {index} has wrong format')
                    if output_format != expected_formats[render_target]:
                        raise ValueError(f'row {row}: selected native output format disagrees')
                    if len(outputs) > 1 and result['execution'] != 'single_SFBD_target_replay':
                        raise ValueError(f'row {row}: multi-output execution must be explicit replay')
                    required = set(expected_formats) - {1} if 1 not in outputs else set(expected_formats)
                    if not required.issubset(range(len(attachments))):
                        raise ValueError(f'row {row}: configured attachment was dropped')
            source_profiles.add((group, entry['vertex'], entry['fragment'], fmt))
            results.append(result)
    expected = {r['row'] for g, rs in targets['groups'].items() if g != 'existing' for r in rs}
    if set(rows) != expected:
        raise ValueError(f'row coverage differs: missing={expected-set(rows)}, extra={set(rows)-expected}')
    # Every selected AIR output must have a separately authenticated executable.
    for row, indexes in rows.items():
        variants = [results[i] for i in indexes]
        if variants[0]['group'] == 'misc':
            required = set(variants[0]['full_air_output_targets'])
            if {v['render_target'] for v in variants} != required:
                raise ValueError(f'row {row}: incomplete native target replays')
            for stage in ('vert', 'frag'):
                if len({v['stages'][stage]['spirv']['sha256'] for v in variants}) != 1:
                    raise ValueError(f'row {row}: replays use different full-source SPIR-V')
    return {'scope': 'host compilation and artifact consistency only; no runtime acceptance',
            'quartzcore_uuid': targets['quartzcore_uuid'],
            'new_unique_pairs': len({(x['vertex'], x['fragment']) for x in results}),
            'source_attachment_profiles': len(source_profiles),
            'native_execution_profiles': len(results),
            'single_SFBD_target_replay_profiles': sum(
                x['execution'] == 'single_SFBD_target_replay' for x in results),
            'pipeline_rows': len(rows),
            'completed_profiles': sum(x['status'] in COMPILED for x in results),
            'empty_fragment_profiles': sum(x['status'] == 'compiled_empty_fragment' for x in results),
            'profiles': results, 'row_to_profiles': rows}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('blur', 'path', 'misc', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    args = p.parse_args()
    result = collect(args.blur.resolve(), args.path.resolve(), args.misc.resolve())
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('profiles', 'row_to_profiles')}, indent=2))


if __name__ == '__main__':
    main()
