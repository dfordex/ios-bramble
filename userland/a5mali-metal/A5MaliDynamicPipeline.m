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
static BOOL vertexABI(A5MaliDynamicShaderCacheEntry *e) {
    unsigned locations[]={0,12,32,33},bases[]={0,1,2,3},masks[]={15,1,3,15};
    NSDictionary *n=e.nativeABI[@"native_info"];
    unsigned inLocations[]={15,16,17},inBases[]={0,1,2},inMasks[]={15,3,15};
    if(!ioShape(e.nativeABI[@"inputs"],inLocations,inBases,inMasks,3))return NO;
    if(!interfaceABI(e)||e.stage!=A5MaliStageVertex||[n[@"attributes"] unsignedIntValue]!=3||
       [n[@"textures"] unsignedIntValue]||[n[@"samplers"] unsignedIntValue]||
       !ioShape(e.nativeABI[@"outputs"],locations,bases,masks,4))return NO;
    /* Configured QC packing maps Metal color attribute3 to Vulkan location2.
     * Unused Metal attribute2 remains part of the validated actual descriptor. */
    NSDictionary *want=@{@"bindings":@[@{@"binding":@0,@"buffer_index":@1,
        @"input_rate":@0,@"divisor":@1,@"stride":@{@"Static":@48}}],
        @"attributes":@[@{@"location":@0,@"binding":@0,@"format":@109,@"offset":@0},
          @{@"location":@1,@"binding":@0,@"format":@103,@"offset":@16},
          @{@"location":@2,@"binding":@0,@"format":@97,@"offset":@32}],
        @"pulled":@[],@"variant_pulled":@[]};
    return [e.reflection[@"vertex_input"] isEqual:want];
}
static BOOL fragmentABI(A5MaliDynamicShaderCacheEntry *e,BOOL *color,BOOL *fetch,BOOL *position) {
    NSDictionary *n=e.nativeABI[@"native_info"];
    if(!interfaceABI(e)||e.stage!=A5MaliStageFragment||[n[@"attributes"] unsignedIntValue]||
       [n[@"textures"] unsignedIntValue]<1||[n[@"textures"] unsignedIntValue]>4||
       [n[@"samplers"] unsignedIntValue]!=[n[@"textures"] unsignedIntValue]||
       ![e.nativeABI[@"live_textures"] count])return NO;
    unsigned locations[]={32,33,0},bases[]={0,1,2},masks[]={3,15,15};
    NSArray *io=e.nativeABI[@"inputs"];
    *position=NO;for(NSDictionary *r in io)if([r[@"location"] unsignedIntValue]==0)*position=YES;
    *color=NO;for(NSDictionary *r in io)if([r[@"location"] unsignedIntValue]==33)*color=YES;
    unsigned selectedLocations[3],selectedBases[3],selectedMasks[3],count=0;
    for(unsigned i=0;i<3;i++)if(!i||(i==1?*color:*position)){
        selectedLocations[count]=locations[i];selectedBases[count]=bases[i];selectedMasks[count++]=masks[i];
    }
    if(!ioShape(io,selectedLocations,selectedBases,selectedMasks,count))return NO;
    unsigned outLocations[]={4},outBases[]={0},outMasks[]={15};
    if(!ioShape(e.nativeABI[@"outputs"],outLocations,outBases,outMasks,1))return NO;
    NSDictionary *g=e.reflection[@"graphics"];
    *fetch=[e.nativeABI[@"framebuffer_fetch"] boolValue];
    BOOL attachment=*fetch?
        ([g[@"rasterization_order_attachment_access"] boolValue]&&[g[@"rasterization_samples"] unsignedIntValue]==1&&
         [g[@"input_attachments"] isEqual:@[@{@"color_index":@0,@"input_attachment_index":@0,@"format_class":@"Float"}]]):
        ![g[@"input_attachments"] count];
    return [g[@"color_write_rules"] isEqual:@[@[@0,@8738]]]&&
        ![g[@"writes_depth"] boolValue]&&![g[@"fragment_writes_memory"] boolValue]&&
        ![g[@"reads_position_depth"] boolValue]&&![g[@"snapshot_reads"] boolValue]&&
        attachment&&![g[@"storage_attachments"] count]&&
        [g[@"color_outputs"] unsignedIntValue]==1;
}
A5MaliDynamicPipelineEntry *A5MaliComposeDynamicPipeline(MTLRenderPipelineDescriptor *d,NSError **error) {
    if(error)*error=nil;
    id v=d.vertexFunction,f=d.fragmentFunction;
    if(![v isMemberOfClass:A5MaliMetalFunction.class]||![f isMemberOfClass:A5MaliMetalFunction.class]||
       [v library]!=[f library]||[v device]!=[f device]||[v functionType]!=MTLFunctionTypeVertex||
       [f functionType]!=MTLFunctionTypeFragment){if(error)*error=unsupported(@"dynamic stages require authenticated same-library functions");return nil;}
    A5MaliMetalFunction *vf=v,*ff=f;
    A5MaliDynamicShaderCacheEntry *vs=vf.dynamicShader,*fs=ff.dynamicShader;
    if(!vs&&!fs)return nil;
    if(!A5MaliShaderCompilePipelinePayload(d,vf.compileRequestPayload,ff.compileRequestPayload,error))return nil;
    const A5MaliCompiledProfile *vp=vs?NULL:A5MaliCompiledProfileForID(vf.specializationProfileID);
    const A5MaliCompiledProfile *fp=fs?NULL:A5MaliCompiledProfileForID(ff.specializationProfileID);
    BOOL color=NO,fetch=NO,position=NO;
    if((vs?!vertexABI(vs):(!vp||vp->profileID<603||vp->profileID>606))||
       (fs?!fragmentABI(fs,&color,&fetch,&position):(!fp||fp->profileID<603||fp->profileID>606))){
        if(error)*error=unsupported(@"compiled stage IO is outside the implemented QC textured runtime ABI");return nil;
    }
    if(!fs)color=fp->profileID==604;
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
            if(resourceCount==16){if(error)*error=unsupported(@"too many dynamic resources");return nil;}
            e->_resources[resourceCount++]=rs[i];
        }
        for(unsigned i=0;i<np;++i)if(ps[i].stage==stage){
            if(pushCount==16){if(error)*error=unsupported(@"too many dynamic push fields");return nil;}
            e->_pushes[pushCount++]=ps[i];
        }
    }
    const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
    for(unsigned i=0;i<4;++i)e->_attributes[i]=(A5MaliCompiledVertexAttribute){i,formats[i],offsets[i],1};
    e->_layout=(A5MaliCompiledVertexLayout){1,48,1,1};
    for(unsigned c=0;c<2;++c)for(unsigned i=0;i<8;++i){unsigned over=c==1&&i==0;
        e->_attachments[c].attachments[i]=(A5MaliCompiledAttachmentState){15,over,0,0,1,over?5u:0u,1,over?5u:0u};}
    unsigned immutableCount=fs?fs.immutableSamplerCount:0;
    if(immutableCount>4){if(error)*error=unsupported(@"too many immutable samplers");return nil;}
    if(immutableCount)memcpy(e->_samplers,fs.immutableSamplers,immutableCount*sizeof(e->_samplers[0]));
    e->_profile=(A5MaliCompiledProfile){.profileID=A5MaliDynamicProfileID,.name="dynamic-reflected-QC",
        .vertexName=e->_vertexName.UTF8String,.fragmentName=e->_fragmentName.UTF8String,
        .colorFormats={80},.flags=A5MaliProfileDynamicStages|A5MaliProfileSourceOverBlend|
            (color?A5MaliProfileDynamicColorVarying:0)|(fetch?A5MaliProfileFramebufferFetch:0)|(position?A5MaliProfileFragmentPosition:0),.passes=&e->_pass,.passCount=1,
        .resources=e->_resources,.resourceCount=resourceCount,.pushFields=e->_pushes,.pushFieldCount=pushCount,
        .attributes=e->_attributes,.attributeCount=4,.layouts=&e->_layout,.layoutCount=1,
        .attachmentContracts=e->_attachments,.attachmentContractCount=2,.immutableSamplers=e->_samplers,.immutableSamplerCount=immutableCount};
#if __has_include("A5MaliCompiledRegistryData.inc") || defined(A5_MALI_REQUIRE_COMPILED_REGISTRY)
    if(!A5MaliDynamicRuntimeProfileSupported(&e->_profile)){if(error)*error=unsupported(@"dynamic resource graph is outside native emitter bounds");return nil;}
#else
    if(error)*error=unsupported(@"native descriptor backend unavailable");return nil;
#endif
    NSString *mismatch=A5MaliCompiledDescriptorMismatch(&e->_profile,d);
    if(mismatch){if(error)*error=unsupported(mismatch);return nil;}
    return e;
}
