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
@class A5MaliMetalLibrary, A5MaliMetalFunction;
@class A5MaliPrivateBuffer, A5MaliSamplerState, A5MaliDepthStencilState;

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
- (instancetype)initWithTransport:(A5MaliTransport)transport context:(void *)context
             commandCapabilities:(uint32_t)commands operationCapabilities:(uint32_t)operations;
#endif
/* No shader compiler or general Midgard renderer is wired yet. */
- (nullable id)newPrivateRenderPipelineWithVertex:(NSString *)vertex
                                         fragment:(NSString *)fragment
                                            error:(NSError * _Nullable * _Nullable)error;
@end

/* A checked descriptor shape, not an MTLRenderPipelineState. */
@interface A5MaliReadSurfCandidate : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
/* No tile shader, indirect commands, or imageblock memory is compiled. */
@property (nonatomic, readonly) NSUInteger maxTotalThreadsPerThreadgroup;
@property (nonatomic, readonly) BOOL threadgroupSizeMatchesTileSize;
@property (nonatomic, readonly) NSUInteger imageblockSampleLength;
@property (nonatomic, readonly) BOOL supportIndirectCommandBuffers;
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)dimensions;
@property (nonatomic, readonly) NSUInteger maxTotalThreadsPerObjectThreadgroup;
@property (nonatomic, readonly) NSUInteger maxTotalThreadsPerMeshThreadgroup;
@property (nonatomic, readonly) NSUInteger objectThreadExecutionWidth;
@property (nonatomic, readonly) NSUInteger meshThreadExecutionWidth;
@property (nonatomic, readonly) NSUInteger maxTotalThreadgroupsPerMeshGrid;
@property (nonatomic, readonly) MTLResourceID gpuResourceID;
- (nullable id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)function stage:(MTLRenderStages)stage;
- (nullable id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)descriptor stage:(MTLRenderStages)stage;
- (nullable id<MTLIntersectionFunctionTable>)newIntersectionFunctionTableWithDescriptor:(MTLIntersectionFunctionTableDescriptor *)descriptor stage:(MTLRenderStages)stage;
- (nullable id<MTLRenderPipelineState>)newRenderPipelineStateWithAdditionalBinaryFunctions:(MTLRenderPipelineFunctionsDescriptor *)functions error:(NSError * _Nullable * _Nullable)error;
@end

/* A deliberately narrow public-selector slice. No Metal protocol is claimed. */
@interface A5MaliRestrictedDevice (LimitedMetalSelectors)
- (nullable A5MaliMetalQueue *)newCommandQueue;
/* Validation alone never creates an executable pipeline. */
- (nullable id)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor
                                               error:(NSError * _Nullable * _Nullable)error;

@end

@interface A5MaliRestrictedDevice (TextureResources)
- (nullable A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (nullable A5MaliMetalTexture *)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
                                                   iosurface:(IOSurfaceRef)surface
                                                       plane:(NSUInteger)plane;
#ifdef A5_MALI_HOST_TEST
- (A5MaliMetalTexture *)hostTestTextureWithResource:(A5MaliResource)resource;
#endif
@end

@interface A5MaliRestrictedDevice (ExactQuartzCoreLibrary)
- (nullable A5MaliMetalLibrary *)newDefaultLibraryWithBundle:(NSBundle *)bundle
                                                        error:(NSError * _Nullable * _Nullable)error;
- (nullable A5MaliMetalLibrary *)newLibraryWithURL:(NSURL *)url
                                              error:(NSError * _Nullable * _Nullable)error;
- (nullable A5MaliMetalLibrary *)newLibraryWithData:(dispatch_data_t)data
                                               error:(NSError * _Nullable * _Nullable)error;
@end

/* One authenticated QuartzCore metallib identity; no general AIR compiler. */
@interface A5MaliMetalLibrary : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
@property (nonatomic, readonly) NSArray<NSString *> *functionNames;
- (nullable A5MaliMetalFunction *)newFunctionWithName:(NSString *)name;
- (nullable A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
    constantValues:(nullable MTLFunctionConstantValues *)constants
    error:(NSError * _Nullable * _Nullable)error;
- (nullable A5MaliMetalFunction *)newFunctionWithDescriptor:
    (nullable MTLFunctionDescriptor *)descriptor
    error:(NSError * _Nullable * _Nullable)error;
- (void)newFunctionWithName:(NSString *)name
    constantValues:(nullable MTLFunctionConstantValues *)constants
    completionHandler:(nullable void (^)(id<MTLFunction> _Nullable,NSError * _Nullable))handler;
- (void)newFunctionWithDescriptor:(nullable MTLFunctionDescriptor *)descriptor
    completionHandler:(nullable void (^)(id<MTLFunction> _Nullable,NSError * _Nullable))handler;
@property (nonatomic, readonly) MTLLibraryType type;
@property (nonatomic, readonly, nullable) NSString *installName;
@end

@class A5MaliDynamicShaderCacheEntry;
@interface A5MaliMetalFunction : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) MTLFunctionType functionType;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nonatomic, readonly) A5MaliMetalLibrary *library;
@property (nonatomic, readonly) uint32_t specializationProfileID;
@property (nullable, nonatomic, readonly) A5MaliDynamicShaderCacheEntry *dynamicShader;
@property (nonatomic, readonly) MTLPatchType patchType;
@property (nonatomic, readonly) NSInteger patchControlPointCount;
@property (nonatomic, readonly) MTLFunctionOptions options;
@property (nonatomic, readonly, nullable) NSArray<MTLVertexAttribute *> *vertexAttributes;
@property (nonatomic, readonly, nullable) NSArray<MTLAttribute *> *stageInputAttributes;
@property (nonatomic, readonly) NSDictionary<NSString *,MTLFunctionConstant *> *functionConstantsDictionary;
- (nullable id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)index;
- (nullable id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex:(NSUInteger)index
    reflection:(id _Nullable * _Nullable)reflection;
/* Immutable source/typed-constant request, never an executable cache entry. */
@property (nullable, nonatomic, readonly) NSDictionary *compileRequestPayload;
@property (nullable, copy, atomic) NSString *label;
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
@property (nonatomic, readonly) NSUInteger depth;
@property (nonatomic, readonly) MTLPixelFormat pixelFormat;
@property (nonatomic, readonly) MTLTextureType textureType;
@property (nonatomic, readonly) MTLTextureSwizzleChannels swizzle;
@property (nonatomic, readonly) NSUInteger mipmapLevelCount;
@property (nonatomic, readonly) NSUInteger arrayLength;
@property (nonatomic, readonly) NSUInteger sampleCount;
@property (nonatomic, readonly) MTLTextureUsage usage;
@property (nonatomic, readonly) MTLStorageMode storageMode;
@property (nonatomic, readonly) IOSurfaceRef _Nullable iosurface;
@property (nonatomic, readonly) MTLResourceOptions resourceOptions;
@property (nonatomic, readonly) MTLCPUCacheMode cpuCacheMode;
@property (nonatomic, readonly) MTLHazardTrackingMode hazardTrackingMode;
@property (nonatomic, readonly) NSUInteger allocatedSize;
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level;
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)bytes bytesPerRow:(NSUInteger)row;
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void *)bytes bytesPerRow:(NSUInteger)row bytesPerImage:(NSUInteger)image;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
@end

@interface A5MaliMetalQueue : NSObject
@property (nullable, copy, atomic) NSString *label;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
- (A5MaliMetalBuffer *)commandBuffer;
- (nullable A5MaliMetalBuffer *)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor;
/* iOS16 QuartzCore configures and then releases both supplied queues. */
- (void)setSubmissionQueue:(nullable dispatch_queue_t)queue;
- (void)setCompletionQueue:(nullable dispatch_queue_t)queue;
- (nullable dispatch_queue_t)submissionQueue;
- (nullable dispatch_queue_t)completionQueue;
- (BOOL)setGPUPriority:(NSUInteger)priority;
- (BOOL)setBackgroundGPUPriority:(NSUInteger)priority;
- (A5MaliMetalBuffer *)commandBufferWithUnretainedReferences;
- (void)insertDebugCaptureBoundary;
@end

@interface A5MaliMetalBuffer : NSObject
@property (nullable, copy, atomic) NSString *label;
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nonatomic, readonly) A5MaliMetalQueue *commandQueue;
@property (nonatomic, readonly) MTLCommandBufferStatus status;
@property (nonatomic, readonly, nullable) NSError *error;
@property (nonatomic, readonly) BOOL retainedReferences;
@property (nonatomic, readonly) MTLCommandBufferErrorOption errorOptions;
@property (nonatomic, readonly, nullable) id<MTLLogContainer> logs;
@property (nonatomic, readonly) NSArray<NSString *> *debugSignposts;
/* iOS 16 QuartzCore SPI. Only unprotected command streams are supported. */
@property (nonatomic) uint64_t protectionOptions;
/* No hardware timestamp counter is exported by the current kernel ABI. */
@property (nonatomic, readonly) NSTimeInterval GPUStartTime;
@property (nonatomic, readonly) NSTimeInterval GPUEndTime;
@property (nonatomic, readonly) NSTimeInterval kernelStartTime;
@property (nonatomic, readonly) NSTimeInterval kernelEndTime;
- (nullable A5MaliMetalBlitEncoder *)blitCommandEncoder;
- (nullable A5MaliMetalBlitEncoder *)blitCommandEncoderWithDescriptor:(MTLBlitPassDescriptor *)descriptor;
- (nullable A5MaliMetalRenderEncoder *)renderCommandEncoderWithDescriptor:
    (MTLRenderPassDescriptor *)descriptor;
- (nullable id<MTLComputeCommandEncoder>)computeCommandEncoder;
- (nullable id<MTLComputeCommandEncoder>)computeCommandEncoderWithDescriptor:(MTLComputePassDescriptor *)descriptor;
- (nullable id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)dispatchType;
- (nullable id<MTLParallelRenderCommandEncoder>)parallelRenderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)descriptor;
- (nullable id<MTLResourceStateCommandEncoder>)resourceStateCommandEncoder;
- (nullable id<MTLResourceStateCommandEncoder>)resourceStateCommandEncoderWithDescriptor:(MTLResourceStatePassDescriptor *)descriptor;
- (nullable id<MTLAccelerationStructureCommandEncoder>)accelerationStructureCommandEncoder;
- (nullable id<MTLAccelerationStructureCommandEncoder>)accelerationStructureCommandEncoderWithDescriptor:(MTLAccelerationStructurePassDescriptor *)descriptor;
- (void)presentDrawable:(id<MTLDrawable>)drawable;
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)time;
- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration;
- (void)encodeWaitForEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)encodeSignalEvent:(id<MTLEvent>)event value:(uint64_t)value;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
- (void)enqueue;
- (void)commit;
- (void)waitUntilScheduled;
- (void)waitUntilCompleted;
- (void)addScheduledHandler:(MTLCommandBufferHandler)handler;
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler;
@end

@interface A5MaliMetalRenderEncoder : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
- (void)insertDebugSignpost:(NSString *)string;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
- (void)setCullMode:(MTLCullMode)mode;
- (void)setFrontFacingWinding:(MTLWinding)winding;
- (void)setTriangleFillMode:(MTLTriangleFillMode)mode;
- (void)setDepthClipMode:(MTLDepthClipMode)mode;
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp;
- (void)setDepthStencilState:(nullable A5MaliDepthStencilState *)state;
- (void)setStencilReferenceValue:(uint32_t)value;
- (void)setStencilFrontReferenceValue:(uint32_t)front backReferenceValue:(uint32_t)back;
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset;
- (void)setVertexBuffers:(A5MaliPrivateBuffer * _Nullable const * _Nonnull)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range;
- (void)setFragmentBuffers:(A5MaliPrivateBuffer * _Nullable const * _Nonnull)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range;
- (void)setFragmentTextures:(A5MaliMetalTexture * _Nullable const * _Nonnull)textures withRange:(NSRange)range;
- (void)setFragmentSamplerStates:(A5MaliSamplerState * _Nullable const * _Nonnull)samplers withRange:(NSRange)range;

- (void)setRenderPipelineState:(A5MaliReadSurfCandidate *)pipeline;
- (void)setFragmentTexture:(nullable A5MaliMetalTexture *)texture atIndex:(NSUInteger)index;
- (void)setVertexBuffer:(nullable A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setFragmentBuffer:(nullable A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index;
- (void)setVertexBytes:(const void * _Nullable)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setFragmentBytes:(const void * _Nullable)bytes length:(NSUInteger)length atIndex:(NSUInteger)index;
- (void)setFragmentSamplerState:(nullable A5MaliSamplerState *)sampler atIndex:(NSUInteger)index;
- (void)setScissorRect:(MTLScissorRect)rect;
- (void)setViewport:(MTLViewport)viewport;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType
          vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount;
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart
    vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)indexBufferOffset;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount;
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount
    indexType:(MTLIndexType)indexType indexBuffer:(A5MaliPrivateBuffer *)indexBuffer
    indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount
    baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance;
- (void)endEncoding;
- (nullable id)endEncodingAndRetrieveProgramAddressTable;
@end

/* GPU work is limited to validated BGRA texture copies. Mipmap generation
 * does no work only for a genuine same-device single-level texture; rejected
 * nil/multilevel resources fail the command buffer. Fixed-layout optimization
 * hints preserve the IOSurface layout. Buffer/fill/fence/indirect/counter and
 * managed-storage synchronization APIs set an explicit command-buffer error.
 * Required selector availability does not imply general blit/GPU support. */
@interface A5MaliMetalBlitEncoder : NSObject
@property (nonatomic, readonly) A5MaliRestrictedDevice *device;
@property (nullable, copy, atomic) NSString *label;
- (void)generateMipmapsForTexture:(A5MaliMetalTexture *)texture;
- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
              toTexture:(A5MaliMetalTexture *)destinationTexture;
- (void)copyFromTexture:(A5MaliMetalTexture *)sourceTexture
            sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel
              toTexture:(A5MaliMetalTexture *)destinationTexture
       destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel
             sliceCount:(NSUInteger)sliceCount levelCount:(NSUInteger)levelCount;
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture;
- (void)optimizeContentsForGPUAccess:(A5MaliMetalTexture *)texture
                              slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture;
- (void)optimizeContentsForCPUAccess:(A5MaliMetalTexture *)texture
                              slice:(NSUInteger)slice level:(NSUInteger)level;
- (void)insertDebugSignpost:(NSString *)string;
- (void)pushDebugGroup:(NSString *)string;
- (void)popDebugGroup;
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
- (nullable id)endEncodingAndRetrieveProgramAddressTable;
@end

NS_ASSUME_NONNULL_END
