/* SPDX-License-Identifier: MIT
 * Small iOS-side typed command list for the private Mali queue.
 * These classes intentionally do not claim MTLDevice/MTLCommandBuffer conformance.
 */
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import "A5MaliBridge.h"

NS_ASSUME_NONNULL_BEGIN

@class A5MaliSurface, A5MaliCommandBuffer;

@interface A5MaliDevice : NSObject
- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)error;
- (nullable A5MaliSurface *)importSurface:(IOSurfaceRef)surface
                                    usage:(uint32_t)usage
                                    error:(NSError * _Nullable * _Nullable)error;
- (A5MaliCommandBuffer *)newCommandBuffer;
@end

@interface A5MaliSurface : NSObject
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) uint32_t rowBytes;
@end

@interface A5MaliCommandBuffer : NSObject
- (BOOL)encodeClear:(A5MaliSurface *)destination
               rect:(A5MaliRect)rect
               bgra:(uint32_t)bgra;
- (BOOL)encodeCopy:(A5MaliSurface *)source
       sourceRect:(A5MaliRect)sourceRect
               to:(A5MaliSurface *)destination
  destinationRect:(A5MaliRect)destinationRect;
/* 0151 completes each job synchronously; this call serializes and waits. */
- (BOOL)commitAndWait:(NSError * _Nullable * _Nullable)error;
@property (nonatomic, readonly) A5MaliFence completedFence;
@end

NS_ASSUME_NONNULL_END
