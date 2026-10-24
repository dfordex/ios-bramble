/* SPDX-License-Identifier: MIT
 * Host-only structural test. Native binaries are read from private build
 * artifacts supplied on the command line; no Apple or translated bytes live
 * in the repository. A descriptor check is not a GPU execution result.
 */
#define PAN_ARCH 4
#include "runtime_misc_encode.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"
#if defined(__has_include)
#if __has_include("A5MaliCompiledRegistryData.inc")
#include "A5MaliCompiledRegistryData.inc"
#define A5_TEST_REAL_PROFILE 1
#endif
#endif

static uint8_t descriptor[A5RuntimeJobBytes],syntheticDescriptor[A5RuntimeJobBytes];
static uint8_t vertices[4*48],matrix[64];
static int zeroed(void){for(size_t i=0;i<sizeof(descriptor);++i)if(descriptor[i])return 0;return 1;}
static uint8_t*program(const char*path,size_t expected){
 FILE*f=fopen(path,"rb");assert(f);uint8_t*b=malloc(expected);assert(b);
 assert(fread(b,1,expected,f)==expected&&fgetc(f)==EOF);fclose(f);return b;
}

int main(int argc,char**argv){
 assert(argc==3);
 uint8_t*vs=program(argv[1],1808),*fs=program(argv[2],848);
 A5MaliCompiledPass pass={600,0,
  {vs,1808,5,8,0,0,"3cdf2b0db0b9992ce887242e7cac282cd70c3f8051e3ace3e791a0b676193a79"},
  {fs,848,5,6,0,0,"e66041333f6452510cda4d0ee1f1c1edf443a12007a989871a1546791deb0834"}};
 A5MaliCompiledResource res={A5MaliStageVertex,A5MaliResourceBuffer,2,0,1,
  A5MaliResourceRead,0,64,0,0};
 A5MaliCompiledPushField push[]={
  {A5MaliStageVertex,A5MaliPushBindOffset,2,0,4,0},
  {A5MaliStageFragment,A5MaliPushColorWriteRule,0,68,4,0x2222}};
 A5MaliCompiledVertexAttribute attr[]={
  {0,31,0,1},{1,29,16,1},{2,29,24,1},{3,27,32,1}};
 A5MaliCompiledVertexLayout layout={1,48,1,1};
 A5MaliCompiledAttachmentContract attachments[2]={0};
 A5MaliCompiledAttachmentContract *attachment=attachments;
 for(unsigned i=0;i<8;++i){attachment->attachments[i].writeMask=15;
  attachment->attachments[i].sourceRGB=1;attachment->attachments[i].sourceAlpha=1;}
 A5MaliCompiledProfile profile={0};profile.profileID=600;
 profile.vertexName="std_vert0_lph";profile.fragmentName="fixed_frag_lph_cpf";
 profile.colorFormats[0]=80;
 profile.passes=&pass;profile.passCount=1;profile.resources=&res;profile.resourceCount=1;
 profile.pushFields=push;profile.pushFieldCount=2;profile.attributes=attr;profile.attributeCount=4;
 profile.layouts=&layout;profile.layoutCount=1;
 profile.attachmentContracts=attachment;profile.attachmentContractCount=1;
 A5RuntimeMiscDraw m={0};m.draw.profile=&profile;m.draw.descriptorGPUVA=0x12000000;
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,matrix};
 m.colorAttachments[0]=(A5RuntimeImage){0x22000000,4096,32,32,128,80};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 memcpy(syntheticDescriptor,descriptor,sizeof(descriptor));
#ifdef A5_TEST_REAL_PROFILE
 const A5MaliCompiledProfile*real=NULL;
 for(size_t i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==600)real=&kA5MaliCompiledProfiles[i];
 assert(real);m.draw.profile=real;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
 m.draw.profile=&profile;
#endif
 assert(!memcmp(descriptor+0x6000,vs,1808));assert(!memcmp(descriptor+0x8000,fs,848));
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x500),RENDERER_STATE,vert);
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x540),RENDERER_STATE,frag);
 assert(vert.shader.attribute_count==2&&vert.shader.varying_count==3);
 assert(vert.properties.uniform_buffer_count==2&&vert.properties.work_register_count==8);
 assert(frag.shader.varying_count==1&&frag.shader.texture_count==0&&frag.shader.sampler_count==0);
 assert(frag.properties.uniform_buffer_count==3&&frag.properties.work_register_count==6);
 assert(!frag.multisample_misc.load_destination&&frag.blend_equation.color_mask==15);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0x800),ATTRIBUTE,pos);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0x808),ATTRIBUTE,color);
 assert(pos.buffer_index==0&&(pos.format>>12)==MALI_RGBA32F&&pos.offset==0);
 assert(color.buffer_index==0&&(color.format>>12)==MALI_RGBA16F&&color.offset==32);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0xa10),ATTRIBUTE,outcolor);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0xc00),ATTRIBUTE,incolor);
 assert(outcolor.buffer_index==2&&(outcolor.format>>12)==MALI_RGBA32UI);
 assert(incolor.buffer_index==0&&(incolor.format>>12)==MALI_RGBA32F);
 uint32_t rule;memcpy(&rule,descriptor+0x1400+68,4);assert(rule==0x2222);
 /* The real CPH fragment translates to the same native code, but its
  * original function identity remains a separate exact profile. */
 profile.profileID=601;pass.passID=601;profile.fragmentName="fixed_frag_lph_cph";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
#ifdef A5_TEST_REAL_PROFILE
 real=NULL;
 for(size_t i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==601)real=&kA5MaliCompiledProfiles[i];
 assert(real);m.draw.profile=real;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
 m.draw.profile=&profile;
#endif
 /* 602 is the actual fixed_vert_lph_spc specialization seen in the phone
  * trace. Its compiled VS happens to be byte-identical to std_vert0_lph;
  * keep the captured function identity distinct in the profile contract. */
 profile.profileID=602;pass.passID=602;
 profile.vertexName="fixed_vert_lph_spc";
 profile.flags=A5MaliProfileSourceOverBlend;profile.attachmentContractCount=2;
 attachments[1]=attachments[0];attachments[1].attachments[0]=(A5MaliCompiledAttachmentState){15,1,0,0,1,5,1,5};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
#ifdef A5_TEST_REAL_PROFILE
 real=NULL;
 for(size_t i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==602)real=&kA5MaliCompiledProfiles[i];
 assert(real);m.draw.profile=real;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
 m.draw.profile=&profile;
#endif
 /* The same authentic602 native shader performs premultiplied source-over
  * through real fixed-function blending, not a second blend in the shader. */
 m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x540),RENDERER_STATE,over);
 assert(over.multisample_misc.load_destination&&over.blend_equation.color_mask==15);
 assert(over.blend_equation.rgb.a==MALI_BLEND_OPERAND_A_SRC&&over.blend_equation.rgb.b==MALI_BLEND_OPERAND_B_DEST&&
  over.blend_equation.rgb.c==MALI_BLEND_OPERAND_C_SRC_ALPHA&&over.blend_equation.rgb.invert_c);
 assert(over.blend_equation.alpha.a==MALI_BLEND_OPERAND_A_SRC&&over.blend_equation.alpha.b==MALI_BLEND_OPERAND_B_DEST&&
  over.blend_equation.alpha.c==MALI_BLEND_OPERAND_C_SRC_ALPHA&&over.blend_equation.alpha.invert_c);
 assert(!memcmp(descriptor+0x6000,vs,1808)&&!memcmp(descriptor+0x8000,fs,848));
 attachments[1].attachments[0].destinationRGB=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 attachments[1].attachments[0].destinationRGB=5;profile.flags=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 profile.flags=A5MaliProfileSourceOverBlend;m.draw.blend=A5RuntimeBlendCopy;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(syntheticDescriptor,descriptor,sizeof(descriptor)));
 uint16_t indices16[]={99,0,1,2,2,1,3};
 m.draw.primitive=A5RuntimeTriangle;m.draw.indexCount=6;m.draw.indexSize=2;
 m.draw.indexBuffer=(A5RuntimeBuffer){0,sizeof(indices16),2,(const uint8_t *)indices16};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_primitive_packed*)(descriptor+0x128),PRIMITIVE,indexed16);
 assert(indexed16.index_type==MALI_INDEX_TYPE_UINT16&&indexed16.index_count==6&&
        indexed16.base_vertex_offset==0&&indexed16.primitive_restart==MALI_PRIMITIVE_RESTART_NONE);
 assert(indexed16.indices>=m.draw.descriptorGPUVA+0x20000&&
        indexed16.indices+12<=m.draw.descriptorGPUVA+0x30000&&
        !memcmp(descriptor+(indexed16.indices-m.draw.descriptorGPUVA),indices16+1,12));
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x20),INVOCATION,indexedVS);
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x120),INVOCATION,indexedTiler);
 assert(indexedVS.invocations==3&&indexedTiler.invocations==3);
 uint16_t degenerate[]={0,0,0};
 m.draw.vertexCount=1;m.draw.indexCount=3;
 m.draw.indexBuffer=(A5RuntimeBuffer){0,sizeof(degenerate),0,(const uint8_t *)degenerate};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x20),INVOCATION,oneVS);
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x120),INVOCATION,oneTiler);
 assert(!oneVS.invocations&&!oneTiler.invocations);
 degenerate[1]=1;degenerate[2]=1;m.draw.vertexCount=2;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x20),INVOCATION,twoVS);
 pan_unpack((struct mali_invocation_packed*)(descriptor+0x120),INVOCATION,twoTiler);
 assert(twoVS.invocations==1&&twoTiler.invocations==1);
 m.draw.vertexCount=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.draw.vertexCount=4;m.draw.indexCount=6;
 uint32_t indices32[]={99,0,1,2,2,1,3};
 m.draw.indexSize=4;
 m.draw.indexBuffer=(A5RuntimeBuffer){0,sizeof(indices32),4,(const uint8_t *)indices32};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_primitive_packed*)(descriptor+0x128),PRIMITIVE,indexed32);
 assert(indexed32.index_type==MALI_INDEX_TYPE_UINT32&&indexed32.index_count==6&&
        indexed32.indices>=m.draw.descriptorGPUVA+0x20000&&
        indexed32.indices+24<=m.draw.descriptorGPUVA+0x30000&&
        !memcmp(descriptor+(indexed32.indices-m.draw.descriptorGPUVA),indices32+1,24));
 profile.profileID=601;pass.passID=601;profile.vertexName="std_vert0_lph";profile.flags=0;profile.attachmentContractCount=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 profile.profileID=602;pass.passID=602;profile.vertexName="fixed_vert_lph_spc";profile.flags=A5MaliProfileSourceOverBlend;profile.attachmentContractCount=2;
 indices32[6]=4;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 indices32[6]=3;m.draw.indexBuffer.bytes--;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.indexBuffer.bytes++;m.draw.indexBuffer.offset++;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.indexBuffer.offset--;m.draw.indexBuffer.cpuBytes=NULL;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.indexBuffer.cpuBytes=(const uint8_t *)indices32;m.draw.indexSize=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.draw.indexSize=4;m.draw.indexCount=A5RuntimeMaxIndices+1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.draw.indexCount=5;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.draw.indexCount=m.draw.indexSize=0;m.draw.indexBuffer=(A5RuntimeBuffer){0};
 m.draw.primitive=A5RuntimeTriangleStrip;
 profile.vertexName="std_vert0_lph";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 profile.vertexName="fixed_vert_lph_spc";
 profile.fragmentName="fixed_frag_lph_cpf";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 profile.profileID=600;pass.passID=600;profile.flags=0;profile.attachmentContractCount=1;
 profile.vertexName="std_vert0_lph";
 m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.draw.blend=A5RuntimeBlendCopy;m.draw.vertexBuffers[1].bytes=sizeof(vertices)-1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){m.colorAttachments[0].gpuVA,
  sizeof(vertices),0,NULL};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[1].bytes=sizeof(vertices);attr[3].offset=16;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 attr[3].offset=32;res.uniformBytes=168;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 res.uniformBytes=64;pass.fragment.sha256="wrong";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 free(vs);free(fs);
 puts("PASS generic600/601/602 exact host pair descriptor/ABI and unsupported-state gates; device pixels unverified");
 return 0;
}
