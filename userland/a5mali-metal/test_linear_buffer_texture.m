/* SPDX-License-Identifier: MIT
 * Linear textures alias actual retained Shared/no-copy buffer bytes. This test
 * does not import an IOSurface or claim native GPU execution. */
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliMetalTexture.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
static kern_return_t transport(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;assert(!"linear CPU alias must not allocate/import GPU storage");return kIOReturnError;}
static MTLTextureDescriptor *descriptor(MTLPixelFormat f,BOOL one)
{MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:f width:13 height:one?1:4 mipmapped:NO];
 d.textureType=one?MTLTextureType1D:MTLTextureType2D;d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;return d;}
int main(void)
{
 @autoreleasepool{
 unsigned context=0;A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&context commandCapabilities:63 operationCapabilities:0x7ffff];
 const MTLPixelFormat formats[]={80,115,1,10,30,55,23,25,43,105};
 for(unsigned f=0;f<10;++f)for(unsigned one=0;one<2;++one){
  A5MaliPrivateBuffer*b=[d newBufferWithLength:4096 options:0];assert(b&&b.contents);memset(b.contents,0xa5,b.length);
  MTLTextureDescriptor*desc=descriptor(formats[f],one);NSUInteger pixel=A5MaliTexturePixelBytes(formats[f]);
  A5MaliMetalTexture*t=(id)[b newLinearTextureWithDescriptor:desc offset:64 bytesPerRow:128 bytesPerImage:1024];assert(t);
  assert(t.buffer==b&&t.bufferOffset==64&&t.bufferBytesPerRow==128&&t.bufferBytesPerImage==1024);
  assert(!t.privateSurface&&!t.iosurface&&t.device==d&&t.pixelFormat==formats[f]&&t.width==13&&t.height==(one?1u:4u));
  A5MaliTextureLevelLayout l;assert([t getLevelLayout:&l level:0]&&l.byteOffset==64&&l.rowBytes==128&&l.byteLength==128*t.height);
  desc.width=1;desc.pixelFormat=80;assert(t.width==13&&t.pixelFormat==formats[f]); /* descriptor copied */
  uint8_t out[512],in[512];memset(in,0x37,sizeof(in));memset(out,0,sizeof(out));
  MTLRegion r=MTLRegionMake2D(2,0,5,one?1:3);NSUInteger stride=5*pixel+7;
  [t replaceRegion:r mipmapLevel:0 withBytes:in bytesPerRow:stride];
  for(NSUInteger y=0;y<r.size.height;++y){assert(!memcmp((uint8_t*)b.contents+64+y*128+2*pixel,in+y*stride,5*pixel));
   assert(((uint8_t*)b.contents)[64+y*128]==0xa5);}
  /* Direct external buffer writes after view creation are immediately visible. */
  memset((uint8_t*)b.contents+64+2*pixel,0x6b,5*pixel);
  [t getBytes:out bytesPerRow:stride fromRegion:r mipmapLevel:0];
  for(NSUInteger i=0;i<5*pixel;++i)assert(out[i]==0x6b);
  for(NSUInteger y=1;y<r.size.height;++y)assert(!memcmp(out+y*stride,in+y*stride,5*pixel));
  BOOL raised=NO;@try{[t getBytes:out bytesPerRow:128 fromRegion:MTLRegionMake2D(12,0,2,1) mipmapLevel:0];}@catch(NSException*e){raised=YES;}assert(raised);
  assert(![t getLevelLayout:&l level:1]);
 }
 A5MaliPrivateBuffer*b=[d newBufferWithLength:4096 options:0];MTLTextureDescriptor*good=descriptor(80,NO);
 A5MaliMetalTexture*publicView=(id)[b newTextureWithDescriptor:good offset:64 bytesPerRow:128];
 assert(publicView&&publicView.buffer==b&&publicView.bufferBytesPerImage==512);
 A5MaliMetalTexture*unalignedImage=(id)[b newLinearTextureWithDescriptor:good offset:64 bytesPerRow:128 bytesPerImage:513];
 assert(unalignedImage&&unalignedImage.bufferBytesPerImage==513);
 /* Exact0191 live request: only last-row active texels count toward the
  * declared image length. The real buffer also owns the GPU padded span. */
 MTLTextureDescriptor*live=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:80 width:194 height:237 mipmapped:NO];
 live.storageMode=MTLStorageModeShared;live.usage=MTLTextureUsageShaderRead;
 void*livePages=NULL;assert(!posix_memalign(&livePages,4096,200704));memset(livePages,0xa5,200704);
 A5MaliPrivateBuffer*liveBuffer=[d newBufferWithBytesNoCopy:livePages length:200704 options:0
  deallocator:^(void*p,NSUInteger n){assert(n==200704);free(p);}];assert(liveBuffer&&liveBuffer.contents==livePages);
 const NSUInteger active=236*832+194*4,padded=237*832;
 assert(active==197128&&padded==197184);
 A5MaliMetalTexture*liveTexture=(id)[liveBuffer newLinearTextureWithDescriptor:live offset:0 bytesPerRow:832 bytesPerImage:active];
 A5MaliTextureLevelLayout liveLayout;
 assert(liveTexture&&liveTexture.buffer==liveBuffer&&liveTexture.bufferBytesPerImage==active&&
  [liveTexture getLevelLayout:&liveLayout level:0]&&liveLayout.byteLength==padded&&liveLayout.rowBytes==832);
 uint32_t lastPixel=0x12345678,result=0;memcpy((uint8_t*)liveBuffer.contents+active-4,&lastPixel,4);
 [liveTexture getBytes:&result bytesPerRow:4 fromRegion:MTLRegionMake2D(193,236,1,1) mipmapLevel:0];assert(result==lastPixel);
 result=0xaabbccdd;[liveTexture replaceRegion:MTLRegionMake2D(193,236,1,1) mipmapLevel:0 withBytes:&result bytesPerRow:4];
 assert(!memcmp((uint8_t*)liveBuffer.contents+active-4,&result,4));
 assert(![liveBuffer newLinearTextureWithDescriptor:live offset:0 bytesPerRow:832 bytesPerImage:active-1]);
 A5MaliPrivateBuffer*shortBuffer=[d newBufferWithLength:padded-1 options:0];
 assert(![shortBuffer newLinearTextureWithDescriptor:live offset:0 bytesPerRow:832 bytesPerImage:active]);
 assert(![liveBuffer newLinearTextureWithDescriptor:live offset:0 bytesPerRow:832 bytesPerImage:NSUIntegerMax]);
 assert(![liveBuffer newLinearTextureWithDescriptor:live offset:NSUIntegerMax-63 bytesPerRow:832 bytesPerImage:active]);
 /* Exact0204 alpha-only upload: retain byteOffset64 and final alpha byte. */
 MTLTextureDescriptor*alpha=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatA8Unorm width:576 height:301 mipmapped:NO];
 alpha.storageMode=MTLStorageModeShared;alpha.usage=MTLTextureUsageShaderRead;
 A5MaliPrivateBuffer*alphaBuffer=[d newBufferWithLength:176128 options:0];
 A5MaliMetalTexture*alphaTexture=(id)[alphaBuffer newLinearTextureWithDescriptor:alpha offset:64 bytesPerRow:576 bytesPerImage:173376];
 A5MaliTextureLevelLayout alphaLayout;assert(alphaTexture&&alphaTexture.pixelFormat==MTLPixelFormatA8Unorm&&
  [alphaTexture getLevelLayout:&alphaLayout level:0]&&alphaLayout.byteOffset==64&&alphaLayout.byteLength==173376&&alphaLayout.rowBytes==576);
 assert(A5MaliTexturePixelCode(MTLPixelFormatA8Unorm)==0x41303038&&
  A5MaliTexturePixelCode(MTLPixelFormatA8Unorm)!=A5MaliTexturePixelCode(MTLPixelFormatR8Unorm));
 uint8_t alphaByte=0x93,alphaRead=0;[alphaTexture replaceRegion:MTLRegionMake2D(575,300,1,1) mipmapLevel:0 withBytes:&alphaByte bytesPerRow:1];
 assert(((uint8_t*)alphaBuffer.contents)[64+173376-1]==alphaByte);
 [alphaTexture getBytes:&alphaRead bytesPerRow:1 fromRegion:MTLRegionMake2D(575,300,1,1) mipmapLevel:0];assert(alphaRead==alphaByte);
 assert(![alphaBuffer newLinearTextureWithDescriptor:alpha offset:64 bytesPerRow:576 bytesPerImage:173375]);
 for(unsigned fault=0;fault<15;++fault){MTLTextureDescriptor*bad=[good copy];NSUInteger off=64,row=128,image=512;
  switch(fault){case 0:off=1;break;case 1:row=65;break;case 2:row=0;break;case 3:row=32769;break;
   case 4:row=64;bad.width=17;break;case 5:off=4096;break;case 6:off=NSUIntegerMax-63;break;
   case 7:image=128;break;case 8:image=3*128+13*4-1;break;case 9:bad.mipmapLevelCount=2;break;
   case 10:bad.storageMode=MTLStorageModePrivate;break;case 11:bad.usage=MTLTextureUsageRenderTarget;break;
   case 12:bad.textureType=MTLTextureType3D;break;case 13:bad.arrayLength=2;break;case 14:bad.pixelFormat=MTLPixelFormatRGBA32Float;break;}
  assert(![b newLinearTextureWithDescriptor:bad offset:off bytesPerRow:row bytesPerImage:image]);
 }
 MTLTextureDescriptor *nilDescriptor=nil;assert(![b newLinearTextureWithDescriptor:nilDescriptor offset:64 bytesPerRow:128 bytesPerImage:0]);
 __block unsigned releases=0;__weak A5MaliPrivateBuffer*weak=nil;A5MaliMetalTexture*held=nil;
 @autoreleasepool{void*pages=NULL;assert(!posix_memalign(&pages,4096,8192));memset(pages,0xa5,8192);
  A5MaliPrivateBuffer*alias=[d newBufferWithBytesNoCopy:pages length:8192 options:0 deallocator:^(void*p,NSUInteger n){assert(n==8192);++releases;free(p);}];
  weak=alias;held=(id)[alias newLinearTextureWithDescriptor:good offset:64 bytesPerRow:128 bytesPerImage:0];assert(held);
  alias=nil;assert(weak&&!releases);uint8_t in[8]={1,2,3,4,5,6,7,8};[held replaceRegion:MTLRegionMake2D(0,0,2,1) mipmapLevel:0 withBytes:in bytesPerRow:8];
  assert(!memcmp((uint8_t*)pages+64,in,8));
 }
 assert(weak&&!releases);held=nil;assert(!weak&&releases==1);
 puts("linear buffer textures: public+SPI real alias, ten formats,1D/2D paddedstrides/offsets, latewrites, CPU ranges, descriptor/lifetime and invalid bounds PASS (CPU/mock transport; no GPU pixels)");
 }return 0;
}
