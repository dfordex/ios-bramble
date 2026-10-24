#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-surface-residency}
mkdir -p "$out"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
 "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliCommandBuffer.m" \
 "$src_dir/test_surface_residency.m" -framework Foundation -framework IOSurface -framework IOKit \
 -o "$out/test-residency"
"$out/test-residency"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto \
 -isysroot "$sdk" -fobjc-arc -fblocks -Wall -Wextra -Werror -c \
 "$src_dir/A5MaliCommandBuffer.m" -o "$out/A5MaliCommandBuffer.o"
