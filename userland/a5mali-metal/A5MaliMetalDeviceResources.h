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
- (nullable void *)contents;
/* Explicit driver transfers; no public shared contents pointer is fabricated.
 * A failure may follow earlier successful chunks; callers must discard failed
 * uploads rather than submit the partially updated resource. */
- (kern_return_t)uploadBytes:(const void * _Nullable)bytes offset:(NSUInteger)offset
                     length:(NSUInteger)length;
- (kern_return_t)readBytes:(void * _Nullable)bytes offset:(NSUInteger)offset
                   length:(NSUInteger)length;
- (nullable id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                           offset:(NSUInteger)offset
                                      bytesPerRow:(NSUInteger)bytesPerRow;
@end

/* CPU-visible storage for read-only shader bindings. It has a genuine contents
 * allocation, no invented GPU mapping/handle. Submission must capture and copy
 * it into the GPU job's retained resource storage immediately before executing.
 * GPU writes, no-copy ownership, and persistent GPU aliases are unsupported. */
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
@end
@interface A5MaliDepthStencilState : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, readonly, copy) NSString *label;
@property (nonatomic, readonly) MTLDepthStencilDescriptor *descriptor;
@end

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
- (nullable A5MaliPrivateBuffer *)newBufferWithBytesNoCopy:(void *)bytes
    length:(NSUInteger)length options:(MTLResourceOptions)options
    deallocator:(nullable void (^)(void *, NSUInteger))deallocator;
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length
                                         options:(MTLResourceOptions)options;
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (nullable A5MaliSamplerState *)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor;
- (nullable A5MaliDepthStencilState *)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor;
@end

NS_ASSUME_NONNULL_END
