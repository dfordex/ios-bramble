#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-long-command-queue}
mkdir -p "$out"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -DA5_MALI_HOST_TEST \
 "$src/A5MaliBridge.c" "$src/A5MaliNative.c" "$src/A5MaliNativeUpload.c" \
 "$src/A5MaliCommandBuffer.m" "$src/test_long_command_queue.m" \
 -framework Foundation -framework IOSurface -framework IOKit -o "$out/test"
"$out/test"
