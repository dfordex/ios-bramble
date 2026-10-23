#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-resource-dependencies}
mkdir -p "$out"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
  "$here/A5MaliResourceDependencies.m" "$here/test_resource_dependencies.m" \
  -o "$out/test-resource-dependencies"
"$out/test-resource-dependencies"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
  -c "$here/A5MaliResourceDependencies.m" -o "$out/A5MaliResourceDependencies-ios.o"
