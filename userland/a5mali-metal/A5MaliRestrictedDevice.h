/* SPDX-License-Identifier: MIT
 * Non-discoverable bridge to the private Metal superclass on iOS 16.
 * It deliberately declares no MTLDevice or MTLDeviceSPI conformance.
 */
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOSurface/IOSurfaceRef.h>
#import <Metal/Metal.h>
#import "A5MaliCommandBuffer.h"

NS_ASSUME_NONNULL_BEGIN

/* iOS 16.7.16 Metal exports this private superclass. This declaration is
 * limited to its ObjC inheritance relationship, observed in the staged OS.
 */
#ifdef A5_MALI_HOST_TEST
#define A5_MALI_DEVICE_SUPER NSObject
#else
@interface _MTLDevice : NSObject
@end
#define A5_MALI_DEVICE_SUPER _MTLDevice
#endif

@class A5MaliMetalQueue, A5MaliMetalTexture;
@class A5MaliMetalBuffer, A5MaliMetalBlitEncoder;
@class A5MaliReadSurfCandidate, A5MaliMetalRenderEncoder;

@interface A5MaliRestrictedDevice : A5_MALI_DEVICE_SUPER
/* The selector Metal calls after discovering a genuine IOAcceleratorES.
 * Today's private A5XELTEGPU is not one, so this class is never advertised.
 */
- (nullable instancetype)initWithAcceleratorPort:(io_service_t)service;
- (nullable A5MaliSurface *)importPrivateBGRA8Surface:(IOSurfaceRef)surface
                                                usage:(uint32_t)usage
                                                error:(NSError * _Nullable * _Nullable)error;
- (A5MaliCommandQueue *)newPrivateCommandQueue;
- (nullable A5MaliReadSurfCandidate *)newPrivateReadSurfCandidateWithDescriptor:
    (MTLRenderPipelineDescriptor *)descriptor;
#ifdef A5_MALI_HOST_TEST
- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context;
- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context
             commandCapabilities:(uint32_t)commands;
#endif
/* No shader compiler or general Midgard renderer is wired yet. */
- (nullable id)newPrivateRenderPipelineWithVertex:(NSString *)vertex
                                         fragment:(NSString *)fragment
                                            error:(NSError * _Nullable * _Nullable)error;
@end

/* A checked descriptor shape, not an MTLRenderPipelineState. */
@interface A5MaliReadSurfCandidate : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@end

/* A deliberately narrow public-selector slice. No Metal protocol is claimed. */
@interface A5MaliRestrictedDevice (LimitedMetalSelectors)
- (nullable A5MaliMetalQueue *)newCommandQueue;
- (nullable A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                                   iosurface:(IOSurfaceRef)surface
                                                       plane:(NSUInteger)plane;
/* Validation alone never creates an executable pipeline. */
- (nullable id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                               error:(NSError * _Nullable * _Nullable)error;
#ifdef A5_MALI_HOST_TEST
- (A5MaliMetalTexture *)hostTestTextureWithResource:(A5MaliResource)resource;
#endif
@end

typedef NS_ENUM(NSUInteger, A5MaliPipelineShape) {
    A5MaliPipelineShapeUnsupported = 0,
    A5MaliPipelineShapeReadSurfCandidate = 1,
};
/* Checks descriptor shape and function labels, not shader binary identity. */
A5MaliPipelineShape A5MaliInspectReadSurfPipelineDescriptor(
    MTLRenderPipelineDescriptor * _Nullable descriptor);

@interface A5MaliMetalTexture : NSObject
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) MTLPixelFormat pixelFormat;
@property (nonatomic, readonly) MTLTextureType textureType;
@property (nonatomic, readonly) NSUInteger mipmapLevelCount;
@property (nonatomic, readonly) NSUInteger arrayLength;
@property (nonatomic, readonly) NSUInteger sampleCount;
@property (nonatomic, readonly) MTLTextureUsage usage;
@property (nonatomic, readonly) MTLStorageMode storageMode;
@property (nonatomic, readonly) IOSurfaceRef iosurface;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
@end

@interface A5MaliMetalQueue : NSObject
@property (nullable, copy, atomic) NSString *label;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
- (A5MaliMetalBuffer *)commandBuffer;
- (A5MaliMetalBuffer *)commandBufferWithUnretainedReferences;
@end

@interface A5MaliMetalBuffer : NSObject
@property (nullable, copy, atomic) NSString *label;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nonatomic, readonly) A5MaliMetalQueue *commandQueue;
@property (nonatomic, readonly) MTLCommandBufferStatus status;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly) BOOL retainedReferences;
- (nullable A5MaliMetalBlitEncoder *)blitCommandEncoder;
- (nullable A5MaliMetalRenderEncoder *)renderCommandEncoderWithDescriptor:
    (MTLRenderPassDescriptor *)descriptor;
- (void)enqueue;
- (void)commit;
- (void)waitUntilScheduled;
- (void)waitUntilCompleted;
- (void)addScheduledHandler:(MTLCommandBufferHandler)handler;
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler;
@end

@interface A5MaliMetalRenderEncoder : NSObject
- (void)setRenderPipelineState:(A5MaliReadSurfCandidate *)pipeline;
- (void)setFragmentTexture:(A5MaliMetalTexture *)texture atIndex:(NSUInteger)index;
- (void)setViewport:(MTLViewport)viewport;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType
          vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount;
- (void)endEncoding;
@end

@interface A5MaliMetalBlitEncoder : NSObject
- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
            sourceSlice:(NSUInteger)sourceSlice
            sourceLevel:(NSUInteger)sourceLevel
           sourceOrigin:(MTLOrigin)sourceOrigin
             sourceSize:(MTLSize)sourceSize
              toTexture:(A5MaliMetalTexture *)destinationTexture
       destinationSlice:(NSUInteger)destinationSlice
       destinationLevel:(NSUInteger)destinationLevel
      destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)endEncoding;
@end

NS_ASSUME_NONNULL_END
