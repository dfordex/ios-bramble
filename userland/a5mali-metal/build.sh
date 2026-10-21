#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/tmp/a5mali-bridge-build}
mkdir -p "$out_dir"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -isysroot "$sdk" -fobjc-arc -Wall -Wextra -Werror \
    -dynamiclib -install_name @rpath/libA5MaliBridge.dylib \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliCommandBuffer.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -o "$out_dir/libA5MaliBridge.dylib"
codesign --force --sign - "$out_dir/libA5MaliBridge.dylib"
codesign --verify --strict "$out_dir/libA5MaliBridge.dylib"
file "$out_dir/libA5MaliBridge.dylib"

clang -std=c11 -Wall -Wextra -Werror -pedantic \
    "$src_dir/A5MaliBridge.c" "$src_dir/test_bridge.c" \
    -framework IOKit -framework CoreFoundation \
    -o "$out_dir/test_bridge"
"$out_dir/test_bridge"
