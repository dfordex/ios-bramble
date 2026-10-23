# AIR translator on iOS

## Dynamic standalone stages

The request worker also accepts bounded typed vertex/fragment requests from
its canonical per-owner spool. Admission checks the stock QuartzCore library
digest, Mali-T720 GPU ID, compiler ABI, identifier, exact scalar/vector byte
widths and at most64 named plus64 indexed constants. Function names and
constant combinations are not matched against the602–606 recipes. Known
pipeline recipes remain available unchanged.

The host regression compiles an actual previously unregistered
coord0/image17 fragment through AIR, mandatory SPIR-V validation, and the
dynamic Midgard backend; it publishes an864-byte stage different from every
602–606 native fragment pin. The same route compiles a standalone vertex and
tests malformed typed bytes, spoofed library identity, old unsupported-status
migration and public terminal-failure publication after a real translator
error. These host results do not prove device pixels or pipeline execution.

The current AIR tool exposes render-pair translation. For a standalone
fragment request the worker supplies a trusted stock companion vertex and
vertex descriptor; for a vertex request it supplies a trusted stock fragment
and its constants, overridden by the requested constants. The selected
function is actually translated and compiled. Only that selected native stage
is published. The companion is translation scaffolding, and is explicitly
recorded in the semantic reflection; it is not silently substituted for the
requested function or represented as the application's pipeline.

Reflected resource bindings, bounded buffer specialization ranges, texture
indices and push ranges produce a bounded `A5MIDGARD1` backend manifest. The
`--dynamic-stage` backend compiles the resulting SPIR-V without the known
module fingerprint allowlist, retains active NIR validation, and emits actual
native resource/varying metadata. Unsupported descriptor/specialization
lowerings fail visibly. Mandatory SPIR-V validation and process/memory/output
limits remain active.

A root-owned0755 request directory in
`/private/var/tmp/a5mali-shader-compiled` atomically publishes three root-owned
0444 files: `receipt.json`, `stage.midgard`, and `reflection.json`. Schema2
receipts carry the full request/source/stage identity, named/indexed constant
hashes, native code hash and metadata, reflection hash, and the backend
`native_abi` report. `stage_compiled=true` always accompanies
`pipeline_compatible=false`: the provider must independently validate and link
resources, varyings and pipeline state before submission.

An older trusted `unsupported` status is retried only when the complete request
now passes this dynamic typed-stage gate (or the existing exact606 pair gate).
A genuine `failed` status is retained. After a child/compiler failure the
KeepAlive worker's next scan publishes a schema2 terminal failure receipt with
`stage_compiled=false` and `error`; it does not fabricate shader bytes or leave
the consumer waiting forever on an inaccessible root-private status.

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

At the user's explicit request, compilation has no wall-time or CPU-time
cutoff. Child output-file limits are inherited; the parent polls the entire compiler process group's RSS/physical
footprint every20ms with a500MiB ceiling, including the validator. Completed
worker peak RSS is checked too. Darwin RLIMIT_DATA cannot serve as this
resident-memory bound: shared-cache virtual data can already exceed it at
entry. Unexpected live descendants are killed. Failed workspaces are removed;
retained cache entries and bytes have finite limits. Outputs and directories
are fsynced before publication. These bounds still need measurement on the A53.

The launch job runs `--serve` and scans the bounded request spool immediately;
the baseline pairs remain available through the separate `--selftest` action.
The exact captured QuartzCore `fixed_vert_lph_spc` +
`fixed_frag_lph_cph` profile 602 and the four captured textured fragment
specializations (profiles 603–606) have source-pinned translation and Midgard
recipes. Textured profiles require their own exact 58 typed fragment constants,
four vertex constants, and a ClampToEdge S/T/R sampler.
The 0204 phone log records real 604/605 jobs. Profile606 adds the observed
coordinate5/image17 combination: a FragmentBuffer1 UV clamp and sampled alpha
replicated to RGBA. Host compilation and cache admission do not establish606
phone pixels or successful backboardd startup.
Unrecognized pipeline recipes retain explicit unsupported results; standalone
typed functions can enter the dynamic stage path above. Translation or
lowering failures publish a terminal error. A compiled stage does not prove
an arbitrary Metal pipeline can draw.

Build the explicit no-timeout translator with `build_air_no_timeout.py`, the
Midgard tools with `build_midgard_ios.py`, and the validator with
`build_spirv_tools_ios.py`. `prepare_package.py` requires the patched
translator's paired host binary and provenance manifest. It verifies the
patch, both artifact hashes and the host CLI's `--no-timeout` option before
staging; the older optimized translator fails this gate. The package script
also checks iOS-device Mach-O dependencies, signs all five executables and
verifies 4 KiB signature pages. The generic backend's build manifest must
also bind the current source, exact module whitelist, pinned Mesa release,
active NIR validation and original executable hash. The package provenance
manifest retains this binding; an older backend that rejects606 cannot pass
packaging merely by supplying a new606 JSON recipe. No shader binaries are
bundled.

Package invocation (all generated artifacts remain outside Git):

```sh
python3 prepare_package.py PATCHED_AIR_IOS MIDGARD_IOS SPIRV_VAL_IOS \
  PROFILE_JSON OUTPUT_DIR \
  --generic602 MIDGARD_GENERIC602_IOS \
  --receipt602 VERIFIED_PRIVATE_602_RECEIPT_JSON \
  --fragment-capture602 PRIVATE_0186_FRAGMENT_CAPTURE_JSON \
  --vertex-capture602 PRIVATE_0187_VERTEX_CAPTURE_JSON \
  --receipt603 VERIFIED_PRIVATE_603_RECEIPT_JSON \
  --fragment-capture603 PRIVATE_0189_FRAGMENT_CAPTURE_JSON \
  --receipt604 VERIFIED_PRIVATE_604_RECEIPT_JSON \
  --fragment-capture604 PRIVATE_0198_TEXTURE_FUNCTION_CAPTURE_JSON \
  --receipt605 VERIFIED_PRIVATE_605_RECEIPT_JSON \
  --fragment-capture605 PRIVATE_0198_IMAGE_FUNCTION_CAPTURE_JSON \
  --receipt606 VERIFIED_PRIVATE_606_RECEIPT_JSON \
  --fragment-capture606 PRIVATE_0204_COORD5_IMAGE17_CAPTURE_JSON \
  --metallib PRIVATE_QUARTZCORE_METALLIB
python3 test_package_air_gate.py PATCHED_TRANSLATOR_BUILD_DIR \
  --old-translator OLD_OPTIMIZED_TRANSLATOR_IOS
```

The package contains only the runner, launchd plist, four tools and six JSON
resources. The host-only provenance manifest is written beside it as
`OUTPUT_DIR-package-manifest.json`, outside the embedder's exact member list.

`tools/a5xelte-metal-bundle-embed.py --compiler-dir OUTPUT` adds this private
package and its launchd-cache job to the existing payload. Patch0172 streams
the zlib payload in64KiB chunks through the normal mounted HFS VFS, validates
all streams before writes, and skips files with identical content. It neither
formats a partition nor copies a whole root image. Patch0173 restricts the
extra platform authorization to the signed identities/paths with compiler
entitlements and the explicit `a5compiler=1` boot option.

**0205 host evidence:** the combined backend reproduces the pinned602–606
native pairs. The606 end-to-end worker test runs actual AIR translation,
SPIR-V validation and the combined Midgard backend, then publishes the exact
2192-byte vertex and896-byte fragment pair. It starts with an older
root-private `unsupported` status for that same request ID and proves that
only the exact newly supported606 request is retried. Failed statuses and
unrecognized requests remain terminal. Symlink, hardlink, wrong-mode and wrong
identity status files fail closed; publication cache tests for602–606 reject
mutated code, receipts, ownership and stage ABI. The rebuilt iOS package passes
Cortex-A53 compilation, device Mach-O and4KiB signature-page checks. These are
host/package results;606 device execution remains to be tested.

**Current evidence:** the 0200 package passed signed iOS Mach-O checks and
host request-to-publication tests for both 604 and 605; earlier tests covered
602 and 603, including retirement
and recompilation of the previous 976-byte profile 603 cache entry. The 0197 phone run
accepted the textured vertex and fragment pair but produced black output.
The corrected profile 603 host output is a 2192-byte vertex shader and
880-byte normalized-coordinate textured fragment; its private receipt pins
both SHA-256 hashes. Corrected output pixels still need a live device check.
The earlier
0188b translator lacked `--no-timeout` and failed before spool scanning.
See `A5XELTE_PROGRESS.md` for the latest installation and device measurements.

`build_air_translator.py` cross-builds the reviewed upstream `metal2vulkan`
revision as a thin ARM64 **iOS device** executable with minimum OS 16.0 and
Cortex-A53 code generation. It checks the Mach-O platform, architecture,
deployment version and dynamic dependencies before publishing the artifact.
The translator source is not modified by that baseline builder. It is useful
for comparison but is rejected by the current package gate. Generated binaries
stay outside Git.

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

The on-device caller keeps the500MiB process-group memory ceiling,
rejects unsupported translations, and pass only validated SPIR-V to the native
Midgard compiler. Cross-compilation and Mach-O checks establish an iOS artifact;
they do not establish successful execution or correct rendering on the phone.

## User-requested timing and visible completion update

After0172 reached real on-phone SPIR-V validation but hit the parent20-second
wall cutoff, the user explicitly removed the time limit. The runner has no
wall or child-CPU cutoff and supplies the patched upstream CLI's explicit
`--no-timeout`; that selects `Budget::with_deadline(None)` without changing
translation or validation. Progress logs report elapsed time and resident
bytes. Memory, log size and cache bounds remain.

The completion indicator is a fixed green8-pixel bottom line. The native
runner requests it only after both pairs compile, all four outputs match
the validated reference sizes/SHA256s, and both immediate cache reads pass.
A dedicated type1 IOKit connection can only submit this completion report;
it cannot submit GPU jobs or map resources. The line is a CPU-drawn status
indicator, not evidence of a new compositor frame.

To reproduce this explicitly patched CLI, run `build_air_no_timeout.py
PINNED_SOURCE PRIVATE_OUTPUT --cargo /path/to/cargo` with the same Rust homes
as above. It builds a detached private worktree, applies only the stored
CLI-deadline patch, and records the patch digest. The original upstream source
and default20-second CLI policy remain intact; only the on-device service's
explicit flag selects no deadline.
