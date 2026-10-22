#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/private/tmp/a5mali-private-texture-test}
mkdir -p "$out_dir"
python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
 --mesa-build "${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}" \
 --target host --family resource --output "$out_dir/runtime_resource_ops.o"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -Wall -Wextra -Werror \
 "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
 "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
 "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
 "$src_dir/test_private_textures.m" "$out_dir/runtime_resource_ops.o" \
 -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
 -o "$out_dir/test_private_textures"
if [ "${A5_MALI_BUILD_ONLY:-0}" != 1 ]; then "$out_dir/test_private_textures"; fi
