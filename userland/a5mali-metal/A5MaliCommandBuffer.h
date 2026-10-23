/* SPDX-License-Identifier: MIT
 * Small iOS-side typed command list for the private Mali queue.
 * These classes intentionally do not claim MTLDevice/MTLCommandBuffer conformance.
 */
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import "A5MaliBridge.h"

NS_ASSUME_NONNULL_BEGIN

@class A5MaliSurface, A5MaliCommandBuffer, A5MaliCommandQueue;
/* Called exactly in encoded order under the device transport lock. Captured
 * resources stay retained until work has completed. Success requires real
 * nonzero GPU fences, not merely descriptor construction. */
typedef kern_return_t (^A5MaliNativeWork)(A5MaliClient *client, A5MaliFence *fence);

@interface A5MaliDevice : NSObject
- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)error;
- (nullable instancetype)initWithService:(io_service_t)service
                                  error:(NSError * _Nullable * _Nullable)error;
/* Injected transport is for a local harness; it never opens a device. */
- (nullable instancetype)initWithTransport:(A5MaliTransport)transport
                                   context:(void *)context
                         commandCapabilities:(uint32_t)commands
                        operationCapabilities:(uint32_t)operations;
- (nullable A5MaliSurface *)importSurface:(IOSurfaceRef)surface
                                    usage:(uint32_t)usage
                                    error:(NSError * _Nullable * _Nullable)error;
- (A5MaliCommandBuffer *)newCommandBuffer;
- (A5MaliCommandQueue *)newCommandQueue;
- (BOOL)supportsPrivateReadSurf;
- (BOOL)supportsNativePrograms;
#ifdef A5_MALI_HOST_TEST
- (A5MaliSurface *)hostTestSurfaceWithResource:(A5MaliResource)resource;
#endif
@end

@interface A5MaliCommandQueue : NSObject
- (A5MaliCommandBuffer *)newCommandBuffer;
@end

@interface A5MaliSurface : NSObject
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) uint32_t rowBytes;
@property (nonatomic, readonly) IOSurfaceRef iosurface;
@end

@interface A5MaliCommandBuffer : NSObject
- (BOOL)encodeClear:(A5MaliSurface *)destination
               rect:(A5MaliRect)rect
               bgra:(uint32_t)bgra;
- (BOOL)encodeCopy:(A5MaliSurface *)source
       sourceRect:(A5MaliRect)sourceRect
               to:(A5MaliSurface *)destination
  destinationRect:(A5MaliRect)destinationRect;
- (BOOL)encodeTexturedQuad:(A5MaliSurface *)source
               sourceRect:(A5MaliRect)sourceRect
                       to:(A5MaliSurface *)destination
          destinationRect:(A5MaliRect)destinationRect;
- (BOOL)encodeReadSurf:(A5MaliSurface *)source
                   to:(A5MaliSurface *)destination;
- (BOOL)encodeNativeWork:(A5MaliNativeWork)work;
/* 0151 completes each job synchronously; this call serializes and waits. */
- (BOOL)commitAndWait:(NSError * _Nullable * _Nullable)error;
@property (nonatomic, readonly) A5MaliFence completedFence;
/* Legacy batch/copy transports do not expose the native Submit18 outcome. */
- (BOOL)usesLegacyGPUWork;
@end

NS_ASSUME_NONNULL_END
