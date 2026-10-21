/* SPDX-License-Identifier: MIT
 * Host-only Objective-C dispatch test with an injected IOKit transport.
 */
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import "A5MaliCommandBuffer.h"
#include <assert.h>
#include <string.h>

typedef struct { A5MaliHeader h; uint32_t port, usage; uint64_t reserved; } ImportRequest;
typedef struct { A5MaliHeader h; uint64_t handle; uint32_t width, height, rowBytes, format; } ImportReply;
typedef struct { A5MaliHeader h; uint64_t handle; } HandleRequest;
typedef struct { A5MaliHeader h; uint64_t token; uint32_t mappedBytes, flags; } MapReply;
typedef struct {
    uint32_t operation, color; uint64_t source, destination;
    A5MaliRect sourceRect, destinationRect;
} BatchCommand;
typedef struct { A5MaliHeader h; uint32_t count, reserved; BatchCommand commands[8]; } BatchRequest;
typedef struct { uint32_t status, reserved; uint64_t tilerFence, fragmentFence; } BatchItem;
typedef struct {
    A5MaliHeader h; uint32_t count, completedCount, failedIndex, reserved;
    BatchItem items[8];
} BatchReply;

typedef struct { uint32_t imports, batches, releases; } Fake;

static kern_return_t mock(void *context, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    Fake *fake = context;
    if (selector == A5MaliImport) {
        assert(inputSize == sizeof(ImportRequest));
        const ImportRequest *request = input;
        assert(request->port && request->usage);
        ImportReply reply = {{1, sizeof(reply), 0, 0},
            0x100000001ULL + fake->imports, 64, 64, 256, 0x42475241};
        assert(*outputSize == sizeof(reply));
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        fake->imports++;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliMap) {
        assert(inputSize == sizeof(HandleRequest));
        const HandleRequest *request = input;
        MapReply reply = {{1, sizeof(reply), 0, 0},
            request->handle, 16384, A5MaliRead | A5MaliWrite};
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        return KERN_SUCCESS;
    }
    if (selector == A5MaliBatchSubmit) {
        assert(inputSize == sizeof(BatchRequest));
        const BatchRequest *request = input;
        assert(request->count == 3);
        assert(request->commands[0].operation == A5MaliClearBGRA);
        assert(request->commands[1].operation == A5MaliCopyBGRA);
        assert(request->commands[2].operation ==
            A5MaliDrawTexturedQuadBGRA);
        BatchReply reply = {0};
        reply.h = (A5MaliHeader){1, sizeof(reply), 0, 0};
        reply.count = reply.completedCount = 3;
        reply.failedIndex = UINT32_MAX;
        for (unsigned i = 0; i < 3; ++i)
            reply.items[i].fragmentFence = 100 + i;
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        fake->batches++;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliUnmap || selector == A5MaliRelease) {
        assert(inputSize == sizeof(HandleRequest) && !output);
        if (selector == A5MaliRelease) fake->releases++;
        return KERN_SUCCESS;
    }
    assert(0 && "unexpected selector");
    return KERN_INVALID_ARGUMENT;
}

int main(void)
{
    @autoreleasepool {
        Fake fake = {0};
        A5MaliDevice *device = [[A5MaliDevice alloc]
            initWithTransport:mock context:&fake
            commandCapabilities:15 operationCapabilities:127];
        assert(device);
        NSError *error = nil;
        A5MaliSurface *source = [device hostTestSurfaceWithResource:
            (A5MaliResource){0x100000001ULL, 64, 64, 256, A5MaliRead}];
        A5MaliSurface *destination = [device hostTestSurfaceWithResource:
            (A5MaliResource){0x100000002ULL, 64, 64, 256, A5MaliWrite}];
        assert(source && destination && !error);
        A5MaliCommandQueue *queue = [device newCommandQueue];
        A5MaliCommandBuffer *buffer = [queue newCommandBuffer];
        A5MaliRect full = {0, 0, 64, 64};
        A5MaliRect small = {0, 0, 4, 4};
        assert([buffer encodeClear:destination
            rect:full bgra:0xff112233]);
        assert([buffer encodeCopy:source
            sourceRect:small to:destination destinationRect:small]);
        assert([buffer encodeTexturedQuad:source
            sourceRect:small to:destination destinationRect:full]);
        assert([buffer commitAndWait:&error] && !error);
        assert(buffer.completedFence.fragmentFence == 102);
        assert(fake.batches == 1);
        buffer = nil;
        source = nil;
        destination = nil;
        queue = nil;
        device = nil;
        assert(fake.releases == 2);
    }
    return 0;
}
