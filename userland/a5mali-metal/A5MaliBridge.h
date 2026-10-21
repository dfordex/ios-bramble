/* SPDX-License-Identifier: MIT
 * Private A5XELTE BGRA command bridge, not an MTLDevice implementation.
 */
#ifndef A5_MALI_BRIDGE_H
#define A5_MALI_BRIDGE_H

#include <mach/mach.h>
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <stdint.h>

/* This ABI mirrors XNU A5XELTEGPUUserClient.h version 1. */
enum {
    A5MaliProtocolVersion = 1,
    A5MaliSurfaceMaxBytes = 0x2000000,
    A5MaliRead = 1,
    A5MaliWrite = 2,
    A5MaliQuery = 0,
    A5MaliImport = 1,
    A5MaliRelease = 2,
    A5MaliMap = 4,
    A5MaliUnmap = 5,
    A5MaliSubmit = 6,
    A5MaliBatchSubmit = 7,
    A5MaliBatchMaxCommands = 8,
    A5MaliClearBGRA = 1,
    A5MaliCopyBGRA = 2,
    A5MaliDrawTexturedQuadBGRA = 3,
    A5MaliReadSurfBGRA = 4,
    A5MaliCompleted = 0,
};

typedef struct {
    uint32_t version, size, reserved0, reserved1;
} A5MaliHeader;

typedef struct {
    uint32_t x, y, width, height;
} A5MaliRect;

typedef struct {
    uint64_t token;
    uint32_t width, height, rowBytes, usage;
} A5MaliResource;

typedef struct {
    uint64_t tilerFence, fragmentFence;
} A5MaliFence;

typedef struct {
    uint32_t operation, color;
    const A5MaliResource *source, *destination;
    A5MaliRect sourceRect, destinationRect;
} A5MaliBatchCommand;

typedef struct {
    uint32_t status;
    A5MaliFence fence;
} A5MaliBatchItem;

typedef struct {
    uint32_t count, completedCount, failedIndex;
    A5MaliBatchItem items[A5MaliBatchMaxCommands];
} A5MaliBatchResult;

typedef kern_return_t (*A5MaliTransport)(void *context, uint32_t selector,
    const void *input, size_t inputSize, void *output, size_t *outputSize);

typedef struct {
    A5MaliTransport call;
    void *context;
    io_connect_t connection;
    int ownsConnection;
    uint32_t gpuCommandsSupported;
    uint32_t supportedOperations;
} A5MaliClient;

/* Open the opt-in, entitlement-gated A5XELTEGPU service. */
kern_return_t A5MaliOpen(A5MaliClient *client);
kern_return_t A5MaliOpenService(A5MaliClient *client, io_service_t service);
void A5MaliClose(A5MaliClient *client);

/* Tests may inject transport without claiming a Metal or IOGPU service. */
kern_return_t A5MaliInitTransport(A5MaliClient *client,
    A5MaliTransport call, void *context);
kern_return_t A5MaliInitTransportWithCapabilities(A5MaliClient *client,
    A5MaliTransport call, void *context, uint32_t gpuCommandsSupported);

/* Caller retains the send right until A5MaliImportSurface returns. */
kern_return_t A5MaliImportSurface(A5MaliClient *client,
    mach_port_t surfacePort, uint32_t usage, A5MaliResource *resource);
kern_return_t A5MaliReleaseSurface(A5MaliClient *client,
    A5MaliResource *resource);
kern_return_t A5MaliClear(A5MaliClient *client,
    const A5MaliResource *destination, A5MaliRect rect, uint32_t bgra,
    A5MaliFence *fence);
kern_return_t A5MaliCopy(A5MaliClient *client,
    const A5MaliResource *source, A5MaliRect sourceRect,
    const A5MaliResource *destination, A5MaliRect destinationRect,
    A5MaliFence *fence);
kern_return_t A5MaliDrawTexturedQuad(A5MaliClient *client,
    const A5MaliResource *source, A5MaliRect sourceRect,
    const A5MaliResource *destination, A5MaliRect destinationRect,
    A5MaliFence *fence);
/* 0154 proof fixture: equal 1080x1920 BGRA8 full surfaces, stride 4320. */
kern_return_t A5MaliReadSurf(A5MaliClient *client,
    const A5MaliResource *source, const A5MaliResource *destination,
    A5MaliFence *fence);
kern_return_t A5MaliSubmitBatchCommands(A5MaliClient *client,
    const A5MaliBatchCommand *commands, uint32_t count,
    A5MaliBatchResult *result);

#endif
