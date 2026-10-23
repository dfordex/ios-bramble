#!/usr/bin/env python3
"""Check actual linked loader DCS byte reads before MMU-off device testing."""
import argparse
import re
import subprocess

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('elf')
ap.add_argument('--objdump', default='llvm-objdump')
args = ap.parse_args()
disassembly = subprocess.check_output([args.objdump, '-d', args.elf], text=True)
block = re.search(r'<dcs_long>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)', disassembly, re.S)
if not block:
    raise SystemExit('FAIL: missing linked dcs_long; review compiler changes')
instructions = block.group(1).splitlines()
byte_reads = [line for line in instructions if re.search(r'\bldrb\b.*\[x0(?:,|\])', line)]
wide_reads = [line for line in instructions if re.search(r'\b(?:ldr|ldur|ldp|ldrh)\b.*\[x0(?:,|\])', line)]
# The current compiler specializes this function to each five-byte DCS command.
# Fail closed if it changes source-register allocation or loop lowering.
if len(byte_reads) < 5 or wide_reads:
    raise SystemExit('FAIL: expected five byte source reads and no widened source read\n' +
                     '\n'.join(byte_reads + wide_reads))
print('PASS: actual linked DCS command uses five byte reads, no widened source read')
