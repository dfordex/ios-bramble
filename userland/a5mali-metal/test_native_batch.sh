#!/bin/sh
set -eu
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-native-batch-test}
mkdir -p "$out"
clang -Wall -Wextra -Werror -fsanitize=address,undefined \
 "$src/A5MaliNative.c" "$src/test_native_batch.c" -framework IOKit -o "$out/transport"
"$out/transport"
clang -Wall -Wextra -Werror -fsanitize=address,undefined \
 "$src/A5MaliNative.c" "$src/test_native_upload_arena.c" -framework IOKit -o "$out/upload-arena"
"$out/upload-arena"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -fsanitize=address,undefined \
 "$src/A5MaliBridge.c" "$src/A5MaliNative.c" "$src/A5MaliCommandBuffer.m" \
 "$src/test_native_batch_command.m" -framework Foundation -framework IOSurface \
 -framework IOKit -o "$out/command-buffer"
"$out/command-buffer"
