#!/bin/bash
# Build a boot.img v3 for `fastboot boot` on bramble (Pixel 4a 5G).
#   build-bramble.sh              -> out/bramble/probe-boot.img (bramble.c probe)
#   build-bramble.sh PAYLOAD.bin  -> out/bramble/shim-boot.img (sweet shim + xnu payload)
set -euo pipefail
cd "$(dirname "$0")"
CROSS=${CROSS:-aarch64-linux-gnu-}
CC=${CROSS}gcc
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
# docs/BRAMBLE.md: splash buffer, panel height, IMEM restart_reason
BOARD="-DFB_BASE=0xa0000000UL -DFB_PHYS=0xa0000000UL -DFB_H=2340 -DIMEM_RESTART_REASON=0x146ab65cUL"
O=out/bramble
mkdir -p $O
if [ -n "${1:-}" ]; then
	name=shim
	srcs="shim.c console.c mmu.c fdt.c loader.c ufs.c"
else
	name=probe
	srcs="bramble.c"
fi
$CC $CFLAGS -DTEXT_OFFSET=0x80000 -c start.S -o $O/start.o
objs=""
for f in $srcs; do
	$CC $CFLAGS $BOARD -c $f -o $O/${f%.*}.o
	objs="$objs $O/${f%.*}.o"
done
# No relocation pass at runtime: only start.o's image_size may be absolute.
abs=$(${CROSS}readelf -r $objs | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	$O/start.o $objs -o $O/$name.elf
${CROSS}objcopy -O binary $O/$name.elf $O/$name.Image
# Pad to image_size so .bss and the stacks exist as zeroed bytes.
size=$((0x$(${CROSS}nm $O/$name.elf | awk '$3=="_end"{print $1}')))
truncate -s "$size" $O/$name.Image
# bramble's ABL refuses a raw Image ("Unsupported"): LZ4 frame like stock.
lz4 -9 -B7 -f -q $O/$name.Image $O/$name.Image.lz4
# ABL wants a signed vbmeta: borrow the one of the phone's own boot_a dump.
STOCK_BOOT=${STOCK_BOOT:-../backup/boot_a.img}
python3 ../tools/mkbootv3.py --kernel $O/$name.Image.lz4 ${1:+--ramdisk "$1"} --cmdline '' \
	--avb_from "$STOCK_BOOT" -o $O/$name-boot.img
ls -l $O/$name.Image $O/$name-boot.img
