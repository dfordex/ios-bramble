#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-render-state-test}
mkdir -p "$out"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$src_dir/test_render_state.c" -o "$out/test"
"$out/test"
