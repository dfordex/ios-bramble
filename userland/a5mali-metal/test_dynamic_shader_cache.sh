#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-dynamic-cache-test}
mkdir -p "$out"
root="$out/publication"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -fsanitize=address,undefined \
 -DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1 \
 -DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="\"$root\"" \
 "$src/A5MaliDynamicShaderCache.m" "$src/test_dynamic_shader_cache.m" \
 -framework Foundation -framework Metal -o "$out/test"
"$out/test"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$sdk" \
 -fobjc-arc -fblocks -Wall -Wextra -Werror -c "$src/A5MaliDynamicShaderCache.m" \
 -o "$out/A5MaliDynamicShaderCache-ios.o"
