/* SPDX-License-Identifier: MIT */
#include "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
static int calls;
static unsigned fail;
static kern_return_t transport(void *context,uint32_t selector,const void *in,
 size_t bytes,void *out,size_t *outSize)
{
 (void)context;calls++;
 if (selector==17) {
  assert(bytes==sizeof(A5NativeQueryRequest));
  const A5NativeQueryRequest *q=in; A5NativeQueryResult *r=out;
  memset(r,0,sizeof(*r));r->header=(A5NativeHeader){1,sizeof(*r),0,0};
  r->jobVA=A5NativeJobVA;r->jobBytes=A5NativeJobBytes;r->flags=1;
  r->surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,4096,16,16,64,0x42475241,1};
  r->surfaces[1]=(A5NativeSpan){q->surfaces[1],0x10800000,4096,16,16,64,0x42475241,2};
  if(fail==1)r->surfaces[1].token++;
  *outSize=sizeof(*r);return 0;
 }
 assert(selector==18 && bytes==sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
 const A5NativeSubmitRequest *q=in;
 assert(q->profileID==99 && !memcmp((const char *)in+sizeof(*q)+0x2f00,"REAL",4));
 A5NativeSubmitResult *r=out;memset(r,0,sizeof(*r));
 r->header=(A5NativeHeader){1,sizeof(*r),0,0};r->tilerFence=5;r->fragmentFence=6;
 if(fail==2)r->fragmentFence=0;
 if(fail==3)r->status=5;
 *outSize=sizeof(*r);return 0;
}
int main(void)
{
 A5MaliClient c={0};assert(!A5MaliInitTransportWithCapabilities(&c,transport,0,32));
 A5NativeQueryRequest q={.header={1,sizeof(q),0,0},.surfaces={0x100000001,0x100000002}};
 A5NativeQueryResult r={0};assert(!A5MaliQueryNative(&c,&q,&r));
 fail=1;assert(A5MaliQueryNative(&c,&q,&r)==kIOReturnBadArgument);fail=0;
 void *jobs=calloc(1,A5NativeJobBytes);assert(jobs);memcpy((char *)jobs+0x2f00,"REAL",4);
 uint32_t *w=jobs;w[4]=(1u<<16)|11u;w[6]=A5NativeJobVA+256;
 w[0x110/4]=(2u<<16)|15u;w[0x114/4]=1;
 w[0x210/4]=(3u<<16)|19u;
 A5NativeSubmitRequest s={.header={1,sizeof(s),0,0},.jobBytes=A5NativeJobBytes,
  .vertexOffset=0,.tilerOffset=256,.fragmentOffset=512,.readSurfaces=1,
  .writeSurfaces=2,.profileID=99,.mappingEpoch=1};memcpy(s.surfaces,q.surfaces,sizeof(s.surfaces));
 A5MaliFence fence={0};assert(!A5MaliSubmitNative(&c,&s,jobs,&fence));assert(fence.fragmentFence==6);
 fail=2;assert(A5MaliSubmitNative(&c,&s,jobs,&fence)==kIOReturnIOError);assert(!fence.fragmentFence);
 fail=3;assert(A5MaliSubmitNative(&c,&s,jobs,&fence)==kIOReturnIOError);fail=0;
 int before=calls;
 w[6]=A5NativeJobVA+A5NativePreloadOffset;
 w[(A5NativePreloadOffset+16)/4]=(2u<<16)|15u;
 w[(A5NativePreloadOffset+20)/4]=1;
 w[(A5NativePreloadOffset+24)/4]=A5NativeJobVA+256;
 w[0x110/4]=(3u<<16)|15u;w[0x114/4]=1u|(2u<<16);
 assert(!A5MaliSubmitNative(&c,&s,jobs,&fence));before=calls;
 w[(A5NativePreloadOffset+24)/4]=A5NativeJobVA;
 assert(A5MaliSubmitNative(&c,&s,jobs,&fence)==kIOReturnBadArgument);assert(calls==before);
 w[(A5NativePreloadOffset+24)/4]=A5NativeJobVA+256;
 s.jobBytes++;assert(A5MaliSubmitNative(&c,&s,jobs,&fence)==kIOReturnBadArgument);assert(calls==before);s.jobBytes--;
 s.fragmentOffset=A5NativeJobBytes;assert(A5MaliSubmitNative(&c,&s,jobs,&fence)==kIOReturnBadArgument);assert(calls==before);
 c.gpuCommandsSupported=0;assert(A5MaliQueryNative(&c,&q,&r)==kIOReturnUnsupported);assert(calls==before);
 free(jobs);return 0;
}
