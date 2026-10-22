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
 A5MaliCompiledAttachmentContract attachment={0};
 for(unsigned i=0;i<8;++i){attachment.attachments[i].writeMask=15;
  attachment.attachments[i].sourceRGB=1;attachment.attachments[i].sourceAlpha=1;}
 A5MaliCompiledProfile profile={0};profile.profileID=600;
 profile.vertexName="std_vert0_lph";profile.fragmentName="fixed_frag_lph_cpf";
 profile.colorFormats[0]=80;
 profile.passes=&pass;profile.passCount=1;profile.resources=&res;profile.resourceCount=1;
 profile.pushFields=push;profile.pushFieldCount=2;profile.attributes=attr;profile.attributeCount=4;
 profile.layouts=&layout;profile.layoutCount=1;
 profile.attachmentContracts=&attachment;profile.attachmentContractCount=1;
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
 profile.fragmentName="fixed_frag_lph_cpf";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 profile.profileID=600;pass.passID=600;
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
 puts("PASS generic600/601 exact host pair descriptor/ABI and unsupported-state gates; device pixels unverified");
 return 0;
}
