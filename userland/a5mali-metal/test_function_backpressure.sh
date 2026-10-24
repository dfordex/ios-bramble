#!/bin/sh
# SPDX-License-Identifier: MIT
# Requires a real authenticated stage publication/request and original library.
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ "$#" = 4 ] || { echo 'usage: test_function_backpressure.sh REGISTRY STAGE_REQUEST STAGE_DIRECTORY STOCK_METALLIB' >&2; exit 2; }
registry=$1
request=$2
publication=$3
stock=$4
out=$(mktemp -d /private/tmp/a5mali-function-pressure.XXXXXX)
mesa=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
for family in blur misc clear path resource; do
 python3 "$src/../a5xelte-air-translation/families/build_runtime_encoder.py" --mesa-build "$mesa" --target host --family "$family" --output "$out/$family.o"
done
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -DA5_MALI_HOST_TEST \
 -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 -DA5_MALI_DYNAMIC_SHADER_COMPILER=1 \
 -DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1 "-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT=\"$out/published\"" \
 -DA5_SHADER_REQUEST_HOST_TEST=1 "-DA5_SHADER_REQUEST_TEST_ROOT=\"$out/requests\"" -I"$registry" \
 "$src/A5MaliBridge.c" "$src/A5MaliNative.c" "$src/A5MaliNativeUpload.c" "$src/A5MaliCommandBuffer.m" \
 "$src/A5MaliRestrictedDevice.m" "$src/A5MaliMetalAPI.m" "$src/A5MaliMetalTexture.m" "$src/A5MaliNativeTextureOps.m" \
 "$src/A5MaliShaderCompiledCache.m" "$src/A5MaliShaderCompileRequest.m" "$src/A5MaliMetalLibrary.m" \
 "$src/A5MaliDynamicShaderCache.m" "$src/A5MaliDynamicPipeline.m" "$src/A5MaliMetalDeviceResources.m" \
 "$src/A5MaliResourceDependencies.m" "$src/test_function_backpressure.m" \
 "$out/blur.o" "$out/misc.o" "$out/clear.o" "$out/path.o" "$out/resource.o" \
 -framework Foundation -framework Metal -framework IOSurface -framework IOKit -o "$out/test"
"$out/test" "$request" "$publication" "$stock"
printf 'Private artifacts: %s\n' "$out"
