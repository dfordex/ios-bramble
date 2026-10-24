# Metal to Mali: shared lowering layer and remaining implementation

Status: **in progress**. This is a source refactor with a signed local provider build, not a new installed BOOT or a claim of complete Metal support.

## 0230 physical readout

SYSTEM flush37 contains497,950bytes/5,889lines without ring overwrite.25 captured CB results complete/error0; two fail with `0xe00002be`. The SDK defines this as **kIOReturnNoResources**, not NotReady. No recorded kernel panic, backboardd/SpringBoard CRASH record, terminal pipeline rejection or terminal function rejection appears.47touch/264key HID records and eight sampled source/panel comparisons with zero mismatches are captured; responsive UI is not established.

The compiler remains in metal2vulkan for210.8s, reports an exec-observed child, empty output, about0.00043s group user CPU and0.014s system CPU. These facts indicate almost no accounted execution, but do not identify the wait cause. Two current-function enqueue attempts report Busy. A bounded147,968-byte read recovers the active function request; the later Busy request is absent, as are their terminal status files. Thus queue admission pressure is real and the later request was not persisted. Do not call this a shader arithmetic error or a proven compiler deadlock.

The successful native-phase diagnostic budget had expired before the two resource errors; their precise originating allocation/mapping/binding is unknown. Native failure receipts now have a separate64-entry budget, and asynchronous command exceptions preserve their bounded name/reason/phase rather than collapsing all context into NotReady. No resource-error ignore path is introduced.

## Implemented shared state pass

`A5MaliRenderState.h` is a portable Metal attachment-state IR and v4 algebraic lowering pass. It receives write mask, independent RGB/alpha operations and factors. It contains no shader names, module hashes, function constants or profile IDs. Its result explicitly distinguishes invalid state, actual fixed-function equations, and state requiring shader lowering.

The existing generic static-stage adapters and reflected dynamic pipeline constructor preserve the actual API attachment instead of synthesizing only a copy/source-over/screen contract. Shader program authentication and existing resource/vertex/output-format gates remain independent and enforced. The production misc encoder carries that immutable state to real Mali RSD coefficients. The new mode supersedes three named blend presets for these admitted pipelines; established blur/path/inline-blend routes remain separate until migrated with their own proofs.

ADD, SUBTRACT and REVERSE_SUBTRACT are factored into v4 `A+B*C` when representable, with independent RGB and alpha. All16 Metal channel masks are translated to the opposite Mali channel-bit ordering. Destination preload follows masked channels and real destination dependencies. MIN/MAX, constants, saturation, dual-source and nonfactorable equations are recognized shader-lowering requirements; **their shader fallback is not implemented by this commit**. It would be incorrect to report these as supported pipelines.

The decoded renderer state's `blend_shader` union arm must be cleared before repacking a changed equation: it aliases the previous packed coefficients. The production descriptor test exposed old bits being ORed into the new equation; this is fixed before any device installation.

## Verification

- ASan/UBSan independent scalar Metal oracle:264 accepted channel states,3,346 explicit shader routes,8,448 numeric comparisons and all16 channel masks. No proprietary inputs required.
-54 actual producer combinations across600/601/602, Float4/Float2, copy/over/screen/straight-alpha/add/multiply/subtract/reverse-subtract/alpha-only-mask. Decoded released v4 RSD operands, masks and negative descriptor cases are checked. Native transport is mocked; no new physical pixel result is claimed.
- All18 native integration executables pass, including textured603..606, indexed, buffer-backed, blur, path, dependency and fence/error quarantine regressions. Independent RGB/alpha is now a positive case; unimplemented MIN is retained as a negative case.
- All52 recovered complete pipeline snapshots pass actual authenticated factory replay and exact serialized-descriptor roundtrip, with zero missing stages. This is observed-request coverage, not universal coverage.
- A signed arm64 iOS16/Cortex-A53 provider builds with4KiB signature-page verification. BOOT packaging/installation is intentionally not performed for this incomplete architecture transition.

## Interfaces that still need generalization

| Layer | Existing/implemented behavior | Remaining work |
| --- | --- | --- |
| AIR compilation | Exact typed vertex/fragment request, real AIR/SPIR-V/NIR/Midgard compilation, authenticated persistent publication | Determine near-idle child wait; isolate scheduling/admission so one blocked compilation cannot prevent current function persistence; keep memory bounds and user-requested no time limit |
| Pipeline linking | Reflected QC position/UV/color variants, original Metal offsets/stride; new independent render-state IR | General reflected varying/location/component linking and vertex input/format plans, beyond implemented QC shapes |
| Draw-state lowering | Shared v4 fixed-function algebra and channel masks | NIR shader fallback with state-specific cache identity; broader target formats, depth/stencil, samples, topology and renderpass behavior |
| Resource planning | Real IOSurface/buffer handles, snapshots, generations, mapping epochs and fence ownership | Plan/pack bindings against physical windows and staging buffers; obtain exact NoResources origin; distinguish reclaimable pressure from active/ambiguous ownership without false success |
| Submission/presentation | Real Query17/Submit18, terminal fences, source-to-panel checks | Integrate general resource/state plans with batch lifetime and validate device UI scenarios |

A completed shared state pass is one component. Universal compositor support is not achieved by renaming profiles or returning success for unsupported requests. Next installation must follow integration of the still-needed paths and device verification; this refactor alone does not establish that the0230 UI stall is repaired.
