#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-runtime-audit-test}
mkdir -p "$out"
clang -fobjc-arc -Wall -Wextra -Werror "$here/test_runtime_audit.m" \
    -framework Foundation -o "$out/test"
"$out/test"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -mcpu=cortex-a53 \
    -march=armv8-a+crypto -fobjc-arc -Wall -Wextra -Werror \
    -DA5_MALI_RUNTIME_AUDIT_LIBRARY=1 -c "$here/A5ProtocolRuntimeAudit.m" \
    -o "$out/runtime-audit.o"
