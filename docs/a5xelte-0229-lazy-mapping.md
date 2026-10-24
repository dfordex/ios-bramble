# 0229: logical imports, protected GPU mapping and verified prewarm

## Implemented correction

0228 logged Map selector4 NoResources for an externally imported1200×489 BGRA surface. Map4 immediately evicted/mapped a physical AS1 window; its MMU update acquires the global GPU runtime queue nonblockingly. A valid import can therefore fail while unrelated work owns the queue. The generic0228 error does not by itself establish which internal check failed.

Patch0211 makes Map4 validate the actual retained IOBuffer, exact format/layout, rounded allocation span and every physical page without reserving a window or touching MMIO. This retains all previous invalid-page, protected-framebuffer, physical-address and bounds guards. Logical resources remain bounded128 and physical windows remain4.

The actual first Query17 creates AS1 as needed, maps the protected participating surfaces and returns real spans. Submit18 retains epoch/handle/usage checks. Typed legacy submission already ensures mappings. Unmap of a valid resource with no current physical mapping becomes a successful no-op; mapped resources still unmap and uncertain failures still preserve backing. Closed/stale handles remain rejected.

The actual backing helper, Map4 and token-query functions pass host ASan/UBSan tests for the live allocation size, invalid pages/short allocations, stale/closed handles, first-query mapping and AS1 allocation failure. This tests real source with mocked memory/hardware interfaces; physical operation is pending.

Patch0212 expands the existing bounded backboardd tee from1024 to2048 chunks per lifetime, still four lifetimes maximum. Concurrent-writer tests verify8192 chunks total. This helps preserve terminal pipeline receipts after warmup; it is not a rendering fix and does not remove a safety cap.

## Real shader and pipeline replay

The two new phone-produced fragments,1,072 and2,624 bytes, are authenticated against their complete request/receipt/reflection/code. Single-UV and dual-UV factory/native-emitter matrix tests pass with actual programs (64/448 and32/480 positive/negative layout cases respectively). Released native descriptors and target/blend combinations are exercised; no host test is labeled a physical pixel result.

A replay of all51 complete captured pipeline snapshots now passes the actual authenticated provider factory, with zero rejected pipelines or missing stages. Reconstructed descriptors must serialize back to exact equality with the captured complete descriptor before factory invocation. All installed30 stage publications were recovered from the existing private kernel payload for the replay. Three initially missing local programs were also genuinely recompiled by the unchanged Mac worker; this was a host-fixture completeness check. The two phone-produced programs are newly embedded, bringing persistent stages to32.

The exact final pipeline responsible for the0228 abort was not present among complete captured requests. Thus51 successful replays do not prove that specific rejection was repaired. No shader identity/resource/IO gate is relaxed, and no dummy success or substituted program is introduced.

## Build/install

XNU make exits0. BOOT25,686,032 bytes; linked kernel25,019,736 bytes. Provider remains exactly the signed0228 binary (963,888 bytes). Existing367 payload files remain byte/metadata identical, and six validated publication files bring the total to373. Original270 app files and metadata remain exact.

Actual installer preflight, final linked-segment checks, CRCs, stage authentication and safe selected-DT staging pass. Loader/ADT/DTBH/boot arguments remain exactly0228: native rendering, four cores,736MiB,32-sector I/O and functional quiet touch; optional GPU suites remain disabled.

Correct model/recovery/p10/capacity checks pass. The write acknowledges25,686,032 bytes, sync succeeds and reboot is requested. No BOOT backup/readback or full USERDATA transfer. Physical UI progression/interaction, new GPU pixels, and whether the earlier generic mapping/pipeline failures recur remain pending.

## Prewarm scope

Metallib entry names can be enumerated ahead of time. Function constants and associated rendering state create many specialized variants, so entry-name coverage is not equivalent to covering every possible shader program. A practical prewarm set covers actual boot/lock/home/application scenarios and persists authenticated outputs, while retaining the general compiler for unseen combinations. This build carries32 genuine stages and verifies51 observed complete pipelines; it does not claim universal CoreAnimation/Metal shader support.
