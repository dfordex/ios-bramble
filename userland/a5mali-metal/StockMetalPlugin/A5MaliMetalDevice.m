/* SPDX-License-Identifier: MIT
 * Source-only stock Metal entry-point scaffold. No Metal protocol is claimed;
 * the kernel discovery proxy is disabled in ordinary builds.
 */
#import "../A5MaliRestrictedDevice.h"

@interface A5MaliMetalDevice : A5MaliRestrictedDevice
@end

@implementation A5MaliMetalDevice

- (instancetype)initWithAcceleratorPort:(io_service_t)service
{
    if (!service || !IOObjectConformsTo(service, "A5XELTEGPUAccelerator"))
        return nil;

    io_registry_entry_t privateGPU = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(service, kIOServicePlane,
                                     &privateGPU) != KERN_SUCCESS)
        return nil;
    BOOL isPrivateGPU = IOObjectConformsTo(privateGPU, "A5XELTEGPU");
    id result = isPrivateGPU ? [super initWithAcceleratorPort:privateGPU] : nil;
    IOObjectRelease(privateGPU);
    return result;
}

@end
