#!/bin/sh
# SPDX-License-Identifier: MIT
# Real unregistered worker publication must be produced by test_request_worker.py.
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
registry=$1
publication=$2
spool=$3
out=${4:-/private/tmp/a5mali-dynamic-native-test}
mkdir -p "$out"
mesa=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
for family in misc clear path resource; do
 python3 "$src/../a5xelte-air-translation/families/build_runtime_encoder.py" \
  --mesa-build "$mesa" --target host --family "$family" --output "$out/runtime-$family.o"
done
python3 "$src/../a5xelte-air-translation/families/build_runtime_encoder.py" \
 --mesa-build "$mesa" --target host --output "$out/runtime-encode.o"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -DA5_MALI_HOST_TEST \
 -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 -DA5_MALI_DYNAMIC_SHADER_COMPILER=1 \
 -DA5_TEST_DYNAMIC_SHADER=1 -DA5_TEST_TEXTURED_PROFILE=603 \
 -DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1 -DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT="\"$publication\"" \
 -DA5_SHADER_REQUEST_HOST_TEST=1 -DA5_SHADER_REQUEST_TEST_ROOT="\"$spool\"" -I"$registry" \
 "$src/A5MaliBridge.c" "$src/A5MaliNative.c" "$src/A5MaliNativeUpload.c" "$src/A5MaliCommandBuffer.m" \
 "$src/A5MaliRestrictedDevice.m" "$src/A5MaliMetalAPI.m" "$src/A5MaliMetalTexture.m" "$src/A5MaliNativeTextureOps.m" \
 "$src/A5MaliShaderCompiledCache.m" "$src/A5MaliShaderCompileRequest.m" "$src/A5MaliMetalLibrary.m" \
 "$src/A5MaliDynamicShaderCache.m" "$src/A5MaliDynamicPipeline.m" "$src/A5MaliMetalDeviceResources.m" \
 "$src/test_native_buffer_texture603.m" "$out/runtime-encode.o" "$out/runtime-misc.o" \
 "$out/runtime-clear.o" "$out/runtime-path.o" "$out/runtime-resource.o" \
 -framework Foundation -framework IOSurface -framework IOKit -framework Metal -o "$out/test"
env -u A5_TEST_DYNAMIC_VERTEX_REQUEST "$out/test"
if [ -n "${A5_TEST_DYNAMIC_VERTEX_REQUEST:-}" ]; then
 A5_TEST_DYNAMIC_VERTEX_REQUEST="$A5_TEST_DYNAMIC_VERTEX_REQUEST" "$out/test"
fi
