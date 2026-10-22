# Authenticated compiled QuartzCore profiles

`A5MaliMetalLibrary.m` first authenticates the complete local QuartzCore
metallib by size, magic and SHA256. Additional function objects are created
only for actual programs in the private compiled registry. Each native stage
is checked against its recorded SHA256 before the registry is exposed.
Unknown names, unsupported Metal function constants, specialization names,
archives and changed library bytes are rejected. Profiles600–602 are the exact
named-constant exception described below; arbitrary specialization remains unsupported.

The source-only generator reads the actual compiler outputs and reflected
resources. It rechecks the blur translation's resource, attachment and bind
specialization ABI against the reviewed translation recipe. It emits private
native byte arrays and immutable binding contracts outside the Git tree:

```sh
python3 tools/a5mali-compiled-registry.py \
  --quartzcore-image PRIVATE/QuartzCore \
  --blur-manifest PRIVATE/blur/manifest.json \
  --blur-runtime-manifest PRIVATE/blur-dynamic/manifest.json \
  --ds4-vertex PRIVATE/downsample4.vert.midgard \
  --ds4-fragment PRIVATE/downsample4.frag.midgard \
  --misc-manifest PRIVATE/misc/full-mrt/manifest.json \
  --path-manifest PRIVATE/path/manifest.json \
  --path-runtime-manifest PRIVATE/path-runtime/manifest.json \
  --raw204-runtime-manifest PRIVATE/raw204-blend/manifest.json \
  --generic-receipt PRIVATE/generic-cpf/receipt.json \
  --generic-capture PRIVATE/captured-cpf.json \
  --generic-metallib PRIVATE/default.metallib \
  --generic-cph-receipt PRIVATE/generic-cph/receipt.json \
  --generic-cph-capture PRIVATE/captured-cph.json \
  --generic-fixed-receipt PRIVATE/generic-fixed/receipt.json \
  --generic-fixed-fragment-capture PRIVATE/captured-cph.json \
  --generic-fixed-vertex-capture PRIVATE/captured-fixed-vertex.json \
  --output-dir PRIVATE/compiled-registry
```

All inputs must be the user's actual local outputs. The generated include
contains proprietary native programs and must never be committed. The receipt
records input, generator, include and per-stage digests. The full attachment audit also requires the exact extracted QuartzCore image.
Its UUID, relevant instruction words, actual warmup rows and named blend table
are checked before contracts are emitted. Reflection output locations are not
used to infer attachment write masks. Production packaging
checks the complete include digest against this receipt, covering metadata as
well as shader bytes, and records it in the signed bundle. Requiring a registry
without its generated include fails compilation.

`A5MaliSelectCompiledProfile` matches genuine same-library/device function
objects, all eight attachment formats, complete vertex attribute/layout state,
single sampling and supported blend/depth/raster state. Each profile carries
one or more complete eight-attachment contracts reconstructed from actual QC
rows. Every format, write mask, blend-enable flag and blend equation/factor
is checked, including disabled and unconfigured attachments. DS4/DS8 have two
actual warmup variants, source-over and copy; other blur programs only admit
the actual copy rows. Rejections identify the first differing field and index.
Exact premultiplied source-over is admitted where the BGRA/R8 fixed blend renderer supports it.
Blur23 RAW64 RGBA16Float permits copying only. The stroke variant uses genuine
inline source-over code and native half packing, rather than RAW fixed blending. This lookup returns a contract;
it does not by itself make a pipeline executable.

| Profile IDs | Meaning | Runtime gate |
| --- | --- | --- |
|99|Actual downsample4 BGRA program|Native capability required|
|100–107|Actual eight blur BGRA programs|Native capability required|
|108|Actual blur23 RAW64 RGBA16Float program|Native capability required; no blending|
|200,202,204|Actual A3 formats retained; only RT0 active|One native pass;204 uses genuine inline half source-over|
|206|Actual A2 home formats retained; only RT0 active|One native pass|
|207|Actual A2/S1 clear formats retained; only RT1 active|One native pass208 targeting logical RT1|
|300,301|Original rect/cubic attachment contract; genuine R32Float addition only on logical RT2|Native capability; one actual target and exact Red/Add state|
|302|Original stroke attachment contract; genuine inline RGBA16Float source-over only on logical RT0|Native capability; RT1/RT2 writes disabled|
|400–403|Actual original path MRT/ordered-fetch metadata|Explicitly nonexecutable|
|600,601|Genuine fixed_frag_lph_cpf / fixed_frag_lph_cph with captured58 named constants|Exact specialization, std_vert0_lph packing0, one BGRA8 RT0 and copy-only state|
|602|Actual fixed_vert_lph_spc + fixed_frag_lph_cph with independent4+58 typed constants|Exact stage identities, full original packing0, one BGRA8 RT0 and copy-only state|

The two generic profiles are independently translated from their real stock
functions and exact typed captures. Their optimized native programs happen to
be identical for these constants; function identities are not aliased. Missing,
changed or indexed constants reject. The fragment program only reads VAR0 color
and ColorWriteRule at UBO0 byte68. The candidate vertex reads VB1 Float4 position
and Half4 color (stride48), plus the VB2 matrix. This vertex/attachment/blend
combination has not yet been observed after live fragment specialization; a
different stock pipeline must reject rather than silently use this contract.

Profile602 uses the actual vertex name observed in0187. Its genuine native
vertex code optimizes to the same bytes as the candidate, but the function
objects remain distinct. Vertex constants are checked separately from fragment
constants; sharing the identical CPH fragment across601/602 requires the same
name, stage and complete typed constant table. Full attachment/blend state is
still checked independently. See [0188 automatic requests](../../docs/a5xelte-0188-native-vertex-and-compiler-requests.md)
for the bounded on-device compilation, publication and known602 cache loader.

Original path metadata retains all actual attachment formats, including RT2.
Coverage300/301 only enables RT2 Red with sourceOne + destinationOne/Add;
RT0/RT1 writes are disabled. Stroke302 only enables RT0 premultiplied source-over;
RT1/RT2 writes are disabled. QuartzCore warmup zeroes its24-byte Spec at
`0x18847f3ec`, defaults S=0, and the write-mask loop at `0x18838179c` disables
nonselected attachments. Coverage has the explicit later override at
`0x188381988`. Consequently no artificial second stroke color pass is submitted.

Original `path_blit` remains nonexecutable. It reads and clears ordered RT2 while
also producing color. A snapshot texture or independent pass does not preserve
that dependency. Global/SSBO writes plus `memoryBarrierBuffer` alone would not
establish ordering between overlapping fragment invocations; a source-backed
ordering mechanism and overlap oracle are still required.

Full A2 blur/home descriptors retain a second same-format attachment with
writeMaskNone. Misc A3 retains its actual inactive RT1 and R32Float RT2;
R8 uses the actual RG8Unorm RT1 format. Clear retains BGRA RT0 but disables it
and writes BGRA RT1. Format0 slots beyond A2/A3 retain Metal's default All mask.
A later disable of cubic RT0 leaves its earlier source-over factors intact;
these values are recorded instead of reset or ignored. Only passes for enabled
logical targets are submitted: with all three generic profiles, the25 registry
passes comprise21 executable passes and4 host-only original metadata entries.

The native renderer admits99–108, the five logical misc profiles,300–302 and600–602.
Uniform bindings preserve
Metal slot numbers and dynamic contents: vertex buffers2/3 map to hardware
UBOs1/2; fragment buffers1/6 map to UBOs3/4; texture3 and sampler0 map to native
index0. Actual uniform windows are64/16 bytes for vertex,72 bytes for DS4,
32 for DS8,82 for other blur filters, and2 for EDR. Native UBO entries may pad
these ranges; caller bytes outside the verified window are not fabricated.
Metal vertex buffer1 uses the verified48-byte packing0 layout. The translated
viewport is genuinely dynamic when `--blur-runtime-manifest` is supplied:
UBO0 scale512/offset528,576-byte stage record. This selects separately compiled
actual vertex code and removes the fixed viewport flag; fragment bytes remain
unchanged. Omitting that option preserves the old fixed1080×1920 control profile.
The current runtime still rejects nonzero baseVertex and unsupported sampler state.
Path shaders independently use the same dynamic viewport record.

`test_compiled_registry.sh PRIVATE/compiled-registry PRIVATE/test-output` uses the exact metallib selected with
`A5_MALI_STOCK_QUARTZCORE_METALLIB`. It checks all names/contracts, pipeline
capability gating, wrong attachments/layouts/samples/blends, unsupported
constants, cross-library functions and changed native bytes. These are host
lookup/packing checks. They do not prove live iOS draws, compositor coverage,
performance or backboardd stability; those require recovered device evidence.

## Path blend verification boundary

`families/build_runtime_path.py` validates the original SPIR-V and compiles genuine
inline tilebuffer destination reads, released `nir_lower_blend` arithmetic and
released native framebuffer packing. It does not replace those shaders with a
copy. The exact single-sample contract is lowered through the released
`nir_lower_single_sampled` pass. Path jobs preload the actual existing destination
and enable its native load-destination state.

`families/build_path_blend_suite.py` creates three private256KiB GPU test payloads.
Coverage targets begin at0.25 and interior pixels must become1.25. Stroke begins
at(.25,.125,.5,.5), receives premultiplied(.125,.25,.375,.5), and must produce
(.25,.3125,.625,.75). These are exact binary fractions at every f16 arithmetic
step, allowing masked tolerance0. Expected images live separately from GPU output;
raster-edge masks exclude uncertain boundaries. These new blend programs require
their own recovered device pixel result. The earlier0175 copy/remap tests do not
prove these added destination reads or blending.

`families/test_runtime_path.c` checks actual native code copies, dynamic viewport,
single logical-target metadata, preload/load-destination state, and rejects wrong
blend or aliased buffers/targets. It is a host descriptor test, not GPU execution.

## RAW204 actual source-over

`families/build_raw204_blend.py` authenticates the actual original vertex and
fragment SPIR-V against the prior translation receipt and runs real spirv-val.
It recompiles the original fragment through released `nir_lower_blend` with
premultiplied One / OneMinusSourceAlpha, the strict single-sample lowering and
native RGBA16 framebuffer packing. Its vertex code must remain byte-identical.
`--raw204-runtime-manifest` supplies this separate compiled fragment; without
it profile204 is explicitly nonexecutable. With it the profile carries the
InlineSourceOver flag and only the actual QC source-over attachment contract.
The old copy-only RAW fragment is never used for that operation. This new native
shader still requires its own nonzero-destination device oracle and the real
preload route; compilation/factory acceptance alone does not prove pixels.
