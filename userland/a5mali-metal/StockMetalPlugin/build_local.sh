#!/bin/sh
# SPDX-License-Identifier: MIT
# Builds the opt-in iOS16 bounded Mali Metal provider bundle.
set -eu
plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src_dir=$(dirname "$plugin_dir")
out_dir=/private/tmp/a5mali-stock-plugin
registry_dir=
mesa_build=
if [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; then
    out_dir=$1
    shift
fi
while [ "$#" -gt 0 ]; do
    case $1 in
        --compiled-registry-dir)
            [ "$#" -ge 2 ] || { echo "--compiled-registry-dir requires a directory" >&2; exit 2; }
            registry_dir=$2
            shift 2
            ;;
        --mesa-build)
            [ "$#" -ge 2 ] || { echo "--mesa-build requires a directory" >&2; exit 2; }
            mesa_build=$2
            shift 2
            ;;
        *) echo "usage: $0 [OUT] [--compiled-registry-dir PRIVATE_DIR] [--mesa-build BUILD]" >&2; exit 2 ;;
    esac
done
# The private generated registry contains authenticated translated programs.
# Require the exact include explicitly for a family-enabled production build;
# the ordinary read_surf-only host build remains useful without Apple inputs.
set --
if [ -n "$registry_dir" ]; then
    registry_dir=$(CDPATH= cd -- "$registry_dir" && pwd)
    registry_include="$registry_dir/A5MaliCompiledRegistryData.inc"
    [ -f "$registry_include" ] && [ ! -L "$registry_include" ] || {
        echo "regular A5MaliCompiledRegistryData.inc required in $registry_dir" >&2
        exit 2
    }
    set -- "-I$registry_dir" -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1
fi
bundle="$out_dir/A5MaliMetal.bundle"
mkdir -p "$bundle"
cp "$plugin_dir/Info.plist" "$bundle/Info.plist"
if [ -n "$registry_dir" ]; then
    registry_snapshot="$out_dir/compiled-registry"
    python3 - "$bundle/Info.plist" "$registry_include" "$registry_snapshot" <<'PYREGISTRY'
import hashlib, plistlib, sys
from pathlib import Path
plist, registry, snapshot = map(Path, sys.argv[1:])
data = plistlib.loads(plist.read_bytes())
raw_registry = registry.read_bytes()
digest = hashlib.sha256(raw_registry).hexdigest()
import json
receipt = json.loads(registry.with_name('compiled-registry.json').read_text())
if receipt.get('include_sha256') != digest:
    raise SystemExit('compiled registry changed since its verified generation receipt')
snapshot.mkdir(parents=True, exist_ok=True)
(snapshot / registry.name).write_bytes(raw_registry)
(snapshot / 'compiled-registry.json').write_text(json.dumps(receipt, indent=2) + '\n')
data['A5MaliCompiledRegistrySHA256'] = digest
data['A5MaliCompiledRegistryIncluded'] = True
plist.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False))
PYREGISTRY
    set -- "-I$registry_snapshot" -DA5_MALI_REQUIRE_COMPILED_REGISTRY=1
fi
if [ -n "$registry_dir" ] && [ -z "$mesa_build" ]; then
    echo "family-enabled builds require --mesa-build for the real runtime emitter" >&2
    exit 2
fi
if [ -n "$mesa_build" ]; then
    python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
        --mesa-build "$mesa_build" --target ios --output "$out_dir/runtime-encoder.o"
    python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
        --mesa-build "$mesa_build" --family misc --target ios --output "$out_dir/runtime-misc.o"
    python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
        --mesa-build "$mesa_build" --family clear --target ios --output "$out_dir/runtime-clear.o"
    python3 "$src_dir/../a5xelte-air-translation/families/build_runtime_encoder.py" \
        --mesa-build "$mesa_build" --family path --target ios --output "$out_dir/runtime-path.o"
    set -- "$@" "$out_dir/runtime-encoder.o" "$out_dir/runtime-misc.o" "$out_dir/runtime-clear.o" "$out_dir/runtime-path.o"
fi
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto \
    -isysroot "$sdk" -fobjc-arc -fblocks -Wall -Wextra -Werror \
    "$@" -bundle \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliNative.c" "$src_dir/A5MaliNativeUpload.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" \
    "$src_dir/A5MaliMetalLibrary.m" \
    "$src_dir/A5MaliMetalDeviceResources.m" \
    "$src_dir/A5MaliMetalUnsupportedSPI.m" \
    "$src_dir/A5MaliDiscoveryAudit.m" "$plugin_dir/A5MaliMetalDevice.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$bundle/A5MaliMetal"
# XNU's initial Mach-O header validation allocates 4 KiB on A5XELTE.
# A 16 KiB CodeDirectory would hash beyond that allocation in cs_validate_range.
codesign --force --sign - --pagesize 4096 "$bundle"
codesign --verify --strict "$bundle"
plutil -lint "$bundle/Info.plist"
file "$bundle/A5MaliMetal"

xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -mcpu=cortex-a53 -march=armv8-a+crypto -isysroot "$sdk" \
    -fobjc-arc -fblocks -Wall -Wextra -Werror \
    "$plugin_dir/acceptance_probe.m" -framework Foundation -framework Metal \
    -framework IOKit -o "$out_dir/a5mali-metal-probe"
codesign --force --sign - --pagesize 4096 --identifier com.orhunnx.a5mali-metal-probe \
    --entitlements "$plugin_dir/probe-entitlements.plist" \
    "$out_dir/a5mali-metal-probe"
codesign --verify --strict "$out_dir/a5mali-metal-probe"
python3 "$plugin_dir/verify_signature_pages.py" \
    "$bundle/A5MaliMetal" "$out_dir/a5mali-metal-probe"
cp "$plugin_dir/probe-launchdaemon.plist" "$out_dir/com.orhunnx.a5mali-metal-probe.plist"
