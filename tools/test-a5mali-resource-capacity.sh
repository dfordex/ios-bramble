#!/bin/sh
# SPDX-License-Identifier: MIT
# Host-only tests; takes iokit/Kernel/arm from an XNU tree with patch0204.
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
 echo "usage: $0 PATCHED_XNU_KERNEL_ARM_DIRECTORY [OUTPUT_DIRECTORY]" >&2
 exit 2
fi
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
headers=$(CDPATH= cd -- "$1" && pwd)
out=${2:-/private/tmp/a5mali-resource-capacity}
[ -f "$headers/A5XELTEGPUResourceSlots.h" ] || { echo 'XNU patch0204 required' >&2; exit 1; }
mkdir -p "$out"
clang++ -std=c++17 -Wall -Wextra -Werror -I"$headers" \
 "$repo/xnu/tests/gpu_resource_slots.cpp" -o "$out/resource_slots"
"$out/resource_slots"
clang -std=c11 -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
 "$repo/userland/a5mali-metal/A5MaliBridge.c" "$repo/userland/a5mali-metal/test_import_failure.c" \
 -framework IOKit -framework CoreFoundation -o "$out/import_failure"
"$out/import_failure"
"$repo/userland/a5mali-metal/test_operation_retirement.sh" "$out/operation_retirement"
