/* SPDX-License-Identifier: MIT
 * Distinguish selector1 table quota from selector4 physical mapping failure.
 * The actual bridge must return the failure and release partial imports. */
#include "A5MaliBridge.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t width,height,row,format;}Imported;
typedef struct{unsigned failSelector,imports,maps,releases;}State;
static kern_return_t wire(void*p,uint32_t selector,const void*in,size_t n,void*out,size_t*z){
 State*s=p;(void)in;(void)n;
 if(selector==A5MaliImport){s->imports++;if(s->failSelector==selector)return kIOReturnNoResources;
  Imported r={{1,sizeof(r),0,0},UINT64_C(0x100000021),128,64,512,0x42475241};
  assert(*z==sizeof(r));memcpy(out,&r,sizeof(r));*z=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5MaliMap){s->maps++;assert(s->failSelector==selector);return kIOReturnNoResources;}
 assert(selector==A5MaliRelease);s->releases++;return KERN_SUCCESS;
}
int main(void){
 for(unsigned selector=A5MaliImport;selector<=A5MaliMap;selector+=A5MaliMap-A5MaliImport){
  State state={.failSelector=selector};A5MaliClient client={0};A5MaliResource resource={0};
  assert(!A5MaliInitTransportWithCapabilities(&client,wire,&state,32));
  assert(A5MaliImportSurface(&client,1,3,&resource)==kIOReturnNoResources&&!resource.token);
  assert(state.imports==1&&state.maps==(selector==A5MaliMap)&&state.releases==(selector==A5MaliMap));
 }
 puts("PASS actual bridge selector1/selector4 failure identity and partial import release; mocked transport only");
}
