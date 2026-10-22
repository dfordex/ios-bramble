/* SPDX-License-Identifier: MIT
 * Actual external aliases, retained bindings and queued native-work lifetime.
 * Only the transport/fences are mocked; no shader execution/pixels claimed.
 */
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    atomic_uint deallocations;
    unsigned baseline,submits;
    BOOL fail;
    void *expectedPointer;
    NSUInteger expectedLength;
} State;
static kern_return_t transport(void *context,uint32_t selector,const void *input,
    size_t inputBytes,void *output,size_t *outputBytes)
{
    State *s=context;
    assert(selector==A5NativeSubmitSelector);
    const A5NativeSubmitRequest *q=input;
    assert(inputBytes==sizeof(*q)+A5NativeJobBytes&&q->profileID==602&&q->mappingEpoch==1);
    assert(atomic_load(&s->deallocations)==s->baseline); /* still owned before terminal fence */
    const uint8_t *jobs=(const uint8_t *)input+sizeof(*q);
    assert(!memcmp(jobs+0x4000,s->expectedPointer,s->expectedLength));
    for(NSUInteger i=0;i<s->expectedLength;++i)assert(jobs[0x4000+i]==(uint8_t)(i*37+11));
    ++s->submits;if(s->fail)return kIOReturnTimeout;
    A5NativeSubmitResult result={.header={1,sizeof(result),0,0},.tilerFence=90,.fragmentFence=91};
    assert(*outputBytes==sizeof(result));memcpy(output,&result,sizeof(result));*outputBytes=sizeof(result);
    return KERN_SUCCESS;
}
static A5MaliRestrictedDevice *device(State *s,uint32_t commands,uint32_t operations)
{
    return [[A5MaliRestrictedDevice alloc]initWithTransport:transport context:s
        commandCapabilities:commands operationCapabilities:operations];
}
static void queuedOwnership(A5MaliRestrictedDevice *device,State *s,BOOL failure)
{
    enum { bytes=200704 }; /* actual observed QC page-aligned allocation */
    void *memory=NULL;assert(!posix_memalign(&memory,A5MaliBufferPageSize,bytes));memset(memory,0x22,bytes);
    s->expectedPointer=memory;s->expectedLength=bytes;s->baseline=atomic_load(&s->deallocations);s->fail=failure;
    __weak A5MaliRestrictedDevice *weakDevice=device;
    __weak A5MaliPrivateBuffer *weakBuffer;
    @autoreleasepool {
        A5MaliPrivateBuffer *buffer=[device newBufferWithBytesNoCopy:memory length:bytes options:0
            deallocator:^(void *p,NSUInteger length){
                assert(p==s->expectedPointer&&length==bytes&&weakDevice);
                assert(A5MaliAllocatedSharedReadBufferBytes(weakDevice)==0);
                atomic_fetch_add(&s->deallocations,1);free(p);
            }];
        assert(buffer&&buffer.contents==memory&&buffer.length==bytes&&buffer.allocatedSize==bytes);
        assert(buffer.storageMode==MTLStorageModeShared&&buffer.resourceOptions==0&&!buffer.privateKernelHandle);
        assert(buffer.readyForRead&&A5MaliAllocatedSharedReadBufferBytes(device)==bytes);
        weakBuffer=buffer;
        A5MaliBufferBinding *binding=[A5MaliBufferBinding bindingWithBuffer:buffer offset:0 length:bytes device:device error:NULL];
        assert(binding&&!binding.inlineBytes&&!binding.privateKernelHandle);
        A5MaliCommandBuffer *command=[[device newPrivateCommandQueue]newCommandBuffer];
        BOOL queued=[command encodeNativeWork:^kern_return_t(A5MaliClient *client,A5MaliFence *fence){
            assert(atomic_load(&s->deallocations)==s->baseline);
            NSData *captured=[binding captureBytesForSubmission:NULL];assert(captured.length==bytes);
            NSMutableData *jobs=[NSMutableData dataWithLength:A5NativeJobBytes];uint32_t *w=jobs.mutableBytes;
            /* Valid native envelope only. Transport is mocked: these headers
             * are not claimed to be an executable GPU shader program. */
            w[4]=(1u<<16)|11u;w[6]=A5NativeJobVA+0x100;
            w[0x110/4]=(2u<<16)|15u;w[0x114/4]=1;w[0x210/4]=(3u<<16)|19u;
            memcpy((uint8_t *)jobs.mutableBytes+0x4000,captured.bytes,captured.length);
            A5NativeSubmitRequest q={.header={1,sizeof(q),0,0},.jobBytes=A5NativeJobBytes,
                .vertexOffset=0,.tilerOffset=0x100,.fragmentOffset=0x200,.readSurfaces=1,.writeSurfaces=1,
                .profileID=602,.mappingEpoch=1,.surfaces={UINT64_C(0x100000001)}};
            return A5MaliSubmitNative(client,&q,jobs.bytes,fence);
        }];assert(queued);
        buffer=nil;binding=nil;
        assert(weakBuffer&&atomic_load(&s->deallocations)==s->baseline);
        /* Later external writes must be visible at commit, without calling
         * uploadBytes or replacing the externally supplied allocation. */
        for(NSUInteger i=0;i<bytes;++i)((uint8_t *)memory)[i]=(uint8_t)(i*37+11);
        NSError *error=nil;BOOL complete=[command commitAndWait:&error];
        assert(complete!=failure);
        if(failure)assert(error.code==kIOReturnTimeout&&!command.completedFence.fragmentFence);
        else assert(!error&&command.completedFence.tilerFence==90&&command.completedFence.fragmentFence==91);
        assert(atomic_load(&s->deallocations)==s->baseline&&weakBuffer);
        command=nil;
    }
    assert(!weakBuffer&&atomic_load(&s->deallocations)==s->baseline+1);
    assert(!A5MaliAllocatedSharedReadBufferBytes(device));
}
int main(void)
{
    @autoreleasepool {
        State s={0};const uint32_t native=(1u<<16)|(1u<<17);
        A5MaliRestrictedDevice *d=device(&s,63,127|native);
        queuedOwnership(d,&s,NO);queuedOwnership(d,&s,YES);assert(s.submits==2);
        void *memory=NULL;assert(!posix_memalign(&memory,4096,8192));memset(memory,0,8192);
        unsigned baseline=atomic_load(&s.deallocations);
        State *state=&s;
        void (^releaseMemory)(void *,NSUInteger)=^(void *p,NSUInteger n){(void)p;(void)n;atomic_fetch_add(&state->deallocations,1);};
        assert(![d newBufferWithBytesNoCopy:NULL length:4096 options:0 deallocator:releaseMemory]);
        assert(![d newBufferWithBytesNoCopy:memory length:0 options:0 deallocator:releaseMemory]);
        assert(![d newBufferWithBytesNoCopy:(uint8_t *)memory+1 length:4096 options:0 deallocator:releaseMemory]);
        assert(![d newBufferWithBytesNoCopy:memory length:4095 options:0 deallocator:releaseMemory]);
        assert(![d newBufferWithBytesNoCopy:memory length:A5MaliMaxPrivateBufferLength+4096 options:0 deallocator:releaseMemory]);
        assert(![d newBufferWithBytesNoCopy:(void *)(UINTPTR_MAX-4095) length:4096 options:0 deallocator:releaseMemory]);
        /* Managed's public numeric storage value is1, independently of the
         * hostSDK deprecation: this test requires its explicit rejection. */
        for(NSNumber *options in @[@(MTLResourceStorageModePrivate),@((NSUInteger)1<<MTLResourceStorageModeShift),
            @(MTLResourceStorageModeMemoryless),@(MTLResourceCPUCacheModeWriteCombined),@(MTLResourceHazardTrackingModeUntracked)])
            assert(![d newBufferWithBytesNoCopy:memory length:4096 options:options.unsignedIntegerValue deallocator:releaseMemory]);
        for(unsigned variant=0;variant<3;++variant){
            A5MaliRestrictedDevice *old=device(&s,variant?63:31,variant==1?(1u<<16):variant==2?(1u<<17):native);
            assert(![old newBufferWithBytesNoCopy:memory length:4096 options:0 deallocator:releaseMemory]);
        }
        assert(atomic_load(&s.deallocations)==baseline&&!A5MaliAllocatedSharedReadBufferBytes(d));
        @autoreleasepool {
            A5MaliPrivateBuffer *alias=[d newBufferWithBytesNoCopy:memory length:8192 options:0 deallocator:nil];
            assert(alias.contents==memory);uint8_t value=0xa7,out=0;
            assert([alias uploadBytes:&value offset:8191 length:1]==KERN_SUCCESS&&((uint8_t *)memory)[8191]==value);
            ((uint8_t *)memory)[17]=0x55;
            assert([alias readBytes:&out offset:17 length:1]==KERN_SUCCESS&&out==0x55);
            assert([alias readBytes:&out offset:8192 length:1]==kIOReturnBadArgument);
        }
        assert(((uint8_t *)memory)[8191]==0xa7&&!A5MaliAllocatedSharedReadBufferBytes(d));free(memory);
        /* Account external aliases against the existing64MiB shared budget.
         * No deallocator means these wrappers never free caller memory. */
        assert(!posix_memalign(&memory,4096,A5MaliMaxPrivateBufferLength));
        @autoreleasepool {
            NSMutableArray *aliases=[NSMutableArray new];
            for(unsigned i=0;i<8;++i){id alias=[d newBufferWithBytesNoCopy:memory length:A5MaliMaxPrivateBufferLength options:0 deallocator:nil];assert(alias);[aliases addObject:alias];}
            assert(A5MaliAllocatedSharedReadBufferBytes(d)==64*1024*1024);
            assert(![d newBufferWithBytesNoCopy:memory length:4096 options:0 deallocator:releaseMemory]);
            assert(![d newBufferWithLength:1 options:0]);
            assert(atomic_load(&s.deallocations)==baseline);
        }
        assert(!A5MaliAllocatedSharedReadBufferBytes(d));free(memory);
        puts("no-copy buffers: real200704-byte alias, commit-time external writes, binding/job lifetime, terminal/error fences, exact-once deallocator, nil-owner/invalid/capability/quota cases PASS (mock transport; no GPU pixels)");
    }
    return 0;
}
