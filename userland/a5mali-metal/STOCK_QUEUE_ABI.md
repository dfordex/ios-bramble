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
