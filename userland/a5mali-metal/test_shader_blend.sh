#!/bin/sh
# SPDX-License-Identifier: MIT
# Requires a real authenticated stage publication/request and original library.
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ "$#" = 4 ] || { echo 'usage: test_shader_blend.sh REGISTRY BASE_REQUEST PUBLICATIONS STOCK_METALLIB' >&2; exit 2; }
registry=$1
request=$2
publication=$3
stock=$4
out=$(mktemp -d /private/tmp/a5mali-shader-blend.XXXXXX)
mesa=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
for family in blur misc clear path resource; do
 python3 "$src/../a5xelte-air-translation/families/build_runtime_encoder.py" --mesa-build "$mesa" --target host --family "$family" --output "$out/$family.o"
done
python3 - "$src" "$mesa" "$out" <<'PYCODE'
import sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1]).parent / 'a5xelte-air-translation/families'))
from build_runtime_encoder import compile_runtime
compile_runtime(Path(sys.argv[2]),Path(sys.argv[3])/'decode.o','host',Path(sys.argv[1])/'test_shader_blend_decode.c')
PYCODE
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -DA5_MALI_HOST_TEST \
 -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 -DA5_MALI_DYNAMIC_SHADER_COMPILER=1 \
 -DA5_DYNAMIC_SHADER_CACHE_HOST_TEST=1 "-DA5_DYNAMIC_SHADER_CACHE_TEST_ROOT=\"$publication\"" \
 -DA5_SHADER_REQUEST_HOST_TEST=1 "-DA5_SHADER_REQUEST_TEST_ROOT=\"$out/requests\"" -I"$registry" \
 "$src/A5MaliBridge.c" "$src/A5MaliNative.c" "$src/A5MaliNativeUpload.c" "$src/A5MaliCommandBuffer.m" \
 "$src/A5MaliRestrictedDevice.m" "$src/A5MaliMetalAPI.m" "$src/A5MaliMetalTexture.m" "$src/A5MaliNativeTextureOps.m" \
 "$src/A5MaliShaderCompiledCache.m" "$src/A5MaliShaderCompileRequest.m" "$src/A5MaliMetalLibrary.m" \
 "$src/A5MaliDynamicShaderCache.m" "$src/A5MaliDynamicPipeline.m" "$src/A5MaliMetalDeviceResources.m" \
 "$src/A5MaliResourceDependencies.m" "$src/test_shader_blend.m" \
 "$out/decode.o" "$out/blur.o" "$out/misc.o" "$out/clear.o" "$out/path.o" "$out/resource.o" \
 -framework Foundation -framework Metal -framework IOSurface -framework IOKit -o "$out/test"
"$out/test" "$request" "$publication" "$stock"
printf 'Private artifacts: %s\n' "$out"
