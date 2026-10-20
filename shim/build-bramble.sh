#!/bin/bash
# Build the bramble display probe (bramble.c) as a boot.img v3 for `fastboot boot`.
set -euo pipefail
cd "$(dirname "$0")"
CROSS=${CROSS:-aarch64-linux-gnu-}
CC=${CROSS}gcc
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
mkdir -p out/bramble
for f in start.S bramble.c; do
	$CC $CFLAGS -c $f -o out/bramble/${f%.*}.o
done
# No relocation pass at runtime: only start.o's image_size may be absolute.
abs=$(${CROSS}readelf -r out/bramble/bramble.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in bramble.o" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	out/bramble/start.o out/bramble/bramble.o -o out/bramble/probe.elf
${CROSS}objcopy -O binary out/bramble/probe.elf out/bramble/Image
# Pad to image_size so .bss and the stacks exist as zeroed bytes.
size=$((0x$(${CROSS}nm out/bramble/probe.elf | awk '$3=="_end"{print $1}')))
truncate -s "$size" out/bramble/Image
python3 ../tools/mkbootv3.py --kernel out/bramble/Image -o out/bramble/probe-boot.img
ls -l out/bramble/Image out/bramble/probe-boot.img
