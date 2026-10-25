/* SPDX-License-Identifier: MIT
 * Reproduce the observed64-operation compositor ceiling with the actual
 * private command list. Work/fences are mocked; no physical GPU is used. */
#import "A5MaliCommandBuffer.h"
#include <assert.h>
static kern_return_t transport(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;assert(!"software queue test must not use IOKit");return kIOReturnError;}
int main(void){@autoreleasepool{
 unsigned context=0;
 A5MaliDevice*d=[[A5MaliDevice alloc]initWithTransport:transport context:&context commandCapabilities:32 operationCapabilities:0x30000];
 for(unsigned trial=0;trial<2;trial++){@autoreleasepool{
  unsigned count=trial?A5MaliCommandOperationLimit:96;__block unsigned executed=0;
  A5MaliCommandBuffer*b=[d newCommandBuffer];__weak NSObject*retained=nil;
  @autoreleasepool{
   NSObject*owner=[NSObject new];retained=owner;
   for(unsigned i=0;i<count;i++)assert(([b encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){
    (void)c;assert(owner&&executed==i);executed++;*f=(A5MaliFence){2*i+1,2*i+2};return KERN_SUCCESS;
   }]));
  }
  assert(retained&&executed==0);
  if(trial)assert(![b encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){(void)c;(void)f;assert(0);return KERN_SUCCESS;}]);
  NSError*error=nil;assert([b commitAndWait:&error]&&!error&&executed==count&&!retained);
  assert(b.completedFence.fragmentFence==2*count);
  assert(![b commitAndWait:&error]&&error);
 }}
 puts("PASS96/4096 software operations preserve order/fences, reject4097, retire captures and reject recommit; mocked GPU only");
}return 0;}
