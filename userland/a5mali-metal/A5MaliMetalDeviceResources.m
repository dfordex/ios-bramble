/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalDeviceResources.h"
#import <objc/runtime.h>
#include <string.h>

enum { CreateBuffer = 8, ReleaseBuffer = 9, WriteBuffer = 14,
       ReadBuffer = 15, TransferMax = 256 };
typedef struct { A5MaliHeader h; uint32_t bytes, usage; } CreateRequest;
typedef struct { A5MaliHeader h; uint64_t handle; uint32_t bytes, usage; } CreateReply;
typedef struct { A5MaliHeader h; uint64_t handle; } ReleaseRequest;
typedef struct {
    A5MaliHeader h; uint64_t handle; uint32_t offset, length;
    uint8_t bytes[TransferMax];
} TransferRequest;
typedef struct {
    A5MaliHeader h; uint32_t length, reserved; uint8_t bytes[TransferMax];
} ReadReply;
_Static_assert(sizeof(CreateRequest) == 24 && sizeof(CreateReply) == 32,
    "kernel0155 create ABI");
_Static_assert(sizeof(TransferRequest) == 288 && sizeof(ReadReply) == 280,
    "kernel0155 transfer ABI");

@interface A5MaliRestrictedDevice (ResourcePrivateDevice)
- (A5MaliDevice *)privateDevice;
@end
@interface A5MaliDevice (ResourcePrivateClient)
- (A5MaliClient *)client;
- (NSLock *)lock;
@end

@interface A5MaliResourceAccounting : NSObject
@property (nonatomic) NSUInteger bytes;
@end
@implementation A5MaliResourceAccounting
@end
static char accountingKey;
static A5MaliResourceAccounting *accounting(A5MaliRestrictedDevice *device)
{
    @synchronized (device) {
        A5MaliResourceAccounting *result = objc_getAssociatedObject(device, &accountingKey);
        if (!result) {
            result = [A5MaliResourceAccounting new];
            objc_setAssociatedObject(device, &accountingKey, result,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return result;
    }
}
NSUInteger A5MaliAllocatedPrivateBufferBytes(A5MaliRestrictedDevice *device)
{
    A5MaliResourceAccounting *state = accounting(device);
    @synchronized (state) { return state.bytes; }
}

static A5MaliHeader wireHeader(NSUInteger size)
{ return (A5MaliHeader){A5MaliProtocolVersion, (uint32_t)size, 0, 0}; }
static BOOL validHeader(A5MaliHeader h, NSUInteger expected, NSUInteger actual)
{ return expected == actual && h.version == A5MaliProtocolVersion &&
    h.size == expected && !h.reserved0 && !h.reserved1; }
static BOOL hasSelector(A5MaliClient *client, uint32_t selector)
{ return client && client->call &&
    (client->supportedOperations & (1U << (selector - 1))) != 0; }
static kern_return_t call(A5MaliDevice *device, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    [[device lock] lock];
    A5MaliClient *client = [device client];
    size_t noOutput = 0;
    kern_return_t result = hasSelector(client, selector) ?
        client->call(client->context, selector, input, inputSize, output,
            outputSize ?: &noOutput) : kIOReturnUnsupported;
    [[device lock] unlock];
    return result;
}

MTLSizeAndAlign A5MaliPrivateBufferSizeAndAlign(NSUInteger length,
    MTLResourceOptions options)
{
    /* Shared storage and no-copy would require clientMemoryForType/mmap.
     * Hazard tracking is not exposed until buffers participate in draws. */
    if (!length || length > A5MaliMaxPrivateBufferLength ||
        options != MTLResourceStorageModePrivate)
        return (MTLSizeAndAlign){0, 0};
    return (MTLSizeAndAlign){(length + 4095) & ~(NSUInteger)4095, 4096};
}
MTLSizeAndAlign A5MaliBGRA8TextureSizeAndAlign(MTLTextureDescriptor *d)
{
    if (!d || d.textureType != MTLTextureType2D ||
        d.pixelFormat != MTLPixelFormatBGRA8Unorm || !d.width || !d.height ||
        d.width > 2048 || d.height > 2048 || d.depth != 1 ||
        d.mipmapLevelCount != 1 || d.arrayLength != 1 || d.sampleCount != 1 ||
        d.storageMode != MTLStorageModeShared || !d.usage ||
        (d.usage & ~(MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget)))
        return (MTLSizeAndAlign){0, 0};
    return (MTLSizeAndAlign){(d.width * d.height * 4 + 4095) & ~(NSUInteger)4095, 4096};
}

@interface A5MaliPrivateBuffer () {
    A5MaliRestrictedDevice *_device;
    A5MaliDevice *_privateDevice;
    A5MaliResourceAccounting *_accounting;
    NSUInteger _length, _allocatedSize;
    uint64_t _handle;
    NSLock *_transferLock;
}
- (nullable instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
    length:(NSUInteger)length options:(MTLResourceOptions)options;
@end

@implementation A5MaliPrivateBuffer
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device
    length:(NSUInteger)length options:(MTLResourceOptions)options
{
    MTLSizeAndAlign size = A5MaliPrivateBufferSizeAndAlign(length, options);
    if (!size.size || !(self = [super init])) return nil;
    _device = device;
    _privateDevice = [device privateDevice];
    if (!_privateDevice) return nil;
    A5MaliClient *client = [_privateDevice client];
    if (!hasSelector(client, CreateBuffer) || !hasSelector(client, ReleaseBuffer) ||
        !hasSelector(client, WriteBuffer) || !hasSelector(client, ReadBuffer))
        return nil;
    CreateRequest request = {wireHeader(sizeof(request)),
        (uint32_t)size.size, A5MaliRead | A5MaliWrite};
    CreateReply reply = {0};
    size_t actual = sizeof(reply);
    kern_return_t status = call(_privateDevice, CreateBuffer, &request,
        sizeof(request), &reply, &actual);
    if (status != KERN_SUCCESS) return nil;
    uint32_t low = (uint32_t)reply.handle;
    if (!validHeader(reply.h, sizeof(reply), actual) || !(reply.handle >> 32) ||
        low < 0x101 || low >= 0x101 + A5MaliPrivateBufferSlots ||
        reply.bytes != size.size || reply.usage != request.usage) {
        if (reply.handle) {
            ReleaseRequest release = {wireHeader(sizeof(release)), reply.handle};
            call(_privateDevice, ReleaseBuffer, &release, sizeof(release), NULL, NULL);
        }
        return nil;
    }
    _handle = reply.handle;
    _length = length;
    _allocatedSize = size.size;
    _transferLock = [NSLock new];
    _accounting = accounting(device);
    @synchronized (_accounting) { _accounting.bytes += size.size; }
    return self;
}
- (void)dealloc
{
    if (_handle) {
        ReleaseRequest request = {wireHeader(sizeof(request)), _handle};
        kern_return_t kr = call(_privateDevice, ReleaseBuffer, &request,
            sizeof(request), NULL, NULL);
        /* If the kernel retained a failed release, keep it counted. */
        if (kr == KERN_SUCCESS)
            @synchronized (_accounting) { _accounting.bytes -= _allocatedSize; }
    }
}
- (A5MaliRestrictedDevice *)device { return _device; }
- (NSUInteger)length { return _length; }
- (NSUInteger)allocatedSize { return _allocatedSize; }
- (MTLStorageMode)storageMode { return MTLStorageModePrivate; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModePrivate; }
- (uint64_t)privateKernelHandle { return _handle; }
- (void *)contents { return NULL; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
    offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow
{ (void)descriptor; (void)offset; (void)bytesPerRow; return nil; }
- (kern_return_t)transferBytes:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length write:(BOOL)write
{
    if (!bytes || !length || offset > _length || length > _length - offset)
        return kIOReturnBadArgument;
    [_transferLock lock];
    kern_return_t result = KERN_SUCCESS;
    for (NSUInteger done = 0; done < length; ) {
        NSUInteger count = MIN((NSUInteger)TransferMax, length - done);
        TransferRequest request = {0};
        request.h = wireHeader(sizeof(request));
        request.handle = _handle;
        request.offset = (uint32_t)(offset + done);
        request.length = (uint32_t)count;
        if (write) memcpy(request.bytes, (uint8_t *)bytes + done, count);
        ReadReply reply = {0};
        size_t actual = sizeof(reply);
        result = call(_privateDevice, write ? WriteBuffer : ReadBuffer,
            &request, sizeof(request), write ? NULL : &reply,
            write ? NULL : &actual);
        if (result != KERN_SUCCESS) break;
        if (!write) {
            if (!validHeader(reply.h, sizeof(reply), actual) ||
                reply.reserved || reply.length != count) {
                result = kIOReturnBadArgument;
                break;
            }
            memcpy((uint8_t *)bytes + done, reply.bytes, count);
        }
        done += count;
    }
    [_transferLock unlock];
    return result;
}
- (kern_return_t)uploadBytes:(const void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length
{ return [self transferBytes:(void *)bytes offset:offset length:length write:YES]; }
- (kern_return_t)readBytes:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length
{ return [self transferBytes:bytes offset:offset length:length write:NO]; }
@end

@interface A5MaliSamplerState ()
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device descriptor:(MTLSamplerDescriptor *)descriptor;
@end
@implementation A5MaliSamplerState {
    A5MaliRestrictedDevice *_device;
    MTLSamplerDescriptor *_descriptor;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device descriptor:(MTLSamplerDescriptor *)descriptor
{ if ((self = [super init])) { _device = device; _descriptor = [descriptor copy]; } return self; }
- (A5MaliRestrictedDevice *)device { return _device; }
- (NSString *)label { return _descriptor.label; }
- (MTLSamplerDescriptor *)descriptor { return [_descriptor copy]; }
@end
@interface A5MaliDepthStencilState ()
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device descriptor:(MTLDepthStencilDescriptor *)descriptor;
@end
@implementation A5MaliDepthStencilState {
    A5MaliRestrictedDevice *_device;
    MTLDepthStencilDescriptor *_descriptor;
}
- (instancetype)initWithDevice:(A5MaliRestrictedDevice *)device descriptor:(MTLDepthStencilDescriptor *)descriptor
{ if ((self = [super init])) { _device = device; _descriptor = [descriptor copy]; } return self; }
- (A5MaliRestrictedDevice *)device { return _device; }
- (NSString *)label { return _descriptor.label; }
- (MTLDepthStencilDescriptor *)descriptor { return [_descriptor copy]; }
@end

static BOOL noStencilOperation(MTLStencilDescriptor *stencil)
{
    return !stencil ||
        (stencil.stencilCompareFunction == MTLCompareFunctionAlways &&
         stencil.stencilFailureOperation == MTLStencilOperationKeep &&
         stencil.depthFailureOperation == MTLStencilOperationKeep &&
         stencil.depthStencilPassOperation == MTLStencilOperationKeep);
}

@implementation A5MaliRestrictedDevice (PrivateBufferResources)
- (A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{ return [[A5MaliPrivateBuffer alloc] initWithDevice:self length:length options:options]; }
- (A5MaliPrivateBuffer *)newBufferWithBytes:(const void *)bytes length:(NSUInteger)length
    options:(MTLResourceOptions)options
{
    /* The Metal bytes initializer requires CPU-accessible storage. */
    (void)bytes; (void)length; (void)options;
    return nil;
}
- (A5MaliPrivateBuffer *)newBufferWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
    options:(MTLResourceOptions)options deallocator:(void (^)(void *, NSUInteger))deallocator
{ (void)bytes; (void)length; (void)options; (void)deallocator; return nil; }
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{ return A5MaliPrivateBufferSizeAndAlign(length, options); }
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)descriptor
{ return A5MaliBGRA8TextureSizeAndAlign(descriptor); }
- (A5MaliSamplerState *)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)d
{
    if (!d || d.minFilter != MTLSamplerMinMagFilterNearest ||
        d.magFilter != MTLSamplerMinMagFilterNearest ||
        d.mipFilter != MTLSamplerMipFilterNotMipmapped || d.maxAnisotropy != 1 ||
        d.sAddressMode != MTLSamplerAddressModeClampToEdge ||
        d.tAddressMode != MTLSamplerAddressModeClampToEdge ||
        d.rAddressMode != MTLSamplerAddressModeClampToEdge ||
        !d.normalizedCoordinates || d.compareFunction != MTLCompareFunctionNever ||
        d.supportArgumentBuffers || d.lodMinClamp != 0)
        return nil;
    return [[A5MaliSamplerState alloc] initWithDevice:self descriptor:d];
}
- (A5MaliDepthStencilState *)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)d
{
    if (!d || d.depthCompareFunction != MTLCompareFunctionAlways ||
        d.depthWriteEnabled || !noStencilOperation(d.frontFaceStencil) ||
        !noStencilOperation(d.backFaceStencil))
        return nil;
    return [[A5MaliDepthStencilState alloc] initWithDevice:self descriptor:d];
}
@end
