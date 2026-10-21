#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output=${1:-/tmp/a5xelte-metal-probe}
sdk=$(/usr/bin/xcrun --sdk iphoneos --show-sdk-path)

/usr/bin/xcrun --sdk iphoneos clang \
    -arch arm64 -miphoneos-version-min=16.0 -isysroot "$sdk" \
    -fobjc-arc -Os -Wall -Wextra -Werror \
    -framework Foundation -framework Metal -framework IOKit \
    -framework IOSurface \
    "$script_dir/probe.m" -o "$output"

/usr/bin/codesign --force --sign - \
    --entitlements "$script_dir/entitlements.plist" "$output"
/usr/bin/file "$output"
