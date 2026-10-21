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
    uint32_t operation, color;
    uint64_t source, destination;
    A5MaliRect sourceRect, destinationRect;
} BatchWireCommand;
typedef struct {
    A5MaliHeader h; uint32_t count, reserved;
    BatchWireCommand commands[8];
} BatchWireRequest;
typedef struct {
    uint32_t status, reserved;
    uint64_t tilerFence, fragmentFence;
} BatchWireItem;
typedef struct {
    A5MaliHeader h;
    uint32_t count, completedCount, failedIndex, reserved;
    BatchWireItem items[8];
} BatchWireReply;

typedef struct {
    uint32_t imports, maps, submits, batches, unmaps, releases;
    uint32_t lastOperation, lastColor;
    uint64_t lastSource, lastDestination;
    A5MaliRect lastSourceRect, lastDestinationRect;
    int failSubmit;
    int malformedImport;
    uint32_t batchFailIndex;
    uint32_t importWidth,importHeight,importRow,importFormat,mapBytes;
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
        if(fake->importWidth){reply.width=fake->importWidth;reply.height=fake->importHeight;
            reply.rowBytes=fake->importRow;reply.format=fake->importFormat;}
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
        if(fake->mapBytes)reply.mappedBytes=fake->mapBytes;
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
        fake->lastSourceRect = request->sourceRect;
        fake->lastDestinationRect = request->destinationRect;
        fake->submits++;
        SubmitReply reply = {
            {1, sizeof(SubmitReply), 0, 0},
            (uint32_t)fake->failSubmit, 0, 11, 12
        };
        memcpy(output, &reply, sizeof(reply));
        *outputSize = sizeof(reply);
        return KERN_SUCCESS;
    }
    if (selector == A5MaliBatchSubmit) {
        assert(inputSize == 472 && *outputSize == 224 && output);
        const BatchWireRequest *request = input;
        assert(request->h.version == 1 && request->h.size == 472);
        assert(request->count >= 1 && request->count <= 8);
        fake->batches++;
        BatchWireReply reply = {0};
        reply.h = (A5MaliHeader){1, sizeof(reply), 0, 0};
        reply.count = request->count;
        reply.failedIndex = fake->batchFailIndex;
        reply.completedCount = fake->batchFailIndex == UINT32_MAX ?
            request->count : fake->batchFailIndex;
        for (uint32_t i = 0; i < request->count; ++i) {
            assert(request->commands[i].destination);
            reply.items[i].status = i < reply.completedCount ? 0 :
                i == reply.failedIndex ? 4 : 6;
            if (i < reply.completedCount)
                reply.items[i].fragmentFence = 100 + i;
        }
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
    Fake fake = {.batchFailIndex = UINT32_MAX};
    A5MaliClient client;
    assert(A5MaliInitTransportWithCapabilities(&client, fakeCall, &fake,
        15) == KERN_SUCCESS);
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
    A5MaliRect larger = {6, 8, 32, 32};
    assert(A5MaliDrawTexturedQuad(&client, &source, rect, &destination,
        larger, &fence) == KERN_SUCCESS);
    assert(fake.lastOperation == A5MaliDrawTexturedQuadBGRA &&
        fake.lastSource == source.token &&
        fake.lastDestination == destination.token &&
        fake.lastSourceRect.width == 16 &&
        fake.lastDestinationRect.width == 32 && fence.fragmentFence == 12);
    A5MaliBatchCommand commands[3] = {
        {A5MaliClearBGRA, 0xff112233, NULL, &destination, {0}, rect},
        {A5MaliCopyBGRA, 0, &source, &destination, rect, rect},
        {A5MaliDrawTexturedQuadBGRA, 0, &source, &destination,
            rect, larger},
    };
    A5MaliBatchResult batch = {0};
    assert(A5MaliSubmitBatchCommands(&client, commands, 3, &batch) ==
        kIOReturnUnsupported);
    client.supportedOperations = 127;
    assert(A5MaliSubmitBatchCommands(&client, commands, 3, &batch) ==
        KERN_SUCCESS);
    assert(fake.batches == 1 && batch.completedCount == 3 &&
        batch.failedIndex == UINT32_MAX &&
        batch.items[2].fence.fragmentFence == 102);
    fake.batchFailIndex = 1;
    assert(A5MaliSubmitBatchCommands(&client, commands, 3, &batch) ==
        kIOReturnTimeout);
    assert(fake.batches == 2 && batch.completedCount == 1 &&
        batch.failedIndex == 1 && batch.items[2].status == 6);
    const uint32_t batches = fake.batches;
    commands[2].sourceRect.width = 0;
    assert(A5MaliSubmitBatchCommands(&client, commands, 3, &batch) ==
        kIOReturnBadArgument && fake.batches == batches);
    const uint32_t before = fake.submits;
    A5MaliRect outside = {60, 0, 16, 16};
    assert(A5MaliCopy(&client, &source, outside, &destination, rect, NULL) != KERN_SUCCESS);
    assert(A5MaliDrawTexturedQuad(&client, &source, outside,
        &destination, larger, NULL) != KERN_SUCCESS);
    assert(fake.submits == before);
    client.gpuCommandsSupported = 7;
    assert(A5MaliDrawTexturedQuad(&client, &source, rect,
        &destination, larger, NULL) == kIOReturnUnsupported);
    assert(fake.submits == before);
    client.gpuCommandsSupported = 15;
    fake.failSubmit = 4;
    assert(A5MaliCopy(&client, &source, rect, &destination, rect, NULL) == kIOReturnTimeout);
    fake.failSubmit = 0;
    A5MaliResource fullSource = {0x100000011ULL, 1080, 1920, 4320,
        A5MaliRead};
    A5MaliResource fullDestination = {0x100000012ULL, 1080, 1920, 4320,
        A5MaliWrite};
    assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
        NULL) == kIOReturnUnsupported);
    client.gpuCommandsSupported = 31;
    assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
        &fence) == KERN_SUCCESS);
    assert(fake.lastOperation == A5MaliReadSurfBGRA &&
        fake.lastSourceRect.width == 1080 &&
        fake.lastDestinationRect.height == 1920 &&
        fence.fragmentFence == 12);
    A5MaliBatchCommand readSurf = {A5MaliReadSurfBGRA, 0,
        &fullSource, &fullDestination, {0, 0, 1080, 1920},
        {0, 0, 1080, 1920}};
    fake.batchFailIndex = UINT32_MAX;
    assert(A5MaliSubmitBatchCommands(&client, &readSurf, 1,
        &batch) == KERN_SUCCESS && batch.completedCount == 1);
    fullSource.rowBytes = 4352;
    assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
        NULL) == KERN_SUCCESS);
    assert(A5MaliSubmitBatchCommands(&client, &readSurf, 1,
        &batch) == KERN_SUCCESS && batch.completedCount == 1);
    fullDestination.rowBytes = 4352;
    assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
        NULL) == KERN_SUCCESS);
    const uint32_t beforeInvalid = fake.submits;
    const uint32_t invalidRows[] = {4316, 4324, 8208};
    for (unsigned i = 0; i < sizeof(invalidRows) / sizeof(invalidRows[0]); ++i) {
        fullSource.rowBytes = invalidRows[i];
        assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
            NULL) == kIOReturnBadArgument && fake.submits == beforeInvalid);
        assert(A5MaliSubmitBatchCommands(&client, &readSurf, 1,
            &batch) == kIOReturnBadArgument);
        fullSource.rowBytes = 4352;
        fullDestination.rowBytes = invalidRows[i];
        assert(A5MaliReadSurf(&client, &fullSource, &fullDestination,
            NULL) == kIOReturnBadArgument && fake.submits == beforeInvalid);
        assert(A5MaliSubmitBatchCommands(&client, &readSurf, 1,
            &batch) == kIOReturnBadArgument);
        fullDestination.rowBytes = 4352;
    }
    fake.malformedImport = 1;
    A5MaliResource rejected;
    const uint32_t released = fake.releases;
    assert(A5MaliImportSurface(&client, 123, A5MaliRead, &rejected) != KERN_SUCCESS);
    assert(rejected.token == 0 && fake.releases == released + 1);
    assert(A5MaliReleaseSurface(&client, &source) == KERN_SUCCESS);
    assert(A5MaliReleaseSurface(&client, &destination) == KERN_SUCCESS);
    assert(fake.unmaps == 2 && fake.releases == 3);
    A5MaliClose(&client);
    Fake bounds={.batchFailIndex=UINT32_MAX,.importWidth=1080,.importHeight=1920,
        .importRow=8640,.importFormat=0x52476841,.mapBytes=16588800};
    assert(A5MaliInitTransportWithCapabilities(&client,fakeCall,&bounds,15)==KERN_SUCCESS);
    A5MaliResource half;
    assert(A5MaliImportSurface(&client,123,A5MaliRead|A5MaliWrite,&half)==KERN_SUCCESS);
    assert(half.width==1080&&half.height==1920&&half.rowBytes==8640);
    assert(A5MaliReleaseSurface(&client,&half)==KERN_SUCCESS);
    bounds.importWidth=2048;bounds.importHeight=2048;bounds.importRow=16384;bounds.mapBytes=A5MaliSurfaceMaxBytes;
    assert(A5MaliImportSurface(&client,123,A5MaliRead|A5MaliWrite,&half)==KERN_SUCCESS);
    assert(A5MaliReleaseSurface(&client,&half)==KERN_SUCCESS);
    uint32_t maps=bounds.maps,releases=bounds.releases;
    bounds.mapBytes=A5MaliSurfaceMaxBytes+4096;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument);
    assert(!half.token&&bounds.maps==maps+1&&bounds.releases==releases+1);
    maps=bounds.maps;bounds.mapBytes=A5MaliSurfaceMaxBytes;bounds.importWidth=UINT32_MAX;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument&&bounds.maps==maps);
    bounds.importWidth=2048;bounds.importHeight=2049;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument&&bounds.maps==maps);
    bounds.importHeight=2048;bounds.importRow=16400;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument&&bounds.maps==maps);
    /* Physical texture backing can contain a full mip chain or a 4096-wide
     * typed 1D level. The 32 MiB map limit is unchanged. */
    const uint32_t typedFormats[]={0x52313655,0x4c303068,0x42354131,0x32433066};
    for(unsigned i=0;i<sizeof(typedFormats)/sizeof(typedFormats[0]);++i){
        bounds.importWidth=4096;bounds.importHeight=1;
        bounds.importRow=i==3?32768:8192;bounds.importFormat=typedFormats[i];
        bounds.mapBytes=bounds.importRow;
        assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==KERN_SUCCESS);
        assert(half.width==4096&&half.height==1&&half.rowBytes==bounds.importRow);
        assert(A5MaliReleaseSurface(&client,&half)==KERN_SUCCESS);
    }
    bounds.importWidth=4097;bounds.importRow=32784;bounds.mapBytes=36864;
    maps=bounds.maps;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument&&bounds.maps==maps);
    bounds.importWidth=4096;bounds.importRow=32768;bounds.importFormat=0xdeadbeef;
    assert(A5MaliImportSurface(&client,123,A5MaliRead,&half)==kIOReturnBadArgument&&bounds.maps==maps);
    A5MaliClose(&client);
    return 0;
}
