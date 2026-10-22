#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/tmp/a5mali-bridge-build}
mkdir -p "$out_dir"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -isysroot "$sdk" -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -dynamiclib -install_name @rpath/libA5MaliBridge.dylib \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/libA5MaliBridge.dylib"
codesign --force --sign - "$out_dir/libA5MaliBridge.dylib"
codesign --verify --strict "$out_dir/libA5MaliBridge.dylib"
file "$out_dir/libA5MaliBridge.dylib"

clang -std=c11 -Wall -Wextra -Werror -pedantic \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/test_bridge.c" \
    -framework IOKit -framework CoreFoundation \
    -o "$out_dir/test_bridge"
"$out_dir/test_bridge"

clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/test_objc_queue.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -o "$out_dir/test_objc_queue"
"$out_dir/test_objc_queue"

clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/test_public_metal_slice.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$out_dir/test_public_metal_slice"
"$out_dir/test_public_metal_slice"

clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" "$src_dir/test_stock_library.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$out_dir/test_stock_library"
"$out_dir/test_stock_library"
