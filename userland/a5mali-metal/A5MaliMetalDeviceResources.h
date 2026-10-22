/* SPDX-License-Identifier: MIT */
#import "A5MaliRestrictedDevice.h"

NS_ASSUME_NONNULL_BEGIN

enum { A5MaliMaxPrivateBufferLength = 0x800000,
       A5MaliPrivateBufferSlots = 4, A5MaliBufferPageSize = 4096 };

/* Kernel0155 allocates pinned private buffers, not user-mappable shared
 * memory. These objects do not imply general shader buffer binding support. */
@interface A5MaliPrivateBuffer : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly) NSUInteger allocatedSize;
@property (nonatomic, readonly) MTLStorageMode storageMode;
@property (nonatomic, readonly) MTLCPUCacheMode cpuCacheMode;
@property (nonatomic, readonly) MTLHazardTrackingMode hazardTrackingMode;
@property (nonatomic, readonly) MTLResourceOptions resourceOptions;
@property (nonatomic, readonly) uint64_t privateKernelHandle;
/* A failed, partially completed private upload must not be read by a draw. */
@property (nonatomic, readonly) BOOL readyForRead;
@property (nullable, copy, atomic) NSString *label;
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state;
@property (nullable, nonatomic, readonly) id<MTLHeap> heap;
@property (nonatomic, readonly) NSUInteger heapOffset;
- (BOOL)isAliasable;
- (void)makeAliasable;
/* No stable GPU virtual address/argument-buffer ABI is exported. */
@property (nonatomic, readonly) MTLGPUAddress gpuAddress;
/* Audited iOS16 ResourceSPI. Completion/opaque IDs have no exported backend
 * contract: isComplete reports NO, waiting raises, allocationID is invalid0. */
@property (nonatomic, readonly) uint64_t allocationID,protectionOptions,unfilteredResourceOptions;
@property (nonatomic) int responsibleProcess;
- (BOOL)isPurgeable;
- (BOOL)isComplete;
- (void)waitUntilComplete;
- (BOOL)doesAliasResource:(id)resource;
- (BOOL)doesAliasAnyResources:(id _Nonnull __unsafe_unretained const * _Nullable)resources count:(NSUInteger)count;
- (BOOL)doesAliasAllResources:(id _Nonnull __unsafe_unretained const * _Nullable)resources count:(NSUInteger)count;
- (kern_return_t)setOwnerWithIdentity:(uint32_t)identity;
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range;
- (void)removeAllDebugMarkers;
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *debugMarkers;
- (void)didModifyRange:(NSRange)range;
- (nullable void *)contents;
/* Explicit driver transfers; no public shared contents pointer is fabricated.
 * A failure may follow earlier successful chunks; callers must discard failed
 * uploads rather than submit the partially updated resource. */
- (kern_return_t)uploadBytes:(const void * _Nullable)bytes offset:(NSUInteger)offset
                     length:(NSUInteger)length;
- (kern_return_t)readBytes:(void * _Nullable)bytes offset:(NSUInteger)offset
                   length:(NSUInteger)length;
/* Internal submission path: caller already holds the device connection lock.
 * Do not reacquire it through the public transfer API. Kernel transfers stay
 * serialized with uploads and all jobs on this connection. */
- (kern_return_t)readBytesForSubmission:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length client:(A5MaliClient *)client;
- (nullable id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                           offset:(NSUInteger)offset
                                      bytesPerRow:(NSUInteger)bytesPerRow;
/* iOS16 linear-texture SPI uses the same retained, real buffer alias as the
 * public method. Only Shared single-level read textures are currently bound. */
- (nullable id<MTLTexture>)newLinearTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
    offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow
    bytesPerImage:(NSUInteger)bytesPerImage;
@end

/* CPU-visible storage for read-only shader bindings. It owns an allocation or
 * genuinely aliases the caller's page-aligned no-copy allocation. Submission
 * snapshots current bytes into retained GPU job storage immediately before
 * execution; there is no upfront no-copy substitute or persistent GPU alias.
 * A no-copy deallocator runs once after the last buffer/binding/job releases
 * the object. With a nil deallocator the caller retains allocation ownership.
 * The caller must keep no-copy pages mapped and accessible until that point. */
@interface A5MaliSharedReadBuffer : A5MaliPrivateBuffer
@end

/* A retained buffer/range binding, distinct from an inline setBytes copy.
 * Buffer contents are captured at submission, so CPU writes before commit are
 * visible. setBytes owns an immediate immutable copy instead. Private handles
 * remain kernel handles; no userland GPU address is exposed or fabricated. */
@interface A5MaliBufferBinding : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, nonatomic, readonly) A5MaliPrivateBuffer *buffer;
@property (nonatomic, readonly) NSUInteger offset, length;
@property (nonatomic, readonly) uint64_t privateKernelHandle;
@property (nonatomic, readonly) BOOL inlineBytes;
+ (nullable instancetype)bindingWithBuffer:(A5MaliPrivateBuffer *)buffer
    offset:(NSUInteger)offset length:(NSUInteger)length
    device:(A5MaliRestrictedDevice *)device error:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)bindingWithBytes:(const void *)bytes length:(NSUInteger)length
    device:(A5MaliRestrictedDevice *)device error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)captureBytesForSubmission:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)capturePrefixBytesForSubmission:(NSUInteger)length
    error:(NSError * _Nullable * _Nullable)error;
@end

/* Immutable state values for the one existing no-depth, nearest/clamp shader
 * profile. Creation is not evidence that a render encoder can bind the state. */
@interface A5MaliSamplerState : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, readonly, copy) NSString *label;
@property (nonatomic, readonly) MTLSamplerDescriptor *descriptor;
/* Zero: no permanent argument-buffer identity is exported by this backend. */
@property (nonatomic, readonly) MTLResourceID gpuResourceID;
@property (nonatomic, readonly) MTLPixelFormat pixelFormat;
@end
@interface A5MaliDepthStencilState : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, readonly, copy) NSString *label;
@property (nonatomic, readonly) MTLDepthStencilDescriptor *descriptor;
@property (nonatomic, readonly) BOOL readsDepth,writesDepth,readsStencil,writesStencil;
@end

/* Physical identity/range comparison shared by buffer and texture SPI. */
BOOL A5MaliResourcesAlias(id a,id b);

/* Valid sizes describe driver allocations, not heap allocation support. */
MTLSizeAndAlign A5MaliPrivateBufferSizeAndAlign(NSUInteger length,
    MTLResourceOptions options);
MTLSizeAndAlign A5MaliBGRA8TextureSizeAndAlign(MTLTextureDescriptor * _Nullable descriptor);
NSUInteger A5MaliAllocatedPrivateBufferBytes(A5MaliRestrictedDevice *device);
NSUInteger A5MaliAllocatedSharedReadBufferBytes(A5MaliRestrictedDevice *device);

@interface A5MaliRestrictedDevice (PrivateBufferResources)
- (nullable A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length
                                            options:(MTLResourceOptions)options;
- (nullable A5MaliPrivateBuffer *)newBufferWithBytes:(const void *)bytes
                                           length:(NSUInteger)length
                                          options:(MTLResourceOptions)options;
- (nullable A5MaliPrivateBuffer *)newBufferWithBytesNoCopy:(void * _Nullable)bytes
    length:(NSUInteger)length options:(MTLResourceOptions)options
    deallocator:(nullable void (^)(void *, NSUInteger))deallocator;
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length
                                         options:(MTLResourceOptions)options;
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (nullable A5MaliSamplerState *)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor;
- (nullable A5MaliDepthStencilState *)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor;
@end

NS_ASSUME_NONNULL_END
