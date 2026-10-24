# 0228: RGBA8 sources and compiler backpressure

## Evidence and implemented changes

0227 rejected an actual buffer-backed 37×37 `RGBA8Unorm` source (Metal70), row192, active image7060 bytes, buffer8192. It also reached the per-UID64-request limit. The subsequent backboardd fragment-specialization abort did not identify the exact function or NSError, so temporal proximity alone does not establish its cause.

0228 implements these confirmed missing paths together:

- Distinct RGBA byte identity through texture allocation/IOSurface import, CPU-visible buffer views and native sampling. Metal70 maps to RGBA8 with identity swizzle; BGRA80 retains the red/blue swizzle. Both compact Texture3 and reflected multiple-resource tables preserve the distinction. Typed raw copies, mip filtering and blur sampling carry the actual order. Render-target/profile checks remain explicit; this is not unrestricted admission of arbitrary formats or shaders.
- Executable pipelines compute a pure request identity for optional cache lookup, but no longer publish redundant complete-pipeline requests. Rejected authenticated pipelines retain bounded capture.
- A full64-entry spool returns retryable Busy with the same canonical identity. Synchronous function creation waits/retries for real compiled code, without returning nil solely for queue pressure, deleting another request, increasing the cap, or inventing executable code. Filesystem/identity/security failures remain terminal.
- Independent bounded terminal function receipts preserve function/request/error-domain/code/reason. The descriptor wrapper preserves the original NSError. These should identify a later specialization failure even after successful warmup receipts exhaust their budget.

The separate AttentionAwareness/SpringBoard exception seen in0227 is not claimed fixed by this patch.

## Verification completed

- Actual 37×37/row192/7060-byte linear alias accepts, exposes the final colored texel and rejects a one-byte-short view. Eleven texture identities retain CPU range and lifetime checks.
- Real Mac IOSurface allocation/import of Shared/Private RGBA8 passes. Kernel layout helpers pass bounds, byte-size and distinct-identity checks with ASan/UBSan.
- Released Mesa26.2.4 v4 descriptor decoding verifies both RGBA/BGRA sampled channel orders on compact and expanded descriptor paths. Raw copies and mip filtering preserve the matching order.
- Production Metal encoding with real authenticated603/604/605 programs admits RGBA8 buffer sources, snapshots/uploads real bytes and produces native Submit18 descriptors for copy/source-over. Eighteen native provider regression executables pass, including606 alpha-only restrictions and failed-fence quarantine. Transport is mocked: these tests do not prove physical GPU pixels.
- A real synchronous Metal function call is held behind64 pending requests; it does not return nil. After one retirement, the exact request publishes; an unchanged genuine2464-byte stage publication then completes the function. Its executable dynamic pipeline adds no spool request. The reusable test accepts private authenticated inputs; no shader bytes are committed.
- Snapshot/spool tests retain deduplication, concurrent publication, quota, forged/corrupt/symlink and directory-permission guards. Cortex-A53/iOS16 Werror compile and signed provider build pass.

## Built and installed

Full XNU make exits0. BOOT25,669,648 bytes, kernel25,002,656 bytes, provider963,888 bytes. The367-file payload retains30 genuine persistent stages. Only the provider payload file changes from0227; the kernel also gains the distinct RGBA8 import identity. Compiler helpers, original270 app files and their metadata remain exact.

Actual installer preflight and every final linked segment pass. Loader/ADT/DTBH/arguments match0227; the selected DT source remains wholly below0x42000000. Native GPU, four CPUs,736MiB,32-sector I/O and quiet functional touch remain enabled; optional GPU suites remain disabled.

The guarded recovery/model/BOOT-p10/capacity check passes. The write acknowledges all25,669,648 bytes, sync exits0 and reboot is requested. No backup, post-write readback or full USERDATA transfer was performed. Private images/logs/receipts stay in the local research build directory.

**Pending physical evidence:** current UI progression/interaction, actual RGBA8 consumption and GPU pixels, and whether another specialization or independent process error remains. A successful build/write is not a claim that the UI problem is resolved.
