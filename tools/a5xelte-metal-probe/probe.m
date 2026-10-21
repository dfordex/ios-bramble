/*
 * iOS graphics-discovery probe for the A5XELTE bring-up. When the private
 * client is available, it submits one bounded 16x16 GPU fixture.
 * This deliberately does not register an IOAccelerator or implement Metal.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurfaceRef.h>
#include <IOKit/IOKitLib.h>
#include <inttypes.h>
#include <stdio.h>

typedef struct {
    uint32_t version;
    uint32_t size;
    uint32_t reserved0;
    uint32_t reserved1;
} A5GPUQuery;

typedef struct {
    A5GPUQuery header;
    uint32_t maxResources;
    uint32_t supportedOperations;
    uint32_t gpuCommandsSupported;
    uint32_t reserved;
} A5GPUQueryResult;

typedef struct {
    A5GPUQuery header;
    uint32_t surfacePort;
    uint32_t usage;
    uint64_t reserved;
} A5GPUImport;

typedef struct {
    A5GPUQuery header;
    uint64_t handle;
    uint32_t width;
    uint32_t height;
    uint32_t bytesPerRow;
    uint32_t pixelFormat;
} A5GPUImportResult;

typedef struct {
    A5GPUQuery header;
    uint64_t handle;
} A5GPURelease;

typedef struct {
    A5GPUQuery header;
    uint64_t handle;
    uint32_t x;
    uint32_t y;
} A5GPUSampleRequest;

typedef struct {
    A5GPUQuery header;
    uint32_t status;
    uint32_t matchingPixels;
    uint64_t tilerFence;
    uint64_t fragmentFence;
    uint32_t pixels[16 * 16];
} A5GPUSampleResult;

_Static_assert(sizeof(A5GPUQuery) == 16, "query ABI size");
_Static_assert(sizeof(A5GPUQueryResult) == 32, "query result ABI size");
_Static_assert(sizeof(A5GPUImport) == 32, "import ABI size");
_Static_assert(sizeof(A5GPUImportResult) == 40, "import result ABI size");
_Static_assert(sizeof(A5GPURelease) == 24, "release ABI size");
_Static_assert(sizeof(A5GPUSampleRequest) == 32, "sample request ABI size");
_Static_assert(sizeof(A5GPUSampleResult) == 1064, "sample result ABI size");

static void
probe_surface_import(io_connect_t connection)
{
    NSDictionary *properties = @{
        (__bridge NSString *)kIOSurfaceWidth: @16,
        (__bridge NSString *)kIOSurfaceHeight: @16,
        (__bridge NSString *)kIOSurfaceBytesPerElement: @4,
        (__bridge NSString *)kIOSurfaceBytesPerRow: @64,
        (__bridge NSString *)kIOSurfacePixelFormat: @(0x42475241),
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!surface) {
        printf("A5XELTEGPU test surface: create failed\n");
        return;
    }
    kern_return_t kr = IOSurfaceLock(surface, 0, NULL);
    if (kr != KERN_SUCCESS) {
        printf("A5XELTEGPU test surface: lock failed 0x%08x\n", kr);
        CFRelease(surface);
        return;
    }
    uint32_t *pixels = IOSurfaceGetBaseAddress(surface);
    if (!pixels) {
        printf("A5XELTEGPU test surface: no base address\n");
        IOSurfaceUnlock(surface, 0, NULL);
        CFRelease(surface);
        return;
    }
    for (uint32_t y = 0; y < 16; ++y)
        for (uint32_t x = 0; x < 16; ++x)
            pixels[y * 16 + x] = 0xff000000u | (y << 8) | x;
    IOSurfaceUnlock(surface, 0, NULL);
    mach_port_t port = IOSurfaceCreateMachPort(surface);
    if (port == MACH_PORT_NULL) {
        printf("A5XELTEGPU test surface: Mach port create failed\n");
        CFRelease(surface);
        return;
    }

    const A5GPUImport request = {{1, sizeof(request), 0, 0}, port, 1, 0};
    A5GPUImportResult result = {0};
    size_t result_size = sizeof(result);
    kr = IOConnectCallStructMethod(connection, 1, &request,
        sizeof(request), &result, &result_size);
    printf("A5XELTEGPU surface import: 0x%08x size=%zu handle=%" PRIu64
        " geometry=%" PRIu32 "x%" PRIu32 " stride=%" PRIu32
        " pixel_format=0x%08" PRIx32 "\n", kr, result_size,
        result.handle, result.width, result.height, result.bytesPerRow,
        result.pixelFormat);
    if (kr == KERN_SUCCESS && result.handle != 0) {
        const A5GPUSampleRequest sample_request = {
            {1, sizeof(sample_request), 0, 0}, result.handle, 0, 0};
        A5GPUSampleResult sample_result = {0};
        size_t sample_size = sizeof(sample_result);
        kern_return_t sample_kr = IOConnectCallStructMethod(connection, 3,
            &sample_request, sizeof(sample_request), &sample_result,
            &sample_size);
        printf("A5XELTEGPU sample: 0x%08x size=%zu status=%" PRIu32
            " matches=%" PRIu32 " fences=%" PRIu64 "/%" PRIu64 "\n",
            sample_kr, sample_size, sample_result.status,
            sample_result.matchingPixels, sample_result.tilerFence,
            sample_result.fragmentFence);
        const A5GPURelease release = {{1, sizeof(release), 0, 0}, result.handle};
        size_t release_output_size = 0;
        kr = IOConnectCallStructMethod(connection, 2, &release,
            sizeof(release), NULL, &release_output_size);
        printf("A5XELTEGPU surface release: 0x%08x\n", kr);
    }
    mach_port_deallocate(mach_task_self(), port);
    CFRelease(surface);
}

static void
inspect_class(const char *name, bool query_private_client)
{
    CFMutableDictionaryRef matching = IOServiceMatching(name);
    if (!matching) {
        printf("service %s: cannot create matching dictionary\n", name);
        return;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        matching, &iterator); /* IOServiceGetMatchingServices consumes matching. */
    if (kr != KERN_SUCCESS) {
        printf("service %s: match error 0x%08x\n", name, kr);
        return;
    }

    unsigned int count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        ++count;
        if (count == 1) {
            io_name_t actual_class = {0};
            io_name_t entry_name = {0};
            IOObjectGetClass(service, actual_class);
            IORegistryEntryGetName(service, entry_name);
            printf("service %s: first class=%s name=%s\n", name,
                actual_class, entry_name);

            if (query_private_client) {
                io_connect_t connection = IO_OBJECT_NULL;
                kr = IOServiceOpen(service, mach_task_self(), 0, &connection);
                printf("A5XELTEGPU client open: 0x%08x\n", kr);
                if (kr == KERN_SUCCESS) {
                    const A5GPUQuery input = {1, sizeof(input), 0, 0};
                    A5GPUQueryResult output = {0};
                    size_t output_size = sizeof(output);
                    kr = IOConnectCallStructMethod(connection, 0, &input,
                        sizeof(input), &output, &output_size);
                    printf("A5XELTEGPU query: 0x%08x size=%zu version=%" PRIu32
                        " resources=%" PRIu32 " operations=0x%08" PRIx32
                        " gpu_commands=%" PRIu32 "\n", kr, output_size,
                        output.header.version, output.maxResources,
                        output.supportedOperations, output.gpuCommandsSupported);
                    if (kr == KERN_SUCCESS &&
                        output.supportedOperations == 7 &&
                        output.gpuCommandsSupported == 1)
                        probe_surface_import(connection);
                    IOServiceClose(connection);
                }
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    printf("service %s: count=%u\n", name, count);
}

int
main(void)
{
    @autoreleasepool {
        printf("A5XELTE graphics discovery probe v1\n");
        inspect_class("A5XELTEGPU", true);
        inspect_class("IOAcceleratorES", false);
        inspect_class("IOGPU", false);

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            printf("Metal default device: none\n");
        } else {
            printf("Metal default device: %s\n",
                device.name.UTF8String ?: "(unnamed)");
            id<MTLCommandQueue> queue = [device newCommandQueue];
            printf("Metal command queue: %s\n", queue ? "created" : "none");
        }
    }
    return 0;
}
