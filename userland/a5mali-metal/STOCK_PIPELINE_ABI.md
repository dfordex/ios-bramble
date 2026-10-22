# iOS 16.7.16 QuartzCore pipeline boundary

This source-only audit describes the operator-supplied stock binaries. No Apple
binary, metallib or shader bytes are included. Static caller coverage and local
validation do not establish successful compositor rendering on the phone.

## 0162 failure

The saved 0162 device log repeats the same backboardd SIGSEGV 31 times and has
no completed GPU frames. Runtime PC/LR `0x1b352b660`, with image slide
`0x31aec000`, maps to Metal `0x181a3f660`:

```asm
; MTLPipelineLibraryBuilder::newLibraryWithFile(...) + 836
ldr x8, [x23, #0x10]
```

FAR is `0x10`. Earlier at `0x181a3f61c`, this builder calls the device's
`targetDeviceInfo` and puts its result in x23. The inherited implementation at
`0x181aabb14` returns NULL. The builder checks whether the selector exists, then
uses the returned pointer without checking NULL. Inheritance satisfies that
selector check, but supplies no native Apple target architecture.

The caller is QuartzCore `CA::OGL::new_metal_context(...)`:
`0x188488534` sends `newPipelineLibraryWithFilePath:error:`; the return address
`0x188488538` matches runtime frame `0x1b9f74538`. This is an unsupported native
Apple precompiled-pipeline builder, rather than a failed Mali GPU submission.
The safe boundary returns nil and an unsupported NSError; it must not fabricate
Apple target-device structures to let that builder continue.

## QuartzCore handles an absent pipeline library

The call at `0x188488538` stores the result in context offset `0xc58`. A nil
result proceeds through the failure-message branch at `0x188488548`; subsequent
messages to that nil library are harmless. The precompiled render lookup checks
the same field for NULL at `0x188375858` / `0x18837585c` and skips its lookup when
absent. Its `newRenderPipelineStateWithName:options:reflection:error:` call at
`0x188375908` is on an **MTLPipelineLibrary**, not on MTLDevice.

The direct fallback calls the custom device's
`newRenderPipelineStateWithDescriptor:error:` at `0x188381b9c` and
`0x188381bf4`. The compute caller uses
`newComputePipelineStateWithFunction:error:` at `0x188482e20`. These factories
still require implemented shader translations and matching descriptor support;
skipping a precompiled library does not create general shader compilation.

## Function descriptor factory

QuartzCore creates an MTLFunctionDescriptor at `0x1884829bc`, sets its name at
`0x1884829c8`, optionally supplies function constants at `0x1884829d8`, and calls
the library at `0x1884829e8`. The exact arm64 Objective-C method shape is:

```objc
- (id)newFunctionWithDescriptor:(id)descriptor error:(id *)error;
```

`A5MaliMetalLibrary` implements this selector for its authenticated QuartzCore
library identity. A plain descriptor is copied before validation. Only
`read_surf_vert` and `read_surf_frag`, with no constant-values object, no
specialized name, zero options and no archives are accepted. Even an empty
constant-values object is rejected; no translation of specialization values has
been established. Audited private getters, when present, also reject nonzero
pipeline options, any plugin data and nonempty private-function arrays.
Descriptor subclasses are unsupported. No generic selector forwarding or native
compiler fallback is used.

The stock initializer sets `applyFunctionConstants=YES` and creates an empty
private-function array. With constantValues absent, the former has no constants
to apply. Validation does not depend on fixed descriptor ivar offsets.

## Other inherited factories that bypass bounded custom methods

The inherited implementations of these APIs directly reach the native Apple
compiler or library builder. Guarding only the simplest synchronous factory is
insufficient:

- render descriptor with options/reflection, and both asynchronous variants;
- compute descriptor with error, options/reflection, and asynchronous variants;
- asynchronous source-library creation;
- file-library creation and private pipeline-library creation.

Unsupported completion factories must invoke their callback exactly once with
nil and an NSError. File-library creation can forward to authenticated URL
loading. Native pipeline libraries remain unsupported. The stock tile options
factories already reject, but explicit custom rejects keep this boundary clear.

## Verification

The host stock-library test was built with ARC, blocks and warnings as errors,
then run against the user's local, unmodified QuartzCore default.metallib.
Both ordinary descriptor names passed; missing or changed names, nil or wrong
descriptor objects, specialization values, options, archives and private
descriptor extensions were rejected with `kIOReturnUnsupported`. The factory
was also syntax-compiled for arm64 iOS 16 with warnings as errors. These checks
perform no GPU jobs and do not mutate the phone.

## 0164: accepted device, missing compositor shaders

The 0164 phone log confirms `STOCK DEVICE ACCEPTED` and creation of the bounded
queue. The previous missing blit selector no longer appears. Backboardd instead
aborts with namespace 13, code 2, `Metal failed to load fragment function`.
Runtime `0x1b272a2ac` minus slide `0x2a2a4000` is QuartzCore `0x1884862ac`, in
`create_fragment_shader(...)`. Its callers are `create_pipeline_state(...)`
at `0x188380d88` and the asynchronous pipeline-dispatch block. This is a real
shader coverage gap after device acceptance.

The fragment factory takes one of two routes:

- A direct fast fragment name, suffixed `_lph` or `_lpf`, with no constants.
- `fixed_frag_lph_cph`, `fixed_frag_lph_cpf` or `fixed_frag_lpf_cpf`, with a
  nonnil function-constants object populated from the fragment specification.

The former failure uses exit code 2; the latter uses code 7, selected at
`0x188486044` through `0x188486050`. Thus code 2 also establishes that the failing
0164 request was **unspecialized**. None of the direct fast names or generic
fragment names is `read_surf_frag`. Accepting only the authenticated read_surf
pair cannot satisfy ordinary compositor shader creation, regardless of whether
constant validation is relaxed. Creating name-only placeholder functions would
not supply the missing executable translation.

### First fast profile in static warmup order

The audited warmup table has 1079 entries. For the conservative profile (all
feature sets unsupported; no native precompiled pipeline library; normal lookup
branch with context `0x1e2` bit 4 clear), 821 entries require
an unavailable feature set, 14 generic entries cannot create a pipeline without
that library, and 223 entries have no fast shader and are skipped by warmup.
The remaining 21 direct fast profiles begin at row 67:

```text
pipeline: PBGRABsovXm_Tds4A2Xhf_Isrc
vertex:   downsample_blur_vert_lph
fragment: downsample_4_frag_lph
constants object: nil for both functions
```

This is a static prediction of the first enqueued fast profile. The phone log
does not record the requested function's name, and asynchronous execution can
change which request reaches the abort first. It is not a dynamic observation
of the exact failed name. Subsequent table entries also need executable coverage;
implementing this pair alone does not establish complete compositor support.

The mapping is bounded by the staged QuartzCore UUID
`9E40B2EB-260C-3AF1-AE45-A1A551A8C1B9`:

- Warmup names and feature gates: table `0x1d5b3b350`, stride 40.
- Fragment `Tds4` decodes to texture-function index 26.
- Config table `0x188564d4c`, stride 7, maps index 26 to fast shader index 1.
- Fast shader table `0x1d5b45c08`, stride 16, gives `downsample_4_frag` and
  shader vertex-layout index 4. The `h` flag adds `_lph`.
- Vertex shader table `0x1d5b48050`, stride 24, maps index 4 to
  `downsample_blur_vert`. Its direct path also supplies no constants.

The shader vertex-layout index differs from buffer packing. This profile has no
`L` packing token, so QuartzCore uses packing index 0 in table `0x188565090`:

| Attribute | MTLVertexFormat | Byte offset | Buffer index |
|---|---|---:|---:|
| 0 | Float4 (31) | 0 | 1 |
| 1 | Float2 (29) | 16 | 1 |
| 2 | Float2 (29) | 24 | 1 |
| 3 | Half4 (27) | 32 | 1 |

The buffer stride is 48; step function is PerVertex, with default step rate 1.
QuartzCore applies these fields at `0x1883816b0` through `0x188381714`.

`tools/a5mali-quartzcore-coverage.py` reproduces this read-only table analysis
from a locally extracted image, rejects other UUIDs and invalid mapped ranges,
and emits only bounded names/metadata. It does not copy shader or executable
bytes into its output, create Metal functions, or install anything. The audit
was run against the staged image and its first pair and partitioned row counts
were checked. The script models this conservative profile, not arbitrary
device feature configurations or an override that bypasses precompiled lookup.

### Generic specialization schema

The generic fragment branch writes typed constants using
`setConstantValue:type:withName:`. Its schema includes `fc_generic`,
`fc_vertex_layout`, framebuffer fetch/sample flags, attachment count, optional
LOD/noise/YCbCr/gamma/color/LUT flags, texture/blend/destination function,
image and destination counts, range/premultiply/HDR/EDR flags, and indexed image
function, coordinate function, plane count, texture-coordinate count, filter and
color opcode fields. These values affect shader behavior; they cannot be ignored
or accepted merely because their names are known. No generic constant-value
combination has been established as the exact 0164 failing request.


## 0184: the first live draw needs a generic fragment specialization

The recovered first backboardd stack, minus slide 0x22b54000, resolves through
create_fragment_shader (return 0x1884862ac), create_pipeline_state
(0x188380d88) and MetalContext::draw (0x1882cbf64). Code 7 is the generic
function-constant failure branch. The three possible generic names are
fixed_frag_lph_cph, fixed_frag_lph_cpf and fixed_frag_lpf_cpf; the actual dynamic
choice and values were not logged and must not be invented from warmup names.

0185 records rejected function requests through actual iOS16 constant SPI:
newNamedConstantArray and newIndexedConstantArray return retained arrays of
MTLNamedConstantValue / MTLIndexedConstantValue, exposing typed dataType/data
and name/index getters. No private ivar offsets are read. The audited generic
fragment factory writes at most 58 named values. Capture permits 64 entries
per array and four requests per process, bounds names to identifier characters,
and logs explicit truncation/unavailability. No shader bytes, data addresses or
resource contents are printed.

Types are critical: UChar is 49 (1 byte), UChar3 is 51 (3 bytes), and Bool is
53 (1 byte). fc_color_opcodes0/1 uses UChar3, not UInt (33). These sizes agree
with the actual iOS16 _MTLConstantDataSize table. Unknown data types are logged
without dereferencing their data. Host tests use real Metal constant storage,
verify the complete 3-byte packed opcode receipt, exercise an unsupported Float
index without reading its payload, verify the request budget, and keep function
creation rejected. This adds missing request evidence; it does not implement
generic shader execution or fix the known specialization abort by itself.
