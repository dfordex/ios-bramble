/* SPDX-License-Identifier: MIT
 * REAL Mac IOSurface allocations/import ports, mocked kernel queue transport.
 * Requires permission to access IOSurface; no phone or persistent disk writes.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
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
  A5MaliMetalTexture*shared=[d newTextureWithDescriptor:desc];assert(shared&&!shared.iosurface&&shared.storageMode==MTLStorageModeShared);
  assert(shared.pixelFormat==format&&shared.allocatedSize);
  assert(state.imports==2);
  A5MaliMetalTexture *external=[d newTextureWithDescriptor:desc iosurface:shared.privateSurface.iosurface plane:0];
  assert(external&&external.iosurface==shared.privateSurface.iosurface&&external.storageMode==MTLStorageModeShared);
  if(format==MTLPixelFormatBGRA8Unorm){
   desc.storageMode=MTLStorageModePrivate;A5MaliMetalTexture*second=[d newTextureWithDescriptor:desc];assert(second);
   A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];A5MaliMetalBlitEncoder*e=[b blitCommandEncoder];
   [e copyFromTexture:t toTexture:second];[e endEncoding];[b commit];[b waitUntilCompleted];
   assert(b.status==MTLCommandBufferStatusCompleted&&!b.error&&state.batches==1);
  }
  desc.storageMode=MTLStorageModePrivate;desc.mipmapLevelCount=2;
  A5MaliMetalTexture *mipped=[d newTextureWithDescriptor:desc];assert(mipped&&mipped.mipmapLevelCount==2);
  A5MaliTextureLevelLayout level0,level1;
  assert([mipped getLevelLayout:&level0 level:0]&&[mipped getLevelLayout:&level1 level:1]);
  assert(level1.width==31&&level1.height==15&&level1.byteOffset>=level0.byteLength);
  A5MaliMetalTexture *view=[mipped newRenderViewForLevel:1 memorylessLease:nil error:NULL];
  assert(view&&view.width==31&&view.height==15&&view.mipmapLevelCount==1&&view.privateSurface==mipped.privateSurface);
  A5MaliTextureLevelLayout viewLayout;assert([view getLevelLayout:&viewLayout level:0]&&viewLayout.byteOffset==level1.byteOffset);
  unsigned imports=state.imports;desc.mipmapLevelCount=1;desc.width=2049;
  assert(![d newTextureWithDescriptor:desc]);desc.width=63;desc.sampleCount=4;
  assert(![d newTextureWithDescriptor:desc]);desc.sampleCount=1;desc.storageMode=MTLStorageModeMemoryless;
  A5MaliMetalTexture *memoryless=[d newTextureWithDescriptor:desc];
  assert(memoryless&&memoryless.storageMode==MTLStorageModeMemoryless&&!memoryless.privateSurface&&!memoryless.iosurface&&!memoryless.allocatedSize);
  assert(state.imports==imports&&![d heapTextureSizeAndAlignWithDescriptor:desc].size);
  A5MaliTexturePassBacking *lease=[memoryless newMemorylessPassBackingForLevel:0 error:NULL];assert(lease&&lease.valid&&state.imports==imports+1);
  A5MaliMetalTexture *passView=[memoryless newRenderViewForLevel:0 memorylessLease:lease error:NULL];
  assert(passView&&passView.passBacking==lease&&passView.privateSurface==lease.surface);
  assert(![memoryless surfaceForLevel:0 memorylessLease:nil]&&![shared surfaceForLevel:0 memorylessLease:lease]);
  uint8_t untouched=0x6b;BOOL memorylessCPURejected=NO;
  @try{[passView getBytes:&untouched bytesPerRow:pixelBytes fromRegion:MTLRegionMake2D(0,0,1,1)mipmapLevel:0];}
  @catch(NSException*exception){memorylessCPURejected=[exception.name isEqualToString:NSInvalidArgumentException];}
  assert(memorylessCPURejected&&untouched==0x6b);
  [lease invalidateAfterCompletion];assert(!lease.valid&&!passView.privateSurface);
  A5MaliTexturePassBacking *nextLease=[memoryless newMemorylessPassBackingForLevel:0 error:NULL];
  assert(nextLease&&nextLease.valid&&nextLease!=lease&&!lease.valid);[nextLease invalidateAfterCompletion];
  imports=state.imports;
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

static void testShared1DAndMipBytes(void)
{
 const MTLPixelFormat formats[]={23,25,43,55,105};
 for(unsigned f=0;f<sizeof(formats)/sizeof(formats[0]);++f){State state={0};@autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state];
  MTLTextureDescriptor*desc=[MTLTextureDescriptor new];desc.textureType=MTLTextureType1D;
  desc.pixelFormat=formats[f];desc.width=f==0?3072:4096;desc.height=1;desc.depth=1;
  desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
  desc.mipmapLevelCount=1;A5MaliMetalTexture*t=[d newTextureWithDescriptor:desc];assert(t&&t.textureType==MTLTextureType1D);
  assert(t.width==desc.width&&t.height==1&&!t.iosurface&&t.privateSurface.iosurface);
  unsigned pixel=(unsigned)A5MaliTexturePixelBytes(formats[f]);size_t size=t.width*pixel;
  uint8_t*in=malloc(size),*out=malloc(size+32);assert(in&&out);
  for(size_t i=0;i<size;++i)in[i]=(uint8_t)(i*37+f*23);memset(out,0x7b,size+32);
  [t replaceRegion:MTLRegionMake1D(0,t.width)mipmapLevel:0 withBytes:in bytesPerRow:0];
  [t getBytes:out bytesPerRow:0 fromRegion:MTLRegionMake1D(0,t.width)mipmapLevel:0];
  assert(!memcmp(in,out,size));for(unsigned i=0;i<32;++i)assert(out[size+i]==0x7b);
  /* Integer/half/packed values are copied bitwise, including uint0xffff and
   * half NaN payloads; no accidental normalization or color conversion. */
  if(pixel==2){uint16_t values[]={0xffff,0x7e01,0x8001,0x3c00,0xbc00};
   [t replaceRegion:MTLRegionMake1D(7,5)mipmapLevel:0 withBytes:values bytesPerRow:0];
   uint16_t got[5]={0};[t getBytes:got bytesPerRow:0 fromRegion:MTLRegionMake1D(7,5)mipmapLevel:0];assert(!memcmp(values,got,sizeof(values)));}
  BOOL bad=NO;@try{[t replaceRegion:MTLRegionMake1D(t.width,1)mipmapLevel:0 withBytes:in bytesPerRow:0];}
  @catch(NSException*e){bad=[e.name isEqualToString:NSInvalidArgumentException];}assert(bad);
  desc.width=4097;assert(![d newTextureWithDescriptor:desc]);
  free(in);free(out);
 }assert(state.releases==state.imports);}
 State state={0};@autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&state];
  MTLTextureDescriptor*desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:80 width:776 height:24 mipmapped:YES];
  desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
  A5MaliMetalTexture*t=[d newTextureWithDescriptor:desc];assert(t&&t.mipmapLevelCount==10&&state.imports==1);
  IOSurfaceRef backing=t.privateSurface.iosurface;assert(!IOSurfaceLock(backing,0,NULL));
  memset(IOSurfaceGetBaseAddress(backing),0x6d,IOSurfaceGetAllocSize(backing));assert(!IOSurfaceUnlock(backing,0,NULL));
  uint32_t expectedWidth=776,expectedHeight=24,previousEnd=0;
  for(unsigned level=0;level<10;++level){A5MaliTextureLevelLayout l;assert([t getLevelLayout:&l level:level]);
   assert(l.width==expectedWidth&&l.height==expectedHeight&&!(l.byteOffset&63)&&!(l.rowBytes&15)&&l.byteOffset>=previousEnd);
   size_t row=l.width*4+12,bytes=row*l.height;uint8_t*in=malloc(bytes),*out=malloc(bytes);assert(in&&out);
   memset(in,0x20+level,bytes);memset(out,0x73,bytes);
   [t replaceRegion:MTLRegionMake2D(0,0,l.width,l.height)mipmapLevel:level withBytes:in bytesPerRow:row];
   [t getBytes:out bytesPerRow:row fromRegion:MTLRegionMake2D(0,0,l.width,l.height)mipmapLevel:level];
   for(unsigned y=0;y<l.height;++y){assert(!memcmp(in+y*row,out+y*row,l.width*4));
    for(unsigned x=l.width*4;x<row;++x)assert(out[y*row+x]==0x73);}
   assert(!IOSurfaceLock(backing,kIOSurfaceLockReadOnly,NULL));const uint8_t*raw=IOSurfaceGetBaseAddress(backing);
   for(unsigned at=previousEnd;at<l.byteOffset;++at)assert(raw[at]==0x6d);
   for(unsigned y=0;y<l.height;++y)for(unsigned x=l.width*4;x<l.rowBytes;++x)assert(raw[l.byteOffset+y*l.rowBytes+x]==0x6d);
   assert(!IOSurfaceUnlock(backing,kIOSurfaceLockReadOnly,NULL));
   previousEnd=l.byteOffset+l.byteLength;expectedWidth=MAX(1,expectedWidth/2);expectedHeight=MAX(1,expectedHeight/2);
   free(in);free(out);
  }
  A5MaliTextureLevelLayout invalid;assert(![t getLevelLayout:&invalid level:10]);
  BOOL bad=NO;uint32_t data=1;@try{[t replaceRegion:MTLRegionMake2D(0,0,1,1)mipmapLevel:0 slice:1 withBytes:&data bytesPerRow:4 bytesPerImage:0];}
  @catch(NSException*e){bad=[e.name isEqualToString:NSInvalidArgumentException];}assert(bad);
  desc.width=1;desc.height=1;desc.mipmapLevelCount=2;assert(![d newTextureWithDescriptor:desc]);
  desc.mipmapLevelCount=1;assert([d newTextureWithDescriptor:desc]);
  desc.pixelFormat=115;desc.width=2048;desc.height=2048;desc.mipmapLevelCount=12;assert(![d newTextureWithDescriptor:desc]);
 }assert(state.releases==state.imports);
}

int main(void)
{
 testFormat(MTLPixelFormatBGRA8Unorm,0x42475241,4);testFormat(MTLPixelFormatR8Unorm,0x4c303038,1);
 testFormat(MTLPixelFormatRG8Unorm,0x32433038,2);testFormat(MTLPixelFormatR32Float,0x4c303066,4);
 testFormat(MTLPixelFormatRGBA16Float,0x52476841,8);
 testFormat(MTLPixelFormatR16Uint,0x52313655,2);testFormat(MTLPixelFormatR16Float,0x4c303068,2);
 testFormat(MTLPixelFormatBGR5A1Unorm,0x42354131,2);testFormat(MTLPixelFormatRG32Float,0x32433066,8);testLargeHalf();testShared1DAndMipBytes();
 puts("private textures: nine real formats, fullHDhalf and32MiB bounds, real mip views, ephemeral memoryless leases, CPU denial and cleanup passed");return 0;
}
