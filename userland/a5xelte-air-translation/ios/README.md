# AIR translator on iOS

## Native compilation service

`a5shader_compile.m` runs the actual AIR translator, mandatory Khronos
SPIR-V validator and Mesa26.2.4 Midgard compiler on iOS. It performs no GPU
submission and supplies no substitute shader. The initial backend retains its
two validated lowering profiles: `read_surf` and `downsample_4`. Moving these
compilers onto the phone does not implement arbitrary Metal pipeline state,
new shader lowerings or automatic compositor integration.

The native service is `/usr/libexec/a5shader-compile`; its tools and JSON
resources live in `/usr/libexec/a5shader`. It reads the installed QuartzCore
metallib, checks reflected resources/specialization, and publishes outputs to
the root-owned0700 directory `/private/var/db/a5shader-cache` only after both
stages compile successfully. The key includes complete source-library,
tool/runner, device-profile and binding-profile digests. Cached shader content
is checked again on a hit. Corrupted caches fail visibly; no CPU shader or
other cached profile is silently substituted.

Each pair has a20-second wall deadline. Child CPU and output-file limits are
inherited; the parent polls the entire compiler process group's RSS/physical
footprint every20ms with a500MiB ceiling, including the validator. Completed
worker peak RSS is checked too. Darwin RLIMIT_DATA cannot serve as this
resident-memory bound: shared-cache virtual data can already exceed it at
entry. Unexpected live descendants are killed. Failed workspaces are removed;
retained cache entries and bytes have finite limits. Outputs and directories
are fsynced before publication. These bounds still need measurement on the A53.

The opt-in launch job runs `--selftest`: compile both real pairs and immediately
request each again to exercise the cache. It reports output byte counts and
SHA256s to the bounded SYSTEM console tee. A successful native compilation
does not prove a draw; compare its outputs with the existing validated shader
reference, then test the runtime pipeline consuming them separately.

Build the three tools with `build_air_translator.py`, `build_midgard_ios.py`
and `build_spirv_tools_ios.py`. `prepare_package.py AIR MIDGARD VALIDATOR
PROFILE OUTPUT` builds the runner, verifies device-platform Mach-O metadata,
rejects macOS/simulator/non-system dependencies and signs all four executables
with4KiB signature pages. No shader binaries are bundled.

`tools/a5xelte-metal-bundle-embed.py --compiler-dir OUTPUT` adds this private
package and its launchd-cache job to the existing payload. Patch0172 streams
the zlib payload in64KiB chunks through the normal mounted HFS VFS, validates
all streams before writes, and skips files with identical content. It neither
formats a partition nor copies a whole root image. Patch0173 restricts the
extra platform authorization to four signed identities/paths with compiler
entitlements and the explicit `a5compiler=1` boot option.

**Current evidence:** genuine iOS-device ARM64 artifacts and the host runner's
real compile/cache regression are separate from execution on the phone.
See `A5XELTE_PROGRESS.md` for the latest installation and device measurements.

`build_air_translator.py` cross-builds the reviewed upstream `metal2vulkan`
revision as a thin ARM64 **iOS device** executable with minimum OS 16.0 and
Cortex-A53 code generation. It checks the Mach-O platform, architecture,
deployment version and dynamic dependencies before publishing the artifact.
The translator source is not modified. Generated binaries stay outside Git.

Requirements on the build Mac:

- Xcode with the iPhoneOS SDK.
- Rust 1.98 or later and its `aarch64-apple-ios` standard library installed.
- A clean checkout of the script's pinned upstream revision, with `Cargo.lock`
  and dependency crates already cached. The build is offline and locked.

Example using the private temporary toolchain:

```sh
RUSTUP_HOME=/private/tmp/a5-rustup CARGO_HOME=/private/tmp/a5-cargo \
python3 build_air_translator.py /private/tmp/a5-metal2vulkan \
  /private/tmp/a5xelte-ondevice-compiler --cargo /private/tmp/a5-cargo/bin/cargo
```

The output directory receives `metal2vulkan-ios` and a source/toolchain/SDK/hash
manifest. The script does not sign, install, or execute the artifact on a
phone. The runtime dependency is iOS `libSystem.B.dylib`; it does not require
LLVM or Vulkan libraries to translate binary AIR/metallib inputs. Text LLVM
IR inputs additionally require an on-device `llvm-as` and are not part of
the current binary-input integration.

## Validation at the caller boundary

The caller must provide a real iOS `spirv-val`, set
`METAL2VULKAN_SPIRV_VAL` to its absolute path, and accept output only after
the CLI reports actual validation `PASS` for the requested target environments.
Upstream returns translation success when the validator is absent and prints
`spirv-val: not found`; this is insufficient for installing a generated shader.
Do not pass `--no-spirv-val` or accept the absent-validator result.

The caller must also enforce the upstream 20-second and 500-MiB worker limits,
reject unsupported translations, and pass only validated SPIR-V to the native
Midgard compiler. Cross-compilation and Mach-O checks establish an iOS artifact;
they do not establish successful execution or correct rendering on the phone.
