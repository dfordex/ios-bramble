/* Actual upload/session code: bytes are consumed by mock terminal GPU jobs. */
#include "A5MaliNative.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef struct {uint8_t *bytes;uint32_t size;uint64_t token;} BO;
static BO bo[4];static unsigned creates,releases,writes,queries,batches,draws,counts[16],fault,writeFail,releaseFail;
static uint64_t generation,fence;
static unsigned slot(uint64_t token){unsigned i=(uint32_t)token-0x101;assert(i<4&&bo[i].token==token);return i;}
static kern_return_t call(void*ctx,uint32_t sel,const void*input,size_t n,void*out,size_t*z){
 (void)ctx;
 if(sel==8){
  const uint32_t *q=input;assert(n==24);unsigned i;for(i=0;i<4&&bo[i].token;i++){}if(i==4){*z=0;return kIOReturnNoResources;}
  assert(*z==32);
  bo[i].size=q[4];bo[i].bytes=calloc(1,q[4]);bo[i].token=(++generation<<32)|(0x101+i);++creates;
  struct {A5NativeHeader h;uint64_t token;uint32_t bytes,usage;}r={{1,sizeof(r),0,0},bo[i].token,q[4],q[5]};
  memcpy(out,&r,sizeof(r));*z=sizeof(r);return 0;
 }
 if(sel==9){uint64_t token;memcpy(&token,(const uint8_t*)input+16,8);unsigned i=slot(token);
  if(releaseFail)return kIOReturnBusy;
  free(bo[i].bytes);memset(&bo[i],0,sizeof(bo[i]));++releases;*z=0;return 0;}
 if(sel==A5NativeBulkWriteSelector){
  const A5NativeBulkWriteRequest*q=input;unsigned i=slot(q->handle);assert(n==sizeof(*q)+q->length&&q->offset+q->length<=bo[i].size);
  if(writeFail)return kIOReturnIOError;memcpy(bo[i].bytes+q->offset,q+1,q->length);++writes;*z=0;return 0;
 }
 if(sel==A5NativeQuerySelector){
  const A5NativeQueryRequest*q=input;A5NativeQueryResult*r=out;memset(r,0,sizeof(*r));r->header=(A5NativeHeader){1,sizeof(*r),0,0};r->flags=(uint32_t)generation;r->jobVA=A5NativeJobVA;r->jobBytes=A5NativeJobBytes;
  for(unsigned i=0;i<4;i++){
   if(q->surfaces[i])r->surfaces[i]=(A5NativeSpan){q->surfaces[i],0x10000000,4096,16,16,64,0x42475241,3};
   if(q->buffers[i]){unsigned b=slot(q->buffers[i]);r->buffers[i]=(A5NativeSpan){.token=q->buffers[i],.gpuVA=0x20000000+b*0x800000,.bytes=bo[b].size,.usage=3};}
  }++queries;*z=sizeof(*r);return 0;
 }
 assert(sel==A5NativeBatchSelector);const A5NativeBatchRequest*h=input;assert(batches<16);counts[batches++]=h->count;
 A5NativeBatchResult*r=out;memset(r,0,sizeof(*r));r->header=(A5NativeHeader){1,sizeof(*r),0,0};r->count=h->count;
 if(fault){r->status=5;*z=sizeof(*r);return 0;}
 for(unsigned j=0;j<h->count;j++){
  const uint8_t*p=(const uint8_t*)input+sizeof(*h)+j*(sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
  A5NativeSubmitRequest q;memcpy(&q,p,sizeof(q));unsigned i=slot(q.buffers[0]);
  uint32_t payload[3];memcpy(payload,p+sizeof(q)+0x1000,sizeof(payload));assert(payload[0]+payload[1]<=bo[i].size);
  for(unsigned k=0;k<payload[1];k++)assert(bo[i].bytes[payload[0]+k]==payload[2]);
  ++draws;r->items[j].header=(A5NativeHeader){1,sizeof(r->items[j]),0,0};r->items[j].tilerFence=++fence;r->items[j].fragmentFence=++fence;++r->completedCount;
 }*z=sizeof(*r);return 0;
}
static A5MaliClient client(void){A5MaliClient c={.call=call,.gpuCommandsSupported=A5NativeCapability|A5NativeBatchCapability};return c;}
static void reset(void){for(unsigned i=0;i<4;i++){free(bo[i].bytes);memset(&bo[i],0,sizeof(bo[i]));}creates=releases=writes=queries=batches=draws=fault=writeFail=releaseFail=0;generation=fence=0;}
static void draw(A5MaliClient*c,uint32_t length,uint8_t value){
 uint8_t*bytes=malloc(length);memset(bytes,value,length);A5MaliNativeUploadPart part={bytes,length};uint64_t handle;uint32_t offset;
 A5MaliBeginNativeSubmissionTracking();assert(!A5MaliStageNativeUploads(c,1,&part,&handle,&offset));free(bytes);
 A5NativeQueryRequest query={.header={1,sizeof(query),0,0},.surfaces={0x100000001},.buffers={handle}};A5NativeQueryResult mapped;
 assert(!A5MaliQueryNative(c,&query,&mapped));uint8_t*jobs=calloc(1,A5NativeJobBytes);uint32_t*w=(uint32_t*)jobs;
 w[4]=(1u<<16)|11;w[6]=A5NativeJobVA+256;w[0x110/4]=(2u<<16)|15;w[0x114/4]=1;w[0x210/4]=(3u<<16)|19;
 uint32_t payload[3]={offset,length,value};memcpy(jobs+0x1000,payload,sizeof(payload));
 A5NativeSubmitRequest q={.header={1,sizeof(q),0,0},.jobBytes=A5NativeJobBytes,.vertexOffset=0,.tilerOffset=256,.fragmentOffset=512,.writeSurfaces=1,.readBuffers=1,.profileID=99,.mappingEpoch=mapped.flags};memcpy(q.surfaces,query.surfaces,sizeof(q.surfaces));q.buffers[0]=handle;A5MaliFence f;
 assert(!A5MaliSubmitNative(c,&q,jobs,&f)&&!f.fragmentFence);free(jobs);
}
int main(void){A5MaliClient c=client();A5MaliFence f;
 assert(!A5MaliBeginNativeBatch(&c));for(unsigned i=0;i<16;i++)draw(&c,127,(uint8_t)(i+1));
 assert(creates==1&&releases==0&&queries==1&&batches==1&&counts[0]==8);
 assert(!A5MaliEndNativeBatch(&c,1,&f));assert(batches==2&&counts[1]==8&&draws==16&&releases==1&&writes==2&&f.fragmentFence==32);
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));for(unsigned i=0;i<3;i++)draw(&c,0x20000,(uint8_t)(i+1));
 assert(!A5MaliEndNativeBatch(&c,1,&f));assert(creates==1&&batches==2&&counts[0]==2&&counts[1]==1&&draws==3&&releases==1);
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);draw(&c,0x80000,2);assert(!A5MaliEndNativeBatch(&c,1,&f));assert(creates==2&&releases==2&&draws==2);
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);assert(!A5MaliEndNativeBatch(&c,0,&f));assert(!draws&&!writes&&releases==1&&!f.fragmentFence);
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);writeFail=1;assert(A5MaliEndNativeBatch(&c,1,&f)==kIOReturnIOError);assert(!draws&&releases==1&&!A5MaliNativeSubmissionMayBeActive());
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);fault=1;assert(A5MaliEndNativeBatch(&c,1,&f)==kIOReturnIOError);assert(!releases&&c.nativeUploadQuarantine[0]&&A5MaliNativeSubmissionMayBeActive());assert(A5MaliBeginNativeBatch(&c)==kIOReturnNotReady);
 reset();A5MaliBeginNativeSubmissionTracking();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);
 struct {A5NativeHeader h;uint32_t bytes,usage;} create={{1,sizeof(create),0,0},4096,3};
 struct {A5NativeHeader h;uint64_t handle;uint32_t bytes,usage;} created;
 uint64_t ordinary[4];
 for(unsigned i=0;i<4;i++){size_t size=sizeof(created);assert(!c.call(c.context,8,&create,sizeof(create),&created,&size));ordinary[i]=created.handle;}
 assert(draws==1&&creates==5&&releases==1);assert(!A5MaliEndNativeBatch(&c,1,&f));
 for(unsigned i=0;i<4;i++){struct {A5NativeHeader h;uint64_t handle;}q={{1,sizeof(q),0,0},ordinary[i]};size_t z=0;assert(!call(NULL,9,&q,sizeof(q),NULL,&z));}
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));uint8_t bytes[17]={0};A5MaliNativeUploadPart parts[4];for(unsigned i=0;i<4;i++)parts[i]=(A5MaliNativeUploadPart){bytes,sizeof(bytes)};
 uint64_t handles[4];uint32_t offsets[4];assert(!A5MaliStageNativeUploads(&c,4,parts,handles,offsets));size_t z=sizeof(created);
 assert(c.call(c.context,8,&create,sizeof(create),&created,&z)==kIOReturnNoResources&&!releases&&!draws);
 assert(!A5MaliEndNativeBatch(&c,0,&f)&&releases==4);
 reset();c=client();assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,1);releaseFail=1;assert(A5MaliEndNativeBatch(&c,1,&f)==kIOReturnBusy&&draws==1&&!releases&&c.nativeUploadQuarantine[0]);
 reset();c=client();c.nativeUploadReuse=1;
 assert(!A5MaliBeginNativeBatch(&c));draw(&c,127,0x31);assert(!A5MaliEndNativeBatch(&c,1,&f));
 assert(c.nativeUploadPool&&creates==1&&!releases&&draws==1);
 assert(!A5MaliBeginNativeBatch(&c));draw(&c,127,0x52);
 assert(A5MaliEvictIdleNativeUpload(&c)==kIOReturnNoResources); /* current immutable slice is protected */
 assert(!A5MaliEndNativeBatch(&c,1,&f));assert(creates==1&&!releases&&draws==2&&f.fragmentFence==4&&writes==2);
 assert(!A5MaliEvictIdleNativeUpload(&c)&&releases==1);A5MaliDiscardNativeUploads(&c);assert(!c.nativeUploadPool);
 assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,0x63);assert(!A5MaliEndNativeBatch(&c,1,&f));
 assert(c.nativeUploadPool&&creates==2);assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,0x74);fault=1;
 assert(A5MaliEndNativeBatch(&c,1,&f)==kIOReturnIOError&&!c.nativeUploadPool&&c.nativeUploadQuarantine[0]);
 reset();A5MaliBeginNativeSubmissionTracking();c=client();c.nativeUploadReuse=1;
 assert(!A5MaliBeginNativeBatch(&c));draw(&c,17,0x85);assert(!A5MaliEndNativeBatch(&c,1,&f));
 releaseFail=1;assert(A5MaliEvictIdleNativeUpload(&c)==kIOReturnBusy&&c.nativeUploadQuarantine[0]);
 A5MaliDiscardNativeUploads(&c);assert(!c.nativeUploadPool);reset();
 puts("PASS actual native upload arena: 8+8 real groups, immutable bytes, cross-CB reuse after real fences, idle eviction, protected pending slices, fault/release quarantine, rollover and abort");return 0;
}
