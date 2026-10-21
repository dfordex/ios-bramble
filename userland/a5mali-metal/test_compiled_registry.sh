#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
registry_dir=$1
out_dir=${2:-/private/tmp/a5mali-compiled-registry-test}
: "${A5_MALI_STOCK_QUARTZCORE_METALLIB:?exact local QuartzCore metallib required}"
mkdir -p "$out_dir"
mesa_build=${A5_MALI_MESA_BUILD:-/private/tmp/a5xelte-mesa-full/buildtools}
for family in blur misc clear; do
 python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" --mesa-build "$mesa_build" --target host --family "$family" --output "$out_dir/runtime_$family.o"
done
python3 - "$mesa_build" "$out_dir/runtime_path.o" "$src_dir" <<'PYPATH'
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(sys.argv[3]).parent/'a5xelte-air-translation/families'))
from build_runtime_encoder import compile_runtime
compile_runtime(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),'host',pathlib.Path(sys.argv[3]).parent/'a5xelte-air-translation/families/runtime_path_encode.c')
PYPATH
set -- "$out_dir/runtime_blur.o" "$out_dir/runtime_misc.o" "$out_dir/runtime_clear.o" "$out_dir/runtime_path.o"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 \
    -Wall -Wextra -Werror -I"$registry_dir" \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" \
    "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/A5MaliMetalLibrary.m" "$src_dir/test_compiled_registry.m" "$@" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/test_compiled_registry"
"$out_dir/test_compiled_registry"

# Corrupt genuine native code after generation. The embedded expected digest is
# unchanged: runtime must reject the complete registry before exposing names.
mkdir -p "$out_dir/corrupt"
python3 - "$registry_dir/A5MaliCompiledRegistryData.inc" "$out_dir/corrupt/A5MaliCompiledRegistryData.inc" <<'PYTEST'
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
text,n=re.subn(r'(static const uint8_t a5shader_[0-9a-f]+\[\] = \{\s*)0x([0-9a-f]{2})',
    lambda m:m.group(1)+'0x%02x'%(int(m.group(2),16)^1),text,count=1)
assert n==1
Path(sys.argv[2]).write_text(text)
PYTEST
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1 \
    -Wall -Wextra -Werror -I"$out_dir/corrupt" \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" \
    "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/A5MaliMetalLibrary.m" "$src_dir/test_compiled_registry.m" "$@" \
    -framework Foundation -framework IOSurface -framework IOKit -framework Metal \
    -o "$out_dir/test_corrupt_registry"
A5_MALI_EXPECT_BAD_REGISTRY=1 "$out_dir/test_corrupt_registry"
echo 'changed native code: registry rejected before function lookup'
