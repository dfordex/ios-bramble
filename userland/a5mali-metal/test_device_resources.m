/* SPDX-License-Identifier: MIT */
#import "A5MaliMetalDeviceResources.h"
#include <assert.h>
#include <string.h>

typedef struct { A5MaliHeader h; uint32_t bytes, usage; } CreateRequest;
typedef struct { A5MaliHeader h; uint64_t handle; uint32_t bytes, usage; } CreateReply;
typedef struct { A5MaliHeader h; uint64_t handle; } ReleaseRequest;
typedef struct {
    A5MaliHeader h; uint64_t handle; uint32_t offset, length;
    uint8_t bytes[256];
} TransferRequest;
typedef struct { A5MaliHeader h; uint32_t length, reserved; uint8_t bytes[256]; } ReadReply;
typedef struct {
    uint8_t data[8192];
    BOOL allocated, corruptCreate, corruptRead, failWrite;
    uint32_t creates, releases, writes, reads;
} Fake;
static kern_return_t transport(void *context, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    Fake *f = context;
    const A5MaliHeader *h = input;
    assert(h->version == 1 && h->size == inputSize && !h->reserved0 && !h->reserved1);
    if (selector == 8) {
        assert(inputSize == 24 && *outputSize == 32);
        const CreateRequest *r = input;
        assert(r->bytes == 8192 && r->usage == 3);
        ++f->creates;
        if (f->allocated) return kIOReturnNoResources;
        f->allocated = YES;
        memset(f->data, 0, sizeof(f->data));
        CreateReply result = {{1, 32, 0, 0}, 0x100000101ULL,
            r->bytes, r->usage};
        if (f->corruptCreate) result.bytes = 4096;
        memcpy(output, &result, sizeof(result));
        *outputSize = sizeof(result);
        return KERN_SUCCESS;
    }
    if (selector == 9) {
        assert(inputSize == 24 && !output && !*outputSize);
        assert(((const ReleaseRequest *)input)->handle == 0x100000101ULL);
        assert(f->allocated);
        f->allocated = NO;
        ++f->releases;
        return KERN_SUCCESS;
    }
    assert(selector == 14 || selector == 15);
    const TransferRequest *r = input;
    assert(inputSize == 288 && r->handle == 0x100000101ULL && f->allocated);
    assert(r->length && r->length <= 256 &&
        r->offset <= sizeof(f->data) && r->length <= sizeof(f->data) - r->offset);
    if (selector == 14) {
        ++f->writes;
        if (f->failWrite) return kIOReturnError;
        assert(!output && !*outputSize);
        memcpy(f->data + r->offset, r->bytes, r->length);
    } else {
        ++f->reads;
        assert(*outputSize == 280);
        ReadReply result = {{1, 280, 0, 0}, r->length, 0, {0}};
        memcpy(result.bytes, f->data + r->offset, r->length);
        if (f->corruptRead) result.length++;
        memcpy(output, &result, sizeof(result));
        *outputSize = sizeof(result);
    }
    return KERN_SUCCESS;
}

@interface ResourceDeviceFixture : A5MaliRestrictedDevice
- (instancetype)initWithFake:(Fake *)fake operations:(uint32_t)operations;
@end
@implementation ResourceDeviceFixture {
    A5MaliDevice *_fixture;
}
- (instancetype)initWithFake:(Fake *)fake operations:(uint32_t)operations
{
    if ((self = [super init]))
        _fixture = [[A5MaliDevice alloc] initWithTransport:transport context:fake
            commandCapabilities:15 operationCapabilities:operations];
    return self;
}
- (A5MaliDevice *)privateDevice { return _fixture; }
@end

int main(void)
{
    @autoreleasepool {
        Fake fake = {0};
        A5MaliRestrictedDevice *device = [[ResourceDeviceFixture alloc]
            initWithFake:&fake operations:32767];
        assert(![device newBufferWithLength:8191 options:MTLResourceStorageModeShared]);
        assert(![device newBufferWithLength:0 options:MTLResourceStorageModePrivate]);
        assert(![device newBufferWithLength:A5MaliMaxPrivateBufferLength + 1
            options:MTLResourceStorageModePrivate]);
        assert(![device newBufferWithLength:8191 options:
            MTLResourceStorageModePrivate | MTLResourceHazardTrackingModeUntracked]);
        assert(fake.creates == 0);
        @autoreleasepool {
            A5MaliPrivateBuffer *buffer = [device newBufferWithLength:8191
                options:MTLResourceStorageModePrivate];
            assert(buffer && buffer.length == 8191 && buffer.allocatedSize == 8192);
            assert(buffer.storageMode == MTLStorageModePrivate && !buffer.contents);
            assert(buffer.device == device && buffer.privateKernelHandle == 0x100000101ULL);
            assert(A5MaliAllocatedPrivateBufferBytes(device) == 8192);
            uint8_t input[777], output[777];
            for (NSUInteger i = 0; i < sizeof(input); ++i) input[i] = (uint8_t)(i * 37);
            assert([buffer uploadBytes:input offset:7000 length:sizeof(input)] == KERN_SUCCESS);
            assert(fake.writes == 4);
            assert([buffer readBytes:output offset:7000 length:sizeof(output)] == KERN_SUCCESS);
            assert(fake.reads == 4 && !memcmp(input, output, sizeof(input)));
            assert([buffer uploadBytes:input offset:NSUIntegerMax length:1] == kIOReturnBadArgument);
            assert([buffer readBytes:output offset:8190 length:2] == kIOReturnBadArgument);
            assert([buffer uploadBytes:NULL offset:0 length:1] == kIOReturnBadArgument);
            assert(fake.writes == 4 && fake.reads == 4);
            fake.corruptRead = YES;
            memset(output, 0xa5, sizeof(output));
            assert([buffer readBytes:output offset:0 length:1] == kIOReturnBadArgument);
            assert(output[0] == 0xa5);
            fake.corruptRead = NO;
            fake.failWrite = YES;
            assert([buffer uploadBytes:input offset:0 length:1] == kIOReturnError);
            fake.failWrite = NO;
            assert(![buffer newTextureWithDescriptor:[MTLTextureDescriptor new]
                offset:0 bytesPerRow:256]);
            buffer = nil;
        }
        assert(fake.releases == 1 && !fake.allocated &&
            A5MaliAllocatedPrivateBufferBytes(device) == 0);
        fake.corruptCreate = YES;
        assert(![device newBufferWithLength:8191 options:MTLResourceStorageModePrivate]);
        assert(fake.releases == 2 && !fake.allocated);
        A5MaliRestrictedDevice *oldKernel = [[ResourceDeviceFixture alloc]
            initWithFake:&fake operations:127];
        assert(![oldKernel newBufferWithLength:8191 options:MTLResourceStorageModePrivate]);
        assert(fake.creates == 2);
        uint8_t bytes[1] = {0};
        assert(![device newBufferWithBytes:bytes length:1 options:MTLResourceStorageModePrivate]);
        __block BOOL deallocated = NO;
        assert(![device newBufferWithBytesNoCopy:bytes length:1 options:0
            deallocator:^(void *pointer, NSUInteger length) {
                (void)pointer; (void)length; deallocated = YES;
            }]);
        assert(!deallocated);

        MTLSizeAndAlign size = [device heapBufferSizeAndAlignWithLength:4097
            options:MTLResourceStorageModePrivate];
        assert(size.size == 8192 && size.align == 4096);
        MTLTextureDescriptor *texture = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:1080 height:1920 mipmapped:NO];
        texture.storageMode = MTLStorageModeShared;
        texture.usage = MTLTextureUsageShaderRead;
        size = [device heapTextureSizeAndAlignWithDescriptor:texture];
        assert(size.size == 8294400 && size.align == 4096);
        texture.pixelFormat = MTLPixelFormatRGBA16Float;
        assert(![device heapTextureSizeAndAlignWithDescriptor:texture].size);
        MTLSamplerDescriptor *sampler = [MTLSamplerDescriptor new];
        sampler.label = @"immutable sampler";
        A5MaliSamplerState *state = [device newSamplerStateWithDescriptor:sampler];
        assert(state && [state.label isEqualToString:@"immutable sampler"]);
        sampler.minFilter = MTLSamplerMinMagFilterLinear;
        assert(state.descriptor.minFilter == MTLSamplerMinMagFilterNearest);
        assert(![device newSamplerStateWithDescriptor:sampler]);
        MTLDepthStencilDescriptor *depth = [MTLDepthStencilDescriptor new];
        A5MaliDepthStencilState *depthState = [device newDepthStencilStateWithDescriptor:depth];
        assert(depthState);
        depth.depthWriteEnabled = YES;
        assert(!depthState.descriptor.depthWriteEnabled);
        assert(![device newDepthStencilStateWithDescriptor:depth]);
    }
    puts("device resources: private ABI, bounds, transfer errors, cleanup and unsupported paths passed");
    return 0;
}
