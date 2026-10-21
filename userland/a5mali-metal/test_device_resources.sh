#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/private/tmp/a5mali-device-resources}
mkdir -p "$out_dir"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/test_device_resources.m" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/test_device_resources"
"$out_dir/test_device_resources"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -c \
    "$src_dir/A5MaliMetalDeviceResources.m" -o "$out_dir/A5MaliMetalDeviceResources.o"
