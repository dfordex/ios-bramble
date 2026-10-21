/* SPDX-License-Identifier: MIT */
#include "A5MaliBridge.h"
#include <string.h>

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

_Static_assert(sizeof(A5MaliHeader) == 16, "header ABI");
_Static_assert(sizeof(QueryReply) == 32, "query ABI");
_Static_assert(sizeof(ImportRequest) == 32 && sizeof(ImportReply) == 40,
    "import ABI");
_Static_assert(sizeof(HandleRequest) == 24 && sizeof(MapReply) == 32,
    "map ABI");
_Static_assert(sizeof(SubmitRequest) == 72 && sizeof(SubmitReply) == 40,
    "submit ABI");

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
    if (!client || !transport)
        return kIOReturnBadArgument;
    memset(client, 0, sizeof(*client));
    client->call = transport;
    client->context = context;
    return KERN_SUCCESS;
}

kern_return_t A5MaliOpen(A5MaliClient *client)
{
    if (!client)
        return kIOReturnBadArgument;
    memset(client, 0, sizeof(*client));
    CFMutableDictionaryRef matching = IOServiceMatching("A5XELTEGPU");
    if (!matching)
        return kIOReturnNoMemory;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
        matching);
    if (!service)
        return kIOReturnNotFound;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0,
        &client->connection);
    IOObjectRelease(service);
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
    return KERN_SUCCESS;
}

void A5MaliClose(A5MaliClient *client)
{
    if (!client)
        return;
    if (client->ownsConnection && client->connection)
        IOServiceClose(client->connection);
    memset(client, 0, sizeof(*client));
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
    if (kr != KERN_SUCCESS)
        return kr;
    if (!validReply(&reply.h, sizeof(reply), size) || !reply.handle) {
        if (reply.handle) {
            HandleRequest release = { header(sizeof(release)), reply.handle };
            call(client, A5MaliRelease, &release, sizeof(release), NULL, NULL);
        }
        return kIOReturnBadArgument;
    }
    HandleRequest map = { header(sizeof(map)), reply.handle };
    if (reply.format != 0x42475241 || !reply.width || !reply.height ||
        reply.width > UINT32_MAX / 4 || reply.rowBytes < reply.width * 4) {
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
         mapped.mappedBytes < (uint64_t)reply.rowBytes * reply.height))
        kr = kIOReturnBadArgument;
    if (kr != KERN_SUCCESS) {
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
    switch (reply.status) {
    case A5MaliCompleted: break;
    case 1: return kIOReturnBadArgument;
    case 2: return kIOReturnBusy;
    case 3: return kIOReturnIOError;
    case 4: return kIOReturnTimeout;
    case 5: return kIOReturnError;
    default: return kIOReturnError;
    }
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
