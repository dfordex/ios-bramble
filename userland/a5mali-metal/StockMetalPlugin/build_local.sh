#!/bin/sh
# SPDX-License-Identifier: MIT
# Produces a local, unadvertised bundle for ABI/link checks only.
set -eu
plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src_dir=$(dirname "$plugin_dir")
out_dir=${1:-/private/tmp/a5mali-stock-plugin}
bundle="$out_dir/A5MaliMetal.bundle"
mkdir -p "$bundle"
cp "$plugin_dir/Info.plist" "$bundle/Info.plist"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -isysroot "$sdk" -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -bundle \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" \
    "$src_dir/A5MaliMetalLibrary.m" \
    "$src_dir/A5MaliDiscoveryAudit.m" "$plugin_dir/A5MaliMetalDevice.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$bundle/A5MaliMetal"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
plutil -lint "$bundle/Info.plist"
file "$bundle/A5MaliMetal"
