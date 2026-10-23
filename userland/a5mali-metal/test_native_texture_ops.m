/* SPDX-License-Identifier: MIT
 * Real Mac IOSurface storage and real native descriptor emitters. Only the
 * kernel transport/fences are mocked: these checks do not execute GPU pixels.
 */
#import "A5MaliNativeTextureOps.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
@interface A5MaliMetalBuffer (NativeTextureTest)
- (A5MaliCommandBuffer *)privateBuffer;
@end
@interface A5MaliSurface (NativeTextureTest)
- (A5MaliResource)resource;
@end
typedef struct { A5MaliHeader h;uint32_t port,usage;uint64_t reserved; } Import;
typedef struct { A5MaliHeader h;uint64_t token;uint32_t width,height,row,format; } Imported;
typedef struct { A5MaliHeader h;uint64_t token; } HandleRequest;
typedef struct { A5MaliHeader h;uint64_t token;uint32_t bytes,flags; } Mapped;
typedef struct {
 IOSurfaceRef surfaces[64];uint32_t usage[64];BOOL mapped[64];
 unsigned imports,releases,queries,submits,epoch,lastEpoch;
 uint64_t expectedSource,expectedDestination,mipSource[9],mipDestination[9];
 unsigned expectedProfile,failAtSubmit;BOOL sameAllocation,badFence,scratchCopy;
 __unsafe_unretained A5MaliTexturePassBacking *lease;
} State;
static unsigned indexFor(State*s,uint64_t token)
{assert(token>=UINT64_C(0x100000001));unsigned i=(unsigned)(token-UINT64_C(0x100000001));assert(i<s->imports&&s->surfaces[i]);return i;}
static uint64_t gpuVA(unsigned index){return UINT64_C(0x10000000)+(uint64_t)index*UINT64_C(0x02000000);}
static BOOL contains64(const uint8_t*p,size_t bytes,uint64_t value)
{for(size_t i=0;i+8<=bytes;i+=4){uint64_t v;memcpy(&v,p+i,8);if(v==value)return YES;}return NO;}
static kern_return_t wire(void*context,uint32_t selector,const void*input,size_t bytes,void*output,size_t*outBytes)
{
 State*s=context;
 if(selector==A5MaliImport){const Import*q=input;assert(bytes==sizeof(*q)&&s->imports<64);
  IOSurfaceRef surface=IOSurfaceLookupFromMachPort(q->port);assert(surface);unsigned i=s->imports++;
  s->surfaces[i]=surface;s->usage[i]=q->usage;
  Imported r={{1,sizeof(r),0,0},UINT64_C(0x100000001)+i,(uint32_t)IOSurfaceGetWidth(surface),
   (uint32_t)IOSurfaceGetHeight(surface),(uint32_t)IOSurfaceGetBytesPerRow(surface),IOSurfaceGetPixelFormat(surface)};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5MaliMap){const HandleRequest*q=input;unsigned i=indexFor(s,q->token);
  Mapped r={{1,sizeof(r),0,0},q->token,(uint32_t)IOSurfaceGetAllocSize(s->surfaces[i]),s->usage[i]};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5MaliUnmap)return KERN_SUCCESS;
 if(selector==A5MaliRelease){const HandleRequest*q=input;unsigned i=indexFor(s,q->token);
  CFRelease(s->surfaces[i]);s->surfaces[i]=NULL;++s->releases;return KERN_SUCCESS;}
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  assert(bytes==sizeof(*q)&&*outBytes==sizeof(A5NativeQueryResult));
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes};
  for(unsigned j=0;j<4;++j){assert(!q->buffers[j]);if(!q->surfaces[j])continue;
   unsigned i=indexFor(s,q->surfaces[j]);if(!s->mapped[i]){s->mapped[i]=YES;++s->epoch;}
   IOSurfaceRef v=s->surfaces[i];r.surfaces[j]=(A5NativeSpan){q->surfaces[j],gpuVA(i),
    IOSurfaceGetAllocSize(v),(uint32_t)IOSurfaceGetWidth(v),(uint32_t)IOSurfaceGetHeight(v),
    (uint32_t)IOSurfaceGetBytesPerRow(v),IOSurfaceGetPixelFormat(v),s->usage[i]};}
  if(s->sameAllocation)assert(q->surfaces[0]&&q->surfaces[0]==q->surfaces[1]&&
   r.surfaces[0].gpuVA==r.surfaces[1].gpuVA);
  if(s->scratchCopy){
   assert(s->submits<2&&q->surfaces[0]!=q->surfaces[1]&&!q->surfaces[2]&&!q->surfaces[3]);
   uint64_t original=UINT64_C(0x100000001),scratch=UINT64_C(0x100000002);
   assert(q->surfaces[0]==(s->submits?scratch:original));
   assert(q->surfaces[1]==(s->submits?original:scratch));
   assert(s->imports==2&&!s->releases&&s->surfaces[0]&&s->surfaces[1]);
  }
  r.flags=s->epoch;s->lastEpoch=r.flags;++s->queries;
  if(s->lease)assert(s->lease.valid);
  memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector);const A5NativeSubmitRequest*q=input;
 assert(bytes==sizeof(*q)+A5NativeJobBytes&&q->mappingEpoch==s->lastEpoch&&q->mappingEpoch==s->epoch);
 assert(q->profileID==s->expectedProfile&&q->writeSurfaces);
 const uint8_t*jobs=(const uint8_t*)input+sizeof(*q);
 if(q->profileID){assert(q->vertexOffset==0&&q->tilerOffset==0x100&&q->fragmentOffset==0x200);
  assert(q->readSurfaces==3&&q->writeSurfaces==2);
  uint64_t source;memcpy(&source,jobs+0x620,8);
  uint64_t expectedSource=s->sameAllocation?s->mipSource[s->submits]:s->expectedSource;
  uint64_t expectedDestination=s->sameAllocation?s->mipDestination[s->submits]:s->expectedDestination;
  if(s->scratchCopy){
   assert(s->submits<2&&q->surfaces[0]!=q->surfaces[1]);
   expectedSource=gpuVA(s->submits?1:0);
   expectedDestination=gpuVA(s->submits?0:1);
   assert(!s->releases&&s->surfaces[0]&&s->surfaces[1]);
  }
  assert(source==expectedSource);assert(contains64(jobs+0x300,0x140,expectedDestination));
  /* The first scratch draw fills its whole new target; the second writes
   * a region of the original and must preload its untouched destination. */
  int preload=q->profileID==500&&(!s->scratchCopy||s->submits!=0);
  assert(A5NativeCheckJobChain(jobs,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,NO)==preload);
 }else{assert(q->vertexOffset==UINT32_MAX&&q->tilerOffset==UINT32_MAX&&q->fragmentOffset==0);
  assert(!q->readSurfaces&&q->writeSurfaces==1);if(s->lease)assert(s->lease.valid);
  if(s->expectedDestination)assert(contains64(jobs+0x300,0x140,s->expectedDestination));}
 ++s->submits;A5NativeSubmitResult r={.header={1,sizeof(r),0,0},
  .tilerFence=q->profileID?1000+2*s->submits:0,.fragmentFence=1001+2*s->submits};
 if(s->badFence||(s->failAtSubmit&&s->submits==s->failAtSubmit))r.fragmentFence=0;
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
}
static A5MaliRestrictedDevice *device(State*s)
{return [[A5MaliRestrictedDevice alloc]initWithTransport:wire context:s commandCapabilities:63
 operationCapabilities:127|(1u<<16)|(1u<<17)];}
static A5MaliMetalTexture *texture(A5MaliRestrictedDevice*d,MTLPixelFormat f,unsigned w,unsigned h,BOOL mips,MTLStorageMode storage)
{MTLTextureDescriptor*p=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:w height:h mipmapped:mips];
 p.storageMode=storage;p.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
 A5MaliMetalTexture*t=[d newTextureWithDescriptor:p];assert(t);return t;}
static A5NativeSpan spanFor(A5MaliMetalTexture*t,unsigned i)
{A5MaliSurface*s=t.privateSurface;return(A5NativeSpan){s.resource.token,gpuVA(i),IOSurfaceGetAllocSize(s.iosurface),
 s.width,s.height,s.rowBytes,A5MaliTexturePixelCode(t.pixelFormat),A5MaliRead|A5MaliWrite};}
static void testBytesAndIdentity(void)
{
 State s={.epoch=1};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 const MTLPixelFormat formats[]={23,25,55,105};
 for(unsigned f=0;f<4;++f){MTLTextureDescriptor*p=[MTLTextureDescriptor new];p.textureType=MTLTextureType1D;
  p.pixelFormat=formats[f];p.width=f==0?3072:4096;p.height=1;p.depth=1;p.arrayLength=1;p.mipmapLevelCount=1;
  p.storageMode=MTLStorageModeShared;p.usage=MTLTextureUsageShaderRead;
  A5MaliMetalTexture*t=[d newTextureWithDescriptor:p];assert(t);
  size_t bytes=t.width*A5MaliTexturePixelBytes(t.pixelFormat);NSMutableData*in=[NSMutableData dataWithLength:bytes];
  NSMutableData*out=[NSMutableData dataWithLength:bytes];for(size_t i=0;i<bytes;++i)((uint8_t*)in.mutableBytes)[i]=(uint8_t)(i*37+f);
  [t replaceRegion:MTLRegionMake1D(0,t.width)mipmapLevel:0 withBytes:in.bytes bytesPerRow:0];
  [t getBytes:out.mutableBytes bytesPerRow:0 fromRegion:MTLRegionMake1D(0,t.width)mipmapLevel:0];assert([in isEqualToData:out]);}
 A5MaliMetalTexture*a=texture(d,80,776,24,YES,MTLStorageModePrivate),*b=texture(d,80,776,24,YES,MTLStorageModePrivate);
 unsigned ai=(unsigned)(a.privateSurface.resource.token-UINT64_C(0x100000001));
 unsigned bi=(unsigned)(b.privateSurface.resource.token-UINT64_C(0x100000001));
 A5NativeSpan as=spanFor(a,ai),bs=spanFor(b,bi);A5RuntimeImage image={0};A5MaliTextureLevelLayout level;
 assert([a getLevelLayout:&level level:3]);assert(A5MaliRuntimeImageForTexture(a,3,a.privateSurface,&as,A5MaliRead,&image));
 assert(image.gpuVA==as.gpuVA+level.byteOffset&&image.bytes==level.byteLength&&image.width==level.width);
 assert(!A5MaliRuntimeImageForTexture(a,3,b.privateSurface,&bs,A5MaliRead,&image));
 assert(!A5MaliRuntimeImageForTexture(a,10,a.privateSurface,&as,A5MaliRead,&image));
 A5NativeSpan bad=as;bad.bytes=level.byteOffset;assert(!A5MaliRuntimeImageForTexture(a,3,a.privateSurface,&bad,A5MaliRead,&image));
 bad=as;bad.pixelFormat=0x52476841;assert(!A5MaliRuntimeImageForTexture(a,3,a.privateSurface,&bad,A5MaliRead,&image));
 bad=as;bad.gpuVA=UINT64_MAX;assert(!A5MaliRuntimeImageForTexture(a,3,a.privateSurface,&bad,A5MaliRead,&image));
 uint32_t unchanged=0x55abcdef;BOOL denied=NO;@try{[a getBytes:&unchanged bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1)mipmapLevel:0];}
 @catch(NSException*e){denied=[e.name isEqualToString:NSInvalidArgumentException];}assert(denied&&unchanged==0x55abcdef);
 }assert(s.imports==s.releases);
}
static void testPartialCopy(MTLPixelFormat format)
{
 State s={.epoch=1,.expectedProfile=500};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*a=texture(d,format,63,31,NO,MTLStorageModePrivate),*b=texture(d,format,63,31,NO,MTLStorageModePrivate);
 s.expectedSource=gpuVA(0);s.expectedDestination=gpuVA(1);
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];A5MaliMetalBlitEncoder*e=[cb blitCommandEncoder];
 [e copyFromTexture:a sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(2,3,0)sourceSize:MTLSizeMake(17,11,1)
  toTexture:b destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(5,7,0)];[e endEncoding];
 assert(!s.queries&&!s.submits);[cb commit];[cb waitUntilCompleted];
 assert(cb.status==MTLCommandBufferStatusCompleted&&!cb.error&&s.queries==1&&s.submits==1);
 assert(cb.privateBuffer.completedFence.fragmentFence==1003);
 }assert(s.imports==s.releases);
}
/* A same-level atlas relocation must never feed one allocation to both
 * source and target of a single hardware job. The temporary texture is real
 * IOSurface storage, and both terminal fences are validated by the real bridge. */
static void testSameLevelScratchCopy(unsigned failAtSubmit)
{
 State s={.epoch=1,.expectedProfile=500,.scratchCopy=YES,.failAtSubmit=failAtSubmit};
 @autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*t=texture(d,80,63,31,NO,MTLStorageModePrivate);
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];
 A5MaliMetalBlitEncoder*e=[cb blitCommandEncoder];
 [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(2,3,0)
  sourceSize:MTLSizeMake(17,11,1) toTexture:t destinationSlice:0 destinationLevel:0
  destinationOrigin:MTLOriginMake(31,7,0)];[e endEncoding];
 assert(!s.queries&&!s.submits&&!s.releases);
 [cb commit];[cb waitUntilCompleted];
 unsigned submitted=failAtSubmit?failAtSubmit:2;
 assert(s.queries==submitted&&s.submits==submitted&&s.imports==2);
 assert(cb.status==(failAtSubmit?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));
 assert((cb.error!=nil)==(failAtSubmit!=0));
 assert(cb.privateBuffer.completedFence.fragmentFence==(failAtSubmit==1?0:failAtSubmit==2?1003:1005));
 }assert(s.imports==s.releases);
}
static void testSameLevelRejectedOrNoop(BOOL exact)
{
 State s={.epoch=1,.expectedProfile=500};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*t=texture(d,80,63,31,NO,MTLStorageModePrivate);
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];
 A5MaliMetalBlitEncoder*e=[cb blitCommandEncoder];
 [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(2,3,0)
  sourceSize:MTLSizeMake(17,11,1) toTexture:t destinationSlice:0 destinationLevel:0
  destinationOrigin:exact?MTLOriginMake(2,3,0):MTLOriginMake(10,7,0)];[e endEncoding];
 assert(s.imports==1&&!s.queries&&!s.submits);
 [cb commit];[cb waitUntilCompleted];
 assert(!s.queries&&!s.submits&&s.imports==1&&!cb.privateBuffer.completedFence.fragmentFence);
 assert(cb.status==(exact?MTLCommandBufferStatusCompleted:MTLCommandBufferStatusError));
 assert((cb.error!=nil)==!exact);
 }assert(s.imports==s.releases);
}
static void testMipChain(void)
{
 State s={.epoch=1,.expectedProfile=501,.sameAllocation=YES};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*t=texture(d,80,776,24,YES,MTLStorageModePrivate);assert(t.mipmapLevelCount==10&&s.imports==1);
 for(unsigned level=1;level<10;++level){A5MaliTextureLevelLayout a,b;
  assert([t getLevelLayout:&a level:level-1]&&[t getLevelLayout:&b level:level]);
  assert(a.byteOffset+a.byteLength<=b.byteOffset);
  s.mipSource[level-1]=gpuVA(0)+a.byteOffset;s.mipDestination[level-1]=gpuVA(0)+b.byteOffset;
 }
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];A5MaliMetalBlitEncoder*e=[cb blitCommandEncoder];
 [e generateMipmapsForTexture:t];[e endEncoding];assert(!s.queries&&!s.submits);
 [cb commit];[cb waitUntilCompleted];assert(cb.status==MTLCommandBufferStatusCompleted&&!cb.error);
 assert(s.queries==9&&s.submits==9&&s.epoch==2&&s.lastEpoch==2&&cb.privateBuffer.completedFence.fragmentFence==1019);
 }assert(s.imports==s.releases);
}
static void testLevelClear(void)
{
 State s={.epoch=1,.expectedProfile=0};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*t=texture(d,80,776,24,YES,MTLStorageModePrivate);
 A5MaliTextureLevelLayout l;assert([t getLevelLayout:&l level:3]&&l.byteOffset);
 assert(t.privateSurface.height!=l.height);s.expectedDestination=gpuVA(0)+l.byteOffset;
 MTLRenderPassDescriptor*p=[MTLRenderPassDescriptor renderPassDescriptor];p.colorAttachments[0].texture=(id)t;
 p.colorAttachments[0].level=3;p.colorAttachments[0].loadAction=MTLLoadActionClear;
 p.colorAttachments[0].storeAction=MTLStoreActionStore;
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];A5MaliMetalRenderEncoder*e=[cb renderCommandEncoderWithDescriptor:p];
 assert(e);[e endEncoding];assert(!s.queries&&!s.submits);[cb commit];[cb waitUntilCompleted];
 assert(cb.status==MTLCommandBufferStatusCompleted&&s.queries==1&&s.submits==1);
 }assert(s.imports==s.releases);
}
static void testMemoryless(BOOL badFence)
{
 State s={.epoch=1,.expectedProfile=0,.badFence=badFence};@autoreleasepool{A5MaliRestrictedDevice*d=device(&s);
 A5MaliMetalTexture*t=texture(d,80,776,24,YES,MTLStorageModeMemoryless);assert(!s.imports);
 A5MaliMetalBuffer*cb=[[d newCommandQueue]commandBuffer];MTLRenderPassDescriptor*p=[MTLRenderPassDescriptor renderPassDescriptor];
 p.colorAttachments[0].texture=(id)t;p.colorAttachments[0].level=1;p.colorAttachments[0].loadAction=MTLLoadActionClear;
 p.colorAttachments[0].clearColor=MTLClearColorMake(.25,.5,.75,1);p.colorAttachments[0].storeAction=MTLStoreActionDontCare;
 A5MaliMetalRenderEncoder*e=[cb renderCommandEncoderWithDescriptor:p];assert(e);[e endEncoding];
 NSArray*leases=[cb valueForKey:@"memorylessPassBackings"];assert(leases.count==1);
 A5MaliTexturePassBacking*lease=leases[0];s.lease=lease;
 A5MaliMetalTexture*view=[t newRenderViewForLevel:1 memorylessLease:lease error:NULL];assert(view.privateSurface&&lease.valid);
 State*state=&s;__block BOOL completed=NO;[cb addCompletedHandler:^(id<MTLCommandBuffer> b){
  assert(!lease.valid&&!view.privateSurface&&state->submits==1);assert(b.status==(badFence?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));completed=YES;}];
 assert(!s.queries&&!s.submits);[cb commit];[cb waitUntilCompleted];assert(completed&&!lease.valid&&!view.privateSurface);
 assert(cb.privateBuffer.completedFence.fragmentFence==(badFence?0:1003));s.lease=nil;
 }assert(s.imports==s.releases);
}
int main(void){testBytesAndIdentity();testPartialCopy(MTLPixelFormatBGR5A1Unorm);testPartialCopy(MTLPixelFormatA8Unorm);testSameLevelScratchCopy(0);testSameLevelScratchCopy(1);testSameLevelScratchCopy(2);testSameLevelRejectedOrNoop(YES);testSameLevelRejectedOrNoop(NO);testMipChain();testLevelClear();testMemoryless(NO);testMemoryless(YES);
 puts("native texture ops: real typed1D storage, subresource bounds/identity, queued partialcopy+samelevel scratchcopy+9mips, epochs/fences and memoryless completion cleanup passed; kernel transport mocked, no GPU pixels claimed");return 0;}
