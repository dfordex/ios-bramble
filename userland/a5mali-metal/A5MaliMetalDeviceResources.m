/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#import <objc/runtime.h>
#include <string.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <stdio.h>
#include <math.h>

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
@property (nonatomic) NSUInteger sharedBytes;
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
NSUInteger A5MaliAllocatedSharedReadBufferBytes(A5MaliRestrictedDevice *device)
{
    A5MaliResourceAccounting *state = accounting(device);
    @synchronized (state) { return state.sharedBytes; }
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
    /* This size query describes pinned private BOs. Shared buffers instead
     * snapshot their actual CPU bytes at submission; no mmap is fabricated. */
    if (!length || length > A5MaliMaxPrivateBufferLength ||
        options != MTLResourceStorageModePrivate)
        return (MTLSizeAndAlign){0, 0};
    return (MTLSizeAndAlign){(length + 4095) & ~(NSUInteger)4095, 4096};
}
MTLSizeAndAlign A5MaliBGRA8TextureSizeAndAlign(MTLTextureDescriptor *d)
{
    A5MaliTextureAllocationLayout layout;
    if(!A5MaliBuildTextureAllocationLayout(d,&layout,NULL)||d.storageMode==MTLStorageModeMemoryless)
        return (MTLSizeAndAlign){0,0};
    return (MTLSizeAndAlign){(layout.totalBytes+4095)&~(NSUInteger)4095,4096};
}

@interface A5MaliPrivateBuffer () {
    A5MaliRestrictedDevice *_device;
    A5MaliDevice *_privateDevice;
    A5MaliResourceAccounting *_accounting;
    NSUInteger _length, _allocatedSize;
    uint64_t _handle;
    NSLock *_transferLock;
    atomic_bool _readyForRead;
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
    _readyForRead = YES;
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
- (BOOL)readyForRead
{
    /* A command owns the device lock while checking this flag. Taking the
     * transfer lock here would invert upload's transfer -> device lock order. */
    return _handle && atomic_load_explicit(&_readyForRead,memory_order_acquire);
}
- (void *)contents { return NULL; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
    offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow
{ return (id)[A5MaliMetalTexture newBufferTextureWithBuffer:self descriptor:descriptor
    offset:offset bytesPerRow:bytesPerRow bytesPerImage:0]; }
- (id<MTLTexture>)newLinearTextureWithDescriptor:(MTLTextureDescriptor *)descriptor
    offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage
{ return (id)[A5MaliMetalTexture newBufferTextureWithBuffer:self descriptor:descriptor
    offset:offset bytesPerRow:bytesPerRow bytesPerImage:bytesPerImage]; }
- (kern_return_t)transferBytes:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length write:(BOOL)write
{
    if (!bytes || !length || offset > _length || length > _length - offset)
        return kIOReturnBadArgument;
    [_transferLock lock];
    BOOL wasReady=atomic_load_explicit(&_readyForRead,memory_order_acquire);
    if(write)atomic_store_explicit(&_readyForRead,NO,memory_order_release);
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
    if (write) {
        BOOL complete=result==KERN_SUCCESS && (wasReady || (!offset && length==_length));
        atomic_store_explicit(&_readyForRead,complete,memory_order_release);
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
- (kern_return_t)readBytesForSubmission:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length client:(A5MaliClient *)client
{
    if (!bytes || !length || !self.readyForRead || offset>_length || length>_length-offset ||
        client!=[_privateDevice client] || !hasSelector(client,ReadBuffer))return kIOReturnBadArgument;
    /* The device lock already serializes transport. Taking _transferLock here
     * would invert the public upload's transferLock -> deviceLock ordering. */
    for(NSUInteger done=0;done<length;){
        NSUInteger count=MIN((NSUInteger)TransferMax,length-done);
        TransferRequest request={.h=wireHeader(sizeof(request)),.handle=_handle,
            .offset=(uint32_t)(offset+done),.length=(uint32_t)count};
        ReadReply reply={0};size_t actual=sizeof(reply);
        kern_return_t status=client->call(client->context,ReadBuffer,&request,sizeof(request),&reply,&actual);
        if(status)return status;
        if(!validHeader(reply.h,sizeof(reply),actual)||reply.reserved||reply.length!=count)
            return kIOReturnBadArgument;
        memcpy((uint8_t *)bytes+done,reply.bytes,count);done+=count;
    }
    return KERN_SUCCESS;
}
@end

@interface A5MaliSharedReadBuffer ()
- (nullable instancetype)initSharedWithDevice:(A5MaliRestrictedDevice *)device
    length:(NSUInteger)length;
- (nullable instancetype)initNoCopyWithDevice:(A5MaliRestrictedDevice *)device
    bytes:(void *)bytes length:(NSUInteger)length
    deallocator:(nullable void (^)(void *,NSUInteger))deallocator;
@end
@implementation A5MaliSharedReadBuffer {
    A5MaliRestrictedDevice *_sharedDevice;
    A5MaliResourceAccounting *_sharedAccounting;
    NSLock *_sharedLock;
    void *_sharedContents;
    NSUInteger _sharedLength, _sharedAllocation;
    BOOL _sharedExternal;
    void (^_sharedDeallocator)(void *,NSUInteger);
}
- (instancetype)initSharedWithDevice:(A5MaliRestrictedDevice *)device length:(NSUInteger)length
{
    if (!device || !length || length > A5MaliMaxPrivateBufferLength ||
        !(self = [super init])) return nil;
    NSUInteger allocation = (length + 4095) & ~(NSUInteger)4095;
    A5MaliResourceAccounting *state = accounting(device);
    @synchronized (state) {
        /* Read staging is bounded separately from the four pinned kernel BOs. */
        if (state.sharedBytes > 64 * 1024 * 1024 - allocation) return nil;
        void *pointer = NULL;
        if (posix_memalign(&pointer, 4096, allocation)) return nil;
        memset(pointer, 0, allocation);
        state.sharedBytes += allocation;
        _sharedContents = pointer;
    }
    _sharedDevice = device; _sharedAccounting = state;
    _sharedLength = length; _sharedAllocation = allocation;
    _sharedLock = [NSLock new];
    return self;
}
- (instancetype)initNoCopyWithDevice:(A5MaliRestrictedDevice *)device
    bytes:(void *)bytes length:(NSUInteger)length
    deallocator:(void (^)(void *,NSUInteger))deallocator
{
    if(!device||!bytes||!length||length>A5MaliMaxPrivateBufferLength||
        ((uintptr_t)bytes&(A5MaliBufferPageSize-1))||
        (length&(A5MaliBufferPageSize-1))||(uintptr_t)bytes>UINTPTR_MAX-length||
        ![[device privateDevice] supportsNativePrograms]||!(self=[super init]))return nil;
    NSLock *lock=[NSLock new];if(!lock)return nil;
    /* Copy the block before taking ownership/accounting. A failed creation
     * never invokes it or frees caller memory. No caller byte is read here. */
    void (^releaseBytes)(void *,NSUInteger)=[deallocator copy];
    A5MaliResourceAccounting *state=accounting(device);
    @synchronized(state){
        if(state.sharedBytes>64*1024*1024-length)return nil;
        state.sharedBytes+=length;
    }
    _sharedDevice=device;_sharedAccounting=state;_sharedLock=lock;
    _sharedLength=length;_sharedAllocation=length;_sharedExternal=YES;
    _sharedDeallocator=releaseBytes;_sharedContents=bytes;
    return self;
}
- (void)dealloc
{
    if (_sharedContents) {
        void *bytes=_sharedContents;
        void (^deallocator)(void *,NSUInteger)=_sharedDeallocator;
        _sharedContents=NULL;_sharedDeallocator=nil;
        @synchronized (_sharedAccounting) { _sharedAccounting.sharedBytes -= _sharedAllocation; }
        /* Never call caller code while holding accounting/transfer locks.
         * The device remains retained through the callback's lifetime. */
        if(_sharedExternal){if(deallocator)deallocator(bytes,_sharedLength);}
        else free(bytes);
    }
}
- (A5MaliRestrictedDevice *)device { return _sharedDevice; }
- (NSUInteger)length { return _sharedLength; }
- (NSUInteger)allocatedSize { return _sharedAllocation; }
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModeShared; }
- (uint64_t)privateKernelHandle { return 0; }
- (BOOL)readyForRead { return _sharedContents != NULL; }
- (void *)contents { return _sharedContents; }
- (kern_return_t)sharedTransfer:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length write:(BOOL)write
{
    if (!bytes || !length || offset > _sharedLength || length > _sharedLength - offset)
        return kIOReturnBadArgument;
    [_sharedLock lock];
    if (write) memcpy((uint8_t *)_sharedContents + offset, bytes, length);
    else memcpy(bytes, (uint8_t *)_sharedContents + offset, length);
    [_sharedLock unlock];
    return KERN_SUCCESS;
}
- (kern_return_t)uploadBytes:(const void *)bytes offset:(NSUInteger)offset length:(NSUInteger)length
{ return [self sharedTransfer:(void *)bytes offset:offset length:length write:YES]; }
- (kern_return_t)readBytes:(void *)bytes offset:(NSUInteger)offset length:(NSUInteger)length
{ return [self sharedTransfer:bytes offset:offset length:length write:NO]; }
- (kern_return_t)readBytesForSubmission:(void *)bytes offset:(NSUInteger)offset
    length:(NSUInteger)length client:(A5MaliClient *)client
{ (void)client;return [self sharedTransfer:bytes offset:offset length:length write:NO]; }
@end

static NSError *bindingError(kern_return_t status, NSString *message)
{
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.mali" code:status
        userInfo:@{NSLocalizedDescriptionKey: message}];
}
@implementation A5MaliBufferBinding {
    A5MaliRestrictedDevice *_device;
    A5MaliPrivateBuffer *_buffer;
    NSData *_bytes;
    NSUInteger _offset, _length;
}
+ (instancetype)bindingWithBuffer:(A5MaliPrivateBuffer *)buffer offset:(NSUInteger)offset
    length:(NSUInteger)length device:(A5MaliRestrictedDevice *)device error:(NSError **)error
{
    if (error) *error = nil;
    if (![buffer isKindOfClass:[A5MaliPrivateBuffer class]] || buffer.device != device ||
        !length || offset > buffer.length || length > buffer.length - offset ||
        !buffer.readyForRead) {
        if (error) *error = bindingError(kIOReturnBadArgument, @"invalid or unreadable same-device buffer range");
        return nil;
    }
    A5MaliBufferBinding *binding = [self new];
    binding->_device = device; binding->_buffer = buffer;
    binding->_offset = offset; binding->_length = length;
    return binding;
}
+ (instancetype)bindingWithBytes:(const void *)bytes length:(NSUInteger)length
    device:(A5MaliRestrictedDevice *)device error:(NSError **)error
{
    if (error) *error = nil;
    if (!bytes || !device || !length || length > 4096) {
        if (error) *error = bindingError(kIOReturnBadArgument, @"setBytes requires 1..4096 actual bytes");
        return nil;
    }
    A5MaliBufferBinding *binding = [self new];
    binding->_device = device; binding->_length = length;
    binding->_bytes = [NSData dataWithBytes:bytes length:length];
    return binding;
}
- (A5MaliRestrictedDevice *)device { return _device; }
- (A5MaliPrivateBuffer *)buffer { return _buffer; }
- (NSUInteger)offset { return _offset; }
- (NSUInteger)length { return _length; }
- (uint64_t)privateKernelHandle { return _buffer.privateKernelHandle; }
- (BOOL)inlineBytes { return _bytes != nil; }
- (NSData *)captureBytesForSubmission:(NSError **)error
{ return [self capturePrefixBytesForSubmission:_length error:error]; }
- (NSData *)capturePrefixBytesForSubmission:(NSUInteger)length error:(NSError **)error
{
    if (error) *error = nil;
    if (!length || length > _length) {
        if (error) *error = bindingError(kIOReturnBadArgument, @"submission window exceeds bound buffer bytes");
        return nil;
    }
    if (_bytes) return [_bytes subdataWithRange:NSMakeRange(0, length)];
    if (![_buffer isKindOfClass:[A5MaliSharedReadBuffer class]] || !_buffer.readyForRead) {
        if (error) *error = bindingError(kIOReturnUnsupported,
            @"private buffer bindings require the retained kernel handle and range");
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:length];
    kern_return_t result = [_buffer readBytes:data.mutableBytes offset:_offset length:length];
    if (result != KERN_SUCCESS) {
        if (error) *error = bindingError(result, @"shared read binding capture failed");
        return nil;
    }
    return [data copy];
}
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

static const char *samplerRejectionReason(MTLSamplerDescriptor *d)
{
    if(!d)return "nil-descriptor";
    if(d.minFilter!=MTLSamplerMinMagFilterNearest&&d.minFilter!=MTLSamplerMinMagFilterLinear)return "min-filter";
    if(d.magFilter!=MTLSamplerMinMagFilterNearest&&d.magFilter!=MTLSamplerMinMagFilterLinear)return "mag-filter";
    if(d.mipFilter!=MTLSamplerMipFilterNotMipmapped&&d.mipFilter!=MTLSamplerMipFilterNearest&&
        d.mipFilter!=MTLSamplerMipFilterLinear)return "mip-filter";
    if(d.maxAnisotropy!=1)return "anisotropy";
    if(d.sAddressMode!=MTLSamplerAddressModeClampToEdge||d.tAddressMode!=MTLSamplerAddressModeClampToEdge||
        d.rAddressMode!=MTLSamplerAddressModeClampToEdge)return "address-mode";
    if(!d.normalizedCoordinates)return "unnormalized-coordinates";
    if(d.compareFunction!=MTLCompareFunctionNever)return "compare-function";
    if(d.supportArgumentBuffers)return "argument-buffers";
    if(!isfinite(d.lodMinClamp)||!isfinite(d.lodMaxClamp)||d.lodMinClamp<0||d.lodMaxClamp<d.lodMinClamp)
        return "lod-range";
    return NULL;
}
static void logSamplerRejection(MTLSamplerDescriptor *d,const char *reason)
{
    static atomic_uint count;
    unsigned value=atomic_load_explicit(&count,memory_order_relaxed);
    do {if(value>=64)return;} while(!atomic_compare_exchange_weak_explicit(&count,&value,value+1,
        memory_order_relaxed,memory_order_relaxed));
    fprintf(stderr,"A5XELTE Metal sampler: rejected reason=%s min=%lu mag=%lu mip=%lu anisotropy=%lu address=%lu/%lu/%lu normalized=%u compare=%lu argument_buffers=%u lod_min=%g lod_max=%g\n",
        reason,(unsigned long)d.minFilter,(unsigned long)d.magFilter,(unsigned long)d.mipFilter,
        (unsigned long)d.maxAnisotropy,(unsigned long)d.sAddressMode,(unsigned long)d.tAddressMode,
        (unsigned long)d.rAddressMode,d.normalizedCoordinates,(unsigned long)d.compareFunction,
        d.supportArgumentBuffers,(double)d.lodMinClamp,(double)d.lodMaxClamp);
}

static BOOL noStencilOperation(MTLStencilDescriptor *stencil)
{
    return !stencil ||
        (stencil.stencilCompareFunction == MTLCompareFunctionAlways &&
         stencil.stencilFailureOperation == MTLStencilOperationKeep &&
         stencil.depthFailureOperation == MTLStencilOperationKeep &&
         stencil.depthStencilPassOperation == MTLStencilOperationKeep);
}

static void logBufferRejection(NSUInteger length,MTLResourceOptions options,const char *reason)
{
    static atomic_uint count;
    unsigned value=atomic_load_explicit(&count,memory_order_relaxed);
    do {if(value>=64)return;} while(!atomic_compare_exchange_weak_explicit(&count,&value,value+1,
        memory_order_relaxed,memory_order_relaxed));
    fprintf(stderr,"A5XELTE Metal buffer: rejected reason=%s length=%lu options=%lu\n",
        reason,(unsigned long)length,(unsigned long)options);
}
@implementation A5MaliRestrictedDevice (PrivateBufferResources)
- (A5MaliPrivateBuffer *)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
    A5MaliPrivateBuffer *buffer=options==MTLResourceStorageModeShared?
        [[A5MaliSharedReadBuffer alloc] initSharedWithDevice:self length:length]:
        [[A5MaliPrivateBuffer alloc] initWithDevice:self length:length options:options];
    if(!buffer)logBufferRejection(length,options,!length||length>A5MaliMaxPrivateBufferLength?
        "length":(options!=MTLResourceStorageModeShared&&options!=MTLResourceStorageModePrivate)?
        "options":"allocation-or-kernel-create");
    return buffer;
}
- (A5MaliPrivateBuffer *)newBufferWithBytes:(const void *)bytes length:(NSUInteger)length
    options:(MTLResourceOptions)options
{
    if (!bytes || options != MTLResourceStorageModeShared){
        logBufferRejection(length,options,!bytes?"nil-source":"bytes-require-shared");return nil;
    }
    A5MaliSharedReadBuffer *buffer = [[A5MaliSharedReadBuffer alloc]
        initSharedWithDevice:self length:length];
    BOOL uploaded=[buffer uploadBytes:bytes offset:0 length:length] == KERN_SUCCESS;
    if(!uploaded||!buffer)logBufferRejection(length,options,"shared-allocation-or-upload");
    return uploaded?buffer:nil;
}
- (A5MaliPrivateBuffer *)newBufferWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
    options:(MTLResourceOptions)options deallocator:(void (^)(void *, NSUInteger))deallocator
{
    if(options!=MTLResourceStorageModeShared){
        logBufferRejection(length,options,"no-copy-requires-shared-default-options");return nil;
    }
    A5MaliSharedReadBuffer *buffer=[[A5MaliSharedReadBuffer alloc]initNoCopyWithDevice:self
        bytes:bytes length:length deallocator:deallocator];
    if(!buffer)logBufferRejection(length,options,!bytes?"no-copy-nil-source":
        !length||length>A5MaliMaxPrivateBufferLength?"no-copy-length":
        ((uintptr_t)bytes&(A5MaliBufferPageSize-1))||(length&(A5MaliBufferPageSize-1))?"no-copy-page-alignment":
        (uintptr_t)bytes>UINTPTR_MAX-length?"no-copy-address-span":
        ![[self privateDevice] supportsNativePrograms]?"no-copy-native-queue-unavailable":"no-copy-accounting-or-allocation");
    return buffer;
}
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
    if (options == MTLResourceStorageModeShared && length &&
        length <= A5MaliMaxPrivateBufferLength)
        return (MTLSizeAndAlign){(length + 4095) & ~(NSUInteger)4095, 4096};
    return A5MaliPrivateBufferSizeAndAlign(length, options);
}
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)descriptor
{ return A5MaliBGRA8TextureSizeAndAlign(descriptor); }
- (A5MaliSamplerState *)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)d
{
    MTLSamplerDescriptor *snapshot=[d copy];
    const char *reason=samplerRejectionReason(snapshot);
    if(reason){logSamplerRejection(snapshot,reason);return nil;}
    /* Creation retains exact state. Individual native shader profiles still
     * decide which filter/mip/LOD states their compiled specialization admits. */
    return [[A5MaliSamplerState alloc] initWithDevice:self descriptor:snapshot];
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
