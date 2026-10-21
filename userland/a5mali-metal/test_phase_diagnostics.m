/* SPDX-License-Identifier: MIT
 * Only diagnostic receipts are new. Transport is mocked, no device/filesystem
 * allocation or shader/pixel success is fabricated by this test.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliNative.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
@interface A5MaliMetalBlitEncoder (PhaseTestSelectors)
- (void)fillBuffer:(id<MTLBuffer> _Nullable)buffer range:(NSRange)range value:(uint8_t)value;
- (void)synchronizeResource:(id<MTLResource> _Nullable)resource;
@end
typedef struct { unsigned mode,calls; } Wire;
static kern_return_t wire(void *context,uint32_t selector,const void *input,size_t bytes,void *output,size_t *outBytes)
{
 Wire *w=context;++w->calls;
 if(selector==A5MaliRelease||selector==A5MaliUnmap)return KERN_SUCCESS;
 assert(selector==A5NativeQuerySelector&&bytes==sizeof(A5NativeQueryRequest));
 if(w->mode==1)return kIOReturnNoResources;
 const A5NativeQueryRequest*q=input;
 A5NativeQueryResult r={.header={1,sizeof(r),0,0},.jobVA=A5NativeJobVA,.jobBytes=A5NativeJobBytes,.flags=7};
 if(w->mode==2)r.header.version=0;
 if(q->surfaces[0])r.surfaces[0]=(A5NativeSpan){q->surfaces[0],0x1000,4096,32,32,128,0x42475241,3};
 assert(*outBytes==sizeof(r));memcpy(output,&r,sizeof(r));*outBytes=sizeof(r);return KERN_SUCCESS;
}
static NSUInteger occurrences(NSString *text,NSString *needle)
{ return [text componentsSeparatedByString:needle].count-1; }
int main(void){@autoreleasepool{
 FILE*f=tmpfile();assert(f);int original=dup(STDERR_FILENO);assert(original>=0);
 fflush(stderr);assert(dup2(fileno(f),STDERR_FILENO)>=0);
 Wire w={0};A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&w
  commandCapabilities:63 operationCapabilities:0x7ffff];
 /* Resource rejects are concurrent to prove the process budgets saturate. */
 dispatch_apply(128,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){(void)i;@autoreleasepool{
  MTLTextureDescriptor*t=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:80 width:64 height:64 mipmapped:NO];
  t.storageMode=MTLStorageModeMemoryless;t.usage=MTLTextureUsageRenderTarget;
  assert(![d newTextureWithDescriptor:t]);
  MTLSamplerDescriptor*s=[MTLSamplerDescriptor new];s.minFilter=MTLSamplerMinMagFilterLinear;
  assert(![d newSamplerStateWithDescriptor:s]);
 }});
 assert(![d newBufferWithLength:1 options:MTLResourceStorageModeMemoryless]);
 uint8_t noCopyBytes[32]={0};assert(![d newBufferWithBytesNoCopy:noCopyBytes length:32 options:0 deallocator:nil]);
 A5MaliMetalQueue*q=[d newCommandQueue];assert(q);
 assert(![q commandBufferWithUnretainedReferences]);
 A5MaliMetalBuffer*b=[q commandBuffer];A5MaliMetalBlitEncoder *blit=[b blitCommandEncoder];assert(blit);
 [blit fillBuffer:nil range:NSMakeRange(0,4) value:0];[blit synchronizeResource:nil];[blit endEncoding];
 [b commit];[b waitUntilCompleted];assert(b.status==MTLCommandBufferStatusError);
 /* A second buffer tests public selector forwarding through private setters. */
 A5MaliMetalBuffer*setter=[q commandBuffer];MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];
 pass.colorAttachments[0].texture=(id)[d hostTestTextureWithResource:(A5MaliResource){0x100000001,32,32,128,A5MaliWrite}];
 pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
 A5MaliMetalRenderEncoder*render=[setter renderCommandEncoderWithDescriptor:pass];assert(render);
 uint8_t one=1;[render setVertexBytes:&one length:1 atIndex:31];
 [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:2];
 [render endEncoding];[setter commit];[setter waitUntilCompleted];assert(setter.status==MTLCommandBufferStatusError);
 A5MaliMetalBuffer*empty=[q commandBuffer];[empty commit];[empty waitUntilCompleted];assert(empty.status==MTLCommandBufferStatusCompleted);
 /* Request-validation and transport/reply-validation receipts preserve results. */
 A5MaliClient client={.call=wire,.context=&w,.gpuCommandsSupported=A5NativeCapability};
 A5NativeQueryRequest request={.header={1,sizeof(request),0,0}};
 request.surfaces[0]=UINT64_C(0xdeadbeefdeadbeef);A5NativeQueryResult result={0};
 assert(A5MaliQueryNative(&client,NULL,&result)==kIOReturnBadArgument);
 w.mode=1;assert(A5MaliQueryNative(&client,&request,&result)==kIOReturnNoResources);
 w.mode=2;assert(A5MaliQueryNative(&client,&request,&result)==kIOReturnBadArgument);
 w.mode=0;assert(A5MaliQueryNative(&client,&request,&result)==KERN_SUCCESS&&result.flags==7);
 fflush(stderr);assert(dup2(original,STDERR_FILENO)>=0);close(original);
 assert(!fseek(f,0,SEEK_END));long length=ftell(f);assert(length>0&&length<200000);rewind(f);
 NSMutableData*data=[NSMutableData dataWithLength:(NSUInteger)length];assert(fread(data.mutableBytes,1,data.length,f)==data.length);fclose(f);
 NSString*log=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];assert(log);
 assert(occurrences(log,@"Metal texture: rejected")==64&&occurrences(log,@"Metal sampler: rejected")==64);
 assert([log containsString:@"reason=storage-mode"]&&[log containsString:@"storage=3"]);
 assert([log containsString:@"reason=min-filter min=1"]);
 assert([log containsString:@"no-copy-unsupported"]&&[log containsString:@"commandBufferWithUnretainedReferences-unsupported"]);
 assert(occurrences(log,@"first_error=")==5); /* two first errors plus three commit begin records */
 assert([log containsString:@"selector=fillBuffer:range:value:"]&&![log containsString:@"selector=synchronizeResource:"]);
 assert([log containsString:@"selector=setVertexBytes:length:atIndex:"]&&![log containsString:@"selector=setBoundBytes:"]);
 assert([log containsString:@"draw_calls=1 queued_draws=0"]);
 assert(occurrences(log,@"phase=begin submit=")==3&&occurrences(log,@"phase=result status=")==3);
 assert([log containsString:@"phase=request-validation"]&&[log containsString:@"phase=transport"]);
 assert([log containsString:@"phase=reply-header"]&&[log containsString:@"phase=complete result=0"]);
 assert(![log containsString:@"deadbeef"]); /* tokens, addresses and buffer contents are excluded */
 puts("phase diagnostics: concurrent bounded rejects, public first-error selector, commit counts/results, Query17 phases and token exclusion passed");
}return 0;}
