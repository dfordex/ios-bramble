# Authenticated compiled QuartzCore profiles

`A5MaliMetalLibrary.m` first authenticates the complete local QuartzCore
metallib by size, magic and SHA256. Additional function objects are created
only for actual programs in the private compiled registry. Each native stage
is checked against its recorded SHA256 before the registry is exposed.
Unknown names, nonnull Metal function constants, specialization names,
archives and changed library bytes are rejected.

The source-only generator reads the actual compiler outputs and reflected
resources. It rechecks the blur translation's resource, attachment and bind
specialization ABI against the reviewed translation recipe. It emits private
native byte arrays and immutable binding contracts outside the Git tree:

```sh
python3 tools/a5mali-compiled-registry.py \
  --blur-manifest PRIVATE/blur/manifest.json \
  --blur-runtime-manifest PRIVATE/blur-dynamic/manifest.json \
  --ds4-vertex PRIVATE/downsample4.vert.midgard \
  --ds4-fragment PRIVATE/downsample4.frag.midgard \
  --misc-manifest PRIVATE/misc/full-mrt/manifest.json \
  --path-manifest PRIVATE/path/manifest.json \
  --path-runtime-manifest PRIVATE/path-runtime/manifest.json \
  --output-dir PRIVATE/compiled-registry
```

All inputs must be the user's actual local outputs. The generated include
contains proprietary native programs and must never be committed. The receipt
records input, generator, include and per-stage digests. Production packaging
checks the complete include digest against this receipt, covering metadata as
well as shader bytes, and records it in the signed bundle. Requiring a registry
without its generated include fails compilation.

`A5MaliSelectCompiledProfile` matches genuine same-library/device function
objects, all eight attachment formats, complete vertex attribute/layout state,
single sampling and supported blend/depth/raster state. Only exact premultiplied
source-over is admitted where the BGRA/R8 fixed blend renderer supports it.
Blur23 RAW64 RGBA16Float permits copying only. The stroke variant uses genuine
inline source-over code and native half packing, rather than RAW fixed blending. This lookup returns a contract;
it does not by itself make a pipeline executable.

| Profile IDs | Meaning | Runtime gate |
| --- | --- | --- |
|99|Actual downsample4 BGRA program|Native capability required|
|100–107|Actual eight blur BGRA programs|Native capability required|
|108|Actual blur23 RAW64 RGBA16Float program|Native capability required; no blending|
|200,202,204,206,207|Complete misc pipeline metadata with actual native passes200–208|Native capability; independent logical targets submitted in order|
|300,301|Original rect/cubic attachment contract; genuine R32Float addition only on logical RT2|Native capability; one actual target and exact Red/Add state|
|302|Original stroke attachment contract; genuine inline RGBA16Float source-over only on logical RT0|Native capability; RT1/RT2 writes disabled|
|400–403|Actual original path MRT/ordered-fetch metadata|Explicitly nonexecutable|

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

The native renderer admits99–108, the five logical misc profiles and300–302.
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
