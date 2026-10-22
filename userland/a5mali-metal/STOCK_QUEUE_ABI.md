# Stock iOS 16 queue and callback ABI

This report is derived from the staged iOS 16.7.16 Metal and QuartzCore images.
It records interface metadata and static call sites. It contains no Apple
executable data and does not claim unrestricted Metal rendering support.

## Recovered 0159 failure

The recovered phone log identifies an Objective-C exception:
`-[A5MaliMetalQueue setSubmissionQueue:]: unrecognized selector`.
The unslid QuartzCore call site is 0x1884882a8, in
`CA::OGL::new_metal_context(...)`, and the recorded LR is its following
instruction. The stack continues through `EAGLServer::renderer()`,
`EAGLServer` construction and display-server setup. This is renderer queue
configuration after selection of a device and successful `newCommandQueue`.
It is not `_MTLDevice init` or an initial `MTLAddDevice` protocol assertion.
It establishes that the real compositor reached the custom queue; a rendered
frame and a separate successful acceptance-probe result remain distinct facts.

## QuartzCore queue configuration

The constructor creates separate serial dispatch queues labelled
`com.apple.coreanimation.mtl_submission` and
`com.apple.coreanimation.mtl_completion`. Its exact sequence is:

1. `newCommandQueue` on the selected Metal device.
2. `setLabel:` on the command queue.
3. `setSubmissionQueue:` at 0x1884882a8.
4. `setCompletionQueue:` at 0x1884882b4.
5. Release both dispatch queues at 0x1884882bc and 0x1884882c4.
6. Query `device` on the queue and check it is the selected device.

Both setter arguments therefore need retained Objective-C dispatch ownership.
The signature is `void(id)` in the Objective-C metadata, where the actual object
is a dispatch queue. The constructor also conditionally calls the following
native-driver queue methods, both of which return BOOL:

```objc
- (BOOL)setGPUPriority:(NSUInteger)priority;
- (BOOL)setBackgroundGPUPriority:(NSUInteger)priority;
```

The native driver asks its kernel queue to set priorities and reports success.
A backend without GPU scheduling priorities should return NO rather than
reporting that the requested priority was implemented.

The QuartzCore selector references intersect the staged Metal queue classes at
`setSubmissionQueue:`, `setCompletionQueue:`, both priority setters, `device`,
`setLabel:` and `commandBuffer` (the latter is implemented by concrete drivers,
not the private `_MTLCommandQueue` method list). No queue hazard toggle,
`commandBufferWithDescriptor:` or `finish` selector appears in that image's
selector references. This is a static coverage bound; indirect external
framework calls are not ruled out.

## Submission and completion behavior

Stock `_MTLCommandQueue setSubmissionQueue:` at 0x181a45820 cancels/releases a
previous dispatch event source, releases the old submission queue, retains the
new queue, creates a DATA_ADD dispatch source targeting it, sets the event
handler and resumes the source. The event handler at 0x181a36f9c invokes
`_submitAvailableCommandBuffers` on the queue. It is a dispatch target change,
not an inert stored label.

Stock `MTLIOAccelCommandQueue setCompletionQueue:` at 0x181ada5e0 releases the old
completion queue, retains the new queue, and passes it to the native IOAccel
completion dispatcher. A custom queue must likewise route notifications through
its completion target. Terminal command-buffer state must be visible before
handlers inspect it, and handlers must be delivered once. Do not use
`dispatch_sync` onto the completion target from callbacks that may already be
running there. A caller waiting on that target can also deadlock a backend that
requires the same target to publish terminal state.

A minimal bounded implementation can use an internal serial submission queue
targeted at the supplied dispatch queue: this preserves same-queue FIFO even if
a caller supplies a concurrent target. Retain the target while tasks are queued.
The established synchronous GPU submission/retirement path may run inside those
serial blocks; completion callbacks can then be dispatched to the configured
completion target. Storing the supplied queue without using it for submitted
work does not reproduce stock behavior.

## Public descriptor path

Stock `_MTLCommandQueue commandBufferWithDescriptor:` at 0x181b234e4 reads
`retainedReferences`. It calls `commandBuffer` or
`commandBufferWithUnretainedReferences` accordingly, then reads `errorOptions`
and sends `setErrorOptions:` to the returned command buffer. A bounded backend
may reject unretained-reference descriptors or unsupported enhanced-error
options by returning nil; it must not silently claim unsupported descriptor
semantics. `insertDebugCaptureBoundary` is a no-op in the stock private base.
`finish` waits for all submitted command buffers, not only the most recent one.

## Hazard and ordering scope

The stock queue descriptor provides `commitQueue`, `commitSynchronously`,
`completionQueue`, `disableCrossQueueHazardTracking`, `isOpenGLQueue`,
`maxCommandBufferCount` and `qosLevel`. Base queue initialization copies those
settings and retains provided commit/completion targets. The absence of a
QuartzCore selector reference to a hazard setting does not establish that a
custom backend implements Metal resource hazard tracking. Serializing bounded
jobs through a shared private-device lock provides a bounded execution order;
general buffer/texture aliasing, command-buffer dependencies, events and fences
still require their actual resource semantics.

## Staged stock class interface

These declarations list the private base's methods, not mandatory methods that
a custom NSObject queue must expose. Methods that QuartzCore actually calls are
identified above. Anonymous `id /* block */` metadata does not encode a block's
invoke signature.

### _MTLCommandQueue

```objc
- (void)completeCommandBuffers:(id *)buffers count:(unsigned long long)count;
- (unsigned long long)maxCommandBufferCount;
- (_Bool)isOpenGLQueue;
- (_Bool)disableCrossQueueHazardTracking;
- (void)commandBufferDidComplete:(id)complete startTime:(unsigned long long)time completionTime:(unsigned long long)time error:(id)error;
- (id)commandBufferWithDescriptor:(id)descriptor;
- (void)addPerfSampleHandler:(id /* block */)handler;
- (void)dispatchAvailableCompletionNotifications;
- (_Bool)commitSynchronously;
- (unsigned long long)getStatOptions;
- (void)setSkipRender:(_Bool)render;
- (void)setStatOptions:(unsigned long long)options;
- (_Bool)executionEnabled;
- (unsigned long long)qosLevel;
- (void)commitCommandBuffer:(id)buffer wake:(_Bool)wake;
- (int)backgroundTrackingPID;
- (int)requestCounters:(id)counters;
- (unsigned long long)getAndIncrementNumCommandBuffers;
- (void)setExecutionEnabled:(_Bool)enabled;
- (unsigned long long)getStatLocations;
- (void)setBackgroundTrackingPID:(int)pid;
- (void)insertDebugCaptureBoundary;
- (id)initWithDevice:(id)device descriptor:(id)descriptor;
- (void)setStatLocations:(unsigned long long)locations;
- (void)setSubmissionQueue:(id)queue;
- (_Bool)_submitAvailableCommandBuffers;
- (id)initWithDevice:(id)device;
- (id)availableCounters;
- (int)requestCounters:(id)counters withIndex:(unsigned long long)index;
- (void)submitCommandBuffers:(const id *)buffers count:(unsigned long long)count;
- (_Bool)submitCommandBuffer:(id)buffer;
- (void)setListIndex:(unsigned long long)index;
- (void)enqueueCommandBuffer:(id)buffer;
- (id)initWithDevice:(id)device maxCommandBufferCount:(unsigned long long)count;
- (unsigned long long)globalTraceObjectID;
- (id)commitQueue;
- (_Bool)skipRender;
- (id)completionQueue;
- (void)setLabel:(id)label;
- (void)finish;
- (unsigned long long)getListIndex;
- (void)setStatEnabled:(_Bool)enabled;
- (void)dealloc;
- (void)setProfilingEnabled:(_Bool)enabled;
- (_Bool)isProfilingEnabled;
- (unsigned long long)numCommandBuffers;
- (_Bool)isStatEnabled;
- (id)description;
- (id)formattedDescription:(unsigned long long)description;
```

### MTLIOAccelCommandQueue

```objc
- (_Bool)setGPUPriority:(unsigned long long)gpupriority;
- (_Bool)setBackgroundGPUPriority:(unsigned long long)gpupriority;
- (_Bool)_setGPUPriority:(unsigned long long)gpupriority backgroundPriority:(unsigned long long)priority;
- (_Bool)setGPUPriority:(unsigned long long)gpupriority offset:(unsigned short)offset;
- (unsigned long long)getGPUPriority;
- (id)initWithDevice:(id)device descriptor:(id)descriptor;
- (void)submitCommandBuffers:(const id *)buffers count:(unsigned long long)count;
- (_Bool)setBackgroundGPUPriority:(unsigned long long)gpupriority offset:(unsigned short)offset;
- (unsigned long long)getBackgroundGPUPriority;
- (void)setCompletionQueue:(id)queue;
- (void)setLabel:(id)label;
- (void)dealloc;
- (id)device;
```

## Live command-buffer protection and completion ABI (0184)

0183 reaches a second, live command buffer after the corrected 2048-square
texture limit. Its first backboardd exception is the missing protection setter.
The recovered stack, minus shared-cache slide 0x33e40000, resolves to
QuartzCore `MetalContext::start_command_buffer` at 0x18830acf8, immediately
following `setProtectionOptions:` at 0x18830acf4. The setter argument comes
from WindowServer surface protection options; its numeric value is not present
in the abort record and must be observed on the next run.

Exact iOS16 Metal metadata defines a void setter with a 64-bit unsigned argument
and a 64-bit unsigned getter. `MTLIOAccelCommandBuffer protectionOptions` at
0x181a77308 reads the stored value. The setter at 0x181a77318 checks the active
encoder, commits its encoder state and writes a 16-byte kernel command including
the requested value. Therefore arbitrary nonzero options cannot be treated as
an ignored label on this unprotected driver.

The port supports zero (ordinary unprotected work). A nonzero request records
a sticky Unsupported encoding error, remains unprotected and prevents every
Query17/Submit18 operation at commit. A later zero request cannot erase the
error. A bounded receipt records the requested value and command ID. Mutation
after commit raises a contract exception without altering terminal state.

The always-installed QuartzCore completion block at 0x1882c83a0 reads
`protectionOptions` at 0x1882c83e4, followed by `error`; both are implemented.
The inspected live start sequence otherwise uses existing label, enqueue and
completion-handler methods. Normal flush uses existing commit, wait and
commitAndWaitUntilSubmitted methods. Render debug groups target the encoder,
not the command buffer.

Four other missing selectors have exact double-return ABI: GPUStartTime,
GPUEndTime, kernelStartTime and kernelEndTime. Their inspected callers are
conditional profiling handlers. They now return zero to indicate unavailable
timestamps; the current kernel transport does not expose GPU timestamps, and
CPU wall time is not substituted for GPU execution time. The additional
computeCommandEncoderWithDispatchType: caller requires successful APL compute
pipelines, which the current device does not create; that path is not claimed
as implemented.

Host tests exercise the real native emitter with injected transport: zero
protection preserves a successful draw, nonzero protection prevents query and
submission while delivering the error completion, and post-completion mutation
preserves the result. These checks verify the adapter contract, not a device
frame. Actual requested surface options and later live encoder operations
remain phone observations for 0184.
