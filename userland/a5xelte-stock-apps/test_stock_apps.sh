#!/bin/sh
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=${1:?private root with the three original app bundles}
out=${2:?private test output}
mkdir -p "$out"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -fsanitize=address,undefined \
 -DA5_STOCK_APPS_TEST_ROOT="\"$root\"" "$src/test_stock_apps.m" \
 -framework Foundation -o "$out/test"
for mode in happy existing retry api-unavailable container-failure register-failure invalid-state wrong-path; do
 "$out/test" "$mode"
done
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 -march=armv8-a+crypto \
 -fobjc-arc -fblocks -Wall -Wextra -Werror -c "$src/A5StockApps.m" -o "$out/ios-arm64.o"
