/* SPDX-License-Identifier: MIT
 * Uses the user's private compiler outputs and exact local metallib.
 * Does not submit jobs or infer compositor support from lookup success.
 */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliCompiledRegistry.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

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
static MTLFunctionConstantValues *stageConstants(uint32_t profileID,BOOL vertex)
{
    size_t count=0;const A5MaliCompiledFunctionConstant *constants=vertex?
        A5MaliCompiledVertexConstantsForProfile(profileID,&count):A5MaliCompiledConstantsForProfile(profileID,&count);
    if(!count)return nil;
    MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
    for(size_t i=0;i<count;++i)[values setConstantValue:constants[i].raw
        type:(MTLDataType)constants[i].dataType withName:[NSString stringWithUTF8String:constants[i].name]];
    return values;
}
static MTLRenderPipelineDescriptor *descriptor(const A5MaliCompiledProfile *p,
                                               A5MaliMetalLibrary *library)
{
    MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
    d.vertexFunction = (id)[library newFunctionWithName:
        [NSString stringWithUTF8String:p->vertexName] constantValues:stageConstants(p->profileID,YES) error:NULL];
    d.fragmentFunction = (id)[library newFunctionWithName:
        [NSString stringWithUTF8String:p->fragmentName] constantValues:stageConstants(p->profileID,NO) error:NULL];
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
static void specializationReceipt(A5MaliMetalLibrary *library)
{
    /* Real host Metal storage, including packed UChar3 (not a UInt). Capture
     * typed values without allowing the unsupported function to become live. */
    MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
    uint8_t generic=1,layout=4,opcodes[3]={0x12,0x34,0x56};
    float unsupported=0.5f;
    [values setConstantValue:&generic type:MTLDataTypeBool withName:@"fc_generic"];
    [values setConstantValue:&layout type:MTLDataTypeUChar withName:@"fc_vertex_layout"];
    [values setConstantValue:opcodes type:MTLDataTypeUChar3 withName:@"fc_color_opcodes0"];
    [values setConstantValue:&unsupported type:MTLDataTypeFloat atIndex:7];
    MTLFunctionDescriptor *descriptor=[MTLFunctionDescriptor functionDescriptor];
    descriptor.name=@"fixed_frag_lph_cph";descriptor.constantValues=values;
    FILE *capture=tmpfile();assert(capture);
    int original=dup(STDERR_FILENO);assert(original>=0);
    fflush(stderr);assert(dup2(fileno(capture),STDERR_FILENO)>=0);
    for(unsigned attempt=0;attempt<12;++attempt){
        NSError *error=nil;
        assert(![library newFunctionWithDescriptor:descriptor error:&error]);
        assert(error.code==kIOReturnUnsupported);
    }
    fflush(stderr);assert(dup2(original,STDERR_FILENO)>=0);close(original);
    assert(!fseek(capture,0,SEEK_END));long size=ftell(capture);assert(size>0&&size<8000);
    rewind(capture);NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)size];
    assert(fread(data.mutableBytes,1,data.length,capture)==data.length);fclose(capture);
    NSString *receipt=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];assert(receipt);
    assert([receipt containsString:@"function=fixed_frag_lph_cph constants=1 result=unsupported"]);
    assert([receipt containsString:@"key=fc_generic type=53 bytes=1 raw=01"]);
    assert([receipt containsString:@"key=fc_vertex_layout type=49 bytes=1 raw=04"]);
    assert([receipt containsString:@"key=fc_color_opcodes0 type=51 bytes=3 raw=123456"]);
    assert([receipt containsString:@"key=index_7 type=3 bytes=0 raw=unavailable"]);
    assert(![receipt containsString:@"request=4"]);
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
        specializationReceipt(library);
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
            if ((p->profileID>=99 && p->profileID<=108)||p->profileID==200||p->profileID==202||p->profileID==204||p->profileID==206||p->profileID==207||p->profileID==600||p->profileID==601||p->profileID==602||p->profileID==603||(p->profileID>=300&&p->profileID<=302))
                assert([pipeline isKindOfClass:NSClassFromString(@"A5MaliCompiledPipeline")]&&!pipelineError);
            else assert(!pipeline&&pipelineError.code==kIOReturnUnsupported);

            assert(A5MaliSelectCompiledProfile(d,NULL)==p);
            NSError *error=nil;
            MTLFunctionDescriptor *f=[MTLFunctionDescriptor functionDescriptor];
            f.name=[NSString stringWithUTF8String:p->fragmentName];
            f.constantValues=stageConstants(p->profileID,NO);
            assert([library newFunctionWithDescriptor:f error:&error]&&!error);
            f.constantValues=[MTLFunctionConstantValues new];
            assert(![library newFunctionWithDescriptor:f error:&error]);
            assert(error.code==kIOReturnUnsupported);
            error=nil;
            assert(![library newFunctionWithName:f.name constantValues:f.constantValues error:&error]);
            assert(error.code==kIOReturnUnsupported);
            if(p->profileID==600||p->profileID==601||p->profileID==602||p->profileID==603){
                assert(![library newFunctionWithName:f.name constantValues:nil error:&error]);
                assert(error.code==kIOReturnUnsupported);
                size_t nc=0;const A5MaliCompiledFunctionConstant *values=A5MaliCompiledConstantsForProfile(p->profileID,&nc);
                assert(nc==58);
                for(size_t ci=0;ci<nc;++ci){
                    MTLFunctionConstantValues *changed=stageConstants(p->profileID,NO);
                    uint8_t raw[3];memcpy(raw,values[ci].raw,3);raw[values[ci].byteCount-1]^=1;
                    [changed setConstantValue:raw type:(MTLDataType)values[ci].dataType
                        withName:[NSString stringWithUTF8String:values[ci].name]];
                    assert(![library newFunctionWithName:f.name constantValues:changed error:&error]);
                }
                MTLFunctionConstantValues *extra=stageConstants(p->profileID,NO);uint8_t value=0;
                [extra setConstantValue:&value type:MTLDataTypeBool atIndex:0];
                assert(![library newFunctionWithName:f.name constantValues:extra error:&error]);
            }else assert([library newFunctionWithName:f.name constantValues:nil error:&error]&&!error);
            if(p->profileID==602||p->profileID==603){
                NSString *vertexName=[NSString stringWithUTF8String:p->vertexName];
                assert([vertexName isEqualToString:@"fixed_vert_lph_spc"]);
                assert(![library newFunctionWithName:vertexName]);
                assert(![library newFunctionWithName:vertexName constantValues:nil error:&error]);
                assert(![library newFunctionWithName:vertexName constantValues:[MTLFunctionConstantValues new] error:&error]);
                size_t nc=0;const A5MaliCompiledFunctionConstant *vc=A5MaliCompiledVertexConstantsForProfile(p->profileID,&nc);assert(nc==4);
                for(size_t ci=0;ci<nc;++ci){
                    MTLFunctionConstantValues *changed=stageConstants(p->profileID,YES);uint8_t raw[3];memcpy(raw,vc[ci].raw,3);raw[0]^=1;
                    [changed setConstantValue:raw type:(MTLDataType)vc[ci].dataType withName:[NSString stringWithUTF8String:vc[ci].name]];
                    A5MaliMetalFunction *other=[library newFunctionWithName:vertexName constantValues:changed error:&error];
                    if(!strcmp(vc[ci].name,"fc_texcoord_count0") && A5MaliCompiledProfileForID(603)) {
                        assert(other&&!error); /* Valid sibling specialization, incompatible with this FS. */
                        MTLRenderPipelineDescriptor *mixed=descriptor(p,library);mixed.vertexFunction=(id)other;
                        reject(mixed);
                    } else assert(!other&&error);
                    MTLFunctionConstantValues *wrongType=stageConstants(p->profileID,YES);
                    [wrongType setConstantValue:vc[ci].raw type:vc[ci].dataType==MTLDataTypeBool?MTLDataTypeUChar:MTLDataTypeBool
                        withName:[NSString stringWithUTF8String:vc[ci].name]];
                    assert(![library newFunctionWithName:vertexName constantValues:wrongType error:&error]);
                }
                MTLFunctionConstantValues *extra=stageConstants(p->profileID,YES);uint8_t v=0;
                [extra setConstantValue:&v type:MTLDataTypeBool atIndex:0];
                assert(![library newFunctionWithName:vertexName constantValues:extra error:&error]);
                MTLRenderPipelineDescriptor *missingVertex=descriptor(p,library);
                missingVertex.vertexFunction=(id)[library newFunctionWithName:@"std_vert0_lph"];
                if(p->profileID==602)assert(A5MaliSelectCompiledProfile(missingVertex,NULL)==A5MaliCompiledProfileForID(601));
                else reject(missingVertex);
                /* Byte-identical native code stays in its distinct candidate profile. */
                missingVertex=descriptor(p,library);missingVertex.vertexFunction=missingVertex.fragmentFunction;
                reject(missingVertex);
            }
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
            d=descriptor(p,library);d.colorAttachments[1].pixelFormat=p->colorFormats[1]?MTLPixelFormatInvalid:MTLPixelFormatR8Unorm;
            NSError *formatError=nil;assert(!A5MaliSelectCompiledProfile(d,&formatError));
            assert([formatError.localizedDescription containsString:@"attachment1.pixelFormat"]);
            d=descriptor(p,library);d.colorAttachments[1].blendingEnabled=!d.colorAttachments[1].blendingEnabled;reject(d);
            d=descriptor(p,library);
            A5MaliMetalLibrary *other=[device newLibraryWithURL:url error:NULL];
            d.fragmentFunction=descriptor(p,other).fragmentFunction;
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
