#!/bin/sh
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/private/tmp/a5mali-library-method-contract}
: "${A5_MALI_STOCK_QUARTZCORE_METALLIB:?exact local QuartzCore metallib required}"
mkdir -p "$out_dir"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
 "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
 "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
 "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
 "$src_dir/test_library_method_contract.m" -framework Foundation -framework IOSurface -framework IOKit -framework Metal -o "$out_dir/test"
"$out_dir/test"
