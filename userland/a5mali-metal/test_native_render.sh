#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
registry_dir=$1
out_dir=${2:-/private/tmp/a5mali-native-render-test}
: "${A5_MALI_STOCK_QUARTZCORE_METALLIB:?exact local QuartzCore metallib required}"
mesa_build=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
mkdir -p "$out_dir"
python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
    --mesa-build "$mesa_build" --target host --output "$out_dir/runtime_encode.o"
python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
    --mesa-build "$mesa_build" --target host --family misc --output "$out_dir/runtime_misc_encode.o"
python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
    --mesa-build "$mesa_build" --target host --family clear --output "$out_dir/runtime_clear.o"
python3 - "$src_dir/../a5xelte-air-translation/families" "$mesa_build" "$out_dir/runtime_path_encode.o" <<'PYBUILD'
import sys
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from build_runtime_encoder import compile_runtime
compile_runtime(Path(sys.argv[2]).resolve(),Path(sys.argv[3]).resolve(),'host',Path(sys.argv[1]).resolve()/'runtime_path_encode.c')
PYBUILD
python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
    --mesa-build "$mesa_build" --target host --family resource --output "$out_dir/runtime_resource.o"
for test_name in test_native_render test_native_misc test_native_clear test_native_path test_phase_diagnostics test_native_generic600; do
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 \
    -Wall -Wextra -Werror -I"$registry_dir" \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/$test_name.m" "$out_dir/runtime_encode.o" "$out_dir/runtime_misc_encode.o" "$out_dir/runtime_clear.o" "$out_dir/runtime_path_encode.o" "$out_dir/runtime_resource.o" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/$test_name"
"$out_dir/$test_name"
done
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
    -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 -I"$registry_dir" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror -c \
    "$src_dir/A5MaliMetalAPI.m" -o "$out_dir/A5MaliMetalAPI.o"
