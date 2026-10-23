#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
registry_dir=$1
out_dir=${2:-/private/tmp/a5mali-resource-dependency-integration}
mesa_build=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-0207-mesa/buildtools}
mkdir -p "$out_dir"
runtime_dir=${A5_MALI_RUNTIME_OBJECT_DIR:-$out_dir}
if [ -z "${A5_MALI_RUNTIME_OBJECT_DIR:-}" ]; then
 for family in blur misc clear path resource; do
  file=runtime_encode.o
  case "$family" in misc) file=runtime_misc_encode.o;; clear) file=runtime_clear.o;; path) file=runtime_path_encode.o;; resource) file=runtime_resource_ops.o;; esac
  python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
   --mesa-build "$mesa_build" --target host --family "$family" --output "$out_dir/$file"
 done
fi
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 \
 -Wall -Wextra -Werror -I"$registry_dir" \
 "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
 "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
 "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliDynamicShaderCache.m" "$src_dir/A5MaliDynamicPipeline.m" "$src_dir/A5MaliShaderCompileRequest.m" \
 "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" "$src_dir/A5MaliResourceDependencies.m" \
 "$src_dir/test_resource_dependency_integration.m" \
 "$runtime_dir/runtime_encode.o" "$runtime_dir/runtime_misc_encode.o" "$runtime_dir/runtime_clear.o" \
 "$runtime_dir/runtime_path_encode.o" "$runtime_dir/runtime_resource_ops.o" \
 -framework Foundation -framework IOSurface -framework IOKit -framework Metal -o "$out_dir/test-resource-dependency-integration"
"$out_dir/test-resource-dependency-integration"
