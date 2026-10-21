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
    assert(p->attachmentContracts&&p->attachmentContractCount);
    const A5MaliCompiledAttachmentContract *c=p->attachmentContracts;
    for(NSUInteger i=0;i<8;++i){
        const A5MaliCompiledAttachmentState *w=&c->attachments[i];
        MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[i];
        a.writeMask=w->writeMask;a.blendingEnabled=w->blendEnabled;
        a.rgbBlendOperation=w->rgbOperation;a.alphaBlendOperation=w->alphaOperation;
        a.sourceRGBBlendFactor=w->sourceRGB;a.destinationRGBBlendFactor=w->destinationRGB;
        a.sourceAlphaBlendFactor=w->sourceAlpha;a.destinationAlphaBlendFactor=w->destinationAlpha;
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
            if(p->flags&A5MaliProfileNotExecutable)continue;
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
            for(uint32_t ci=0;ci<p->attachmentContractCount;++ci){
                d=descriptor(p,library);
                for(NSUInteger ai=0;ai<8;++ai){
                    const A5MaliCompiledAttachmentState *w=&p->attachmentContracts[ci].attachments[ai];
                    MTLRenderPipelineColorAttachmentDescriptor *a=d.colorAttachments[ai];
                    a.writeMask=w->writeMask;a.blendingEnabled=w->blendEnabled;
                    a.rgbBlendOperation=w->rgbOperation;a.alphaBlendOperation=w->alphaOperation;
                    a.sourceRGBBlendFactor=w->sourceRGB;a.destinationRGBBlendFactor=w->destinationRGB;
                    a.sourceAlphaBlendFactor=w->sourceAlpha;a.destinationAlphaBlendFactor=w->destinationAlpha;
                }
                assert(A5MaliSelectCompiledProfile(d,NULL)==p);
                d.colorAttachments[1].writeMask^=MTLColorWriteMaskRed;reject(d);
            }
            d=descriptor(p,library);d.colorAttachments[1].pixelFormat=MTLPixelFormatInvalid;
            NSError *formatError=nil;assert(!A5MaliSelectCompiledProfile(d,&formatError));
            assert([formatError.localizedDescription containsString:@"attachment1.pixelFormat"]);
            d=descriptor(p,library);d.colorAttachments[1].blendingEnabled=!d.colorAttachments[1].blendingEnabled;reject(d);
            d=descriptor(p,library);
            A5MaliMetalLibrary *other=[device newLibraryWithURL:url error:NULL];
            d.fragmentFunction=(id)[other newFunctionWithName:[NSString stringWithUTF8String:p->fragmentName]];
            reject(d);
        }
        const A5MaliCompiledProfile *ds4=A5MaliCompiledProfileForID(99);assert(ds4);
        assert(ds4->passes[0].fragment.byteCount==3472);
        assert(ds4->resources[2].uniformBytes==72);
        const A5MaliCompiledProfile *rawBlur=A5MaliCompiledProfileForID(108);
        assert(rawBlur->colorFormats[0]==MTLPixelFormatRGBA16Float);
        assert(!(rawBlur->flags&A5MaliProfileSourceOverBlend));
        MTLRenderPipelineDescriptor *unsupportedRawBlend=descriptor(rawBlur,library);
        unsupportedRawBlend.colorAttachments[0].blendingEnabled=YES;
        unsupportedRawBlend.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;
        unsupportedRawBlend.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
        unsupportedRawBlend.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
        unsupportedRawBlend.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
        reject(unsupportedRawBlend); /* Actual row287 has no Bsov token. */
        const A5MaliCompiledProfile *rawBlit=A5MaliCompiledProfileForID(204);
        assert(rawBlit->flags&A5MaliProfileInlineSourceOver);
        MTLRenderPipelineDescriptor *unsupportedRawCopy=descriptor(rawBlit,library);
        unsupportedRawCopy.colorAttachments[0].blendingEnabled=NO;
        reject(unsupportedRawCopy); /* Inline blend code must not be selected for copy. */
        const A5MaliCompiledProfile *clear=A5MaliCompiledProfileForID(207);assert(clear->passCount==1&&clear->passes[0].logicalTarget==1);
        const A5MaliCompiledProfile *home=A5MaliCompiledProfileForID(206);assert(home->colorFormats[1]==80&&home->attachmentContracts[0].attachments[1].writeMask==0);
        for(uint32_t id=200;id<=204;id+=2){const A5MaliCompiledProfile *p=A5MaliCompiledProfileForID(id);assert(p->passCount==1&&p->passes[0].logicalTarget==0&&p->colorFormats[2]==55);}
        assert(ds4->colorFormats[1]==80&&ds4->attachmentContractCount==2);
        printf("authenticated compiled registry: %zu profiles; wrong state/constants/library rejected; no GPU submitted\n",count);
    }
    return 0;
}
