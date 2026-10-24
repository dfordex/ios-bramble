/* SPDX-License-Identifier: MIT
 * Compose independently compiled stages only when their reflected IO and
 * resource semantics fit an implemented native emitter ABI. No module or
 * function-constant whitelist is consulted for a dynamic stage.
 */
#import "A5MaliDynamicPipeline.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliShaderCompileRequest.h"
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include "../a5xelte-air-translation/families/runtime_misc_encode.h"

@implementation A5MaliDynamicPipelineEntry {
@public
    A5MaliCompiledProfile _profile;
    A5MaliCompiledPass _pass;
    A5MaliCompiledResource _resources[16];
    A5MaliCompiledPushField _pushes[16];
    A5MaliCompiledVertexAttribute _attributes[4];
    A5MaliCompiledVertexLayout _layout;
    A5MaliCompiledAttachmentContract _attachments[2];
    A5MaliCompiledSampler _samplers[4];
    NSArray *_owners;
    NSString *_vertexName,*_fragmentName;
}
- (const A5MaliCompiledProfile *)profile { return &_profile; }
@end

static NSError *unsupported(NSString *reason) {
    return [NSError errorWithDomain:@"com.orhunnx.a5xelte.dynamic-pipeline"
        code:ENOTSUP userInfo:@{NSLocalizedDescriptionKey:reason}];
}
/* Generic pipeline receipts can be exhausted by startup warmup. Keep every
 * dynamic composition failure visible through its own bounded terminal gate,
 * including failures after valid stage IO. Only metadata/reasons are logged. */
static A5MaliDynamicPipelineEntry *rejectPipeline(A5MaliMetalFunction *vertex,
    A5MaliMetalFunction *fragment,NSString *predicate,NSError *failure,NSError **error) {
    static unsigned diagnostics=0;
    if(__atomic_fetch_add(&diagnostics,1,__ATOMIC_RELAXED)<48){
        NSString *reason=[[failure.localizedDescription?:@"unsupported dynamic pipeline"
            stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
            stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        if(reason.length>160)reason=[reason substringToIndex:160];
        A5MaliDynamicShaderCacheEntry *fs=fragment.dynamicShader;
        fprintf(stderr,
            "A5XELTE Metal dynamic link: rejected predicate=%s vertex=%s vertex_profile=%u vertex_dynamic=%u fragment=%s fragment_profile=%u fragment_dynamic=%u fs_inputs=%lu fs_textures=%u fs_samplers=%u vertex_request=%s fragment_request=%s reason=%s\n",
            predicate.UTF8String?:"unknown",vertex.name.UTF8String?:"unavailable",
            vertex.specializationProfileID,!!vertex.dynamicShader,
            fragment.name.UTF8String?:"unavailable",fragment.specializationProfileID,!!fs,
            (unsigned long)[fs.nativeABI[@"inputs"] count],
            [fs.nativeABI[@"native_info"][@"textures"] unsignedIntValue],
            [fs.nativeABI[@"native_info"][@"samplers"] unsignedIntValue],
            vertex.dynamicShader.requestID.UTF8String?:"static-or-unavailable",
            fs.requestID.UTF8String?:"static-or-unavailable",reason.UTF8String);
    }
    if(error)*error=failure;
    return nil;
}
/* The shared validator is authoritative. Explain its generic vertex failure
 * only after rejection, so the terminal dynamic receipt identifies the first
 * actual packing difference even after generic startup logging is exhausted. */
static NSString *descriptorRejection(const A5MaliCompiledProfile *profile,
    MTLRenderPipelineDescriptor *descriptor,NSString *reason) {
    if(![reason isEqual:@"vertex attribute/layout contract differs"])return reason;
    MTLVertexDescriptor *vertex=descriptor.vertexDescriptor;
    for(unsigned i=0;i<31;++i){
        const A5MaliCompiledVertexAttribute *want=NULL;
        for(unsigned j=0;j<profile->attributeCount;++j)
            if(profile->attributes[j].index==i)want=profile->attributes+j;
        MTLVertexAttributeDescriptor *actual=vertex.attributes[i];
        if(actual.format!=(want?want->format:MTLVertexFormatInvalid)||
           (want&&(actual.offset!=want->offset||actual.bufferIndex!=want->bufferIndex)))
            return [NSString stringWithFormat:
                @"vertex attribute%u actual={format:%lu,offset:%lu,buffer:%lu} expected={format:%u,offset:%u,buffer:%u}",
                i,(unsigned long)actual.format,(unsigned long)actual.offset,
                (unsigned long)actual.bufferIndex,want?want->format:0,
                want?want->offset:0,want?want->bufferIndex:0];
    }
    for(unsigned i=0;i<profile->layoutCount;++i){
        const A5MaliCompiledVertexLayout *want=profile->layouts+i;
        MTLVertexBufferLayoutDescriptor *actual=vertex.layouts[want->index];
        if(actual.stride!=want->stride||actual.stepFunction!=want->stepFunction||actual.stepRate!=want->stepRate)
            return [NSString stringWithFormat:
                @"vertex layout%u actual={stride:%lu,step:%lu,rate:%lu} expected={stride:%u,step:%u,rate:%u}",
                want->index,(unsigned long)actual.stride,(unsigned long)actual.stepFunction,
                (unsigned long)actual.stepRate,want->stride,want->stepFunction,want->stepRate];
    }
    return reason;
}
/* Merge constant lanes from optimized NIR records; distinct source loads may
 * repeat one lane. A different hardware base or an unknown semantic rejects. */
static BOOL ioShape(NSArray *records,const unsigned *locations,const unsigned *bases,
    const unsigned *masks,unsigned count) {
    if(![records isKindOfClass:NSArray.class]||records.count>32)return NO;
    unsigned seen[8]={0};if(count>8)return NO;
    for(NSDictionary *r in records){
        if(![r isKindOfClass:NSDictionary.class]||[r[@"bit_size"] unsignedIntValue]!=32)return NO;
        unsigned component=[r[@"component"] unsignedIntValue],n=[r[@"components"] unsignedIntValue];
        if(!n||n>4||component>4-n)return NO;
        unsigned slot=0;for(;slot<count;++slot)if([r[@"location"] unsignedIntValue]==locations[slot])break;
        if(slot==count||[r[@"base"] unsignedIntValue]!=bases[slot])return NO;
        seen[slot]|=((1u<<n)-1)<<component;
    }
    for(unsigned i=0;i<count;++i)if(seen[i]!=masks[i])return NO;
    return YES;
}
static BOOL interfaceABI(A5MaliDynamicShaderCacheEntry *e) {
    NSDictionary *interface=e.reflection[@"interface"];
    if(![interface isKindOfClass:NSDictionary.class]||[interface[@"threadgroup"] count]||
       [interface[@"needs_pointer_translation"] boolValue]||[interface[@"needs_handle_translation"] boolValue]||
       [interface[@"reaches_command_buffers"] boolValue]||[interface[@"texture_writing_stages"] count])return NO;
    NSString *stage=e.stage==A5MaliStageVertex?@"Vertex":@"Fragment";
    for(unsigned i=0;i<e.resourceCount;++i){const A5MaliCompiledResource *r=e.resources+i;
        if(r->kind==A5MaliResourceBuffer||r->kind==A5MaliResourceInputAttachment||(r->flags&A5MaliResourceImmutableSampler))continue;
        NSString *kind=r->kind==A5MaliResourceTexture?@"Texture":@"Sampler";
        NSDictionary *want=r->kind==A5MaliResourceTexture?
            @{@"texture_type":@"Type2D",@"sampled_type":@"Float",@"depth_compare":@NO,
              @"access":@{@"sample":@YES,@"read":@NO,@"write":@NO}}:
            @{@"compare":@NO,@"coordinate_sensitive":@YES};
        unsigned matches=0;
        for(NSArray *slot in interface[@"slots"]){
            if(![slot isKindOfClass:NSArray.class]||slot.count!=2)return NO;
            NSDictionary *identity=slot[0];
            if([identity[@"stage"] isEqual:stage]&&[identity[@"class"] isEqual:kind]&&
               [identity[@"index"] unsignedIntValue]==r->metalIndex){
                if(![slot[1][kind] isEqual:want])return NO;
                matches++;
            }
        }
        if(matches!=1)return NO;
    }
    return YES;
}
/* The private registry authenticates code/constants, not arbitrary stage-ID
 * pairings. Match its native vertex program and stage-only resource/push ABI
 * to an implemented export layout; fragment identities may differ freely when
 * their actual input contract links. This also covers equivalent donor rows. */
static BOOL sameStageProgram(const A5MaliCompiledProfile *p,const A5MaliCompiledProfile *shape,unsigned stage) {
    if(!p||!shape||!p->passes||!shape->passes||!p->passCount||!shape->passCount)return NO;
    const A5MaliCompiledShader *a=stage==A5MaliStageVertex?&p->passes[0].vertex:&p->passes[0].fragment;
    const A5MaliCompiledShader *b=stage==A5MaliStageVertex?&shape->passes[0].vertex:&shape->passes[0].fragment;
    if(!a->bytes||!b->bytes||a->byteCount!=b->byteCount||a->firstTag!=b->firstTag||
       a->workRegisters!=b->workRegisters||a->tlsBytes!=b->tlsBytes||a->wlsBytes!=b->wlsBytes||
       memcmp(a->bytes,b->bytes,a->byteCount))return NO;
    unsigned counts[2]={0};
    for(unsigned set=0;set<2;set++){
        const A5MaliCompiledProfile *x=set?shape:p;
        for(unsigned i=0;i<x->resourceCount;i++)if(x->resources[i].stage==stage){
            unsigned n=counts[set]++,at=0;
            for(;at<shape->resourceCount;at++)if(shape->resources[at].stage==stage){if(!n)break;n--;}
            if(at==shape->resourceCount||memcmp(x->resources+i,shape->resources+at,sizeof(*x->resources)))return NO;
        }
    }
    if(counts[0]!=counts[1])return NO;
    counts[0]=counts[1]=0;
    for(unsigned set=0;set<2;set++){
        const A5MaliCompiledProfile *x=set?shape:p;
        for(unsigned i=0;i<x->pushFieldCount;i++)if(x->pushFields[i].stage==stage){
            unsigned n=counts[set]++,at=0;
            for(;at<shape->pushFieldCount;at++)if(shape->pushFields[at].stage==stage){if(!n)break;n--;}
            if(at==shape->pushFieldCount||memcmp(x->pushFields+i,shape->pushFields+at,sizeof(*x->pushFields)))return NO;
        }
    }
    return counts[0]==counts[1];
}
static BOOL vertexABI(A5MaliDynamicShaderCacheEntry *e,const A5MaliCompiledProfile *p,
    BOOL *colorOnly,BOOL *twoUV,NSString **reason) {
    if(!e){
        if(sameStageProgram(p,A5MaliCompiledProfileForID(602),A5MaliStageVertex)){*colorOnly=YES;return YES;}
        if(sameStageProgram(p,A5MaliCompiledProfileForID(603),A5MaliStageVertex)){*colorOnly=NO;return YES;}
        *reason=@"vertex.native-program-resource-ABI";return NO;
    }
    NSDictionary *n=e.nativeABI[@"native_info"];
    if(!interfaceABI(e)||e.stage!=A5MaliStageVertex||[n[@"textures"] unsignedIntValue]||[n[@"samplers"] unsignedIntValue]){
        *reason=@"vertex.stage-interface-or-sampled-resource";return NO;
    }
    unsigned attributes=[n[@"attributes"] unsignedIntValue];
    BOOL compact=attributes==2,dual=attributes==4;
    unsigned fullLocations[]={0,12,32,33},fullBases[]={0,1,2,3},fullMasks[]={15,1,3,15};
    unsigned fullInputs[]={15,16,17},fullInputBases[]={0,1,2},fullInputMasks[]={15,3,15};
    unsigned compactLocations[]={0,12,32},compactBases[]={0,1,2},compactMasks[]={15,1,15};
    unsigned compactInputs[]={15,16},compactInputBases[]={0,1},compactInputMasks[]={15,15};
    unsigned dualLocations[]={0,12,32,33,34},dualBases[]={0,1,2,3,4},dualMasks[]={15,1,3,3,15};
    unsigned dualInputs[]={15,16,17,18},dualInputBases[]={0,1,2,3},dualInputMasks[]={15,3,3,15};
    if((attributes!=2&&attributes!=3&&attributes!=4)||
       !ioShape(e.nativeABI[@"inputs"],compact?compactInputs:dual?dualInputs:fullInputs,
           compact?compactInputBases:dual?dualInputBases:fullInputBases,compact?compactInputMasks:dual?dualInputMasks:fullInputMasks,compact?2:dual?4:3)||
       !ioShape(e.nativeABI[@"outputs"],compact?compactLocations:dual?dualLocations:fullLocations,
           compact?compactBases:dual?dualBases:fullBases,compact?compactMasks:dual?dualMasks:fullMasks,compact?3:dual?5:4)){
        *reason=@"vertex.reflected-input-export-layout";return NO;
    }
    NSArray *vertexAttributes=compact?
        @[@{@"location":@0,@"binding":@0,@"format":@109,@"offset":@0},
          @{@"location":@1,@"binding":@0,@"format":@97,@"offset":@32}]:dual?
        @[@{@"location":@0,@"binding":@0,@"format":@109,@"offset":@0},
          @{@"location":@1,@"binding":@0,@"format":@103,@"offset":@16},
          @{@"location":@2,@"binding":@0,@"format":@103,@"offset":@24},
          @{@"location":@3,@"binding":@0,@"format":@97,@"offset":@32}]:
        @[@{@"location":@0,@"binding":@0,@"format":@109,@"offset":@0},
          @{@"location":@1,@"binding":@0,@"format":@103,@"offset":@16},
          @{@"location":@2,@"binding":@0,@"format":@97,@"offset":@32}];
    NSDictionary *want=@{@"bindings":@[@{@"binding":@0,@"buffer_index":@1,
        @"input_rate":@0,@"divisor":@1,@"stride":@{@"Static":@48}}],
        @"attributes":vertexAttributes,@"pulled":@[],@"variant_pulled":@[]};
    if(![e.reflection[@"vertex_input"] isEqual:want]){*reason=@"vertex.reflected-Metal-packing";return NO;}
    *colorOnly=compact;*twoUV=dual;return YES;
}
static BOOL fragmentABI(A5MaliDynamicShaderCacheEntry *e,BOOL *color,BOOL *fetch,BOOL *position,BOOL *noInputs,BOOL *twoUV,BOOL *colorOnly,NSString **reason) {
    *reason=@"fragment.native-attributes-or-sampled-count";
    NSDictionary *n=e.nativeABI[@"native_info"];
    if(!interfaceABI(e)||e.stage!=A5MaliStageFragment||[n[@"attributes"] unsignedIntValue]||
       [n[@"textures"] unsignedIntValue]>4||
       [n[@"samplers"] unsignedIntValue]!=[n[@"textures"] unsignedIntValue])return NO;
    unsigned locations[]={32,33,0},bases[]={0,1,2},masks[]={3,15,15};
    NSArray *io=e.nativeABI[@"inputs"];
    *reason=@"fragment.native-input-array";
    if(![io isKindOfClass:NSArray.class])return NO;
    *noInputs=io.count==0;
    unsigned textureCount=[n[@"textures"] unsignedIntValue];
    NSArray *live=e.nativeABI[@"live_textures"];
    *reason=@"fragment.native-texture-liveness-or-no-input-fetch";
    if(![live isKindOfClass:NSArray.class]||
       (textureCount?(!live.count||*noInputs):live.count))return NO;
    /* Untextured VAR0 is the colour exported by the compact QC vertex ABI.
     * Its exact vec4 lanes/base are checked below; zero textures never imply UV. */
    *colorOnly=!textureCount&&!*noInputs;
    unsigned mask33=0;*twoUV=NO;
    for(NSDictionary *r in io){
        unsigned loc=[r[@"location"] unsignedIntValue],c=[r[@"component"] unsignedIntValue],n=[r[@"components"] unsignedIntValue];
        if(loc==34)*twoUV=YES;
        if(loc==33&&n&&n<=4&&c<=4-n)mask33|=((1u<<n)-1)<<c;
    }
    /* Optimized NIR may split either UV1.xy or color.xyzw into scalar/vector
     * loads. Classify merged lanes, preserving the existing split-color ABI. */
    *twoUV|=mask33==3;
    *position=NO;for(NSDictionary *r in io)if([r[@"location"] unsignedIntValue]==0)*position=YES;
    *color=NO;for(NSDictionary *r in io)if([r[@"location"] unsignedIntValue]==(*twoUV?34u:33u))*color=YES;
    unsigned selectedLocations[4],selectedBases[4],selectedMasks[4],count=0;
    if(*colorOnly){
        *color=YES;*twoUV=NO;*position=NO;
        selectedLocations[count]=32;selectedBases[count]=0;selectedMasks[count++]=15;
    }else if(*twoUV){
        selectedLocations[count]=32;selectedBases[count]=0;selectedMasks[count++]=3;
        selectedLocations[count]=33;selectedBases[count]=1;selectedMasks[count++]=3;
        if(*color){selectedLocations[count]=34;selectedBases[count]=2;selectedMasks[count++]=15;}
        if(*position){selectedLocations[count]=0;selectedBases[count]=3;selectedMasks[count++]=15;}
    }else for(unsigned i=0;i<3;i++)if(!*noInputs&&(!i||(i==1?*color:*position))){
        selectedLocations[count]=locations[i];selectedBases[count]=bases[i];selectedMasks[count++]=masks[i];
    }
    *reason=@"fragment.reflected-input-location-base-mask";
    if(!ioShape(io,selectedLocations,selectedBases,selectedMasks,count))return NO;
    unsigned outLocations[]={4},outBases[]={0},outMasks[]={15};
    *reason=@"fragment.reflected-color-output";
    if(!ioShape(e.nativeABI[@"outputs"],outLocations,outBases,outMasks,1))return NO;
    NSDictionary *g=e.reflection[@"graphics"];
    *fetch=[e.nativeABI[@"framebuffer_fetch"] boolValue];
    BOOL attachment=*fetch?
        ([g[@"rasterization_order_attachment_access"] boolValue]&&[g[@"rasterization_samples"] unsignedIntValue]==1&&
         [g[@"input_attachments"] isEqual:@[@{@"color_index":@0,@"input_attachment_index":@0,@"format_class":@"Float"}]]):
        ![g[@"input_attachments"] count];
    *reason=@"fragment.ordered-attachment-and-side-effect-contract";
    return [g[@"color_write_rules"] isEqual:@[@[@0,@8738]]]&&
        ![g[@"writes_depth"] boolValue]&&![g[@"fragment_writes_memory"] boolValue]&&
        ![g[@"reads_position_depth"] boolValue]&&![g[@"snapshot_reads"] boolValue]&&
        attachment&&![g[@"storage_attachments"] count]&&
        [g[@"color_outputs"] unsignedIntValue]==1;
}
static BOOL staticFragmentABI(const A5MaliCompiledProfile *p,BOOL *color) {
    for(unsigned id=603;id<=606;id++)if(sameStageProgram(p,A5MaliCompiledProfileForID(id),A5MaliStageFragment)){
        *color=id==604;return YES;
    }
    return NO;
}
A5MaliDynamicPipelineEntry *A5MaliComposeDynamicPipeline(MTLRenderPipelineDescriptor *d,NSError **error) {
    if(error)*error=nil;
    id v=d.vertexFunction,f=d.fragmentFunction;
    if(![v isMemberOfClass:A5MaliMetalFunction.class]||![f isMemberOfClass:A5MaliMetalFunction.class]||
       [v library]!=[f library]||[v device]!=[f device]||[v functionType]!=MTLFunctionTypeVertex||
       [f functionType]!=MTLFunctionTypeFragment){return rejectPipeline(nil,nil,@"functions.authentication",unsupported(@"dynamic stages require authenticated same-library functions"),error);}
    A5MaliMetalFunction *vf=v,*ff=f;
    A5MaliDynamicShaderCacheEntry *vs=vf.dynamicShader,*fs=ff.dynamicShader;
    if(!vs&&!fs)return nil;
    NSError *snapshotError=nil;
    if(!A5MaliShaderCompilePipelinePayload(d,vf.compileRequestPayload,ff.compileRequestPayload,&snapshotError))
        return rejectPipeline(vf,ff,@"pipeline.source-snapshot",snapshotError,error);
    const A5MaliCompiledProfile *vp=vs?NULL:A5MaliCompiledProfileForID(vf.specializationProfileID);
    const A5MaliCompiledProfile *fp=fs?NULL:A5MaliCompiledProfileForID(ff.specializationProfileID);
    BOOL color=NO,fetch=NO,position=NO,noInputs=NO,vertexColorOnly=NO,vertexTwoUV=NO,fragmentTwoUV=NO,fragmentColorOnly=NO;
    NSString *predicate=nil;
    BOOL vertexOK=vertexABI(vs,vp,&vertexColorOnly,&vertexTwoUV,&predicate);
    BOOL fragmentOK=vertexOK&&(fs?fragmentABI(fs,&color,&fetch,&position,&noInputs,&fragmentTwoUV,&fragmentColorOnly,&predicate):
        staticFragmentABI(fp,&color));
    if(vertexOK&&!fs&&!fragmentOK)predicate=@"fragment.static-native-ABI";
    if(vertexOK&&fragmentOK&&vertexColorOnly&&!noInputs&&!fragmentColorOnly){
        fragmentOK=NO;predicate=@"link.fragment-UV-input-not-exported-by-vertex";
    }
    if(vertexOK&&fragmentOK&&fragmentTwoUV&&!vertexTwoUV){
        fragmentOK=NO;predicate=@"link.second-fragment-UV-not-exported-by-vertex";
    }
    if(!vertexOK||!fragmentOK)
        return rejectPipeline(vf,ff,predicate,unsupported([NSString stringWithFormat:
            @"compiled stage IO ABI rejected: %@ (vertex profile%u fragment profile%u)",
            predicate,vf.specializationProfileID,ff.specializationProfileID]),error);
    /* These formats share the reflected float4 output ABI. SFBD performs
     * distinct BGRA8 versus packed BGR5A1 storage conversion; never alias the
     * descriptor format or infer an sRGB identity from a numeric format. */
    MTLPixelFormat target=d.colorAttachments[0].pixelFormat;
    if(target!=MTLPixelFormatBGRA8Unorm&&target!=MTLPixelFormatBGR5A1Unorm)
        return rejectPipeline(vf,ff,@"descriptor.color0-format",unsupported(@"dynamic target requires BGRA8Unorm or BGR5A1Unorm"),error);
    A5MaliDynamicPipelineEntry *e=[A5MaliDynamicPipelineEntry new];
    e->_owners=@[vs?:v,fs?:f];e->_vertexName=[vf.name copy];e->_fragmentName=[ff.name copy];
    e->_pass=(A5MaliCompiledPass){.passID=A5MaliDynamicProfileID,
        .vertex=vs?*vs.shader:vp->passes[0].vertex,.fragment=fs?*fs.shader:fp->passes[0].fragment};
    unsigned resourceCount=0,pushCount=0;
    for(unsigned stage=1;stage<=2;++stage){
        A5MaliDynamicShaderCacheEntry *entry=stage==1?vs:fs;
        const A5MaliCompiledProfile *p=stage==1?vp:fp;
        unsigned nr=entry?entry.resourceCount:p->resourceCount,np=entry?entry.pushFieldCount:p->pushFieldCount;
        const A5MaliCompiledResource *rs=entry?entry.resources:p->resources;
        const A5MaliCompiledPushField *ps=entry?entry.pushFields:p->pushFields;
        for(unsigned i=0;i<nr;++i)if(rs[i].stage==stage){
            if(resourceCount==16)return rejectPipeline(vf,ff,@"resources.count",unsupported(@"too many dynamic resources"),error);
            e->_resources[resourceCount++]=rs[i];
        }
        for(unsigned i=0;i<np;++i)if(ps[i].stage==stage){
            if(pushCount==16)return rejectPipeline(vf,ff,@"push-fields.count",unsupported(@"too many dynamic push fields"),error);
            e->_pushes[pushCount++]=ps[i];
        }
    }
    const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
    for(unsigned i=0;i<4;++i)e->_attributes[i]=(A5MaliCompiledVertexAttribute){i,formats[i],offsets[i],1};
    e->_layout=(A5MaliCompiledVertexLayout){1,48,1,1};
    for(unsigned c=0;c<2;++c)for(unsigned i=0;i<8;++i){unsigned over=c==1&&i==0;
        e->_attachments[c].attachments[i]=(A5MaliCompiledAttachmentState){15,over,0,0,1,over?5u:0u,1,over?5u:0u};}
    unsigned immutableCount=fs?fs.immutableSamplerCount:0;
    if(immutableCount>4)return rejectPipeline(vf,ff,@"immutable-samplers.count",unsupported(@"too many immutable samplers"),error);
    if(immutableCount)memcpy(e->_samplers,fs.immutableSamplers,immutableCount*sizeof(e->_samplers[0]));
    e->_profile=(A5MaliCompiledProfile){.profileID=A5MaliDynamicProfileID,.name="dynamic-reflected-QC",
        .vertexName=e->_vertexName.UTF8String,.fragmentName=e->_fragmentName.UTF8String,
        .colorFormats={(uint32_t)target},.flags=A5MaliProfileDynamicStages|A5MaliProfileSourceOverBlend|
            (color?A5MaliProfileDynamicColorVarying:0)|(fetch?A5MaliProfileFramebufferFetch:0)|(position?A5MaliProfileFragmentPosition:0)|(noInputs?A5MaliProfileFragmentNoInputs:0)|(vertexColorOnly?A5MaliProfileVertexColorOnly:0)|(vertexTwoUV?A5MaliProfileVertexTwoUV:0)|(fragmentTwoUV?A5MaliProfileFragmentTwoUV:0)|(fragmentColorOnly?A5MaliProfileFragmentColorOnly:0),.passes=&e->_pass,.passCount=1,
        .resources=e->_resources,.resourceCount=resourceCount,.pushFields=e->_pushes,.pushFieldCount=pushCount,
        .attributes=e->_attributes,.attributeCount=4,.layouts=&e->_layout,.layoutCount=1,
        .attachmentContracts=e->_attachments,.attachmentContractCount=2,.immutableSamplers=e->_samplers,.immutableSamplerCount=immutableCount};
#if __has_include("A5MaliCompiledRegistryData.inc") || defined(A5_MALI_REQUIRE_COMPILED_REGISTRY)
    if(!A5MaliDynamicRuntimeProfileSupported(&e->_profile))
        return rejectPipeline(vf,ff,@"emitter.resource-graph",unsupported(@"dynamic resource graph is outside native emitter bounds"),error);
#else
    return rejectPipeline(vf,ff,@"emitter.backend",unsupported(@"native descriptor backend unavailable"),error);
#endif
    NSString *mismatch=A5MaliCompiledDescriptorMismatch(&e->_profile,d);
    if(mismatch)return rejectPipeline(vf,ff,@"descriptor.contract",unsupported(descriptorRejection(&e->_profile,d,mismatch)),error);
    static unsigned acceptedDiagnostics=0;
    if(__atomic_fetch_add(&acceptedDiagnostics,1,__ATOMIC_RELAXED)<32)fprintf(stderr,
        "A5XELTE Metal dynamic link: accepted vertex=%s vertex_profile=%u vertex_dynamic=%u vertex_abi=%s fragment=%s fragment_profile=%u fragment_dynamic=%u fs_no_inputs=%u fetch=%u\n",
        vf.name.UTF8String,vf.specializationProfileID,!!vs,vertexColorOnly?"position-color":vertexTwoUV?"position-two-uv-color":"position-uv-color",
        ff.name.UTF8String,ff.specializationProfileID,!!fs,noInputs,fetch);
    return e;
}
