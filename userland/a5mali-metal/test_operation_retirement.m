/* SPDX-License-Identifier: MIT
 * Retained public command buffers must release terminal operation captures;
 * ambiguous Submit18 outcomes must keep them. Kernel transport is mocked. */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliNative.h"
#include "../a5xelte-air-translation/families/runtime_clear.h"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>
@interface A5MaliMetalBuffer (RetirementTest)
- (A5MaliCommandBuffer*)privateBuffer;
- (void)markEncodingError:(kern_return_t)error selector:(SEL)selector;
@end
@interface A5MaliRestrictedDevice (RetirementTest)
- (A5MaliDevice*)privateDevice;
@end
enum {Success,EncodingError,PreSubmitError,KernelRejected,StaleEpoch,
      ResourceMissing,ResourceLimit,IOError,Timeout,BadReply};
typedef struct{unsigned mode,submits,releases;} State;
static kern_return_t wire(void*context,uint32_t selector,const void*in,size_t n,void*out,size_t*z){
 State*s=context;
 if(selector==A5MaliUnmap)return KERN_SUCCESS;
 if(selector==A5MaliRelease){s->releases++;return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector&&n==sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
 const A5NativeSubmitRequest*q=in;assert(q->profileID==0);s->submits++;
 if(s->mode==Timeout)return kIOReturnTimeout;
 if(s->mode==StaleEpoch)return kIOReturnNotReady;
 if(s->mode==ResourceMissing)return kIOReturnNotFound;
 if(s->mode==ResourceLimit)return kIOReturnNoResources;
 if(s->mode==IOError)return kIOReturnIOError;
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.fragmentFence=41};
 if(s->mode==KernelRejected){r.status=1;r.fragmentFence=0;}
 if(s->mode==BadReply)r.header.size=0;
 assert(*z==sizeof(r));memcpy(out,&r,sizeof(r));*z=sizeof(r);return KERN_SUCCESS;
}
static void encode(A5MaliMetalBuffer*b,A5MaliRestrictedDevice*d,State*s,__weak A5MaliSurface**weak){
 @autoreleasepool{
  A5MaliSurface*surface=[[d privateDevice]hostTestSurfaceWithResource:(A5MaliResource){0x100000001,32,32,128,3}];
  assert(surface);*weak=surface;
  BOOL accepted=[[b privateBuffer]encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){
   assert(surface.width==32);if(s->mode==PreSubmitError)return kIOReturnBadArgument;
   A5RuntimeClear clear={.descriptorGPUVA=A5NativeJobVA,.destination={0x13000000,4096,32,32,128,80},.color={0,0,0,1}};
   NSMutableData*jobs=[NSMutableData dataWithLength:A5NativeJobBytes];assert(!A5MaliEncodeRuntimeClear(&clear,jobs.mutableBytes,jobs.length));
   A5NativeSubmitRequest submit={.header={1,sizeof(submit),0,0},.jobBytes=A5NativeJobBytes,
    .vertexOffset=UINT32_MAX,.tilerOffset=UINT32_MAX,.fragmentOffset=0,.writeSurfaces=1,.profileID=0,.mappingEpoch=1};
   submit.surfaces[0]=0x100000001;
   return A5MaliSubmitNative(c,&submit,jobs.bytes,f);
  }];assert(accepted);
 }
}
int main(){@autoreleasepool{
 alarm(30); /* catches release callbacks attempting to reenter a held transport lock */
 for(unsigned mode=0;mode<=BadReply;mode++){@autoreleasepool{
  State state={.mode=mode};
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state commandCapabilities:32 operationCapabilities:0x30000];assert(d);
  A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];__weak A5MaliSurface*owner=nil;
  encode(b,d,&state,&owner);assert(owner&&!state.releases);
  if(mode==EncodingError)[b markEncodingError:kIOReturnUnsupported selector:@selector(commit)];
  [b commit];[b waitUntilCompleted];
  assert(b.status==(mode==Success?MTLCommandBufferStatusCompleted:MTLCommandBufferStatusError));
  assert(state.submits==((mode==EncodingError||mode==PreSubmitError)?0u:1u));
  BOOL ambiguous=mode==Timeout||mode==BadReply||mode==IOError;
  assert((owner!=nil)==ambiguous&&state.releases==!ambiguous);
  /* Keep b alive: success/cancellation releases are not delayed until dealloc. */
  assert([b privateBuffer]&&b.status>=MTLCommandBufferStatusCompleted);
 }}
 State repeated={.mode=Success};
 A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&repeated commandCapabilities:32 operationCapabilities:0x30000];
 NSMutableArray *retained=[NSMutableArray new];
 for(unsigned i=0;i<40;i++){@autoreleasepool{
  A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];__weak A5MaliSurface*owner=nil;
  encode(b,d,&repeated,&owner);[retained addObject:b];[b commit];[b waitUntilCompleted];
  assert(!owner&&repeated.releases==i+1&&retained.count==i+1);
 }}
 assert(retained.count==40&&repeated.submits==40&&repeated.releases==40);
 puts("PASS retained CB terminal/cancel/pre-submit/kernel-reject/timeout/malformed-reply owner retirement and 40 retained completed buffers; mocked transport only");
}return 0;}
