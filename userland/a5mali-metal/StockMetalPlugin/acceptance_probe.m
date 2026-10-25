/* SPDX-License-Identifier: MIT
 * Runs the unmodified OS Metal discovery entry point after bundle install.
 * Reports acceptance separately from render or shader capability.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>
#include "../../a5xelte-stock-apps/A5StockApps.h"
extern char **environ;

static int metalProbe(void)
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

int main(int argc,char **argv)
{
    if(argc==2&&!strcmp(argv[1],"--register-stock-apps"))return A5RegisterSelectedStockApps();
    if(argc!=1)return 64;
    /* A fresh signed process keeps registration's XPC/container startup out
     * of Metal discovery. Retain the parent until it finishes so launchd
     * cannot discard an unowned child when this one-shot job exits. */
    pid_t registrationPID=0;
    char *registrationArgs[]={"/usr/libexec/a5mali-metal-probe","--register-stock-apps",NULL};
    int spawnError=posix_spawn(&registrationPID,registrationArgs[0],NULL,NULL,registrationArgs,environ);
    fprintf(stderr,"A5XELTE Apps: registration helper spawn=%d pid=%d\n",spawnError,registrationPID);
    int metalStatus=metalProbe();
    if(!spawnError){
        int status=0;pid_t result;
        do {result=waitpid(registrationPID,&status,0);} while(result<0&&errno==EINTR);
        fprintf(stderr,"A5XELTE Apps: registration helper wait=%d exit=%d signal=%d\n",
            result==registrationPID,WIFEXITED(status)?WEXITSTATUS(status):-1,
            WIFSIGNALED(status)?WTERMSIG(status):0);
    }
    return metalStatus;
}
