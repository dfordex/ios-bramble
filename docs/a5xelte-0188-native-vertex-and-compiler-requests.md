# 0188: actual vertex specialization and automatic compiler requests

## Result boundary

The real `fixed_vert_lph_spc` function captured in0187 is compiled with its
four typed named constants, paired with the real `fixed_frag_lph_cph` and its
58 constants. Profile602 preserves these distinct stage identities. Profiles600
and601 retain their earlier candidate `std_vert0_lph` contracts for regression;
they are not aliases for the observed vertex function.

Both actual stages pass translation, SPIR-V validation and Mesa26.2.4 Midgard
compilation. The specialized vertex SPIR-V is3,988bytes with SHA256
`c022ec8724edf2fba6c7860686d07bf3c47c22577804f868f61ebf145018ecbc`.
Its1,808-byte native result is identical to the previous candidate after
optimization, but this does not remove Metal's required function specialization.
The real fragment remains848bytes. Private Apple inputs, shader binaries,
captures and generated registries remain outside Git.

## Stage and native ABI

| Boundary | Implemented contract |
| --- | --- |
| Vertex specialization |`fixed_vert_lph_spc`; Bool `fc_generic=0`, UChar texcoord_count0/1=0 and vertex_layout=0; no indexed/extra/missing constants|
| Fragment specialization |`fixed_frag_lph_cph`; exact58 named typed constants from0186/0187|
| Configured vertex layout |Actual QC packing0: VB1 stride48; A0 Float4@0,A1 Float2@16,A2 Float2@24,A3 Half4@32|
| Optimized native vertex |Dense attributes0/1 read position/Half4 color; UBO1 reads VB2 matrix64bytes, UBO0 reads dynamic viewport; outputs POS,PSIZ,VAR0|
| Optimized native fragment |VAR0 color and UBO0 byte68 ColorWriteRule; no surviving texture, sampler or fragment-buffer1 access|
| Supported pipeline state |One BGRA8 RT0, writeMaskAll and copy-only; complete inactive attachment/layout/state checks remain|
| Submission |Same validated native Query17/Submit18 route; kernel patch0186 admits602 only|

The actual function names and constants are observed. The real target format
and fixed-function blend state are still unknown: `fc_blend_function=54` comes
from a different specification field than the pipeline blend selector. The
strict copy/BGRA contract is supported, not a claim that the next live factory
will match it. Actual mismatches are captured as complete pipeline requests.

## Automatic request path

1. The provider snapshots rejected recognized vertex/fragment requests using
   real Metal constant-array accessors. Authenticated pipeline factories also
   snapshot both stage identities and the actual complete descriptor, including
   all8 attachments,31 vertex attributes/layouts, buffer mutabilities and the
   audited iOS16 raster/tessellation options. Unsupported linked libraries,
   private functions and archives are not silently omitted.
2. Canonical JSON includes the original library digest, T720 identity, compiler
   ABI and owning UID. An atomic0600 request is published in a0700 per-UID
   directory under root-owned01777 `/private/var/tmp/a5mali-shader-requests`.
   Identical requests deduplicate; bounded per-UID pending entries prevent
   unbounded accumulation. Queued is distinct from compiled or executable.
3. The root native compiler runs `--serve`, prepares the spool before selftests,
   and scans serially at low priority. It validates ownership, file type,
   canonical request identity and source digest. The first admitted automatic
   recipe is the actual602 pair with its exact4+58 constants. A separate signed
   `midgard-generic602` executable performs the genuine released Mesa lowering;
   the existing read_surf/downsample selftests remain.
4. Real translated metadata, SPIR-V and native bytes must match the reviewed
   recipe. The worker atomically publishes root-owned0444 shader files and a
   receipt under `/private/var/tmp/a5mali-shader-compiled/<request_id>/`.
   Stage compilation does not grant a new resource or render-state ABI.
5. A pipeline first selected against the exact602 descriptor polls for that
   request's cache at most once per5seconds. The loader independently checks
   native byte hashes, lengths, tags, register counts, TLS/WLS and provenance.
   The pipeline retains its owned stage byte copies and switches future draws
   to those actual phone-compiled bytes. The embedded compiled602 route remains
   available while compilation is pending; no fabricated successful job/fence
   replaces a failed request.

Requests outside the reviewed recipe are retained with an explicit unsupported
status. This first route does **not** automatically implement arbitrary new
Metal resource layouts, shader families or blend operations. Generalizing the
compiler/backend and native emitter is still required for those contracts;
forwarding them now preserves the complete evidence without repeated ad hoc
log additions. No complete compositor-rendering claim follows from this work.

## Validation

- Actual25-profile registry lookup, changed constant/type, missing specialization,
  wrong stage/name, cross-library/state and corrupted native-code tests pass.
- Both stage factories and the actual602 native emitter pass host integration
  through Query17/Submit18, caller-owned buffer snapshots, terminal fences and
  error propagation. Transport is mocked; these are not phone pixels.
- Request tests cover real Metal typed snapshots, immutable state, deterministic
  deduplication, malformed requests, quotas and concurrent publication.
- Cache tests use the actual pinned native bytes and reject changed code,
  source/recipe/constants metadata, ownership/modes, symlinks and hardlinks;
  loaded copies survive removal of their published files.
- Provider/request/cache sources compile for Cortex-A53 iOS16 with Werror.
- A host end-to-end run passes canonical request intake, genuine translation,
  SPIR-V validation, released Midgard compilation and atomic readonly cache
  publication. The actual iOS compiler runner and four tools build/sign with
  4KiB code-signature pages. This is not device execution proof.

The final incremental payload has15files,35,324,002raw /8,908,912packed bytes,
including the612,400-byte provider and127,664-byte runner. It fits the unchanged
10MiB compressed-installer bound. Kernel patch0187 admits only the exact signed
`midgard-generic602` identity/path under the existing compiler boot gate. Fresh
XNU make including symbols succeeds; the resulting BOOT is29,765,648bytes,
within BOOTp10's32MiB capacity. Existing root apps and21 GPU oracles are retained.

Device proof must show actual vertex602 acceptance, the live pipeline decision,
commit/native submission and its completion. Automatic compilation has separate
`PUBLISHED profile=602` and `compile cache: bound ... source=phone-compiled`
markers; neither a queued request nor the old green selftest line proves them.
