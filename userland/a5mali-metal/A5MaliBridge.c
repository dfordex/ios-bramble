/* SPDX-License-Identifier: MIT */
#include "A5MaliBridge.h"
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>

typedef struct { A5MaliHeader h; uint32_t max, operations, commands, reserved; } QueryReply;
typedef struct { A5MaliHeader h; uint32_t port, usage; uint64_t reserved; } ImportRequest;
typedef struct { A5MaliHeader h; uint64_t handle; uint32_t width, height, rowBytes, format; } ImportReply;
typedef struct { A5MaliHeader h; uint64_t handle; } HandleRequest;
typedef struct { A5MaliHeader h; uint64_t token; uint32_t mappedBytes, flags; } MapReply;
typedef struct {
    A5MaliHeader h;
    uint32_t operation, color;
    uint64_t source, destination;
    A5MaliRect sourceRect, destinationRect;
} SubmitRequest;
typedef struct {
    A5MaliHeader h;
    uint32_t status, reserved;
    uint64_t tilerFence, fragmentFence;
} SubmitReply;
typedef struct {
    uint32_t operation, color;
    uint64_t source, destination;
    A5MaliRect sourceRect, destinationRect;
} BatchWireCommand;
typedef struct {
    A5MaliHeader h;
    uint32_t count, reserved;
    BatchWireCommand commands[A5MaliBatchMaxCommands];
} BatchWireRequest;
typedef struct {
    uint32_t status, reserved;
    uint64_t tilerFence, fragmentFence;
} BatchWireItem;
typedef struct {
    A5MaliHeader h;
    uint32_t count, completedCount, failedIndex, reserved;
    BatchWireItem items[A5MaliBatchMaxCommands];
} BatchWireReply;

_Static_assert(sizeof(A5MaliHeader) == 16, "header ABI");
_Static_assert(sizeof(QueryReply) == 32, "query ABI");
_Static_assert(sizeof(ImportRequest) == 32 && sizeof(ImportReply) == 40,
    "import ABI");
_Static_assert(sizeof(HandleRequest) == 24 && sizeof(MapReply) == 32,
    "map ABI");
_Static_assert(sizeof(SubmitRequest) == 72 && sizeof(SubmitReply) == 40,
    "submit ABI");
_Static_assert(sizeof(BatchWireCommand) == 56 &&
    sizeof(BatchWireRequest) == 472 && sizeof(BatchWireItem) == 24 &&
    sizeof(BatchWireReply) == 224, "batch ABI");

static A5MaliHeader header(size_t size)
{
    A5MaliHeader h = { A5MaliProtocolVersion, (uint32_t)size, 0, 0 };
    return h;
}

static int validReply(const A5MaliHeader *h, size_t size, size_t actual)
{
    return actual == size && h->version == A5MaliProtocolVersion &&
        h->size == size && !h->reserved0 && !h->reserved1;
}

static kern_return_t call(A5MaliClient *client, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    if (!client || !client->call)
        return kIOReturnNotOpen;
    size_t emptyOutputSize = 0;
    if (!outputSize)
        outputSize = &emptyOutputSize;
    return client->call(client->context, selector, input, inputSize,
        output, outputSize);
}

static kern_return_t ioCall(void *context, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize)
{
    A5MaliClient *client = context;
    return IOConnectCallStructMethod(client->connection, selector,
        input, inputSize, output, outputSize);
}

kern_return_t A5MaliInitTransport(A5MaliClient *client,
    A5MaliTransport transport, void *context)
{
    return A5MaliInitTransportWithCapabilities(client, transport, context, 7);
}

kern_return_t A5MaliInitTransportWithCapabilities(A5MaliClient *client,
    A5MaliTransport transport, void *context, uint32_t gpuCommandsSupported)
{
    if (!client || !transport)
        return kIOReturnBadArgument;
    memset(client, 0, sizeof(*client));
    client->call = transport;
    client->context = context;
    client->gpuCommandsSupported = gpuCommandsSupported;
    return KERN_SUCCESS;
}

kern_return_t A5MaliOpenService(A5MaliClient *client, io_service_t service)
{
    if (!client || !service)
        return kIOReturnBadArgument;
    memset(client, 0, sizeof(*client));
    if (!IOObjectConformsTo(service, "A5XELTEGPU"))
        return kIOReturnUnsupported;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0,
        &client->connection);
    if (kr != KERN_SUCCESS)
        return kr;
    client->call = ioCall;
    client->context = client;
    client->ownsConnection = 1;
    A5MaliHeader queryRequest = header(sizeof(queryRequest));
    QueryReply query = {0};
    size_t querySize = sizeof(query);
    kr = call(client, A5MaliQuery, &queryRequest,
        sizeof(queryRequest), &query, &querySize);
    if (kr != KERN_SUCCESS ||
        !validReply(&query.h, sizeof(query), querySize) ||
        (query.commands & 0x7) != 0x7) {
        A5MaliClose(client);
        return kr == KERN_SUCCESS ? kIOReturnUnsupported : kr;
    }
    client->gpuCommandsSupported = query.commands;
    client->supportedOperations = query.operations;
    return KERN_SUCCESS;
}

kern_return_t A5MaliOpen(A5MaliClient *client)
{
    if (!client)
        return kIOReturnBadArgument;
    CFMutableDictionaryRef matching = IOServiceMatching("A5XELTEGPU");
    if (!matching)
        return kIOReturnNoMemory;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        matching);
    if (!service)
        return kIOReturnNotFound;
    kern_return_t kr = A5MaliOpenService(client, service);
    IOObjectRelease(service);
    return kr;
}

void A5MaliClose(A5MaliClient *client)
{
    if (!client)
        return;
    if (client->ownsConnection && client->connection)
        IOServiceClose(client->connection);
    memset(client, 0, sizeof(*client));
}

static void importFailure(const char *phase,kern_return_t status,uint64_t token)
{
    static atomic_uint receipts;
    unsigned n=atomic_load_explicit(&receipts,memory_order_relaxed);
    do {if(n>=32)return;}while(!atomic_compare_exchange_weak_explicit(&receipts,&n,n+1,
        memory_order_relaxed,memory_order_relaxed));
    fprintf(stderr,"A5XELTE Metal import: phase=%s status=%x logical_slot=%u generation=%u\n",
        phase,(unsigned)status,(unsigned)token,(unsigned)(token>>32));
}

kern_return_t A5MaliImportSurface(A5MaliClient *client,
    mach_port_t surfacePort, uint32_t usage, A5MaliResource *resource)
{
    if (!resource || surfacePort == MACH_PORT_NULL || !usage ||
        (usage & ~(A5MaliRead | A5MaliWrite)))
        return kIOReturnBadArgument;
    memset(resource, 0, sizeof(*resource));
    ImportRequest request = {0};
    request.h = header(sizeof(request));
    request.port = surfacePort;
    request.usage = usage;
    ImportReply reply = {0};
    size_t size = sizeof(reply);
    kern_return_t kr = call(client, A5MaliImport, &request,
        sizeof(request), &reply, &size);
    if (kr != KERN_SUCCESS) {
        importFailure("import-selector1",kr,0);
        return kr;
    }
    if (!validReply(&reply.h, sizeof(reply), size) || !reply.handle) {
        if (reply.handle) {
            HandleRequest release = { header(sizeof(release)), reply.handle };
            call(client, A5MaliRelease, &release, sizeof(release), NULL, NULL);
        }
        return kIOReturnBadArgument;
    }
    HandleRequest map = { header(sizeof(map)), reply.handle };
    uint32_t elementBytes = (reply.format==0x42475241||reply.format==0x52474241) ? 4 :
        reply.format==0x52476841 ? 8 :
        (reply.format==0x41303038||reply.format==0x4c303038) ? 1 :
        reply.format==0x32433038 ? 2 : reply.format==0x4c303066 ? 4 :
        reply.format==0x52313655 ? 2 : reply.format==0x4c303068 ? 2 :
        reply.format==0x42354131 ? 2 : reply.format==0x32433066 ? 8 : 0;
    if (!elementBytes || !reply.width || !reply.height ||
        reply.width > 4096 || reply.height > 4096 ||
        (reply.rowBytes & 15) || reply.rowBytes > 32768 ||
        reply.rowBytes < reply.width * elementBytes ||
        (uint64_t)reply.rowBytes * reply.height > A5MaliSurfaceMaxBytes) {
        call(client, A5MaliRelease, &map, sizeof(map), NULL, NULL);
        return kIOReturnBadArgument;
    }
    MapReply mapped = {0};
    size = sizeof(mapped);
    kr = call(client, A5MaliMap, &map, sizeof(map), &mapped, &size);
    if (kr == KERN_SUCCESS &&
        (!validReply(&mapped.h, sizeof(mapped), size) ||
         mapped.token != reply.handle ||
         (mapped.flags & usage) != usage ||
         mapped.mappedBytes > A5MaliSurfaceMaxBytes ||
         mapped.mappedBytes < (uint64_t)reply.rowBytes * reply.height))
        kr = kIOReturnBadArgument;
    if (kr != KERN_SUCCESS) {
        importFailure("map-selector4",kr,reply.handle);
        /* The kernel release path also unmaps if map succeeded. */
        call(client, A5MaliRelease, &map, sizeof(map), NULL, NULL);
        return kr;
    }
    *resource = (A5MaliResource){ reply.handle, reply.width, reply.height,
        reply.rowBytes, usage };
    return KERN_SUCCESS;
}

kern_return_t A5MaliReleaseSurface(A5MaliClient *client,
    A5MaliResource *resource)
{
    if (!resource || !resource->token)
        return kIOReturnBadArgument;
    HandleRequest request = { header(sizeof(request)), resource->token };
    kern_return_t kr = call(client, A5MaliUnmap, &request,
        sizeof(request), NULL, NULL);
    if (kr != KERN_SUCCESS)
        return kr;
    kr = call(client, A5MaliRelease, &request, sizeof(request), NULL, NULL);
    if (kr == KERN_SUCCESS)
        memset(resource, 0, sizeof(*resource));
    return kr;
}

static int validRect(const A5MaliResource *image, A5MaliRect rect)
{
    return image && image->token && rect.width && rect.height &&
        rect.x < image->width && rect.y < image->height &&
        rect.width <= image->width - rect.x &&
        rect.height <= image->height - rect.y;
}

static kern_return_t resultStatus(uint32_t status)
{
    switch (status) {
    case A5MaliCompleted: return KERN_SUCCESS;
    case 1: return kIOReturnBadArgument;
    case 2: return kIOReturnBusy;
    case 3: return kIOReturnIOError;
    case 4: return kIOReturnTimeout;
    default: return kIOReturnError;
    }
}

static kern_return_t submit(A5MaliClient *client, SubmitRequest request,
    A5MaliFence *fence)
{
    SubmitReply reply = {0};
    size_t size = sizeof(reply);
    kern_return_t kr = call(client, A5MaliSubmit, &request,
        sizeof(request), &reply, &size);
    if (kr != KERN_SUCCESS)
        return kr;
    if (!validReply(&reply.h, sizeof(reply), size))
        return kIOReturnError;
    /* Values match A5G3DAS1SubmitStatus in XNU patch 0151. */
    kr = resultStatus(reply.status);
    if (kr != KERN_SUCCESS)
        return kr;
    if (!reply.fragmentFence)
        return kIOReturnError;
    if (fence)
        *fence = (A5MaliFence){ reply.tilerFence, reply.fragmentFence };
    return KERN_SUCCESS;
}

kern_return_t A5MaliClear(A5MaliClient *client,
    const A5MaliResource *destination, A5MaliRect rect, uint32_t bgra,
    A5MaliFence *fence)
{
    if (!validRect(destination, rect) || !(destination->usage & A5MaliWrite))
        return kIOReturnBadArgument;
    SubmitRequest request = {0};
    request.h = header(sizeof(request));
    request.operation = A5MaliClearBGRA;
    request.color = bgra;
    request.destination = destination->token;
    request.destinationRect = rect;
    return submit(client, request, fence);
}

kern_return_t A5MaliCopy(A5MaliClient *client,
    const A5MaliResource *source, A5MaliRect sourceRect,
    const A5MaliResource *destination, A5MaliRect destinationRect,
    A5MaliFence *fence)
{
    if (!validRect(source, sourceRect) || !validRect(destination,
        destinationRect) || source->token == destination->token ||
        !(source->usage & A5MaliRead) ||
        !(destination->usage & A5MaliWrite) ||
        sourceRect.width != destinationRect.width ||
        sourceRect.height != destinationRect.height)
        return kIOReturnBadArgument;
    SubmitRequest request = {0};
    request.h = header(sizeof(request));
    request.operation = A5MaliCopyBGRA;
    request.source = source->token;
    request.destination = destination->token;
    request.sourceRect = sourceRect;
    request.destinationRect = destinationRect;
    return submit(client, request, fence);
}

kern_return_t A5MaliDrawTexturedQuad(A5MaliClient *client,
    const A5MaliResource *source, A5MaliRect sourceRect,
    const A5MaliResource *destination, A5MaliRect destinationRect,
    A5MaliFence *fence)
{
    if (!client || !(client->gpuCommandsSupported & (1U << 3)))
        return kIOReturnUnsupported;
    if (!validRect(source, sourceRect) || !validRect(destination,
        destinationRect) || source->token == destination->token ||
        !(source->usage & A5MaliRead) ||
        !(destination->usage & A5MaliWrite))
        return kIOReturnBadArgument;
    SubmitRequest request = {0};
    request.h = header(sizeof(request));
    request.operation = A5MaliDrawTexturedQuadBGRA;
    request.source = source->token;
    request.destination = destination->token;
    request.sourceRect = sourceRect;
    request.destinationRect = destinationRect;
    return submit(client, request, fence);
}

static int validReadSurf(const A5MaliClient *client,
    const A5MaliResource *source, const A5MaliResource *destination)
{
    return client && (client->gpuCommandsSupported & (1U << 4)) &&
        source && destination && source->token && destination->token &&
        source->token != destination->token &&
        (source->usage & A5MaliRead) &&
        (destination->usage & A5MaliWrite) &&
        source->width == 1080 && source->height == 1920 &&
        destination->width == 1080 && destination->height == 1920 &&
        source->rowBytes >= 4320 && source->rowBytes <= 8192 &&
        !(source->rowBytes & 15) && destination->rowBytes >= 4320 &&
        destination->rowBytes <= 8192 && !(destination->rowBytes & 15);
}

kern_return_t A5MaliReadSurf(A5MaliClient *client,
    const A5MaliResource *source, const A5MaliResource *destination,
    A5MaliFence *fence)
{
    if (!client || !(client->gpuCommandsSupported & (1U << 4)))
        return kIOReturnUnsupported;
    if (!validReadSurf(client, source, destination))
        return kIOReturnBadArgument;
    SubmitRequest request = {0};
    request.h = header(sizeof(request));
    request.operation = A5MaliReadSurfBGRA;
    request.source = source->token;
    request.destination = destination->token;
    request.sourceRect = (A5MaliRect){0, 0, source->width, source->height};
    request.destinationRect = (A5MaliRect){0, 0, destination->width,
        destination->height};
    return submit(client, request, fence);
}

kern_return_t A5MaliSubmitBatchCommands(A5MaliClient *client,
    const A5MaliBatchCommand *commands, uint32_t count,
    A5MaliBatchResult *result)
{
    if (!client || !(client->supportedOperations & (1U << 6)))
        return kIOReturnUnsupported;
    if (!commands || !result || !count || count > A5MaliBatchMaxCommands)
        return kIOReturnBadArgument;
    BatchWireRequest request = {0};
    request.h = header(sizeof(request));
    request.count = count;
    for (uint32_t i = 0; i < count; ++i) {
        const A5MaliBatchCommand *command = &commands[i];
        if (!validRect(command->destination, command->destinationRect) ||
            !(command->destination->usage & A5MaliWrite))
            return kIOReturnBadArgument;
        if (command->operation == A5MaliClearBGRA) {
            if (command->source || command->sourceRect.x ||
                command->sourceRect.y || command->sourceRect.width ||
                command->sourceRect.height)
                return kIOReturnBadArgument;
        } else if (command->operation == A5MaliCopyBGRA ||
            command->operation == A5MaliDrawTexturedQuadBGRA ||
            command->operation == A5MaliReadSurfBGRA) {
            if (command->operation == A5MaliDrawTexturedQuadBGRA &&
                !(client->gpuCommandsSupported & (1U << 3)))
                return kIOReturnUnsupported;
            if (command->operation == A5MaliReadSurfBGRA &&
                !(client->gpuCommandsSupported & (1U << 4)))
                return kIOReturnUnsupported;
            if (!validRect(command->source, command->sourceRect) ||
                !(command->source->usage & A5MaliRead) ||
                command->source->token == command->destination->token ||
                command->color ||
                (command->operation == A5MaliReadSurfBGRA &&
                 (!validReadSurf(client, command->source,
                    command->destination) || command->sourceRect.x ||
                  command->sourceRect.y || command->destinationRect.x ||
                  command->destinationRect.y ||
                  command->sourceRect.width != command->source->width ||
                  command->sourceRect.height != command->source->height ||
                  command->destinationRect.width !=
                    command->destination->width ||
                  command->destinationRect.height !=
                    command->destination->height)) ||
                (command->operation == A5MaliCopyBGRA &&
                 (command->sourceRect.width !=
                  command->destinationRect.width ||
                  command->sourceRect.height !=
                  command->destinationRect.height)))
                return kIOReturnBadArgument;
        } else {
            return kIOReturnUnsupported;
        }
        request.commands[i] = (BatchWireCommand){
            command->operation, command->color,
            command->source ? command->source->token : 0,
            command->destination->token,
            command->sourceRect, command->destinationRect
        };
    }
    BatchWireReply reply = {0};
    size_t size = sizeof(reply);
    kern_return_t kr = call(client, A5MaliBatchSubmit, &request,
        sizeof(request), &reply, &size);
    if (kr != KERN_SUCCESS)
        return kr;
    if (!validReply(&reply.h, sizeof(reply), size) ||
        reply.count != count || reply.completedCount > count ||
        (reply.failedIndex != UINT32_MAX &&
         reply.failedIndex >= count))
        return kIOReturnError;
    A5MaliBatchResult checked = {0};
    checked.count = count;
    checked.completedCount = reply.completedCount;
    checked.failedIndex = reply.failedIndex;
    for (uint32_t i = 0; i < count; ++i) {
        BatchWireItem item = reply.items[i];
        if (item.reserved || item.status > 6 ||
            (i < reply.completedCount &&
             (item.status != A5MaliCompleted || !item.fragmentFence)) ||
            (i >= reply.completedCount && reply.failedIndex == UINT32_MAX) ||
            (i == reply.failedIndex &&
             (item.status == A5MaliCompleted || item.status == 6)) ||
            (i > reply.failedIndex && reply.failedIndex != UINT32_MAX &&
             item.status != 6))
            return kIOReturnError;
        checked.items[i] = (A5MaliBatchItem){ item.status,
            {item.tilerFence, item.fragmentFence} };
    }
    if (reply.failedIndex == UINT32_MAX &&
        reply.completedCount != count)
        return kIOReturnError;
    if (reply.failedIndex != UINT32_MAX &&
        reply.failedIndex != reply.completedCount)
        return kIOReturnError;
    *result = checked;
    return reply.failedIndex == UINT32_MAX ? KERN_SUCCESS :
        resultStatus(reply.items[reply.failedIndex].status);
}
