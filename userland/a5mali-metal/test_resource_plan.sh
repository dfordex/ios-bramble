#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-/private/tmp/a5mali-resource-plan-test}
mkdir -p "$out"
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$src_dir/test_resource_plan.c" -o "$out/test"
"$out/test"
