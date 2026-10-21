# Parallel Mac compilation of the QuartzCore warmup candidates

The UUID-guarded `tools/a5mali-quartzcore-coverage.py` audit selects21 table
rows /16 distinct vertex-fragment pairs /23 unique functions. This is the
conservative directly named warmup branch, not the complete iOS shader set.
`targets.json` keeps the individual rows and attachment formats. The already
tested downsample4 pair accounts for two rows; the three parallel recipes
compile the remaining15 pairs /19 rows; explicit target replay adds native execution variants.

| Family | New pairs | Attachment profiles | Host result |
| --- | ---: | ---: | --- |
| Downsample/blur | 8 | 9 | All compile to T720 code |
| Path/stroke | 4 | 4 | Full attachment profiles, including real coverage outputs and ordered fetch |
| Buffer blit/home/attachment clear | 3 | 9 target profiles | Full AIR outputs preserved, explicit single-target replay |

All generated SPIR-V passes the real SPIRV-Tools validator. The source-only
wrappers preserve actual SSBO loads, dynamic resource values and distinct
textures/samplers. NIR validation stays active. Shader inputs, extracted code,
generated SPIR-V/Midgard binaries and compiler logs stay outside Git.

## What these outputs still require

- Blur23/27 need32/64 bytes of real per-thread TLS, allocated using the native
  core-ID range and scratch layout. Shader code allocation uses actual sizes.
- SSBO families require actual GPU address/size records and native vertex-ID /
  instance-ID attributes; the two home textures and samplers remain distinct.
- The attachment token `RGhA` is Metal115 **RGBA16Float**, not Metal65 RG16Float.
  The audit reads the actual indexed QuartzCore format table. Extra `w`-flag
  attachment2 is R32Float, independently checked against the real setter.
- Cubic and rectangle write real coverage to attachment2. An initial profile
  omitted that attachment and incorrectly yielded an empty fragment. That
  result is superseded: full attachment profiles preserve the real output.
  Stroke, buffer-blit and clear also have secondary outputs that must be kept.
- Path-blit machine code preserves an ordered R32Float tilebuffer read from
  attachment2. However, released Mesa restricts arch4/T720 to one color target
  (`pan_get_max_cbufs`, `pan_emit_fbd`). Its three-attachment QuartzCore pass
  therefore needs a structural adapter before execution on this phone. Other
  MRT paths likewise need explicit single-target lowering/replay. This
  native compilation result does not prove an executable T720 render pass or
  advertise a Vulkan extension.

The new host outputs are not installed into the phone's two-profile native
compiler or stock Metal dispatcher by these recipes. Runtime binding, completed
GPU work and pixel correctness must be established separately.

## Reproduce and check

See `BLUR.md`, `PATH_STROKE.md`, and `misc_README.md` for the individual commands
and native resource contracts. Use private input/output paths. After compilation:

```sh
python3 collect_results.py --blur PRIVATE_BLUR/manifest.json \
  --path PRIVATE_PATH/manifest.json --misc PRIVATE_MISC/manifest.json \
  --output PRIVATE_OUTPUT/combined-manifest.json
```

The collector verifies every actual SPIR-V/native file's size and digest,
matches entry names and primary attachment formats to every selected row, rejects
duplicate/missing rows and records the native binding contract. Full attachment
reflection must also be checked by each recipe. It does not submit
jobs, install code or turn a host result into a device claim.

## Device test packaging

The three `build_*_suite` / `make_misc_suite` recipes generate private job
images, independent expected pixels and SHA-pinned manifests. The current
test set is21 cases:9 blur,9 misc output replays and3 path/stroke transforms.
Original simultaneous-MRT path-blit is excluded. These are standalone GPU
pixel tests, not a live compositor installation.

After applying patch0175 to the normal staged kernel, generate its private
`iokit/Kernel/arm/A5XELTEShaderSuiteData.inc` with:

```sh
python3 tools/a5xelte-shader-suite-embed.py \
  --manifest PRIVATE_BLUR_FIXTURES/manifest.json \
  --manifest PRIVATE_PATH_FIXTURES/manifest.json \
  --manifest PRIVATE_MISC_FIXTURES/manifest.json \
  --output PRIVATE_XNU/iokit/Kernel/arm/A5XELTEShaderSuiteData.inc \
  --evidence PRIVATE_OUTPUT/suite-embed.json
```

Build the kernel and pack using `--test-shader-suite`; the opt-in boot argument
is `a5shadersuite=1`. The kernel reports per-output element comparisons,
immutable-region status and completed fence IDs through `A5XELTE G3D SUITE`.
The suite stops on ambiguous GPU completion and retains its pinned pages.
Neither a successful build nor the presence of generated fixtures is a phone
rendering result. Recover SYSTEM logs after the phone trial to evaluate it.
