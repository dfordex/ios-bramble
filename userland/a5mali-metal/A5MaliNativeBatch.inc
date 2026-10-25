/* Internal preparation session. No synthetic hardware fence is returned. */
typedef struct {
 A5MaliClient *client;A5MaliTransport call;void *context;
 uint8_t *packet;unsigned count,accepted;int queryValid;
 A5NativeQueryRequest query;A5NativeQueryResult mapped;
 A5MaliFence last; kern_return_t error;
} A5NativeBatchSession;
static _Thread_local A5NativeBatchSession *nativeBatch;
static kern_return_t a5NativeBatchFlush(void){
 A5NativeBatchSession*s=nativeBatch;if(!s||!s->count)return s?s->error:KERN_SUCCESS;
 unsigned count=s->count;s->count=0;
 size_t bytes=sizeof(A5NativeBatchRequest)+count*(sizeof(A5NativeSubmitRequest)+A5NativeJobBytes);
 A5NativeBatchRequest h={{1,(uint32_t)bytes,0,0},count,0};memcpy(s->packet,&h,sizeof(h));
 A5NativeBatchResult r={0};size_t size=sizeof(r);submissionMayBeActive=1;
 kern_return_t kr=s->call(s->context,A5NativeBatchSelector,s->packet,bytes,&r,&size);
 if(kr){if(kr==kIOReturnNotReady||kr==kIOReturnNotFound||kr==kIOReturnNoResources||kr==kIOReturnBadArgument)submissionMayBeActive=0;return s->error=kr;}
 if(size!=sizeof(r)||r.header.version!=1||r.header.size!=sizeof(r)||r.header.reserved0||r.header.reserved1||r.count!=count||r.reserved||r.completedCount>count||r.status>5||(!r.status&&r.completedCount!=count)||(r.status&&r.completedCount==count))return s->error=kIOReturnIOError;
 uint64_t previous=s->last.fragmentFence;
 for(unsigned i=0;i<r.completedCount;i++){
  A5NativeSubmitRequest q;memcpy(&q,s->packet+sizeof(h)+i*(sizeof(q)+A5NativeJobBytes),sizeof(q));
  A5NativeSubmitResult *v=&r.items[i];
  if(v->header.version!=1||v->header.size!=sizeof(*v)||v->header.reserved0||v->header.reserved1||v->status||v->reserved||!v->fragmentFence||v->fragmentFence<=previous||(q.profileID==0?v->tilerFence!=0:(!v->tilerFence||v->tilerFence<=previous||v->fragmentFence<=v->tilerFence)))return s->error=kIOReturnIOError;
  s->last=(A5MaliFence){v->tilerFence,v->fragmentFence};previous=v->fragmentFence;
 }
 if(r.status){if(r.status==1||r.status==2)submissionMayBeActive=0;return s->error=r.status==1?kIOReturnBadArgument:r.status==2?kIOReturnBusy:r.status==4?kIOReturnTimeout:kIOReturnIOError;}
 submissionMayBeActive=0;return KERN_SUCCESS;
}
static kern_return_t a5NativeBatchTransport(void *context,uint32_t selector,const void *in,size_t bytes,void*out,size_t*size){
 A5NativeBatchSession*s=context;if(s->error)return s->error;
 if(selector==A5NativeQuerySelector&&s->queryValid&&bytes==sizeof(s->query)&&in&&!memcmp(in,&s->query,bytes)&&out&&size&&*size>=sizeof(s->mapped)){
  memcpy(out,&s->mapped,sizeof(s->mapped));*size=sizeof(s->mapped);return KERN_SUCCESS;
 }
 kern_return_t kr=a5NativeBatchFlush();if(kr)return kr;s->queryValid=0;
 kr=s->call(s->context,selector,in,bytes,out,size);
 if(!kr&&selector==A5NativeQuerySelector&&in&&bytes==sizeof(s->query)&&out&&size&&*size==sizeof(s->mapped)){
  memcpy(&s->query,in,bytes);memcpy(&s->mapped,out,sizeof(s->mapped));s->queryValid=1;
 }
 return kr;
}
kern_return_t A5MaliBeginNativeBatch(A5MaliClient*c){
 if(nativeBatch)return kIOReturnBusy;
 if(!c||!c->call||(c->gpuCommandsSupported&(A5NativeCapability|A5NativeBatchCapability))!=(A5NativeCapability|A5NativeBatchCapability))return kIOReturnUnsupported;
 A5NativeBatchSession*s=calloc(1,sizeof(*s));if(!s)return kIOReturnNoMemory;
 s->packet=malloc(sizeof(A5NativeBatchRequest)+A5NativeBatchMax*(sizeof(A5NativeSubmitRequest)+A5NativeJobBytes));
 if(!s->packet){free(s);return kIOReturnNoMemory;}
 s->client=c;s->call=c->call;s->context=c->context;nativeBatch=s;c->call=a5NativeBatchTransport;c->context=s;return KERN_SUCCESS;
}
static kern_return_t a5NativeBatchAppend(const A5NativeSubmitRequest*q,const void*jobs){
 A5NativeBatchSession*s=nativeBatch;if(s->error)return s->error;
 if(s->count){A5NativeSubmitRequest first;memcpy(&first,s->packet+sizeof(A5NativeBatchRequest),sizeof(first));
  if(s->count==A5NativeBatchMax||!A5NativeSameMapping(&first,q)){kern_return_t kr=a5NativeBatchFlush();if(kr)return kr;}}
 size_t offset=sizeof(A5NativeBatchRequest)+s->count*(sizeof(*q)+A5NativeJobBytes);
 memcpy(s->packet+offset,q,sizeof(*q));memcpy(s->packet+offset+sizeof(*q),jobs,A5NativeJobBytes);++s->count;s->accepted=1;return KERN_SUCCESS;
}
int A5MaliNativeBatchAccepted(A5MaliClient*c){return nativeBatch&&nativeBatch->client==c&&nativeBatch->accepted;}
kern_return_t A5MaliEndNativeBatch(A5MaliClient*c,int commit,A5MaliFence*f){
 if(f)memset(f,0,sizeof(*f));A5NativeBatchSession*s=nativeBatch;if(!s)return KERN_SUCCESS;
 if(s->client!=c)return kIOReturnBadArgument;
 kern_return_t kr=commit?a5NativeBatchFlush():s->error;
 if(f)*f=s->last;c->call=s->call;c->context=s->context;nativeBatch=NULL;free(s->packet);free(s);return kr;
}
