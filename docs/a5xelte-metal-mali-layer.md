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
| Resource planning | Real IOSurface/buffer handles, snapshots, generations, mapping epochs and fence ownership; shared bounded upload planner now packs logical CPU uploads into physical BO slices | Persistent buffer residency beyond four slots, window planning/batching beyond existing limits; exact phone NoResources origin still unproven |
| Submission/presentation | Real Query17/Submit18, terminal fences, source-to-panel checks | Integrate general resource/state plans with batch lifetime and validate device UI scenarios |

A completed shared state pass is one component. Universal compositor support is not achieved by renaming profiles or returning success for unsupported requests. Next installation must follow integration of the still-needed paths and device verification; this refactor alone does not establish that the0230 UI stall is repaired.


## 0232: shared uploads and independent function admission

### Resource plan

`A5MaliResourcePlan.h` assigns up to66 immutable logical uploads to up to four8MiB physical BOs using stable first-fit decreasing placement and explicit alignment. The planner contains no function names, shader IDs, handles, host pointers or GPU addresses. It returns a complete plan, invalid input or bounded pressure; failure leaves no partial output. Private buffer bindings already owning kernel handles reduce the available physical BO count.

The production misc submission path captures buffer-backed texture parents and storage bindings at commit, plans the complete set, uploads packed BOs once, then rebases each image/buffer GPU address to its own validated slice. Small ordinary uniforms retain their established descriptor-arena path. Original texture offset/row stride and binding-relative offsets remain intact. Read masks, actual Query17 mapping epochs, terminal fences and failed-release quarantine are preserved. CPU snapshot bytes are budgeted before allocation to at most32MiB for upload data; packed CPU copies and real kernel backing are additional memory. The four-slot/eightMiB-per-buffer kernel ABI is unchanged.

Planning/upload failures receive their own phase/error receipt. A plan cannot create capacity while all physical slots are retained by persistent BOs. This implementation does not claim to repair the two0230 phone NoResources errors; their precise origin remains uncaptured.

### Request admission

Actual function demand now lives in a separate per-UID `functions/` directory with its own lock and64-entry quota. Pipeline receipts keep the legacy per-UID directory/64-entry quota. A saturated receipt lane cannot prevent a new function from being durably published. A shared component-by-component directory opener verifies UID ownership, exact0700 mode and O_NOFOLLOW at both levels; no caller path is passed to the root worker.

The root scanner reads function demand before the legacy lane, retains old flat-function compatibility, authenticates every request as before, deduplicates identities and performs quota retirement in the actual owning lane. Total per-UID capacity is bounded128 requests (at most16MiB of128KiB envelopes); no queued request is arbitrarily deleted to make space. The worker still performs compilation synchronously. An already blocked translator child is **not** repaired by lane separation, and no time limit or guessed success was introduced.

### Verification

- Resource planner ASan/UBSan:66 logical bindings/one physical heap, alignment/nonoverlap/overflow/pressure/failure-output checks and10,000 mixed plans.
- All18 native integration executables pass. The real production profile200/204 submits192B vertex and131,073B fragment storage through one packed BO; original byte content, shifted vertex address, fragment base address, Query/Submit masks, failure fences and release counts are checked. Existing buffer-backed603..606 snapshots, offsets, full bulk uploads and error cleanup pass.
- Provider atomic request tests prove a full receipt lane still admits functions, an independently full function lane returns Busy/deduplicates/retries, and a nested lane symlink rejects. iOS16/A53 Werror compilation passes.
- Genuine AIR/Midgard scanner tests pass for legacy64 entries,64 receipt records plus two separate function records, and functions arriving after the snapshot. The new3632B native result must exactly match the existing genuine reference; no mock compiler output is used. One terminal retirement per scan, malformed-leaf preservation and no recompile on second scan remain checked.
- Actual synchronous Metal specialization under64 function-lane entries waits, retries after one retirement, consumes the real1072B publication and creates a dynamic pipeline without queuing an already executable pipeline.
- Signed iOS provider and compiler-service builds pass4KiB signature-page verification. Current device remains on0230; no BOOT package/write is performed for this source transition.

Remaining: shader-backed blend lowering and pipeline-specific cache identity; broader reflected vertex/varying/resource linking; persistent buffer/window residency generalization; and the near-idle translator child wait. These are implementation gaps, not inferred successes from the tests above.
