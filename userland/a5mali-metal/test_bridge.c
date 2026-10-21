/* SPDX-License-Identifier: MIT */
#include "A5MaliBridge.h"
#include <assert.h>
#include <string.h>

typedef struct { A5MaliHeader h; uint32_t port, usage; uint64_t reserved; } ImportRequest;
typedef struct { A5MaliHeader h; uint64_t handle; uint32_t width, height, rowBytes, format; } ImportReply;
typedef struct { A5MaliHeader h; uint64_t handle; } HandleRequest;
typedef struct { A5MaliHeader h; uint64_t token; uint32_t mappedBytes, flags; } MapReply;
typedef struct {
    A5MaliHeader h; uint32_t operation, color;
    uint64_t source, destination;
    A5MaliRect sourceRect, destinationRect;
} SubmitRequest;
typedef struct {
    A5MaliHeader h; uint32_t status, reserved;
    uint64_t tilerFence, fragmentFence;
} SubmitReply;

typedef struct {
    uint32_t imports, maps, submits, unmaps, releases;
    uint32_t lastOperation, lastColor;
    uint64_t lastSource, lastDestination;
    int failSubmit;
    int malformedImport;
} Fake;

static kern_return_t fakeCall(void *opaque, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    Fake *fake = opaque;
    if (selector == A5MaliImport) {
        assert(inputSize == sizeof(ImportRequest));
        const ImportRequest *request = input;
        assert(request->h.version == 1 && request->h.size == inputSize);
        assert(request->port == 123 && request->reserved == 0);
        assert(output && outputSize && *outputSize == sizeof(ImportReply));
        ImportReply reply = {
            {1, sizeof(ImportReply), 0, 0},
            0x100000001ULL + fake->imports, 64, 64, 256, 0x42475241
        };
        if (fake->malformedImport) reply.h.version = 99;
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        fake->imports++;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliMap) {
        assert(inputSize == sizeof(HandleRequest));
        assert(output && outputSize && *outputSize == sizeof(MapReply));
        const HandleRequest *request = input;
        MapReply reply = {
            {1, sizeof(MapReply), 0, 0}, request->handle,
            64 * 256, A5MaliRead | A5MaliWrite
        };
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        fake->maps++;
        return KERN_SUCCESS;
    }
    if (selector == A5MaliSubmit) {
        assert(inputSize == sizeof(SubmitRequest));
        assert(output && outputSize && *outputSize == sizeof(SubmitReply));
        const SubmitRequest *request = input;
        assert(request->h.version == 1 && request->h.size == inputSize);
        fake->lastOperation = request->operation;
        fake->lastColor = request->color;
        fake->lastSource = request->source;
        fake->lastDestination = request->destination;
        fake->submits++;
        SubmitReply reply = {
            {1, sizeof(SubmitReply), 0, 0},
            (uint32_t)fake->failSubmit, 0, 11, 12
        };
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        return KERN_SUCCESS;
    }
    if (selector == A5MaliUnmap || selector == A5MaliRelease) {
        assert(inputSize == sizeof(HandleRequest));
        assert(output == NULL);
        const HandleRequest *request = input;
        assert(request->h.version == 1 && request->h.size == inputSize);
        if (selector == A5MaliUnmap) fake->unmaps++;
        else fake->releases++;
        return KERN_SUCCESS;
    }
    assert(0 && "unexpected selector");
    return KERN_INVALID_ARGUMENT;
}

int main(void)
{
    Fake fake = {0};
    A5MaliClient client;
    assert(A5MaliInitTransport(&client, fakeCall, &fake) == KERN_SUCCESS);
    A5MaliResource source, destination;
    assert(A5MaliImportSurface(&client, 123, A5MaliRead, &source) == KERN_SUCCESS);
    assert(A5MaliImportSurface(&client, 123, A5MaliWrite, &destination) == KERN_SUCCESS);
    assert(fake.imports == 2 && fake.maps == 2 && source.token != destination.token);
    A5MaliRect rect = {3, 4, 16, 16};
    A5MaliFence fence = {0};
    assert(A5MaliClear(&client, &destination, rect, 0xff00ff00, &fence) == KERN_SUCCESS);
    assert(fake.lastOperation == A5MaliClearBGRA && fake.lastSource == 0 &&
        fake.lastDestination == destination.token && fake.lastColor == 0xff00ff00 &&
        fence.fragmentFence == 12);
    assert(A5MaliCopy(&client, &source, rect, &destination, rect, &fence) == KERN_SUCCESS);
    assert(fake.lastOperation == A5MaliCopyBGRA && fake.lastSource == source.token);
    const uint32_t before = fake.submits;
    A5MaliRect outside = {60, 0, 16, 16};
    assert(A5MaliCopy(&client, &source, outside, &destination, rect, NULL) != KERN_SUCCESS);
    assert(fake.submits == before);
    fake.failSubmit = 4;
    assert(A5MaliCopy(&client, &source, rect, &destination, rect, NULL) == kIOReturnTimeout);
    fake.malformedImport = 1;
    A5MaliResource rejected;
    const uint32_t released = fake.releases;
    assert(A5MaliImportSurface(&client, 123, A5MaliRead, &rejected) != KERN_SUCCESS);
    assert(rejected.token == 0 && fake.releases == released + 1);
    assert(A5MaliReleaseSurface(&client, &source) == KERN_SUCCESS);
    assert(A5MaliReleaseSurface(&client, &destination) == KERN_SUCCESS);
    assert(fake.unmaps == 2 && fake.releases == 3);
    A5MaliClose(&client);
    return 0;
}
