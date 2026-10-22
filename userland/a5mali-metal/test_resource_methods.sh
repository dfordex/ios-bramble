#!/bin/sh
# SPDX-License-Identifier: MIT
# Public iOS16 resource selectors and genuine backing/purge/view semantics.
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/private/tmp/a5mali-resource-methods}
mkdir -p "$out_dir"
for test_name in test_resource_methods; do
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/$test_name.m" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/$test_name"
"$out_dir/$test_name"
done
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -c \
    "$src_dir/A5MaliMetalDeviceResources.m" -o "$out_dir/A5MaliMetalDeviceResources.o"

xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -c \
    "$src_dir/A5MaliMetalTexture.m" -o "$out_dir/A5MaliMetalTexture.o"
printf 'Resource/Texture iOS16 Cortex-A53 Werror compile: PASS\n'
