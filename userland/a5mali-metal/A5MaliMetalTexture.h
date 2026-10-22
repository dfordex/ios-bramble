/* SPDX-License-Identifier: MIT
 * Logical Metal subresources over one real internal IOSurface allocation.
 * Neither the physical atlas nor a memoryless pass lease is a public surface.
 */
#import "A5MaliRestrictedDevice.h"
NS_ASSUME_NONNULL_BEGIN
enum { A5MaliTextureMaxMipLevels=13 };
typedef struct {
    uint32_t width,height,rowBytes,byteOffset,byteLength;
} A5MaliTextureLevelLayout;
typedef struct {
    uint32_t width,height,levelCount,bytesPerElement,totalBytes;
    uint32_t backingWidth,backingHeight,backingRowBytes;
    A5MaliTextureLevelLayout levels[A5MaliTextureMaxMipLevels];
} A5MaliTextureAllocationLayout;
NSUInteger A5MaliTexturePixelBytes(MTLPixelFormat format);
uint32_t A5MaliTexturePixelCode(MTLPixelFormat format);
BOOL A5MaliBuildTextureAllocationLayout(MTLTextureDescriptor *descriptor,
    A5MaliTextureAllocationLayout *layout,NSString * _Nullable * _Nullable reason);

/* A fresh memoryless render-pass allocation. The command buffer retains this
 * lease through its terminal fence, then invalidates it. It never belongs to
 * the texture object and must not be reused by another pass or sampled/blit. */
@interface A5MaliTexturePassBacking : NSObject
@property (nonatomic, readonly, nullable) A5MaliSurface *surface;
@property (nonatomic, readonly) A5MaliTextureLevelLayout layout;
@property (nonatomic, readonly) BOOL valid;
- (void)invalidateAfterCompletion;
@end
@interface A5MaliMetalTexture (ResourceLayout)
/* Buffer views retain this actual Shared allocation. Native submission must
 * read it at commit, map the resulting buffer span, then add bufferOffset.
 * They have no IOSurface; no independent texture allocation is substituted. */
@property (nonatomic, readonly, nullable) A5MaliPrivateBuffer *buffer;
@property (nonatomic, readonly) NSUInteger bufferOffset,bufferBytesPerRow,bufferBytesPerImage;
+ (nullable A5MaliMetalTexture *)newBufferTextureWithBuffer:(A5MaliPrivateBuffer *)buffer
    descriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset
    bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image;
/* Persistent backing is absent for memoryless textures. Map the whole actual
 * backing, then validate level.byteOffset/byteLength before GPUVA addition. */
- (nullable A5MaliSurface *)privateSurface;
@property (nonatomic, readonly, nullable) A5MaliTexturePassBacking *passBacking;
- (nullable A5MaliMetalTexture *)newRenderViewForLevel:(NSUInteger)level
    memorylessLease:(nullable A5MaliTexturePassBacking *)lease
    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)getLevelLayout:(A5MaliTextureLevelLayout *)layout level:(NSUInteger)level;
- (nullable A5MaliTexturePassBacking *)newMemorylessPassBackingForLevel:(NSUInteger)level
    error:(NSError * _Nullable * _Nullable)error;
/* The lease must originate from this exact texture and requested mip level. */
- (nullable A5MaliSurface *)surfaceForLevel:(NSUInteger)level
    memorylessLease:(nullable A5MaliTexturePassBacking *)lease;
@end
NS_ASSUME_NONNULL_END
