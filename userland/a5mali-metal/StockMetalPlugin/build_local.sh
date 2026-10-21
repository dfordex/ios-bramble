#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds the opt-in iOS16 bounded Mali Metal provider bundle.
set -eu
plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src_dir=$(dirname "$plugin_dir")
out_dir=${1:-/private/tmp/a5mali-stock-plugin}
bundle="$out_dir/A5MaliMetal.bundle"
mkdir -p "$bundle"
cp "$plugin_dir/Info.plist" "$bundle/Info.plist"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto \
    -isysroot "$sdk" -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -bundle \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" \
    "$src_dir/A5MaliMetalLibrary.m" \
    "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/A5MaliMetalUnsupportedSPI.m" \
    "$src_dir/A5MaliDiscoveryAudit.m" "$plugin_dir/A5MaliMetalDevice.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$bundle/A5MaliMetal"
# XNU's initial Mach-O header validation allocates 4 KiB on A5XELTE.
# A 16 KiB CodeDirectory would hash beyond that allocation in cs_validate_range.
codesign --force --sign - --pagesize 4096 "$bundle"
codesign --verify --strict "$bundle"
plutil -lint "$bundle/Info.plist"
file "$bundle/A5MaliMetal"

xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror \
    "$plugin_dir/acceptance_probe.m" -framework Foundation -framework Metal \
    -framework IOKit -o "$out_dir/a5mali-metal-probe"
codesign --force --sign - --pagesize 4096 --identifier com.orhunnx.a5mali-metal-probe \
    --entitlements "$plugin_dir/probe-entitlements.plist" \
    "$out_dir/a5mali-metal-probe"
codesign --verify --strict "$out_dir/a5mali-metal-probe"
python3 "$plugin_dir/verify_signature_pages.py" \
    "$bundle/A5MaliMetal" "$out_dir/a5mali-metal-probe"
cp "$plugin_dir/probe-launchdaemon.plist" "$out_dir/com.orhunnx.a5mali-metal-probe.plist"
