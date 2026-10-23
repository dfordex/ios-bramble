#!/bin/sh
# SPDX-License-Identifier: MIT
# Real Mac IOSurface storage plus injected kernel transport, no phone writes.
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
registry_dir=$1
out_dir=${2:-/private/tmp/a5mali-native-texture-ops-test}
mesa_build=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
mkdir -p "$out_dir"
set --
for family in blur misc clear path resource; do
    obj="$out_dir/runtime-$family.o"
    python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
        --mesa-build "$mesa_build" --target host --family "$family" --output "$obj"
    set -- "$@" "$obj"
done
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 \
    -Wall -Wextra -Werror -I"$registry_dir" \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" \
    "$src_dir/A5MaliCommandBuffer.m" "$src_dir/A5MaliRestrictedDevice.m" \
    "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" \
    "$src_dir/A5MaliNativeTextureOps.m" "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliDynamicShaderCache.m" "$src_dir/A5MaliDynamicPipeline.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" \
    "$src_dir/A5MaliMetalDeviceResources.m" "$src_dir/A5MaliResourceDependencies.m" "$src_dir/test_native_texture_ops.m" "$@" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/test_native_texture_ops"
"$out_dir/test_native_texture_ops"
