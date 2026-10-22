/* SPDX-License-Identifier: MIT
 * iOS16 public resource selector coverage + real backing state transitions.
 * Kernel transport is mocked; no native GPU completion is fabricated here. */
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
typedef struct{A5MaliHeader h;uint32_t bytes,usage;}Create;
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t bytes,usage;}Created;
typedef struct{A5MaliHeader h;uint64_t handle;}Release;
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t offset,length;uint8_t bytes[256];}Transfer;
typedef struct{A5MaliHeader h;uint32_t length,reserved;uint8_t bytes[256];}Read;
typedef struct{unsigned creates,releases,generation;BOOL allocated,failCreate,failRelease;uint8_t bytes[8192];}State;
@interface A5MaliMetalTexture (SourceLayoutFixture)
- (instancetype)initWithSurface:(A5MaliSurface *)surface device:(A5MaliRestrictedDevice *)device
 descriptor:(MTLTextureDescriptor *)descriptor layout:(A5MaliTextureAllocationLayout)layout external:(BOOL)external;
@end
static kern_return_t wire(void *ctx,uint32_t sel,const void *in,size_t bytes,void *out,size_t *outBytes)
{
 State*s=ctx;if(sel==A5MaliUnmap||sel==A5MaliRelease)return KERN_SUCCESS;
 if(sel==8){const Create*q=in;assert(bytes==sizeof(*q)&&q->bytes<=8192&&!s->allocated);
  if(s->failCreate)return kIOReturnNoMemory;
  memset(s->bytes,0,sizeof(s->bytes));s->allocated=YES;++s->creates;++s->generation;
  Created r={{1,sizeof(r),0,0},((uint64_t)s->generation<<32)|0x101,q->bytes,q->usage};assert(*outBytes==sizeof(r));
  memcpy(out,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
 }
 if(sel==9){const Release*q=in;assert(bytes==sizeof(*q)&&s->allocated&&q->handle==((uint64_t)s->generation<<32|0x101));
  if(s->failRelease)return kIOReturnBusy;
  s->allocated=NO;++s->releases;return KERN_SUCCESS;
 }
 assert(sel==14||sel==15);const Transfer*q=in;
 assert(bytes==sizeof(*q)&&s->allocated&&q->length<=256&&q->offset+q->length<=8192);
 if(sel==14)memcpy(s->bytes+q->offset,q->bytes,q->length);
 else{Read r={{1,sizeof(r),0,0},q->length,0,{0}};memcpy(r.bytes,s->bytes+q->offset,q->length);
  assert(*outBytes==sizeof(r));memcpy(out,&r,sizeof(r));*outBytes=sizeof(r);}
 return KERN_SUCCESS;
}
static void selectors(id obj,const char * const *names,size_t count)
{for(size_t i=0;i<count;++i){SEL sel=sel_registerName(names[i]);assert([obj respondsToSelector:sel]);assert([obj methodSignatureForSelector:sel]);}}
static const char * const resourceSelectors[]={"label","setLabel:","device","cpuCacheMode","storageMode","hazardTrackingMode","resourceOptions","setPurgeableState:","heap","heapOffset","allocatedSize","isAliasable","makeAliasable"};
static const char * const resourceSPI[]={"allocationID","doesAliasAllResources:count:","doesAliasAnyResources:count:","doesAliasResource:","isComplete","isPurgeable","protectionOptions","responsibleProcess","setResponsibleProcess:","unfilteredResourceOptions","waitUntilComplete"};
static const char * const textureSPI[]={"compressionFeedback","compressionFootprint","gpuHandle","isCompressed","isDrawable","numFaces","rotation","swizzleKey"};
static const char * const bufferSelectors[]={"length","contents","didModifyRange:","newTextureWithDescriptor:offset:bytesPerRow:","addDebugMarker:range:","removeAllDebugMarkers","gpuAddress"};
static const char * const textureSelectors[]={"rootResource","parentTexture","parentRelativeLevel","parentRelativeSlice","buffer","bufferOffset","bufferBytesPerRow","iosurface","iosurfacePlane","textureType","pixelFormat","width","height","depth","mipmapLevelCount","sampleCount","arrayLength","usage","isShareable","isFramebufferOnly","firstMipmapInTail","tailSizeInBytes","isSparse","allowGPUOptimizedContents","compressionType","gpuResourceID","swizzle","getBytes:bytesPerRow:fromRegion:mipmapLevel:","getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:","replaceRegion:mipmapLevel:withBytes:bytesPerRow:","replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:","newTextureViewWithPixelFormat:","newTextureViewWithPixelFormat:textureType:levels:slices:","newTextureViewWithPixelFormat:textureType:levels:slices:swizzle:","newSharedTextureHandle"};
static MTLTextureDescriptor*desc(void)
{MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:80 width:8 height:4 mipmapped:NO];d.usage=MTLTextureUsageShaderRead;d.storageMode=MTLStorageModeShared;return d;}
static void shared(A5MaliRestrictedDevice*d)
{
 NSUInteger start=A5MaliAllocatedSharedReadBufferBytes(d);A5MaliPrivateBuffer*b=[d newBufferWithLength:4096 options:0];assert(b&&b.readyForRead);
 selectors(b,resourceSelectors,sizeof(resourceSelectors)/sizeof(*resourceSelectors));selectors(b,resourceSPI,sizeof(resourceSPI)/sizeof(*resourceSPI));selectors(b,bufferSelectors,sizeof(bufferSelectors)/sizeof(*bufferSelectors));
 assert([b methodSignatureForSelector:@selector(setPurgeableState:)].methodReturnLength==sizeof(NSUInteger));
 memset(b.contents,0x45,b.length);assert([b setPurgeableState:MTLPurgeableStateKeepCurrent]==MTLPurgeableStateNonVolatile);
 assert([b setPurgeableState:MTLPurgeableStateVolatile]==MTLPurgeableStateNonVolatile&&!b.readyForRead);
 uint8_t one=0;assert([b readBytes:&one offset:0 length:1]==kIOReturnNotReady);
 assert([b setPurgeableState:MTLPurgeableStateNonVolatile]==MTLPurgeableStateVolatile&&b.readyForRead&&((uint8_t*)b.contents)[0]==0x45);
 assert([b setPurgeableState:MTLPurgeableStateEmpty]==MTLPurgeableStateNonVolatile&&!b.readyForRead&&!b.contents&&!b.allocatedSize);
 assert(A5MaliAllocatedSharedReadBufferBytes(d)==start);
 assert([b setPurgeableState:MTLPurgeableStateVolatile]==MTLPurgeableStateEmpty&&[b setPurgeableState:MTLPurgeableStateKeepCurrent]==MTLPurgeableStateEmpty);
 assert([b setPurgeableState:MTLPurgeableStateNonVolatile]==MTLPurgeableStateEmpty&&b.readyForRead&&b.allocatedSize==4096);
 for(NSUInteger i=0;i<b.length;++i)assert(!((uint8_t*)b.contents)[i]);
 assert(!b.heap&&!b.heapOffset&&![b isAliasable]&&!b.gpuAddress);
 assert(!b.allocationID&&!b.protectionOptions&&b.unfilteredResourceOptions==b.resourceOptions);
 b.responsibleProcess=123;assert(b.responsibleProcess==123&&[b setOwnerWithIdentity:7]==kIOReturnUnsupported&&!b.isComplete);
 BOOL unsupported=NO;@try{[b waitUntilComplete];}@catch(NSException*e){unsupported=YES;}assert(unsupported);
 A5MaliPrivateBuffer*other=[d newBufferWithLength:4096 options:0];id __unsafe_unretained objects[]={other,b};
 assert([b doesAliasResource:b]&&![b doesAliasResource:other]&&[b doesAliasAnyResources:objects count:2]&&![b doesAliasAllResources:objects count:2]);
 assert([b doesAliasAllResources:NULL count:0]&&![b doesAliasAnyResources:NULL count:0]);
 NSMutableString*marker=[NSMutableString stringWithString:@"actual marker"];
 [b addDebugMarker:marker range:NSMakeRange(3,17)];[marker appendString:@" mutated"];
 assert(b.debugMarkers.count==1&&[b.debugMarkers[0][@"marker"] isEqual:@"actual marker"]&&[b.debugMarkers[0][@"range"] rangeValue].location==3);
 [b removeAllDebugMarkers];assert(!b.debugMarkers.count);
 BOOL raised=NO;@try{[b makeAliasable];}@catch(NSException*e){raised=YES;}assert(raised);
 raised=NO;@try{[b didModifyRange:NSMakeRange(0,1)];}@catch(NSException*e){raised=YES;}assert(raised);
 raised=NO;@try{[b addDebugMarker:@"bad" range:NSMakeRange(NSUIntegerMax,2)];}@catch(NSException*e){raised=YES;}assert(raised);
 raised=NO;@try{[b setPurgeableState:(MTLPurgeableState)99];}@catch(NSException*e){raised=YES;}assert(raised);
}
static void alias(A5MaliRestrictedDevice*d)
{
 __block unsigned freed=0;void*p=NULL;assert(!posix_memalign(&p,4096,4096));memset(p,0x67,4096);
 __weak A5MaliPrivateBuffer*weak=nil;A5MaliMetalTexture*view=nil;
 @autoreleasepool{A5MaliPrivateBuffer*b=[d newBufferWithBytesNoCopy:p length:4096 options:0 deallocator:^(void*bytes,NSUInteger length){assert(length==4096);++freed;free(bytes);}];assert(b);weak=b;
  A5MaliMetalTexture*t=(id)[b newTextureWithDescriptor:desc() offset:64 bytesPerRow:64];assert(t);
  selectors(t,resourceSelectors,sizeof(resourceSelectors)/sizeof(*resourceSelectors));selectors(t,resourceSPI,sizeof(resourceSPI)/sizeof(*resourceSPI));selectors(t,textureSPI,sizeof(textureSPI)/sizeof(*textureSPI));selectors(t,textureSelectors,sizeof(textureSelectors)/sizeof(*textureSelectors));
  assert([t methodSignatureForSelector:@selector(gpuResourceID)].methodReturnLength==sizeof(MTLResourceID));
  view=(id)[t newTextureViewWithPixelFormat:80];assert(view&&view.parentTexture==t&&view.rootResource==(id)b&&view.buffer==b&&view.bufferOffset==64);
  assert([t doesAliasResource:b]&&[view doesAliasResource:t]&&[b doesAliasResource:view]);
  A5MaliMetalTexture*separate=(id)[b newTextureWithDescriptor:desc() offset:1024 bytesPerRow:64];assert(separate&&![t doesAliasResource:separate]);
  A5MaliPrivateBuffer*externalOverlap=[d newBufferWithBytesNoCopy:p length:4096 options:0 deallocator:nil];assert(externalOverlap&&[b doesAliasResource:externalOverlap]);
  assert(!t.isComplete&&[t setOwnerWithIdentity:0]==kIOReturnUnsupported);
  t.responsibleProcess=321;assert(t.responsibleProcess==321&&!t.protectionOptions&&!t.allocationID&&!t.gpuHandle&&t.numFaces==1&&!t.rotation&&!t.isCompressed&&!t.compressionFeedback&&!t.compressionFootprint&&!t.isDrawable);
  MTLTextureSwizzleChannels channels=t.swizzle;uint32_t key=0;memcpy(&key,&channels,sizeof(key));assert(t.swizzleKey==key);
  assert(!t.parentTexture&&t.rootResource==(id)b&&!t.iosurfacePlane&&!t.isShareable&&!t.isFramebufferOnly&&!t.isSparse);
  assert(!t.firstMipmapInTail&&!t.tailSizeInBytes&&!t.gpuResourceID._impl&&!t.heap&&!t.heapOffset&&![t newSharedTextureHandle]);
  assert([view setPurgeableState:MTLPurgeableStateEmpty]==MTLPurgeableStateNonVolatile&&!b.readyForRead&&!freed);
  assert(b.contents==p&&((uint8_t*)p)[0]==0x67); /* external ownership is preserved */
  assert([t setPurgeableState:MTLPurgeableStateKeepCurrent]==MTLPurgeableStateEmpty);
  assert([view setPurgeableState:MTLPurgeableStateNonVolatile]==MTLPurgeableStateEmpty&&b.readyForRead);
  uint32_t pixel=0xabcdef01;[view replaceRegion:MTLRegionMake2D(1,1,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];assert(!memcmp((uint8_t*)p+64+64+4,&pixel,4));
  assert(![t newTextureViewWithPixelFormat:115]);assert(![t newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(1,1) slices:NSMakeRange(0,1)]);
  MTLTextureSwizzleChannels sw={MTLTextureSwizzleBlue,MTLTextureSwizzleGreen,MTLTextureSwizzleRed,MTLTextureSwizzleAlpha};
  assert(![t newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(0,1) slices:NSMakeRange(0,1) swizzle:sw]);
 }
 assert(weak&&!freed);view=nil;assert(!weak&&freed==1);
}
static void privateBO(A5MaliRestrictedDevice*d,State*s)
{
 A5MaliPrivateBuffer*b=[d newBufferWithLength:8191 options:MTLResourceStorageModePrivate];assert(b&&s->allocated);
 uint8_t pixel=0x78;assert(![b uploadBytes:&pixel offset:13 length:1]);uint64_t old=b.privateKernelHandle;
 assert([b setPurgeableState:MTLPurgeableStateVolatile]==MTLPurgeableStateNonVolatile&&!b.readyForRead);
 assert([b setPurgeableState:MTLPurgeableStateNonVolatile]==MTLPurgeableStateVolatile&&b.readyForRead);
 s->failRelease=YES;BOOL raised=NO;@try{[b setPurgeableState:MTLPurgeableStateEmpty];}@catch(NSException*e){raised=YES;}assert(raised&&b.privateKernelHandle==old&&b.readyForRead);s->failRelease=NO;
 assert([b setPurgeableState:MTLPurgeableStateEmpty]==MTLPurgeableStateNonVolatile&&!b.privateKernelHandle&&!b.readyForRead&&!s->allocated&&!b.allocatedSize);
 s->failCreate=YES;raised=NO;@try{[b setPurgeableState:MTLPurgeableStateNonVolatile];}@catch(NSException*e){raised=YES;}assert(raised&&[b setPurgeableState:MTLPurgeableStateKeepCurrent]==MTLPurgeableStateEmpty);s->failCreate=NO;
 assert([b setPurgeableState:MTLPurgeableStateNonVolatile]==MTLPurgeableStateEmpty&&b.readyForRead&&b.privateKernelHandle!=old&&s->allocated);
 assert(![b readBytes:&pixel offset:13 length:1]&&pixel==0);
}
static void subviews(A5MaliRestrictedDevice*d)
{
 MTLTextureDescriptor*spec=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:80 width:16 height:16 mipmapped:YES];spec.storageMode=MTLStorageModeShared;spec.usage=MTLTextureUsageShaderRead;
 A5MaliTextureAllocationLayout l;assert(A5MaliBuildTextureAllocationLayout(spec,&l,NULL));
 A5MaliMetalTexture*host=[d hostTestTextureWithResource:(A5MaliResource){0x100000001,l.backingWidth,l.backingHeight,l.backingRowBytes,3}];
 A5MaliMetalTexture*root=[[A5MaliMetalTexture alloc]initWithSurface:host.privateSurface device:d descriptor:spec layout:l external:NO];
 A5MaliMetalTexture*v=(id)[root newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(1,3) slices:NSMakeRange(0,1)];assert(v&&v.parentTexture==root&&v.parentRelativeLevel==1&&v.width==8&&v.height==8&&v.mipmapLevelCount==3);
 A5MaliTextureLevelLayout a,b;assert([root getLevelLayout:&a level:2]&&[v getLevelLayout:&b level:1]&&!memcmp(&a,&b,sizeof(a)));
 A5MaliMetalTexture*n=(id)[v newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(1,1) slices:NSMakeRange(0,1)];assert(n&&n.parentTexture==v&&n.rootResource==(id)root&&n.width==4&&n.parentRelativeLevel==1);
 assert(n.privateSurface==root.privateSurface&&[n doesAliasResource:root]);
 A5MaliMetalTexture*level0=(id)[root newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(0,1) slices:NSMakeRange(0,1)];assert(level0&&![level0 doesAliasResource:v]);assert([n setPurgeableState:MTLPurgeableStateEmpty]==MTLPurgeableStateNonVolatile&&[root setPurgeableState:MTLPurgeableStateKeepCurrent]==MTLPurgeableStateNonVolatile);
 assert(![root newTextureViewWithPixelFormat:80 textureType:MTLTextureType2D levels:NSMakeRange(NSUIntegerMax,2) slices:NSMakeRange(0,1)]);
 spec.compressionType=MTLTextureCompressionTypeLossy;assert(!A5MaliBuildTextureAllocationLayout(spec,&l,NULL));
}
int main(void){State state={0};@autoreleasepool{A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state commandCapabilities:63 operationCapabilities:0x7ffff];shared(d);alias(d);privateBO(d,&state);subviews(d);
 MTLSamplerDescriptor*sd=[MTLSamplerDescriptor new];A5MaliSamplerState*sampler=[d newSamplerStateWithDescriptor:sd];assert(sampler&&[sampler respondsToSelector:@selector(gpuResourceID)]&&!sampler.gpuResourceID._impl&&sampler.pixelFormat==MTLPixelFormatInvalid);
 MTLDepthStencilDescriptor*ds=[MTLDepthStencilDescriptor new];A5MaliDepthStencilState*depth=[d newDepthStencilStateWithDescriptor:ds];assert(depth&&!depth.readsDepth&&!depth.writesDepth&&!depth.readsStencil&&!depth.writesStencil);}assert(state.creates==state.releases&&!state.allocated);
 puts("iOS16 resource methods: exact public selectors/return ABI, Shared/private realpurge and failure rollback, no-copy alias lifetime, debugmarkers, retained mipviews and explicit unsupported operations PASS (mock transport; no GPU pixels)");return 0;}
