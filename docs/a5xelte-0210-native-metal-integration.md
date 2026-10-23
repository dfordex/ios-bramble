# 0210: pipeline ABI, linear blur and storage dependencies

## Implemented

The UniXNU NativeMetal comparison is pinned to commit
`c6d29caad6d880cc8204ebe3bc34d77479a3255d`. Three bridge concepts are adapted
to the existing Mali/Panfrost path; Adreno hardware commands are not imported.

1. Match authenticated vertex/fragment metadata and resource contracts rather
   than requiring a fixed vertex-profile interval. The actual 1808-byte profile602
   vertex exports position, point size and color, with no UV. Its native export
   layout now links to the phone's 2448-byte zero-input ordered-fetch fragment.
   Reflected dynamic equivalents use the same ABI checks. Invalid IO remains an
   explicit rejection with the actual stage profiles and predicate in the log.
2. Snapshot actual min/mag filters into the Midgard sampler. Blur100..108 admit
   nearest/linear with normalized clamp, one level, zero LOD, no comparison or
   anisotropy. Released-Mesa compilation of four filter combinations across nine
   profiles matches installed shader code in all36 comparisons. Profile99 stays
   nearest-only until its DS4 source equivalence is established. Native indexed
   tests cover linear u16/u32 draws; independent fractional-UV pixel oracles
   distinguish bilinear from nearest results.
3. Track committed resource read/write dependencies per device by underlying
   allocation, overlapping no-copy address range and IOSurface ID. Views alias
   their backing storage. Cross-queue conflicts wait before taking transport
   locks; public CPU reads/writes and resource wait/completion use the same
   identities. Uncommitted work is absent. Terminal success releases owners;
   uncertain GPU submission faults quarantine storage rather than reporting
   completion or allowing reuse. Pre-submit validation errors do not quarantine.

## Local evidence

- Exact602/2448 factory/emitter tests:202 grouped checks,17 malformed ABI cases,
  12 mocked submissions covering genuine success and missing-fence failure.
  Existing4672-byte textured-fetch/noise regression passes.
- Storage concurrency and real production command-buffer integration use actual
  host IOSurfaces with mocked kernel/fence transport. Cross-queue alias ordering,
  CPU waits, owner retention and timeout quarantine pass.
- Resource API tests, linear sampler structural/sanitizer checks and independent
  bilinear oracle checks pass. All18 native wrapper binaries and the final
  Cortex-A53/iOS compile pass. Earlier timeout tests were reordered or updated
  to require quarantined no-copy ownership after an uncertain GPU submission;
  they no longer assume that a failed fence makes the destination reusable.
- Signed iOS provider builds. The actual19-file kernel payload preflight passes:
  40,637,488 raw /9,833,968 packed bytes. Full XNU compile/link/dSYM/strip/symsets
  pass. BOOT is31,641,616 bytes, below its33,554,432-byte partition capacity.
  Loader and ADT are byte-identical to0209/proven0207d. The exact compressed
  signed provider and all four new test names are present in the linked kernel.

## Device scope

The GPU suite contains39 cases: previous35 unchanged, plus actual602 full-target
and same-job overlapping ordered fetch, and fractional-UV u16/u32 linear blur.
The four old physical failures remain open. Local tests do not establish new
phone pixel results, live backboardd admission, or a working home screen.

Only BOOT p10 is explicitly written. The existing embedded installer updates its
exact incremental userland files on HFS root. No whole USERDATA image transfer,
BOOT backup, post-write hash/readback, recovery/EFS/factory partition write occurs.
Physical runtime results remain pending until the next SYSTEM-log capture.
