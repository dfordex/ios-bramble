/* SPDX-License-Identifier: MIT */
#import "A5MaliRestrictedDevice.h"

NS_ASSUME_NONNULL_BEGIN

enum { A5MaliMaxPrivateBufferLength = 0x100000,
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
