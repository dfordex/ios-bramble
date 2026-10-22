# 0190: buffer-backed texture selector blocks the live compositor

## Verdict

FAIL for live compositor submission; PASS for installation and the independent
GPU regression suite. Two concrete software defects stop this trial: a missing
buffer-to-linear-texture method and non-idempotent compiler status-directory
creation. The textured profile603 is installed but has not yet been reached.

## Capture and evidence

Read-only SYSTEM recovery: flush40, all181,378 recorded bytes recovered without
overwrite; decoded text181,133 bytes/2,009 lines. Raw logs remain private.
No device write or reboot was performed during this readout.

| Evidence in recovered log | Observation |
| --- | --- |
|234-263|Payload preflight0; 16 files; new648,432-byte provider, runner and generic603 recipe installed; complete16/sync0.|
|189|All21 private GPU cases evaluated/pass/immutable; 44 terminal fences have header1/MMU0.|
|884|Stock Metal device accepted by the probe.|
|1007-1012|Live command buffer2 created; old fragment601/vertex602/full602 pipeline accepted.|
|1015-1023,1201-1209|Uncaught NSInvalidArgumentException: A5MaliSharedReadBuffer lacks newLinearTextureWithDescriptor:offset:bytesPerRow:bytesPerImage:.|
|1026-1977|14 backboardd signal6 crashes, namespace2/code6, one identical ten-frame crash backtrace. Early heap scans repeat the same missing selector.|
|760,806-807|Compiler serves requests without baseline selftests; one unsupported request is recorded, then status-directory creation fails.|
|811-1988|17 service starts and17 status-directory failures overall; no publication or cache binding.|
|1942-1999|Physical key events and other daemons continue; this is not a kernel-wide freeze.|

## Findings

### P1: the shared buffer lacks a real linear texture view

The newly installed shared buffer object is used by iOS, then immediately
receives the four-argument private Metal selector shown above. Source
A5MaliMetalDeviceResources.m implements shared allocation/no-copy ownership
and buffer transfer methods but no linear-texture creation method. The
Objective-C exception precedes the next textured specialization and any
command-buffer commit.

The previous no-copy rejection and fragment-specialization crash are absent,
but this does not prove profile603 acceptance: the new missing method stops
execution earlier, and no603 specialization/pipeline marker exists. No stock
commit, native phase, Query17 or Submit18 is recorded. All81 framebuffer
measurement windows (430,831ms total) have zero swaps, shown frames and bytes.

Implement a genuine retained buffer-backed texture view: validate descriptor,
format, offset, row/image strides and backing span; preserve parent ownership,
aliasing and late writes; bind its actual bytes through the resource path used
by native draws. Returning an unrelated blank texture or merely adding a nil
stub would not satisfy this call. Both public buffer texture creation and this
private selector should share the validated implementation.

### P1: existing request-status directory kills the compiler worker

The source a5WriteStatus in ios/a5shader_requests.inc.m lines121-133 calls
createDirectoryAtPath withIntermediateDirectories:NO for every new status and
fails on any NO result. The first unsupported request is successfully recorded;
the next attempt encounters the same directory. Subsequent service restarts
repeat the failure before reaching actual602 compilation.

A small Foundation reproduction on the Mac confirms first creation succeeds,
second creation returns NO/NSCocoaErrorDomain516. Thus the source is
non-idempotent and the observed first-success/repeated-failure sequence matches
that defect. The device log does not capture NSError/errno, so it alone cannot
exclude another filesystem error.

Create-or-validate the directory once, accepting an existing real root-owned
0700 directory while rejecting symlinks/non-directories/unsafe ownership or
modes. Preserve atomic status writes and log concrete filesystem errors. Test
multiple unsupported requests followed by a known request, plus service restart
with an existing status directory. No automatic compilation/cache publication
is proven in this boot.

## Other observations and limits

All recorded process crash reports are backboardd. Duplicate gamepad plugin
class warnings, expected APFS/preboot/SEP omissions and persona/Sandbox messages
also appear, but none replaces the explicit missing-selector exception as the
identified compositor failure. One later swap-file-open error follows repeated
crashes; it is not the first abort. No kernel panic or GPU/MMU fault is captured.

The independent GPU suite remains healthy. It does not establish stock iOS
rendering, successful buffer-backed texture import, textured603 acceptance or
on-phone cache binding. Recheck those boundaries after the two repairs.
