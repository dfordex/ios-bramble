/* SPDX-License-Identifier: MIT
 * Runs the unmodified OS Metal discovery entry point after bundle install.
 * Reports acceptance separately from render or shader capability.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
        fprintf(stderr, "A5XELTE Metal: requesting stock MTLCreateSystemDefaultDevice\n");
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fprintf(stderr, "A5XELTE Metal: stock device acceptance FAILED (nil)\n");
            return 1;
        }
        SEL ready = NSSelectorFromString(@"a5MaliAcceptanceInitialized");
        BOOL initialized = [device respondsToSelector:ready] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(device, ready);
        if (!initialized || ![device.name hasPrefix:@"Mali-T720"] ||
            ![device conformsToProtocol:@protocol(MTLDevice)] ||
            ![device conformsToProtocol:NSProtocolFromString(@"MTLDeviceSPI")]) {
            fprintf(stderr, "A5XELTE Metal: unexpected stock device %s class=%s\n",
                device.name.UTF8String, class_getName(object_getClass(device)));
            return 2;
        }
        fprintf(stderr, "A5XELTE Metal: STOCK DEVICE ACCEPTED name=%s registry=%llu maxBuffer=%lu\n",
            device.name.UTF8String, (unsigned long long)device.registryID,
            (unsigned long)device.maxBufferLength);
        id queue = [device newCommandQueue];
        fprintf(stderr, "A5XELTE Metal: bounded command queue %s\n", queue ? "created" : "unavailable");
        return queue ? 0 : 3;
    }
}
