#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
if [ "$#" -ne 2 ] && [ "$#" -ne 4 ]; then
    printf 'usage: %s PRIVATE_602_VERTEX PRIVATE_602_FRAGMENT [PRIVATE_603_VERTEX PRIVATE_603_FRAGMENT]\n' "$0" >&2
    exit 2
fi
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=$(mktemp -d /private/tmp/a5mali-shader-cache-test.XXXXXX)
for profile in 602 603; do
if [ "$profile" -eq 603 ] && [ "$#" -eq 2 ]; then continue; fi
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -DA5_SHADER_COMPILED_CACHE_HOST_TEST \
    "-DA5_CACHE_TEST_PROFILE=$profile" \
    "-DA5_SHADER_COMPILED_CACHE_TEST_ROOT=\"$output/cache\"" \
    "$here/A5MaliShaderCompiledCache.m" "$here/test_shader_compiled_cache.m" \
    -framework Foundation -o "$output/test_shader_compiled_cache-$profile"
if [ "$profile" -eq 602 ]; then
    "$output/test_shader_compiled_cache-$profile" "$1" "$2"
else
    "$output/test_shader_compiled_cache-$profile" "$3" "$4"
fi
done
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -c "$here/A5MaliShaderCompiledCache.m" -o "$output/A5MaliShaderCompiledCache-ios.o"
printf 'iOS16 Cortex-A53 Werror compile: PASS\nPrivate artifacts: %s\n' "$output"
