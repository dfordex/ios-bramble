#!/bin/sh
# Build the SM-A720F stage-0 probe and XNU loader Images. No flash or packaging here.
#   CROSS=aarch64-elf- shim/a720f/build.sh
set -eu
cd "$(dirname "$0")"
mkdir -p out
: "${CROSS:=aarch64-linux-gnu-}"
CC="${CROSS}gcc"
LD="${CROSS}ld"
OBJCOPY="${CROSS}objcopy"
# S-Boot enters with SCTLR_EL1.A=1 and M=0 (observed on a5xelte; assumed here).
# Unaligned widened loads from byte arrays fault with the MMU off.
CFLAGS="-c -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -nostdlib -fno-asynchronous-unwind-tables -mgeneral-regs-only -mstrict-align -march=armv8-a -mcpu=cortex-a53 -Wall -Wextra -Werror"

"$CC" $CFLAGS probe.S -o out/probe.o
"$LD" -static -T a720f.ld --build-id=none out/probe.o -o out/probe.elf
"$OBJCOPY" -O binary out/probe.elf out/probe.Image

"$CC" $CFLAGS xnu_boot.S -o out/xnu_boot.o
"$CC" $CFLAGS xnu_boot.c -o out/xnu_boot_c.o
"$CC" $CFLAGS ../fdt.c -o out/fdt.o
"$LD" -static -T a720f.ld --build-id=none out/xnu_boot.o out/xnu_boot_c.o out/fdt.o -o out/xnu_boot.elf
"$OBJCOPY" -O binary out/xnu_boot.elf out/xnu_boot.Image

python3 - <<'PY'
from pathlib import Path
import struct
for name in ("out/probe.Image", "out/xnu_boot.Image"):
    p = Path(name).read_bytes()
    assert len(p) < 0x200000, name
    assert p[56:60] == b"ARMd", name
    assert struct.unpack_from("<Q", p, 8)[0] == 0x1000, name
    assert struct.unpack_from("<Q", p, 16)[0] == 0, name
    print(f"{name}: {len(p)} bytes; Samsung Image header OK (text_offset 0x1000)")
PY
