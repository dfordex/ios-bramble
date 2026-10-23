#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
if [ "$#" -ne 2 ] && [ "$#" -ne 4 ] && [ "$#" -ne 6 ] && [ "$#" -ne 8 ] && [ "$#" -ne 10 ]; then
    printf 'usage: %s PRIVATE_602_VERTEX PRIVATE_602_FRAGMENT [PRIVATE_603_VERTEX PRIVATE_603_FRAGMENT [PRIVATE_604_VERTEX PRIVATE_604_FRAGMENT [PRIVATE_605_VERTEX PRIVATE_605_FRAGMENT [PRIVATE_606_VERTEX PRIVATE_606_FRAGMENT]]]]\n' "$0" >&2
    exit 2
fi
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=$(mktemp -d /private/tmp/a5mali-shader-cache-test.XXXXXX)
profile=602
while [ "$#" -ge 2 ]; do
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -DA5_SHADER_COMPILED_CACHE_HOST_TEST \
    "-DA5_CACHE_TEST_PROFILE=$profile" \
    "-DA5_SHADER_COMPILED_CACHE_TEST_ROOT=\"$output/cache\"" \
    "$here/A5MaliShaderCompiledCache.m" "$here/test_shader_compiled_cache.m" \
    -framework Foundation -o "$output/test_shader_compiled_cache-$profile"
"$output/test_shader_compiled_cache-$profile" "$1" "$2"
shift 2
profile=$((profile + 1))
done
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -c "$here/A5MaliShaderCompiledCache.m" -o "$output/A5MaliShaderCompiledCache-ios.o"
printf 'iOS16 Cortex-A53 Werror compile: PASS\nPrivate artifacts: %s\n' "$output"
