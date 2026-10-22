#!/bin/sh
# SPDX-License-Identifier: MIT
# Native host snapshot/spool test plus genuine iOS-device source compile.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=$(mktemp -d /private/tmp/a5mali-shader-request-test.XXXXXX)
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -Wno-deprecated-declarations -DA5_SHADER_REQUEST_HOST_TEST \
    "-DA5_SHADER_REQUEST_TEST_ROOT=\"$output/spool\"" \
    "$here/A5MaliShaderCompileRequest.m" "$here/test_shader_compile_request.m" \
    -framework Foundation -framework Metal -o "$output/test_shader_compile_request"
"$output/test_shader_compile_request"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -c "$here/A5MaliShaderCompileRequest.m" -o "$output/A5MaliShaderCompileRequest-ios.o"
printf 'iOS16 Cortex-A53 Werror compile: PASS\nPrivate artifacts: %s\n' "$output"
