/* SPDX-License-Identifier: MIT
 * REAL Mac IOSurface allocations/import ports, mocked kernel queue transport.
 * Requires permission to access IOSurface; no phone or persistent disk writes.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import <IOSurface/IOSurface.h>
#include <assert.h>
#include <string.h>
typedef struct{A5MaliHeader h;uint32_t port,usage;uint64_t reserved;}Import;
typedef struct{A5MaliHeader h;uint64_t handle;uint32_t width,height,row,format;}Imported;
typedef struct{A5MaliHeader h;uint64_t token;}HandleRequest;
typedef struct{A5MaliHeader h;uint64_t token;uint32_t bytes,flags;}Mapped;
typedef struct{uint32_t operation,color;uint64_t source,destination;A5MaliRect src,dst;}BatchCommand;
typedef struct{A5MaliHeader h;uint32_t count,reserved;BatchCommand commands[8];}BatchRequest;
typedef struct{uint32_t status,reserved;uint64_t tiler,fragment;}BatchItem;
typedef struct{A5MaliHeader h;uint32_t count,completed,failed,reserved;BatchItem items[8];}BatchReply;
typedef struct{IOSurfaceRef surface[16];uint32_t usage[16];unsigned imports,releases,batches;}State;
@interface A5MaliMetalTexture(BackingTest)
- (A5MaliSurface *)privateSurface;
@end
static kern_return_t wire(void*context,uint32_t selector,const void*input,size_t bytes,void*output,size_t*outBytes)
{
 State*s=context;
 if(selector==A5MaliImport){const Import*q=input;assert(bytes==sizeof(*q)&&s->imports<16);
  IOSurfaceRef surface=IOSurfaceLookupFromMachPort(q->port);assert(surface);
  unsigned i=s->imports++;s->surface[i]=surface;s->usage[i]=q->usage;
  Imported r={{1,sizeof(r),0,0},UINT64_C(0x100000001)+i,(uint32_t)IOSurfaceGetWidth(surface),
   (uint32_t)IOSurfaceGetHeight(surface),(uint32_t)IOSurfaceGetBytesPerRow(surface),IOSurfaceGetPixelFormat(surface)};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5MaliMap){const HandleRequest*q=input;unsigned i=(unsigned)(q->token-UINT64_C(0x100000001));
  assert(i<s->imports&&s->surface[i]);Mapped r={{1,sizeof(r),0,0},q->token,(uint32_t)IOSurfaceGetAllocSize(s->surface[i]),s->usage[i]};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;}
 if(selector==A5MaliBatchSubmit){const BatchRequest*q=input;assert(bytes==sizeof(*q)&&q->count==1);
  assert(q->commands[0].operation==A5MaliCopyBGRA&&q->commands[0].source&&q->commands[0].destination);
  BatchReply r={.h={1,sizeof(r),0,0},.count=1,.completed=1,.failed=UINT32_MAX};r.items[0].fragment=777;
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->batches;return KERN_SUCCESS;}
 if(selector==A5MaliUnmap)return KERN_SUCCESS;
 assert(selector==A5MaliRelease);const HandleRequest*q=input;unsigned i=(unsigned)(q->token-UINT64_C(0x100000001));
 assert(i<s->imports&&s->surface[i]);CFRelease(s->surface[i]);s->surface[i]=NULL;++s->releases;return KERN_SUCCESS;
}
static void testFormat(MTLPixelFormat format,uint32_t code,unsigned pixelBytes)
{
 State state={0};
 @autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state];
  MTLTextureDescriptor*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:63 height:31 mipmapped:NO];
  desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
  A5MaliMetalTexture*t=[d newTextureWithDescriptor:desc];assert(t&&state.imports==1);
  IOSurfaceRef backing=t.privateSurface.iosurface;
  assert(backing&&t.storageMode==MTLStorageModePrivate&&!t.iosurface);
  assert(t.resourceOptions==MTLResourceStorageModePrivate&&t.pixelFormat==format);
  assert(![t respondsToSelector:@selector(contents)]);
  assert(IOSurfaceGetBytesPerElement(backing)==pixelBytes&&IOSurfaceGetPixelFormat(backing)==code);
  assert(t.allocatedSize==IOSurfaceGetAllocSize(backing)&&t.allocatedSize>=t.privateSurface.rowBytes*31);
  assert(t.privateSurface.rowBytes>=63*pixelBytes&&!(t.privateSurface.rowBytes&15));
  assert([d heapTextureSizeAndAlignWithDescriptor:desc].size);
  uint8_t unchanged[16];memset(unchanged,0x55,sizeof(unchanged));BOOL rejected=NO;
  @try{[t getBytes:unchanged bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,1,1)mipmapLevel:0];}
  @catch(NSException*exception){rejected=[exception.name isEqualToString:NSInvalidArgumentException]&&[exception.reason containsString:@"Private"];}
  assert(rejected&&unchanged[0]==0x55);
  assert(![d newTextureWithDescriptor:desc iosurface:backing plane:0]); /* external Private rejected */
  desc.storageMode=MTLStorageModeShared;
  A5MaliMetalTexture*shared=[d newTextureWithDescriptor:desc];assert(shared&&shared.iosurface&&shared.storageMode==MTLStorageModeShared);
  assert(shared.pixelFormat==format&&shared.allocatedSize);
  assert(state.imports==2);
  if(format==MTLPixelFormatBGRA8Unorm){
   desc.storageMode=MTLStorageModePrivate;A5MaliMetalTexture*second=[d newTextureWithDescriptor:desc];assert(second);
   A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];A5MaliMetalBlitEncoder*e=[b blitCommandEncoder];
   [e copyFromTexture:t toTexture:second];[e endEncoding];[b commit];[b waitUntilCompleted];
   assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&state.batches==1);
  }
  unsigned imports=state.imports;desc.storageMode=MTLStorageModePrivate;desc.mipmapLevelCount=2;
  assert(![d newTextureWithDescriptor:desc]);desc.mipmapLevelCount=1;desc.width=2049;
  assert(![d newTextureWithDescriptor:desc]);desc.width=63;desc.sampleCount=4;
  assert(![d newTextureWithDescriptor:desc]);desc.sampleCount=1;desc.storageMode=MTLStorageModeMemoryless;
  assert(![d newTextureWithDescriptor:desc]);
  desc.storageMode=MTLStorageModePrivate;desc.swizzle=MTLTextureSwizzleChannelsMake(MTLTextureSwizzleBlue,MTLTextureSwizzleGreen,MTLTextureSwizzleRed,MTLTextureSwizzleAlpha);
  assert(![d newTextureWithDescriptor:desc]);assert(state.imports==imports);
 }
 assert(state.releases==state.imports);
}
static void testLargeHalf(void)
{
 State state={0};
 @autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state];
  MTLTextureDescriptor*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:1080 height:1920 mipmapped:NO];
  desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageRenderTarget;
  A5MaliMetalTexture*full=[d newTextureWithDescriptor:desc];assert(full&&!full.iosurface);
  assert(full.storageMode==MTLStorageModePrivate&&full.privateSurface.rowBytes==8640);
  assert(full.allocatedSize==IOSurfaceGetAllocSize(full.privateSurface.iosurface)&&full.allocatedSize>=16588800&&full.allocatedSize<=A5MaliSurfaceMaxBytes);
  assert(state.usage[0]==(A5MaliRead|A5MaliWrite));
  printf("fullHD half realIOSurface allocation=%zu row=%u\n",full.allocatedSize,full.privateSurface.rowBytes);
  desc.width=2048;desc.height=2048;
  A5MaliMetalTexture*maximum=[d newTextureWithDescriptor:desc];assert(maximum);
  assert(maximum.privateSurface.rowBytes==16384&&maximum.allocatedSize==A5MaliSurfaceMaxBytes);
  assert(maximum.allocatedSize==[d heapTextureSizeAndAlignWithDescriptor:desc].size);
  unsigned before=state.imports;
  desc.width=2049;assert(![d newTextureWithDescriptor:desc]);
  desc.width=2048;desc.height=2049;assert(![d newTextureWithDescriptor:desc]);
  desc.width=NSUIntegerMax;desc.height=NSUIntegerMax;assert(![d newTextureWithDescriptor:desc]);
  assert(state.imports==before);
 }
 assert(state.imports==2&&state.releases==2);
}

int main(void)
{
 testFormat(MTLPixelFormatBGRA8Unorm,0x42475241,4);testFormat(MTLPixelFormatR8Unorm,0x4c303038,1);
 testFormat(MTLPixelFormatRG8Unorm,0x32433038,2);testFormat(MTLPixelFormatR32Float,0x4c303066,4);
 testFormat(MTLPixelFormatRGBA16Float,0x52476841,8);testLargeHalf();
 puts("private textures: real five-format IOSurfaces incl fullHDhalf and32MiB boundary, private metadata, GPU blit, CPU rejection and cleanup passed");return 0;
}
