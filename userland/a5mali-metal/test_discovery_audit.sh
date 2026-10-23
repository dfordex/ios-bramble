#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out_dir=${1:-/private/tmp/a5mali-discovery-audit}
mkdir -p "$out_dir"
clang -fobjc-arc -Wall -Wextra -Werror \
    "$src_dir/A5MaliDiscoveryAudit.m" "$src_dir/test_discovery_audit.m" \
    -framework Foundation -o "$out_dir/test_discovery_audit"
"$out_dir/test_discovery_audit"
clang -fobjc-arc -fblocks -DA5_MALI_HOST_TEST -DA5_MALI_CHECK_CURRENT \
    -Wall -Wextra -Werror \
    "$src_dir/A5MaliBridge.c" "$src_dir/A5MaliCommandBuffer.m" \
    "$src_dir/A5MaliRestrictedDevice.m" "$src_dir/A5MaliMetalAPI.m" "$src_dir/A5MaliMetalTexture.m" "$src_dir/A5MaliNativeTextureOps.m" \
    "$src_dir/A5MaliShaderCompiledCache.m" "$src_dir/A5MaliDynamicShaderCache.m" "$src_dir/A5MaliDynamicPipeline.m" "$src_dir/A5MaliShaderCompileRequest.m" "$src_dir/A5MaliMetalLibrary.m" \
    "$src_dir/A5MaliDiscoveryAudit.m" "$src_dir/test_discovery_audit.m" \
    -framework Foundation -framework IOSurface -framework IOKit \
    -framework Metal -o "$out_dir/test_discovery_current"
"$out_dir/test_discovery_current"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 \
    -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    -fobjc-arc -Wall -Wextra -Werror -c \
    "$src_dir/A5MaliDiscoveryAudit.m" -o "$out_dir/A5MaliDiscoveryAudit.o"
