/* SPDX-License-Identifier: MIT */
#include "A5MaliNativeUpload.h"
#include <stdlib.h>
#include <string.h>
enum { CreateSelector=8,ReleaseSelector=9 };
typedef struct { A5MaliHeader header; uint32_t bytes,usage; } CreateRequest;
typedef struct { A5MaliHeader header; uint64_t handle; uint32_t bytes,usage; } CreateResult;
typedef struct { A5MaliHeader header; uint64_t handle; } ReleaseRequest;
_Static_assert(sizeof(CreateRequest)==24&&sizeof(CreateResult)==32&&sizeof(ReleaseRequest)==24,"existing kernel buffer ABI");
_Static_assert(sizeof(A5NativeBulkWriteRequest)==32,"bulk header ABI");
static int supported(A5MaliClient*c,unsigned selector){
 return c&&c->call&&(c->gpuCommandsSupported&A5NativeCapability)&&
  (c->supportedOperations&(1u<<(selector-1)));
}
static int valid_handle(uint64_t h){uint32_t slot=(uint32_t)h;return(h>>32)&&slot>=0x101&&slot<0x105;}
static int valid_header(A5MaliHeader h,size_t actual,size_t expected){
 return actual==expected&&h.version==1&&h.size==expected&&!h.reserved0&&!h.reserved1;
}
kern_return_t A5MaliReleaseNativeBuffer(A5MaliClient*c,uint64_t handle){
 if(!valid_handle(handle))return kIOReturnBadArgument;
 if(!supported(c,ReleaseSelector))return kIOReturnUnsupported;
 ReleaseRequest request={{1,sizeof(request),0,0},handle};size_t output=0;
 return c->call(c->context,ReleaseSelector,&request,sizeof(request),NULL,&output);
}
kern_return_t A5MaliCreateNativeBuffer(A5MaliClient*c,uint32_t bytes,
 const void*source,uint32_t length,uint64_t*handle){
 if(handle)*handle=0;
 if(!handle||!source||!bytes||bytes>A5NativeBufferMax||!length||length>bytes)return kIOReturnBadArgument;
 if(!supported(c,CreateSelector)||!supported(c,ReleaseSelector)||!supported(c,A5NativeBulkWriteSelector))return kIOReturnUnsupported;
 uint32_t allocation=(bytes+4095)&~4095u;
 CreateRequest request={{1,sizeof(request),0,0},allocation,A5MaliRead|A5MaliWrite};
 CreateResult reply={0};size_t output=sizeof(reply);
 kern_return_t result=c->call(c->context,CreateSelector,&request,sizeof(request),&reply,&output);
 if(result)return result;
 if(valid_handle(reply.handle))*handle=reply.handle;
 if(!valid_header(reply.header,output,sizeof(reply))||!*handle||reply.bytes!=allocation||reply.usage!=request.usage){
  if(*handle&&A5MaliReleaseNativeBuffer(c,*handle)==KERN_SUCCESS)*handle=0;
  return kIOReturnBadArgument;
 }
 size_t capacity=sizeof(A5NativeBulkWriteRequest)+A5NativeBulkWriteMax;
 uint8_t*input=malloc(capacity);
 if(!input){result=kIOReturnNoMemory;goto fail;}
 for(uint32_t offset=0;offset<length;){
  uint32_t count=length-offset;if(count>A5NativeBulkWriteMax)count=A5NativeBulkWriteMax;
  A5NativeBulkWriteRequest bulk={{1,(uint32_t)(sizeof(bulk)+count),0,0},*handle,offset,count};
  memcpy(input,&bulk,sizeof(bulk));memcpy(input+sizeof(bulk),(const uint8_t*)source+offset,count);
  output=0;result=c->call(c->context,A5NativeBulkWriteSelector,input,sizeof(bulk)+count,NULL,&output);
  if(result)break;
  if(output){result=kIOReturnBadArgument;break;}
  offset+=count;
 }
 free(input);if(result)goto fail;return KERN_SUCCESS;
fail:
 if(A5MaliReleaseNativeBuffer(c,*handle)==KERN_SUCCESS)*handle=0;
 return result;
}
