/* SPDX-License-Identifier: MIT
 * Uses the user's private compiler outputs and exact local metallib.
 * Does not submit jobs or infer compositor support from lookup success.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliCompiledRegistry.h"
#include <assert.h>
#include <stdlib.h>

@interface A5MaliMetalLibrary (CompiledRegistryTest)
- (A5MaliMetalFunction *)newFunctionWithName:(NSString *)name
    constantValues:(MTLFunctionConstantValues *)values error:(NSError **)error;
@end
static kern_return_t noGPU(void *context, uint32_t selector, const void *in,
    size_t inBytes, void *out, size_t *outBytes)
{
    (void)context;(void)selector;(void)in;(void)inBytes;(void)out;(void)outBytes;
    assert(0 && "registry lookup cannot submit a GPU command");return KERN_FAILURE;
}
static MTLRenderPipelineDescriptor *descriptor(const A5MaliCompiledProfile *p,
                                               A5MaliMetalLibrary *library)
{
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = (id)[library newFunctionWithName:
        [NSString stringWithUTF8String:p->vertexName]];
    d.fragmentFunction = (id)[library newFunctionWithName:
        [NSString stringWithUTF8String:p->fragmentName]];
    for (NSUInteger i=0;i<8;++i) d.colorAttachments[i].pixelFormat=p->colorFormats[i];
    if (p->attributeCount || p->layoutCount) {
        d.vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
        for (uint32_t i=0;i<p->attributeCount;++i) {
            const A5MaliCompiledVertexAttribute *a=&p->attributes[i];
            d.vertexDescriptor.attributes[a->index].format=a->format;
            d.vertexDescriptor.attributes[a->index].offset=a->offset;
            d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;
        }
        for (uint32_t i=0;i<p->layoutCount;++i) {
            const A5MaliCompiledVertexLayout *a=&p->layouts[i];
            d.vertexDescriptor.layouts[a->index].stride=a->stride;
            d.vertexDescriptor.layouts[a->index].stepFunction=a->stepFunction;
            d.vertexDescriptor.layouts[a->index].stepRate=a->stepRate;
        }
    }
    if (p->flags & (A5MaliProfileCoverageAdd|A5MaliProfileStrokeSourceOver)) {
        BOOL coverage=(p->flags&A5MaliProfileCoverageAdd)!=0;
        for(NSUInteger i=0;i<8;++i)d.colorAttachments[i].writeMask=MTLColorWriteMaskNone;
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[coverage?2:0];
        a.writeMask=coverage?MTLColorWriteMaskRed:MTLColorWriteMaskAll;a.blendingEnabled=YES;
        a.sourceRGBBlendFactor=a.sourceAlphaBlendFactor=MTLBlendFactorOne;
        a.destinationRGBBlendFactor=coverage?MTLBlendFactorOne:MTLBlendFactorOneMinusSourceAlpha;
        a.destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    }
    return d;
}
static void reject(MTLRenderPipelineDescriptor *d)
{
    NSError *error=nil; assert(!A5MaliSelectCompiledProfile(d,&error));
    assert(error.code==kIOReturnUnsupported);
}
int main(void)
{
    @autoreleasepool {
        size_t count=0;const A5MaliCompiledProfile *profiles=A5MaliCompiledProfiles(&count);
        if (getenv("A5_MALI_EXPECT_BAD_REGISTRY")) {assert(!profiles&&!count);return 0;}
        assert(profiles && count>=10 && count<=32);
        assert(!A5MaliCompiledProfileForID(0));assert(!A5MaliCompiledProfileForID(9999));
        int context=0;
        A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]
            initWithTransport:noGPU context:&context commandCapabilities:31];
        const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
        NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        A5MaliMetalLibrary *library=[device newLibraryWithURL:url error:NULL];assert(library);
        A5MaliRestrictedDevice *nativeDevice=[[A5MaliRestrictedDevice alloc]
            initWithTransport:noGPU context:&context commandCapabilities:63
            operationCapabilities:((1u<<16)|(1u<<17)|127)];
        A5MaliMetalLibrary *nativeLibrary=[nativeDevice newLibraryWithURL:url error:NULL];
        assert(nativeLibrary);
        assert(![library newFunctionWithName:@"not_a_compiled_function"]);
        assert([library newFunctionWithName:@"downsample_4_frag_lph"]);
        for (size_t i=0;i<count;++i) {
            const A5MaliCompiledProfile *p=&profiles[i];
            assert(A5MaliCompiledProfileForID(p->profileID)==p);
            MTLRenderPipelineDescriptor *d=descriptor(p,library);
            assert(d.vertexFunction&&d.fragmentFunction);
            NSError *pipelineError=nil;
            assert(![device newRenderPipelineStateWithDescriptor:d error:&pipelineError]);
            assert(pipelineError.code==kIOReturnUnsupported);
            MTLRenderPipelineDescriptor *nativeDescriptor=descriptor(p,nativeLibrary);
            id pipeline=[nativeDevice newRenderPipelineStateWithDescriptor:nativeDescriptor error:&pipelineError];
            if ((p->profileID>=99 && p->profileID<=108)||p->profileID==200||p->profileID==202||p->profileID==204||p->profileID==206||p->profileID==207||(p->profileID>=300&&p->profileID<=302))
                assert([pipeline isKindOfClass:NSClassFromString(@"A5MaliCompiledPipeline")]&&!pipelineError);
            else assert(!pipeline&&pipelineError.code==kIOReturnUnsupported);

            assert(A5MaliSelectCompiledProfile(d,NULL)==p);
            NSError *error=nil;
            MTLFunctionDescriptor *f=[MTLFunctionDescriptor functionDescriptor];
            f.name=[NSString stringWithUTF8String:p->fragmentName];
            assert([library newFunctionWithDescriptor:f error:&error]&&!error);
            f.constantValues=[MTLFunctionConstantValues new];
            assert(![library newFunctionWithDescriptor:f error:&error]);
            assert(error.code==kIOReturnUnsupported);
            error=nil;
            assert(![library newFunctionWithName:f.name constantValues:f.constantValues error:&error]);
            assert(error.code==kIOReturnUnsupported);
            assert([library newFunctionWithName:f.name constantValues:nil error:&error]&&!error);
            d.maxVertexAmplificationCount=2;reject(d);d.maxVertexAmplificationCount=1;
            d.supportIndirectCommandBuffers=YES;reject(d);d.supportIndirectCommandBuffers=NO;
            d.rasterSampleCount=4;reject(d);d.rasterSampleCount=1;
            d.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Uint;reject(d);
            d=descriptor(p,library);d.colorAttachments[7].pixelFormat=MTLPixelFormatR8Unorm;reject(d);
            if(p->layoutCount){d=descriptor(p,library);d.vertexDescriptor.layouts[1].stride=47;reject(d);}
            d=descriptor(p,library);if(!d.vertexDescriptor)d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];d.vertexDescriptor.attributes[5].format=MTLVertexFormatFloat;reject(d);
            d=descriptor(p,library);d.colorAttachments[0].blendingEnabled=YES;
            d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorZero;
            reject(d); /* default blend factors differ from premultiplied source over */
            if (p->flags&A5MaliProfileSourceOverBlend) {
                MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[0];
                a.sourceRGBBlendFactor=MTLBlendFactorOne;a.sourceAlphaBlendFactor=MTLBlendFactorOne;
                a.destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                a.destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                assert(A5MaliSelectCompiledProfile(d,NULL)==p);
                a.destinationRGBBlendFactor=MTLBlendFactorOne;reject(d);
            }
            d=descriptor(p,library);
            A5MaliMetalLibrary *other=[device newLibraryWithURL:url error:NULL];
            d.fragmentFunction=(id)[other newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
            reject(d);
        }
        const A5MaliCompiledProfile *ds4=A5MaliCompiledProfileForID(99);assert(ds4);
        assert(ds4->passes[0].fragment.byteCount==3472);
        assert(ds4->resources[2].uniformBytes==72);
        assert(A5MaliCompiledProfileForID(108)->colorFormats[0]==MTLPixelFormatRGBA16Float);
        printf("authenticated compiled registry: %zu profiles; wrong state/constants/library rejected; no GPU submitted\n",count);
    }
    return 0;
}
