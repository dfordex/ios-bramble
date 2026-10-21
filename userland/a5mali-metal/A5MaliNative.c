/* SPDX-License-Identifier: MIT */
#include "A5MaliNative.h"
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(A5NativeQueryRequest)==80,"native query ABI");
_Static_assert(sizeof(A5NativeQueryResult)==352,"native spans ABI");
_Static_assert(sizeof(A5NativeSubmitRequest)==120,"native submit ABI");
_Static_assert(sizeof(A5NativeSubmitResult)==40,"native fences ABI");
static int valid(A5NativeHeader h,size_t bytes,size_t actual)
{ return h.version==1 && h.size==bytes && actual==bytes && !h.reserved0 && !h.reserved1; }
static kern_return_t nativeCall(A5MaliClient *c,uint32_t selector,
 const void *in,size_t count,void *out,size_t *size)
{
 if (!c || !(c->gpuCommandsSupported&A5NativeCapability) || !c->call)
  return kIOReturnUnsupported;
 return c->call(c->context,selector,in,count,out,size);
}
kern_return_t A5MaliQueryNative(A5MaliClient *c,const A5NativeQueryRequest *q,
 A5NativeQueryResult *r)
{
 if (!q || !r || !valid(q->header,sizeof(*q),sizeof(*q))) return kIOReturnBadArgument;
 A5NativeQueryResult result={0}; size_t size=sizeof(result);
 kern_return_t kr=nativeCall(c,A5NativeQuerySelector,q,sizeof(*q),&result,&size);
 if (kr) return kr;
 if (!valid(result.header,sizeof(result),size) || !result.flags ||
     result.jobVA!=A5NativeJobVA || result.jobBytes!=A5NativeJobBytes)
  return kIOReturnBadArgument;
 for (unsigned i=0;i<A5NativeSlots;i++) {
  if (result.surfaces[i].token!=q->surfaces[i] || result.buffers[i].token!=q->buffers[i])
   return kIOReturnBadArgument;
  if (q->surfaces[i] && (!result.surfaces[i].gpuVA || !result.surfaces[i].bytes))
   return kIOReturnBadArgument;
  if (q->buffers[i] && (!result.buffers[i].gpuVA || !result.buffers[i].bytes))
   return kIOReturnBadArgument;
 }
 *r=result; return KERN_SUCCESS;
}
kern_return_t A5MaliSubmitNative(A5MaliClient *c,const A5NativeSubmitRequest *q,
 const void *jobs,A5MaliFence *f)
{
 if (f) memset(f,0,sizeof(*f));
 if (!q || !jobs || !f || q->jobBytes!=A5NativeJobBytes ||
   !valid(q->header,sizeof(*q),sizeof(*q)) || q->reserved || !q->mappingEpoch ||
   (q->readSurfaces|q->writeSurfaces|q->readBuffers)&~15u || !q->writeSurfaces ||
   q->fragmentOffset>=q->jobBytes-256 || (q->fragmentOffset&15u) ||
   (q->profileID==0 ? (q->vertexOffset!=UINT32_MAX || q->tilerOffset!=UINT32_MAX) :
    (q->vertexOffset>=q->jobBytes-256 || q->tilerOffset>=q->jobBytes-256 ||
     ((q->vertexOffset|q->tilerOffset)&15u))))
  return kIOReturnBadArgument;
 size_t count=sizeof(*q)+q->jobBytes;
 uint8_t *input=malloc(count); if (!input) return kIOReturnNoMemory;
 memcpy(input,q,sizeof(*q)); memcpy(input+sizeof(*q),jobs,q->jobBytes);
 A5NativeSubmitResult r={0}; size_t size=sizeof(r);
 kern_return_t kr=nativeCall(c,A5NativeSubmitSelector,input,count,&r,&size);
 free(input); if (kr) return kr;
 if (!valid(r.header,sizeof(r),size) || r.reserved || r.status>5)
  return kIOReturnBadArgument;
 if (r.status) return r.status==1?kIOReturnBadArgument:r.status==2?kIOReturnBusy:
   r.status==4?kIOReturnTimeout:kIOReturnIOError;
 if (!r.fragmentFence || (q->profileID==0 ? r.tilerFence!=0 :
     (!r.tilerFence || r.fragmentFence<=r.tilerFence))) return kIOReturnIOError;
 f->tilerFence=r.tilerFence; f->fragmentFence=r.fragmentFence; return KERN_SUCCESS;
}
