# iOS 16.7.16 device acceptance ABI

This is an interface contract derived from the operator-supplied staged Metal
image and Objective-C metadata. It contains no Apple executable or shader data.
It establishes static call order and types, not device runtime acceptance.

## Device-add sequence

`MTLAddDevice` requires the live runtime protocols `MTLDevice` and
`MTLDeviceSPI`, sends `initLimits` and then `initFeatureQueries`, optionally
sends `allowLibrariesFromOtherPlatforms`, and appends to its device array.
The checks are release assertions, so missing protocol registration aborts.
The ordinary `_MTLDevice init` initializes its own queues, library builder,
compiler manager and helper state; the superclass `initWithAcceleratorPort:`
is abstract and raises `doesNotRecognizeSelector:`.

The limits payload is an inline 0x108-byte structure described in
`StockMetalPlugin/A5MaliStockABI.h`. Runtime ivar lookup and encoding size checks
must precede access. An independent limits pointer without writing the inline
payload is insufficient for inherited methods that access the superclass.

Base `initLimits` chooses Apple-family limits using `featureProfile`, then calls
`argumentBuffersSupport` and `maxBufferLength`. Base `initFeatureQueries` builds
`_MTLDeviceFeatureQueries`, which examines the device capabilities and fills
Apple-family-derived tables. The conservative custom profile instead installs
an ordinary `MTLDeviceFeatureQueries` object through inherited NSObject `init`.
That exact stock class provides explicit false `supports*` implementations and
zero-initialized BOOL `familySupports*` getters. It does not claim an Apple family.
The helper transfers one retained reference into the checked `_featureQueries`
slot: stock `_MTLDevice dealloc` explicitly releases that slot. Its
`_supportedGPUFamilies` C++ vector pointer may remain NULL: dealloc checks it;
`supportsFamily:` and `supportsFeatureSet:` must return NO for this profile.

## Methods absent from the stock superclass

The following lists compare direct protocol instance selectors with the staged
`_MTLDevice` method list, excluding common inherited NSObject selectors. Methods
already implemented by the custom bridge remain in this ABI list. Struct field
names `x0` etc. are metadata's anonymous members; use the corresponding SDK type
(`MTLSizeAndAlign`, `MTLSize`, `NSRange`) where available. Unsigned long long and
long long are 64-bit. `_Bool` is the arm64 Objective-C BOOL ABI. An `id /* block */`
encoding does not describe the block invoke signature, which must be supplied
from the corresponding SDK API or audited call site.

### MTLDevice: 27 selectors

```objc
- (unsigned long long)currentAllocatedSize;
- (_Bool)hasUnifiedMemory;
- (struct { unsigned long long x0; unsigned long long x1; })heapBufferSizeAndAlignWithLength:(unsigned long long)length options:(unsigned long long)options;
- (struct { unsigned long long x0; unsigned long long x1; })heapTextureSizeAndAlignWithDescriptor:(id)descriptor;
- (_Bool)isDepth24Stencil8PixelFormatSupported;
- (_Bool)isHeadless;
- (_Bool)isLowPower;
- (_Bool)isRemovable;
- (unsigned long long)maxBufferLength;
- (unsigned long long)maxThreadgroupMemoryLength;
- (struct { unsigned long long x0; unsigned long long x1; unsigned long long x2; })maxThreadsPerThreadgroup;
- (unsigned long long)minimumTextureBufferAlignmentForPixelFormat:(unsigned long long)format;
- (id)newBufferWithBytes:(const void *)bytes length:(unsigned long long)length options:(unsigned long long)options;
- (id)newBufferWithBytesNoCopy:(void *)copy length:(unsigned long long)length options:(unsigned long long)options deallocator:(id /* block */)deallocator;
- (id)newBufferWithLength:(unsigned long long)length options:(unsigned long long)options;
- (id)newDepthStencilStateWithDescriptor:(id)descriptor;
- (id)newFence;
- (id)newHeapWithDescriptor:(id)descriptor;
- (id)newIndirectCommandBufferWithDescriptor:(id)descriptor maxCommandCount:(unsigned long long)count options:(unsigned long long)options;
- (id)newSamplerStateWithDescriptor:(id)descriptor;
- (id)newTextureWithDescriptor:(id)descriptor;
- (id)newTextureWithDescriptor:(id)descriptor iosurface:(struct __IOSurface *)iosurface plane:(unsigned long long)plane;
- (unsigned long long)recommendedMaxWorkingSetSize;
- (unsigned long long)registryID;
- (struct { unsigned long long x0; unsigned long long x1; unsigned long long x2; })sparseTileSizeWithTextureType:(unsigned long long)type pixelFormat:(unsigned long long)format sampleCount:(unsigned long long)count;
- (struct { unsigned long long x0; unsigned long long x1; unsigned long long x2; })sparseTileSizeWithTextureType:(unsigned long long)type pixelFormat:(unsigned long long)format sampleCount:(unsigned long long)count sparsePageSize:(long long)size;
- (_Bool)supportsVertexAmplificationCount:(unsigned long long)count;
```

### MTLDeviceSPI: 42 selectors

```objc
- (id)copyIOSurfaceSharedTextureProperties:(id)properties;
- (unsigned long long)dedicatedMemorySize;
- (unsigned long long)doubleFPConfig;
- (unsigned long long)featureProfile;
- (unsigned long long)halfFPConfig;
- (id)indirectArgumentBufferDecodingData;
- (_Bool)mapShaderSampleBufferWithBuffer:(struct { unsigned int x0; unsigned int x1; unsigned int x2; } *)buffer capacity:(unsigned long long)capacity size:(unsigned long long)size;
- (_Bool)metalAssertionsEnabled;
- (id)newBufferWithBytes:(const void *)bytes length:(unsigned long long)length options:(unsigned long long)options gpuAddress:(unsigned long long)address;
- (id)newBufferWithBytesNoCopy:(void *)copy length:(unsigned long long)length options:(unsigned long long)options gpuAddress:(unsigned long long)address deallocator:(id /* block */)deallocator;
- (id)newBufferWithDescriptor:(id)descriptor;
- (id)newBufferWithIOSurface:(struct __IOSurface *)iosurface;
- (id)newBufferWithLength:(unsigned long long)length options:(unsigned long long)options gpuAddress:(unsigned long long)address;
- (id)newIndirectArgumentBufferLayoutWithStructType:(id)type;
- (id)newIndirectArgumentEncoderWithArguments:(id)arguments;
- (id)newIndirectArgumentEncoderWithLayout:(id)layout;
- (id)newIndirectCommandBufferWithDescriptor:(id)descriptor maxCount:(unsigned long long)count options:(unsigned long long)options;
- (id)newIndirectComputeCommandEncoderWithBuffer:(id)buffer;
- (id)newIndirectRenderCommandEncoderWithBuffer:(id)buffer;
- (id)newIntersectionFunctionTableWithDescriptor:(id)descriptor;
- (id)newLibraryWithCIFiltersForComputePipeline:(id)pipeline imageFilterFunctionInfo:(const struct { _Bool x0; unsigned long long x1; void * /* struct */ x2; } *)info error:(id *)error;
- (id)newLibraryWithGraphs:(id)graphs functions:(id)functions error:(id *)error;
- (id)newLibraryWithGraphsSPI:(id)spi functions:(id)functions error:(id *)error;
- (void)newRenderPipelineStateWithTileDescriptor:(id)descriptor completionHandler:(id /* block */)handler;
- (id)newRenderPipelineStateWithTileDescriptor:(id)descriptor error:(id *)error;
- (id)newResourceGroupFromResources:(const id *)resources count:(unsigned long long)count;
- (id)newTextureLayoutWithDescriptor:(id)descriptor isHeapOrBufferBacked:(_Bool)backed;
- (id)newTextureWithBytesNoCopy:(void *)copy length:(unsigned long long)length descriptor:(id)descriptor deallocator:(id /* block */)deallocator;
- (id)newTextureWithDescriptor:(id)descriptor iosurface:(struct __IOSurface *)iosurface plane:(unsigned long long)plane;
- (id)newVisibleFunctionTableWithDescriptor:(id)descriptor;
- (_Bool)reserveGPUAddressRange:(struct _NSRange { unsigned long long x0; unsigned long long x1; })range;
- (void)reserveResourceIndicesForResourceType:(unsigned long long)type indices:(unsigned long long *)indices indexCount:(unsigned long long)count;
- (unsigned long long)resourcePatchingTypeForResourceType:(unsigned long long)type;
- (void)setIndirectArgumentBufferDecodingData:(id)data;
- (void)setMetalAssertionsEnabled:(_Bool)enabled;
- (void)setupMPSFunctionTable:(struct MPSFunctionTable *)table;
- (unsigned long long)sharedMemorySize;
- (unsigned long long)singleFPConfig;
- (_Bool)supportPriorityBand;
- (_Bool)supportsSampleCount:(unsigned long long)count;
- (struct { unsigned long long x0; unsigned long long x1; unsigned long long x2; })tileSizeWithSparsePageSize:(long long)size textureType:(unsigned long long)type pixelFormat:(unsigned long long)format sampleCount:(unsigned long long)count;
- (void)unmapShaderSampleBuffer;
```

## Unsupported behavior

Resource factories must return nil (and a concrete error when an error pointer
exists) for unsupported descriptors. Completion-handler factories must invoke
the handler once with an error. Sparse/heap sizing must return a zero structure
when unavailable. An unsupported GPU-address reservation returns NO; never
invent a GPU address. Queries do not establish support for rendering arbitrary
iOS shader programs. Successful device-array insertion and actual command
execution are separate device observations.

## Static evidence locations

Addresses in the staged iOS 16.7.16 Metal image:

- `MTLAddDevice`: 0x181a1b368.
- `_MTLDevice initLimits`: 0x181a1b4bc.
- `_MTLDevice initFeatureQueries`: 0x181a1bd38.
- `_MTLDeviceFeatureQueries initWithDevice:`: 0x181a1c070.
- `_MTLDeviceFeatureQueries validate`: 0x181a1ea24 (returns directly).
- `_MTLDevice initGPUFamilySupport`: 0x181a1ea28.
- `_MTLDevice init`: 0x181a3634c.
- `_MTLDevice initWithAcceleratorPort:`: 0x181aab968 (abstract).
- `_MTLDevice dealloc`: 0x181aab9d8.
- `MTLDeviceFeatureQueries initWithDevice:`: 0x181b24c74 (returns nil).
- `MTLDeviceFeatureQueries familySupportsBufferlessClientStorageTexture`:
  0x181b25214 (reads zero-initialized BOOL storage).

The selected REA deep provider was unavailable in this session. The call order
was verified with local LLVM disassembly; protocol declarations were decoded
with the installed `ipsw --verbose dyld macho --objc` parser against the supplied
cache. The checked header was syntax-compiled with arm64 iOS 16 ARC and warnings
as errors. No phone-side acceptance or arbitrary shader-render result is implied.
