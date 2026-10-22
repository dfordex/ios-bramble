# 0183 full log review — 2026-10-22

## Verdict: the texture-limit fix exposes a missing command-buffer method

The complete recovered capture contains 35,612 lines and 2,568,450 decoded bytes
(flush 3256, no ring overwrite). It was reviewed across the whole capture, not
only the final screen or the first exception. The four CPUs initialize, the
private GPU regression suite passes, and stock backboardd now creates its next
command buffer after constructing a fullHD surface. It then throws an Objective-C
exception because `A5MaliMetalBuffer` does not implement `setProtectionOptions:`.

This is progress beyond 0182's 1080-pixel Metal limit, and a new blocking defect.
It is not proof of a successful live Metal frame: no stock command-buffer commit,
Query17, resource-operation or native-submit receipt appears in this capture.

## Complete capture census

| Boundary | Observed evidence | Meaning |
| --- | --- | --- |
| CPU and root | Four CPUs initialized, SGI1 verified at line 96; root boot continues | No new CPU startup panic or root-mount stop. |
| GPU tests | Line 189: `completed passed=21 evaluated=21 cases=21` | The private shader/resource tests pass; this does not establish compositor coverage. |
| Payload installer | Lines 235–254: free 2,149,183,488 bytes, required 95,324,466; complete files=13, sync=0 | The updated Metal bundle is installed and the other twelve existing files retained. This boot does not reinstall the previously restored six apps. |
| Metal limits | Lines 868 and 1084: `max2D=2048/2048` | The actual provider now publishes a limit large enough for both axes of 1080×1920. |
| Device and preparation | Stock device accepted; 41 pipeline-acceptance receipts; no pipeline-rejection receipt | Initial device/pipeline preparation succeeds at the logged profiles. |
| New command buffer | Lines 976–980: fullHD surface 23, then `commandBuffer cb=2 created=1` | The run crosses the boundary that was absent in 0182. |
| Live submission | Zero stock commit, Query17, resource-op and native-phase receipts | No successful stock Metal draw submission is proven. The exception occurs before the first such receipt. |
| Crash events | 55 headers: 38 backboardd, one PosterBoard, 16 assetsd | Three distinct process/backtrace families; detail below. |
| GPU completions | 52 fence-completion receipts, successful headers and zero MMU status in those receipts | Includes independent tests and presentation probes. Fence completion alone does not identify a stock compositor submission. |
| Framebuffer activity | 6,125 metric windows: 47 swaps, 29 presentations, 18 superseded; 33,177,600 copied bytes | There is limited presentation activity, not a working sustained Metal compositor. Summed metric time is 32,594,173 ms, about 9.05 hours. |
| Independent presentation | Lines 3175–3178: live surface 855 sample passes 256/256; line 3560: full-frame fences 47/48, shown=1 | Kernel GPU-to-panel transport is demonstrated independently of stock Metal commands. |
| Allocation pressure | 90 failed contiguous requests for 84 pages and two for 64 pages | A real later allocation constraint to revisit after the first exception, not proof of global out-of-memory. |

The final four fence records, 49–52, are not accompanied by stock commit/native
submission receipts. They must not be counted as proof that the live iOS draw
path became operational.

## 0182 to 0183: precise success boundary

The previous review established that QuartzCore calls `maxTextureWidth2D` for
both surface-axis limits. A value of 1080 therefore rejects a 1920-pixel target
before creating a live draw command buffer. In 0183 the runtime limit receipt
is 2048/2048. The first captured backboardd process creates surface 23 as
1080×1920 BGRA with row stride 4352 and size 8,355,840 bytes at line 976, then
creates command buffer 2 at line 980. The second captured process repeats this
boundary at line 1147.

Immediately afterward, lines 982–990 report an `NSInvalidArgumentException`:

```text
-[A5MaliMetalBuffer setProtectionOptions:]: unrecognized selector
```

The first throw stack contains runtime return address `0x1bc14acf8`. Subtracting
the recorded shared-cache slide `0x33e40000` gives `0x18830acf8`, exactly the
instruction after QuartzCore's setter call at `0x18830acf4`. This links the live
exception to the new-command-buffer branch of
`CA::OGL::MetalContext::start_command_buffer(unsigned long long, char const*)`.
The conclusion is stronger than simply noticing a new selector name in strings.

There are 38 backboardd SIGABRT events at lines 992–3032. Every event has the
same PC/LR and ten-entry backtrace. They are one repeated failure family, not
38 independently diagnosed defects. Five command-buffer creation receipts are
captured across the early processes; the log does not provide fresh userland
receipts for every later restart.

## Exact protection setter/getter ABI

Evidence uses the unmodified iOS16 QuartzCore image, UUID
`9e40b2eb-260c-3af1-ae45-a1a551a8c1b9`, and Metal image from the same source
shared cache. Addresses below are preferred image VAs unless identified as
runtime addresses.

| Exact code or metadata | Contract |
| --- | --- |
| Metal Objective-C metadata, `MTLIOAccelCommandBuffer` | Getter is `unsigned long long protectionOptions`; setter is `void setProtectionOptions:(unsigned long long)options`. These are 64-bit values, not BOOL or a 32-bit enum. |
| QuartzCore `start_command_buffer`, `0x18830ac94–0x18830acb4` | On an existing buffer, reads `protectionOptions`, compares the full x0 value to requested x20, and calls the setter if they differ. Getter and setter must agree. |
| QuartzCore `0x18830acc0–0x18830acf4` | Obtains a new queue command buffer, stores it, labels it, and calls `setProtectionOptions:` before `enqueue` at `0x18830ad18`. This is the branch identified by the runtime throw stack. |
| Metal getter `0x181a77308–0x181a77314` | Resolves the `_protectionOptions` ivar offset and loads the complete 64-bit value. |
| Metal setter `0x181a77328–0x181a77354` | Takes the argument in x2, checks the current encoder, calls `commitEncoder`, and stores the full 64-bit option value. |
| Metal setter `0x181a77358–0x181a773a0` | Reserves 16 bytes of kernel-command space and emits the protection option value. The native Apple implementation has an execution-side effect; it is not merely a property with an ignored setter. |
| Metal active-encoder branch `0x181a773a4–0x181a773bc` | Reports a validation failure if a command encoder is active before continuing the native implementation. |

The captured error proves the selector is absent. It does not log x2 and thus
does not prove which option value that particular call requested. A replacement
must use the correct 64-bit ABI and preserve truthful state/lifetime semantics.
Supporting the unprotected state is different from claiming protected-resource
isolation: unsupported nonzero/protected options must not be silently accepted
or advertised as implemented. The follow-up trial must record the requested
option and whether execution reaches enqueue, encoding and commit afterward.

## Other crash families

### PosterBoard: duplicate first-time configuration setup

One SIGTRAP occurs at line 3695. Runtime PC `0x1f55b8268`, minus the same slide,
is `0x1c1778268`: an explicit `brk #0` inside
`-[PBFPosterExtensionDataStore _stateLock_setupSwitcherConfigurationForFirstTime]`.
At entry, `0x1c1777ab0` loads `self+0x98`; `0x1c1777ab4` takes the fatal branch
when the value is nonnull. The exact assertion strings decode to:

```text
Invalid condition not satisfying: %@
!_stateLock_switcherConfiguration
PBFPosterExtensionDataStore.m
```

The source-line immediate is `0xd67` (3431). The stack runs through
`_stateLock_updateExtensions:refreshDescriptors:powerLogReason:galleryUpdateOptions:queuedUpOperations:`,
`executeUpdate:refreshStrategy:galleryUpdateOptions:powerLogReason:completion:`
and `PRSServer prewarmWithCompletion:`. The first-time initializer was called
when a switcher configuration already existed. The capture does not show why.
This is not evidence of an unsupported CPU instruction, Mali fault, or missing
wallpaper asset. Recheck it after stopping backboardd's restart loop before
choosing an independent PosterBoard state repair.

### assetsd: repeated uncaught exception, original reason not captured

Sixteen SIGABRT headers occur at lines 4478, 14109, 14148, 19495, 19534, 19569,
21325, 26798, 26857, 26892, 26917, 28730, 34260, 34309, 34340 and 34371. All
sixteen have identical PC/LR and ten-entry backtraces. The symbolicated stack
passes through `pthread_kill`, `abort`, libc++abi termination,
`demangling_terminate_handler`, `_objc_terminate` and dispatch callouts.

The kernel reason contains only namespace 2/code 6, and no assetsd exception
message was captured. The originating exception/API cannot be determined from
this unwind. Capture that exception reason or a deeper origin before selecting
a fix; this stack alone does not justify restoring unrelated assets or changing
the GPU compiler.

## Later workload and latent constraints

The full capture contains 8,351 xpcproxy, 3,149 fairplayd.H2 and 3,131 bluetoothd
execution receipts, plus 203 atc, 202 routined, 202 CommCenterMobileHelper,
186 calaccessd and 179 tccd starts. These counts establish repeated execution
attempts. They are not separately diagnosed crash counts or proof that each
xpcproxy invocation is abnormal. The activity can impose substantial background
work during this long capture.

There are 92 failed contiguous-page requests: 90 requests for 84 pages
(lines 2975–35609) and two for 64 pages (35395/35397). Each reports zero pages
found after scanning roughly 116,000 pages. This begins after the first 37
backboardd aborts. Fragmentation or retained allocations could become a later
blocker; the log does not establish a global memory exhaustion diagnosis or
which caller issued each allocation. Reassess it with the crash loop removed.

Existing mount/preboot/factorydata, user-session/persona, random/swap and sandbox
warnings remain. A cached backboardd string scan mentions missing
`kCMPhotoCompressionOption_RestrictedEncoding`; finding that string in memory
does not override the live, explicit protection-selector exception. No kernel
panic, SIGILL event, DATA_INVALID/JS_STATUS fault or GPU timeout line was found.

## Next verification boundary

1. Implement the correct command-buffer protection getter/setter contract with
   explicit failure for unsupported protected states and invalid lifecycle use.
2. Confirm the live request value, survival past the setter, actual encoder
   creation, commit and Query17/native-submit receipts.
3. Require a successful terminal fence plus a changed live frame before claiming
   stock iOS rendering on Mali. Private shader tests and kernel presentation
   probes do not replace this evidence.
4. Then revisit PosterBoard, assetsd and contiguous-allocation failures if they
   remain. They are distinct observations, not established explanations for the
   first live command-buffer exception.

No phone write or code change was performed as part of this log review. The
0184 implementation and device outcome must be recorded separately.
