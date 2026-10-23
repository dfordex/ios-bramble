#!/usr/bin/env python3
"""Restore the Samsung patch series onto the donor's already-patched XNU tree.

Local source operation only. Private generated payload/test includes are not
inputs. Historical patches contain short/miscounted hunks and blank-only context
drift; fallback preserves unmatched blank context rather than deleting it and
moving a later context-free insertion into a function or declaration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def fallback(root, text):
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        if not lines[i].startswith('--- '):
            i += 1
            continue
        new = lines[i + 1][4:].strip().split('\t')[0]
        i += 2
        if not new.startswith('b/'):
            raise ValueError('only bounded source additions/changes are supported')
        path = root / new[2:]
        if not path.resolve().is_relative_to(root):
            raise ValueError('patch path escapes the source root')
        buf = path.read_text().splitlines(keepends=True) if path.exists() else []
        shift = 0
        while i < len(lines) and not lines[i].startswith('--- '):
            if not lines[i].startswith('@@ '):
                i += 1
                continue
            oldline = int(re.match(r'@@ -(\d+)', lines[i])[1])
            i += 1
            ops = []
            while i < len(lines) and not lines[i].startswith(('@@ ', '--- ')):
                line = lines[i]
                i += 1
                if line.startswith((' ', '+', '-')):
                    ops.append((line[0], line[1:]))
            before = [value for op, value in ops if op != '+']
            after = [value for op, value in ops if op != '-']
            if not before:
                index = max(0, oldline + shift)
                if index > len(buf):
                    raise ValueError('context-free insertion exceeds source length')
                buf[index:index] = after
                shift += len(after)
                continue
            wanted = [line for line in before if line.strip()]
            have = [(index, line) for index, line in enumerate(buf) if line.strip()]
            matches = [have[index][0] for index in range(len(have) - len(wanted) + 1)
                       if [line for _, line in have[index:index + len(wanted)]] == wanted]
            expected = oldline - 1 + shift
            if not matches:
                raise ValueError(f'missing exact nonblank context: {new}:{oldline}')
            ranked = sorted(matches, key=lambda index: abs(index - expected))
            if len(ranked) > 1 and (abs(ranked[0] - expected) > 32 or
                    abs(ranked[0] - expected) == abs(ranked[1] - expected)):
                raise ValueError(f'ambiguous nonblank context: {new}:{oldline}')
            start = ranked[0]
            cursor = start
            result = []
            for op, line in ops:
                if op == '+':
                    result.append(line)
                    continue
                if line.strip():
                    while cursor < len(buf) and not buf[cursor].strip():
                        result.append(buf[cursor])
                        cursor += 1
                    if cursor >= len(buf) or buf[cursor] != line:
                        raise ValueError('nonblank context changed during patch application')
                    if op == ' ':
                        result.append(buf[cursor])
                    cursor += 1
                elif cursor < len(buf) and not buf[cursor].strip():
                    if op == ' ':
                        result.append(buf[cursor])
                    cursor += 1
            buf[start:cursor] = result
            shift = start + len(result) - (oldline - 1 + len(before))
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(''.join(buf))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='fresh donor XNU tree with patches1..81')
    parser.add_argument('--patches', type=Path, default=Path(__file__).resolve().parents[1] / 'xnu/patches')
    parser.add_argument('--through', type=int, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    root = args.source.resolve(strict=True)
    if not (root / 'iokit/Kernel/arm/SweetCPU.cpp').is_file() or \
            (root / 'iokit/Kernel/arm/A5XELTEGPU.cpp').exists():
        parser.error('requires a fresh donor checkpoint; refusing a partial/repeated Samsung overlay')
    patches = sorted(p for p in args.patches.glob('*.patch')
                     if re.fullmatch(r'\d{4}-.+\.patch', p.name)
                     and 82 <= int(p.name[:4]) <= args.through)
    if [int(p.name[:4]) for p in patches] != list(range(82, args.through + 1)):
        parser.error('Samsung patch sequence must be contiguous')
    receipt = []
    with tempfile.TemporaryDirectory(prefix='a5-patch-') as tmp:
        current = Path(tmp) / 'current.patch'
        for patch in patches:
            raw = patch.read_bytes()
            text = raw.decode().replace('a/xnu/', 'a/').replace('b/xnu/', 'b/')
            # Validate every changed destination even when git can apply it.
            for destination in re.findall(r'^\+\+\+ (\S+)', text, re.MULTILINE):
                if not destination.startswith('b/') or \
                        not (root / destination[2:]).resolve().is_relative_to(root):
                    raise ValueError('patch destination escapes the source root')
            current.write_text(text)
            command = ['git', 'apply', '--recount', '--unidiff-zero']
            check = subprocess.run(command + ['--check', str(current)], cwd=root,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if check.returncode:
                fallback(root, text)
                method = 'exact-nonblank-preserve-context'
            else:
                subprocess.run(command + [str(current)], cwd=root, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                method = 'git-recount-unidiff-zero'
            receipt.append({'patch': patch.name, 'sha256': hashlib.sha256(raw).hexdigest(),
                            'method': method})
    args.receipt.write_text(json.dumps({'patches': receipt,
        'claim': 'Source reconstruction only; full compilation and scope review remain required.'}, indent=2) + '\n')
    print(f'Applied {len(receipt)} Samsung patches; build and scope review required.')


if __name__ == '__main__':
    main()
