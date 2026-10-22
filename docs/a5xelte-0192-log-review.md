# 0192: live pipeline admitted; first native submission hits unwired OOL input

## Verdict

The previous pipeline and linear-image validation blockers are passed on the
user's photographed phone screen. Backboardd commits its first observed native
command buffer. Before clear submission returns, XNU panics with
`IOGMD: not wired for the IODMACommand` at IOMemoryDescriptor.cpp:3248.
The native submission input-copy path contains a concrete missing prepare /
complete lifecycle that reaches precisely this panic. No completed stock GPU
fence, source-over pixel result or displayed iOS frame is established.

## Evidence sources and capture boundary

Read-only recovery from the existing SYSTEM log region yields flush18,
83804 recorded bytes, all recovered without overwrite; the decoded text is
83559 bytes /935 lines. No device write or reboot was performed for this
readout. Raw logs and the user's photo remain private.

The persisted log ends at the compiler helper's `exec metal2vulkan`, before
the final events visible in the supplied photo. Absence of the final panic
from this disk snapshot is not evidence that the panic did not occur. It is
an unflushed tail, not a wrapped/overwritten log. The terminal screen evidence
must be kept separate from recovered log line references.

| Persisted lines | Observation |
| --- | --- |
|189|All21 private GPU reference cases pass, with44 terminal fences, header1 and MMU0. These are private tests, not stock compositor work.|
|233-260|The incremental installer completes16 files with sync0.|
|756|One compiler service-start marker. The two helper exec records alone do not prove a restart.|
|848|Backboardd receives CA_IGNORE_MACH_SEND_ERRORS=1. This option only changes the existing Mach-send-failure policy.|
|888-913|Fourteen warmup pipeline request records; the existing embedded profiles admit these warmup pairs.|
|925-926|Last persisted framebuffer window:21 surface creations,3 lock/unlock/write-unlock operations, zero swaps, shown frames and GPU/CPU presentation bytes.|
|933-935|Compiler runner executes and authorizes metal2vulkan; no publication, success, failure or unsupported worker status has been persisted yet.|

Across the entire persisted capture there are39 framebuffer measurement
windows, all without a presented frame, and no CRASH or panic record.
Other warnings concern the existing root authentication override, shared
region startup, Jetsam option, missing preboot/factory data, multiuser/persona
setup, temporary-directory reset and logd privilege. None is a captured
alternative terminal cause; execution subsequently reaches the photographed
Metal commit. Repeated xpcproxy execs alone do not establish a crash loop.

## Later physical screen evidence

- Linear texture accepts the actual BGRA8 request:194x237,row832,
  image197128,backing200704,Shared/ShaderRead. The last-active-byte repair is
  observed on the phone.
- The real fixed_frag_lph_cph / fixed_vert_lph_spc profile603 specializes and
  its full source-over pipeline is accepted. RT0 uses ADD,sourceONE and
  destinationONE_MINUS_SOURCE_ALPHA for RGB and alpha. Other slots retain
  their default state. This proves admission, not executed blending pixels.
- Command buffer2 begins submit1 with first_error0, one render encoder,
  two queued draws, one clear and no blit.
- Query17 receipt1 has one surface and no buffers; completion result0.
  The clear-query17 and clear-emitter phases both return0.
- Next is the kernel panic quoted above. There is no photographed
  clear-submit18 return or terminal native fence.

The first executed operation is the queued clear (profile0); the accepted
textured603 draws have not been proven to run. The panic is not the previous
Metal pipeline rejection and is not evidence of a Mali MMU/job fault.

## Source trace: unprepared out-of-line input

The built kernel's native ABI statically asserts a120-byte submission header;
it is followed by262144 bytes of encoded jobs. A5MaliSubmitNative therefore
sends262264 bytes through IOConnectCallStructMethod selector18, well above the
in-band structure limit. This uses structureInputDescriptor.

The staged XNU path is:

1. IOUserClient.cpp:is_io_connect_method creates the OOL input descriptor with
   kIODirectionOut | kIOMemoryMapCopyOnWrite and current_task. It does not set
   kIOMemoryAutoPrepare or call prepare. callExternalMethod also does not
   prepare it; after dispatch the descriptor is released.
2. A5XELTENativeClient.inc:nativeSubmit calls descriptor->readBytes directly,
   without prepare/complete, before token validation or GPU queue submission.
3. IOMemoryDescriptor::readBytes calls getPhysicalSegment. The API contract
   explicitly requires kIODirectionOut and a prepared descriptor.
4. IOGeneralMemoryDescriptor::dmaCommandOperation rejects a virtual descriptor
   whose wire count is0 with exactly the photographed panic at line3248.

This is a confirmed source defect and the path/phase/size match the physical
failure. No kernel backtrace survives in the recovered snapshot, so the photo
alone does not independently identify the full call stack.

The same direct unprepared read appears in nativeBulkWrite (selector19).
Both entry points need balanced preparation around their bounded snapshot
copy, with prepare failure propagated before readBytes, completion on every
post-prepare exit and no GPU dispatch after a failed copy/completion. Preserve
the existing owned snapshot, exact sizes, resource tokens and queue lease.
Do not bypass XNU's wire-count check or extend the lifetime of a caller-owned
input buffer across the asynchronous GPU operation.

By contrast, the nonpageable IOBufferMemoryDescriptor allocations used for
AS1 tables/jobs and SweetSurface backing set kIOMemoryAutoPrepare in
IOBufferMemoryDescriptor::initWithPhysicalMask and prepare during superclass
initialization. Query17 has already walked the destination mapping in this
clear-only case, and there are no read buffers. Adding unrelated prepares to
all surfaces would not repair the demonstrated missing OOL-input lifecycle.

## Next verification

Exercise the actual kernel input-copy path, not only the existing host mock
transport: prepared copy success, prepare failure without read/complete,
short-copy cleanup, completion failure and balanced lifecycle for submission
and bulk upload. After a corrected BOOT is explicitly installed, require a
clear-submit18 return and terminal native fence; then inspect subsequent
textured603 draw, source-over pixels and presentation separately. The current
readout makes no new build or installation claim.
