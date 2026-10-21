/* SPDX-License-Identifier: MIT
 * Clear-only Metal render passes, backed by the actual released v4 clear
 * emitter. The kernel transport, not the descriptor encoder, is mocked.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <string.h>
@interface A5MaliMetalTexture (TestSurface)
- (A5MaliSurface *)privateSurface;
@end
@interface ClearTexture : A5MaliMetalTexture
@property(nonatomic,strong) A5MaliMetalTexture *backing;
@property(nonatomic) MTLPixelFormat format;
@end
@implementation ClearTexture
- (A5MaliRestrictedDevice *)device{return self.backing.device;}
- (A5MaliSurface *)privateSurface{return [self.backing privateSurface];}
- (NSUInteger)width{return self.backing.width;}
- (NSUInteger)height{return self.backing.height;}
- (MTLPixelFormat)pixelFormat{return self.format;}
- (MTLTextureUsage)usage{return MTLTextureUsageRenderTarget;}
- (IOSurfaceRef)iosurface{return NULL;}
@end
typedef struct {unsigned queries,submits;uint32_t format,code,row;BOOL invalidFence;}State;
static kern_return_t transport(void *context,uint32_t selector,const void *input,size_t count,void *output,size_t *outBytes)
{
 State*s=context;
 if(selector==A5MaliUnmap||selector==A5MaliRelease)return KERN_SUCCESS;
 if(selector==A5NativeQuerySelector){const A5NativeQueryRequest*q=input;
  assert(count==sizeof(*q)&&q->surfaces[0]==0x100000001);
  A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=23};
  r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x10000000,s->row*32,32,32,s->row,s->code,A5MaliWrite};
  assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->queries;return KERN_SUCCESS;}
 assert(selector==A5NativeSubmitSelector);
 const A5NativeSubmitRequest*q=input;
 assert(count==sizeof(*q)+A5NativeJobBytes&&q->profileID==0&&q->mappingEpoch==23);
 assert(q->vertexOffset==UINT32_MAX&&q->tilerOffset==UINT32_MAX&&q->fragmentOffset==0);
 assert(!q->readSurfaces&&q->writeSurfaces==1&&!q->readBuffers);
 const uint8_t*jobs=(const uint8_t*)input+sizeof(*q);uint32_t marker=0;
 memcpy(&marker,jobs+0x1200,4);assert(marker==0xa0000000);
 A5NativeSubmitResult r={.header={1,sizeof(r),0,0},.fragmentFence=701};
 if(s->invalidFence)r.tilerFence=700; /* profile0 must NOT fabricate a tiler job */
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);++s->submits;return KERN_SUCCESS;
}
static void run(uint32_t format,uint32_t code,uint32_t row,BOOL invalidFence)
{
 State s={.format=format,.code=code,.row=row,.invalidFence=invalidFence};
 @autoreleasepool{
  A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&s
   commandCapabilities:63 operationCapabilities:127|(1u<<16)|(1u<<17)];
  ClearTexture*t=[ClearTexture new];t.backing=[d hostTestTextureWithResource:
   (A5MaliResource){0x100000001,32,32,row,A5MaliWrite}];t.format=format;
  MTLRenderPassDescriptor*p=[MTLRenderPassDescriptor renderPassDescriptor];
  p.colorAttachments[0].texture=(id)t;p.colorAttachments[0].loadAction=MTLLoadActionClear;
  p.colorAttachments[0].storeAction=MTLStoreActionStore;
  p.colorAttachments[0].clearColor=format==55?MTLClearColorMake(-.5,0,0,0):MTLClearColorMake(.5,.25,.125,1);
  A5MaliMetalBuffer*b=[[d newCommandQueue]commandBuffer];
  A5MaliMetalRenderEncoder*e=[b renderCommandEncoderWithDescriptor:p];assert(e);
  [e endEncoding]; /* no pipeline/draw is required for a genuine clear pass */
  assert(!s.queries&&!s.submits);[b commit];[b waitUntilCompleted];
  assert(s.queries==1&&s.submits==1);
  assert(b.status==(invalidFence?MTLCommandBufferStatusError:MTLCommandBufferStatusCompleted));
 }
}
int main(void)
{
 run(80,0x42475241,128,NO);run(10,0x4c303038,32,NO);run(30,0x32433038,64,NO);
 run(55,0x4c303066,128,NO);run(115,0x52476841,256,NO);run(115,0x52476841,256,YES);
 puts("native clear: five actual surface formats, clear-only passes and fragment-only fence checks passed (mock transport)");return 0;
}
