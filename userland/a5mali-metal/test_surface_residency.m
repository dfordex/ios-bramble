/* SPDX-License-Identifier: MIT
 * Actual import/release/lazy getters and operation scopes; only the bounded
 * kernel transport is mocked. IOSurface objects and Mach rights are real.
 */
#import "A5MaliCommandBuffer.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
@interface A5MaliSurface (ResidencyTest)
- (A5MaliResource)resource;
@end
typedef struct {IOSurfaceRef surface;uint32_t generation;BOOL mapped;} Slot;
typedef struct {
 Slot slots[128];unsigned capacity,live,peak,imports,releases,unmaps,failedReleases,queries,submits;
 BOOL failUnmap,failRelease,active,failSubmit,poisoned,wrongGeometry;uint64_t activeTokens[128];unsigned activeCount;
} Transport;
static Slot *lookup(Transport*t,uint64_t token){unsigned i=(unsigned)token;uint32_t g=(uint32_t)(token>>32);
 if(!i||i>t->capacity)return NULL;Slot*s=t->slots+i-1;return s->surface&&g==s->generation?s:NULL;}
static kern_return_t call(void*opaque,uint32_t sel,const void*in,size_t bytes,void*out,size_t*outBytes){
 Transport*t=opaque;
 if(sel==A5MaliImport){
  typedef struct {A5MaliHeader h;uint32_t port,usage;uint64_t reserved;} Q;
  typedef struct {A5MaliHeader h;uint64_t handle;uint32_t width,height,row,format;} R;
  const Q*q=in;assert(bytes==sizeof(*q));unsigned at=t->capacity;
  for(unsigned i=0;i<t->capacity;++i)if(!t->slots[i].surface){at=i;break;}
  if(at==t->capacity)return kIOReturnNoResources;
  IOSurfaceRef surface=IOSurfaceLookupFromMachPort(q->port);assert(surface);
  Slot*s=t->slots+at;s->surface=surface;if(!s->generation)s->generation=1;
  R r={{1,sizeof(r),0,0},((uint64_t)s->generation<<32)|(at+1),16,16,64,0x42475241};
  if(t->wrongGeometry)r.width=8;
  assert(IOSurfaceGetWidth(surface)==16&&IOSurfaceGetHeight(surface)==16);
  memcpy(out,&r,sizeof(r));assert(*outBytes==sizeof(r));++t->live;++t->imports;
  if(t->peak<t->live)t->peak=t->live;return KERN_SUCCESS;
 }
 if(sel==A5MaliMap){
  typedef struct {A5MaliHeader h;uint64_t token;} Q;typedef struct{A5MaliHeader h;uint64_t token;uint32_t bytes,flags;}R;
  uint64_t token=((const Q*)in)->token;Slot*s=lookup(t,token);if(!s)return kIOReturnNotFound;s->mapped=YES;
  R r={{1,sizeof(r),0,0},token,4096,3};assert(*outBytes==sizeof(r));memcpy(out,&r,sizeof(r));return KERN_SUCCESS;
 }
 if(sel==A5MaliUnmap||sel==A5MaliRelease){
  typedef struct {A5MaliHeader h;uint64_t token;}Q;uint64_t token=((const Q*)in)->token;Slot*s=lookup(t,token);
  if(!s)return kIOReturnNotFound;
  if(t->poisoned){++t->failedReleases;return kIOReturnBusy;}
  for(unsigned i=0;i<t->activeCount;++i)assert(token!=t->activeTokens[i]);
  if(sel==A5MaliUnmap){if(t->failUnmap){++t->failedReleases;return kIOReturnBusy;}s->mapped=NO;++t->unmaps;}
  else {if(t->failRelease){++t->failedReleases;return kIOReturnError;}
   assert(!s->mapped);CFRelease(s->surface);s->surface=NULL;++s->generation;--t->live;++t->releases;}
  return KERN_SUCCESS;
 }
 if(sel==A5NativeSubmitSelector){
  const A5NativeSubmitRequest*q=in;assert(bytes==sizeof(*q)+A5NativeJobBytes);++t->submits;
  for(unsigned i=0;i<4;++i)if(q->surfaces[i])assert(lookup(t,q->surfaces[i]));
  if(t->failSubmit){t->poisoned=YES;return kIOReturnTimeout;}
  A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.tilerFence=1,.fragmentFence=2};
  assert(*outBytes==sizeof(r));memcpy(out,&r,sizeof(r));return KERN_SUCCESS;
 }
 assert(!"unexpected selector");return kIOReturnUnsupported;
}
static IOSurfaceRef pixels(void){return IOSurfaceCreate((__bridge CFDictionaryRef)@{
 (__bridge id)kIOSurfaceWidth:@16,(__bridge id)kIOSurfaceHeight:@16,
 (__bridge id)kIOSurfaceBytesPerElement:@4,(__bridge id)kIOSurfaceBytesPerRow:@64,
 (__bridge id)kIOSurfacePixelFormat:@(0x42475241)});}
static A5MaliDevice*device(Transport*t,unsigned cap){t->capacity=cap;return [[A5MaliDevice alloc]
 initWithTransport:call context:t commandCapabilities:63 operationCapabilities:(1u<<16)|(1u<<17)];}
static A5MaliSurface*import(A5MaliDevice*d){IOSurfaceRef s=pixels();assert(s);uint32_t*p=IOSurfaceGetBaseAddress(s);p[0]=0xfacea531;
 A5MaliSurface*r=[d importSurface:s usage:3 error:NULL];CFRelease(s);return r;}
static uint8_t *jobs(void){uint8_t*p=calloc(1,A5NativeJobBytes);assert(p);
 uint32_t word=(5u<<1)|1;memcpy(p+16,&word,4);uint64_t next=A5NativeJobVA+0x100;memcpy(p+24,&next,8);
 word=(7u<<1)|1;memcpy(p+0x110,&word,4);word=(9u<<1)|1;memcpy(p+0x210,&word,4);return p;}
static void success(Transport*t,A5MaliDevice*d,NSArray<A5MaliSurface*>*surfaces,BOOL exhaust){
 A5MaliCommandBuffer*b=[d newCommandBuffer];
 assert(([b encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){
  t->activeCount=0;
  for(A5MaliSurface*s in surfaces){uint64_t token=s.resource.token;assert(token&&lookup(t,token));
   t->activeTokens[t->activeCount++]=token;}
  if(exhaust){A5MaliSurface*extra=import(d);assert(!extra&&t->live==t->capacity);}
  A5NativeSubmitRequest q={.header={1,sizeof(q),0,0},.jobBytes=A5NativeJobBytes,.profileID=603,.tilerOffset=0x100,.fragmentOffset=0x200,.writeSurfaces=1,.mappingEpoch=1};
  for(unsigned i=0;i<surfaces.count&&i<4;++i)q.surfaces[i]=t->activeTokens[i];
  uint8_t*bytes=jobs();kern_return_t kr=A5MaliSubmitNative(c,&q,bytes,f);free(bytes);
  t->activeCount=0;return kr;
 }]));assert([b commitAndWait:NULL]);
}
int main(void){@autoreleasepool{
 /* More live retained textures than the kernel quota, with unchanged pixels. */
 Transport t={0};@autoreleasepool{A5MaliDevice*d=device(&t,128);NSMutableArray*held=[NSMutableArray new];
 for(unsigned i=0;i<384;++i){A5MaliSurface*s=import(d);assert(s);[held addObject:s];}
 assert(t.live==128&&t.peak==128&&t.releases==256);
 A5MaliSurface*first=held[0];uint64_t old=((uint64_t)1<<32)|1;
 assert(!lookup(&t,old));uint64_t restored=first.resource.token;
 assert(restored&&restored!=old&&lookup(&t,restored));
 assert(*(uint32_t*)IOSurfaceGetBaseAddress(first.iosurface)==0xfacea531);
 success(&t,d,@[held[0],held[128],held[256]],NO);
 /* Same IOSurface imported twice retains its stable ID despite generations. */
 A5MaliSurface*alias=[d importSurface:first.iosurface usage:3 error:NULL];assert(alias);
 assert(IOSurfaceGetID(alias.iosurface)==IOSurfaceGetID(first.iosurface));
 success(&t,d,@[first,alias],NO);
 [held removeAllObjects];first=nil;alias=nil;}assert(t.live==0);
 /* All current-operation leases remain resident; no capacity increase. */
 Transport busy={0};A5MaliDevice*bd=device(&busy,4);NSMutableArray*all=[NSMutableArray new];
 for(unsigned i=0;i<4;++i)[all addObject:import(bd)];success(&busy,bd,all,YES);
 assert(busy.live==4&&!busy.releases);assert(import(bd));
 /* Failed unmap OR release cannot create a reusable slot or stale generation. */
 for(unsigned mode=0;mode<2;++mode){Transport failure={0};@autoreleasepool{A5MaliDevice*fd=device(&failure,4);NSMutableArray*keep=[NSMutableArray new];
  for(unsigned i=0;i<4;++i)[keep addObject:import(fd)];failure.failUnmap=!mode;failure.failRelease=mode;
  assert(!import(fd));assert(failure.live==4&&failure.releases==0&&failure.failedReleases==4);
  failure.failUnmap=failure.failRelease=NO;
  assert(!import(fd)); /* quarantined candidates are not retried/reused */
  [keep removeAllObjects];}assert(failure.live==0);
 }
 /* Cached geometry is immutable across reimport; mismatch fails once and
  * quarantines instead of exposing a fresh token with stale texture layout. */
 Transport shape={0};@autoreleasepool{A5MaliDevice*sd=device(&shape,4);NSMutableArray*saved=[NSMutableArray new];
  for(unsigned i=0;i<8;++i)[saved addObject:import(sd)];shape.wrongGeometry=YES;
  A5MaliSurface*original=saved[0];A5MaliResource invalid=original.resource;
  assert(!invalid.token&&invalid.width==16);unsigned attempted=shape.imports;
  assert(!original.resource.token&&shape.imports==attempted);
 }assert(!shape.live);
 /* Unknown GPU completion quarantines leased backing even if mock kernel
  * would accept a release later. It cannot be chosen for cache pressure. */
 Transport gpu={0};@autoreleasepool{A5MaliDevice*gd=device(&gpu,4);NSMutableArray*images=[NSMutableArray new];
 for(unsigned i=0;i<4;++i)[images addObject:import(gd)];gpu.failSubmit=YES;
 A5MaliCommandBuffer*cb=[gd newCommandBuffer];assert(([cb encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){
  A5NativeSubmitRequest q={.header={1,sizeof(q),0,0},.jobBytes=A5NativeJobBytes,.profileID=603,.tilerOffset=0x100,.fragmentOffset=0x200,.writeSurfaces=1,.mappingEpoch=1};
  for(unsigned i=0;i<4;++i)q.surfaces[i]=((A5MaliSurface*)images[i]).resource.token;
  uint8_t*bytes=jobs();kern_return_t kr=A5MaliSubmitNative(c,&q,bytes,f);free(bytes);return kr;
 }]));assert(![cb commitAndWait:NULL]&&A5MaliNativeSubmissionMayBeActive());
 assert(!import(gd)&&gpu.live==4&&gpu.releases==0);
 }assert(gpu.live==4&&gpu.releases==0&&gpu.failedReleases==4);
 /* Before-submit rejection has no active DMA and must not quarantine. */
 Transport pre={0};A5MaliDevice*pd=device(&pre,4);NSMutableArray*before=[NSMutableArray new];
 for(unsigned i=0;i<4;++i)[before addObject:import(pd)];A5MaliCommandBuffer*reject=[pd newCommandBuffer];
 assert(([reject encodeNativeWork:^kern_return_t(A5MaliClient*c,A5MaliFence*f){(void)c;(void)f;
  for(A5MaliSurface*s in before)assert(s.resource.token);return kIOReturnBadArgument;}]));
 assert(![reject commitAndWait:NULL]);assert(import(pd)&&pre.releases==1);
 puts("PASS bounded128 residency/384live textures; pixel/backing ownership, stale generations, aliases, lazy reimport, all-busy pins, failed release/unmap, unknown GPU fence quarantine, pre-submit safe retirement");
 }return 0;}
