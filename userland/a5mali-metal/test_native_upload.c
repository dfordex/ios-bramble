/* SPDX-License-Identifier: MIT
 * Exact wire/chunk/lifetime tests; transport is injected, no GPU claim.
 */
#include "A5MaliNativeUpload.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { A5MaliHeader header; uint32_t bytes,usage; } Create;
typedef struct { A5MaliHeader header; uint64_t handle; uint32_t bytes,usage; } Created;
typedef struct {const uint8_t*data;unsigned calls,chunks,release,failChunk,releaseBusy;uint32_t copied,bytes;} State;
static const uint64_t token=UINT64_C(0x123400000101);
static kern_return_t transport(void*context,uint32_t selector,const void*in,size_t count,void*out,size_t*size){
 State*s=context;++s->calls;
 if(selector==8){const Create*q=in;assert(count==sizeof(*q)&&q->header.size==count&&q->bytes==s->bytes&&q->usage==3);
  assert(*size==sizeof(Created));*(Created*)out=(Created){{1,sizeof(Created),0,0},token,q->bytes,q->usage};return KERN_SUCCESS;}
 if(selector==9){assert(count==24&&((const uint64_t*)in)[2]==token);++s->release;assert(!*size);return s->releaseBusy?kIOReturnBusy:KERN_SUCCESS;}
 assert(selector==A5NativeBulkWriteSelector);const A5NativeBulkWriteRequest*q=in;
 assert(q->header.version==1&&q->header.size==count&&!q->header.reserved0&&!q->header.reserved1&&q->handle==token);
 assert(q->length&&q->length<=A5NativeBulkWriteMax&&count==sizeof(*q)+q->length&&q->offset==s->copied);
 assert(!memcmp((const uint8_t*)in+sizeof(*q),s->data+q->offset,q->length));++s->chunks;
 if(s->chunks==s->failChunk)return kIOReturnIOError;
 s->copied+=q->length;assert(!*size);return KERN_SUCCESS;
}
int main(void){
 uint8_t*data=malloc(A5NativeBufferMax);assert(data);for(unsigned i=0;i<A5NativeBufferMax;++i)data[i]=(uint8_t)(i*37+19);
 State s={.data=data,.bytes=A5NativeBufferMax};A5MaliClient c={.call=transport,.context=&s,.gpuCommandsSupported=A5NativeCapability,
  .supportedOperations=(1u<<7)|(1u<<8)|(1u<<18)};uint64_t handle=0;
 assert(A5MaliCreateNativeBuffer(&c,A5NativeBufferMax,data,A5NativeBufferMax,&handle)==KERN_SUCCESS);
 assert(handle==token&&s.chunks==8&&s.copied==A5NativeBufferMax&&!s.release);
 assert(A5MaliReleaseNativeBuffer(&c,handle)==KERN_SUCCESS&&s.release==1);
 s=(State){.data=data,.bytes=0x102000};handle=0;
 assert(A5MaliCreateNativeBuffer(&c,0x101001,data,0x100011,&handle)==KERN_SUCCESS&&handle==token);
 assert(s.chunks==2&&s.copied==0x100011);assert(A5MaliReleaseNativeBuffer(&c,handle)==KERN_SUCCESS);
 s=(State){.data=data,.bytes=A5NativeBufferMax,.failChunk=2};
 assert(A5MaliCreateNativeBuffer(&c,A5NativeBufferMax,data,A5NativeBufferMax,&handle)==kIOReturnIOError&&!handle&&s.release==1);
 s=(State){.data=data,.bytes=A5NativeBufferMax,.failChunk=2,.releaseBusy=1};
 assert(A5MaliCreateNativeBuffer(&c,A5NativeBufferMax,data,A5NativeBufferMax,&handle)==kIOReturnIOError&&handle==token&&s.release==1);
 s.releaseBusy=0;assert(A5MaliReleaseNativeBuffer(&c,handle)==KERN_SUCCESS);
 s=(State){.data=data,.bytes=A5NativeBufferMax};c.supportedOperations&=~(1u<<18);
 assert(A5MaliCreateNativeBuffer(&c,4096,data,4096,&handle)==kIOReturnUnsupported&&!handle&&!s.calls);
 assert(A5MaliCreateNativeBuffer(&c,A5NativeBufferMax+1,data,4096,&handle)==kIOReturnBadArgument&&!s.calls);
 free(data);puts("PASS real native upload wire:8MiB/1MiBchunks+tail byteexact; failed upload cleanup; busy release retains token; unsupported/oversize reject (injected transport, no GPU claim)");return 0;
}
