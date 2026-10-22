/* SPDX-License-Identifier: MIT
 * Host descriptor test for the exact compiled UV/texture candidate. Native
 * programs are private command-line inputs; this test never submits a job.
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

static uint8_t descriptor[A5RuntimeJobBytes],baseline[A5RuntimeJobBytes];
static uint8_t vertices[4*48],matrix[64],uvTransform[16],bias[8];
static int zeroed(void){for(size_t i=0;i<sizeof(descriptor);++i)if(descriptor[i])return 0;return 1;}
static uint8_t*program(const char*path,size_t expected){
 FILE*f=fopen(path,"rb");assert(f);uint8_t*b=malloc(expected);assert(b);
 assert(fread(b,1,expected,f)==expected&&fgetc(f)==EOF);fclose(f);return b;
}
int main(int argc,char**argv){
 assert(argc==3);
 uint8_t*vs=program(argv[1],2192),*fs=program(argv[2],976);
 A5MaliCompiledPass pass={603,0,
  {vs,2192,5,8,0,0,"e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96"},
  {fs,976,5,6,0,0,"b7ab26bc9a0da3ff4a5f87e73fe6aaab07680ae383a3fbdd9d8abc000387cd96"}};
 A5MaliCompiledResource resources[]={
  {1,1,2,0,1,1,0,64,0,0},{1,1,3,1,2,1,0,16,0,4},
  {2,1,2,3,4,1,0,8,0,68},{2,2,3,5,0,1,0,0,0,0},
  {2,3,0,5,0,1,0,0,0,0}
 };
 A5MaliCompiledPushField push[]={
  {1,1,2,0,4,0},{1,1,3,4,4,0},{2,1,2,68,4,0},
  {2,2,0,72,4,0x2222}
 };
 A5MaliCompiledVertexAttribute attrs[]={
  {0,31,0,1},{1,29,16,1},{2,29,24,1},{3,27,32,1}};
 A5MaliCompiledVertexLayout layout={1,48,1,1};
 A5MaliCompiledAttachmentContract attachment[2]={0};
 for(unsigned c=0;c<2;++c)for(unsigned i=0;i<8;++i){
  attachment[c].attachments[i].writeMask=15;
  attachment[c].attachments[i].sourceRGB=1;
  attachment[c].attachments[i].sourceAlpha=1;
 }
 attachment[1].attachments[0].blendEnabled=1;
 attachment[1].attachments[0].destinationRGB=5;
 attachment[1].attachments[0].destinationAlpha=5;
 A5MaliCompiledProfile p={0};p.profileID=603;p.vertexName="fixed_vert_lph_spc";
 p.fragmentName="fixed_frag_lph_cph";p.colorFormats[0]=80;
 p.flags=A5MaliProfileSourceOverBlend;
 p.passes=&pass;p.passCount=1;p.resources=resources;p.resourceCount=5;
 p.pushFields=push;p.pushFieldCount=4;p.attributes=attrs;p.attributeCount=4;
 p.layouts=&layout;p.layoutCount=1;
 p.attachmentContracts=attachment;p.attachmentContractCount=2;
 A5RuntimeMiscDraw m={0};m.draw.profile=&p;m.draw.descriptorGPUVA=0x12000000;
 m.draw.vertexCount=4;m.draw.primitive=A5RuntimeTriangleStrip;
 m.draw.viewportWidth=m.draw.viewportHeight=32;m.draw.viewportFar=1;
 m.draw.scissorWidth=m.draw.scissorHeight=32;
 m.draw.vertexBuffers[1]=(A5RuntimeBuffer){0,sizeof(vertices),0,vertices};
 m.draw.vertexBuffers[2]=(A5RuntimeBuffer){0,sizeof(matrix),0,matrix};
 m.draw.vertexBuffers[3]=(A5RuntimeBuffer){0,sizeof(uvTransform),0,uvTransform};
 m.draw.fragmentBuffers[2]=(A5RuntimeBuffer){0,sizeof(bias),0,bias};
 m.colorAttachments[0]=(A5RuntimeImage){0x22000000,4096,32,32,128,80};
 m.fragmentTextures[3]=(A5RuntimeImage){0x23000000,1024,16,16,64,80};
 m.fragmentSamplers[0]=(A5RuntimeSampler){1,A5RuntimeSamplerLinear,
  A5RuntimeSamplerNearest,A5RuntimeSamplerMipNone,
  A5RuntimeSamplerClampEdge,A5RuntimeSamplerClampEdge,
  A5RuntimeSamplerClampEdge,1,1,0,0,1000};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 memcpy(baseline,descriptor,sizeof(descriptor));
#ifdef A5_TEST_REAL_PROFILE
 const A5MaliCompiledProfile*real=NULL;
 for(size_t i=0;i<sizeof(kA5MaliCompiledProfiles)/sizeof(kA5MaliCompiledProfiles[0]);++i)
  if(kA5MaliCompiledProfiles[i].profileID==603)real=&kA5MaliCompiledProfiles[i];
 assert(real);m.draw.profile=real;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(baseline,descriptor,sizeof(descriptor)));
 m.draw.profile=&p;
#endif
 assert(!memcmp(descriptor+0x6000,vs,2192));assert(!memcmp(descriptor+0x8000,fs,976));
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x500),RENDERER_STATE,vrs);
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x540),RENDERER_STATE,frs);
 assert(vrs.shader.attribute_count==3&&vrs.shader.varying_count==4&&
        vrs.properties.uniform_buffer_count==3&&vrs.properties.work_register_count==8);
 assert(frs.shader.texture_count==1&&frs.shader.sampler_count==1&&
        frs.shader.varying_count==1&&frs.properties.uniform_buffer_count==5&&
        frs.properties.work_register_count==6&&
        !frs.multisample_misc.load_destination);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0x808),ATTRIBUTE,uv);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0x810),ATTRIBUTE,color);
 assert((uv.format>>12)==MALI_RG32F&&uv.offset==16);
 assert((color.format>>12)==MALI_RGBA16F&&color.offset==32);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0xa10),ATTRIBUTE,uvout);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0xa18),ATTRIBUTE,colorout);
 pan_unpack((struct mali_attribute_packed*)(descriptor+0xc00),ATTRIBUTE,uvin);
 assert(uvout.buffer_index==2&&(uvout.format>>12)==MALI_RG32UI);
 assert(colorout.buffer_index==3&&(colorout.format>>12)==MALI_RGBA32UI);
 assert(uvin.buffer_index==0&&(uvin.format>>12)==MALI_RG32F);
 pan_unpack((struct mali_texture_packed*)(descriptor+0x600),TEXTURE,texture);
 pan_unpack((struct mali_surface_with_stride_packed*)(descriptor+0x620),SURFACE_WITH_STRIDE,surface);
 pan_unpack((struct mali_sampler_packed*)(descriptor+0x6a0),SAMPLER,sampler);
 assert(texture.width==16&&texture.height==16&&texture.levels==1);
 assert(surface.pointer==m.fragmentTextures[3].gpuVA&&surface.row_stride==64);
 assert(sampler.normalized_coordinates&&!sampler.minify_nearest&&
        sampler.magnify_nearest&&sampler.maximum_lod==0);
 uint32_t w,h,rule;memcpy(&w,descriptor+0x1400+356,4);
 memcpy(&h,descriptor+0x1400+360,4);
 memcpy(&rule,descriptor+0x1400+72,4);
 assert(w==16&&h==16&&rule==0x2222);
 /* Both pipeline states use the identical genuine native programs. The
  * source-over variant preloads the framebuffer and uses the fixed RSD
  * equation for premultiplied source alpha, retaining the copy path. */
 m.draw.blend=A5RuntimeBlendPremultipliedSourceOver;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_renderer_state_packed*)(descriptor+0x540),RENDERER_STATE,blend);
 assert(blend.multisample_misc.load_destination&&blend.blend_equation.color_mask==15);
 assert(blend.blend_equation.rgb.a==MALI_BLEND_OPERAND_A_SRC&&
        blend.blend_equation.rgb.b==MALI_BLEND_OPERAND_B_DEST&&
        blend.blend_equation.rgb.c==MALI_BLEND_OPERAND_C_SRC_ALPHA&&
        blend.blend_equation.rgb.invert_c);
 assert(blend.blend_equation.alpha.a==MALI_BLEND_OPERAND_A_SRC&&
        blend.blend_equation.alpha.b==MALI_BLEND_OPERAND_B_DEST&&
        blend.blend_equation.alpha.c==MALI_BLEND_OPERAND_C_SRC_ALPHA&&
        blend.blend_equation.alpha.invert_c);
 pan_unpack((struct mali_job_header_packed*)descriptor,JOB_HEADER,first);
 pan_unpack((struct mali_job_header_packed*)(descriptor+0x1800),JOB_HEADER,preload);
 pan_unpack((struct mali_job_header_packed*)(descriptor+0x100),JOB_HEADER,tiler);
 assert(first.next==m.draw.descriptorGPUVA+0x1800&&
        preload.type==MALI_JOB_TYPE_TILER&&preload.index==2&&
        preload.dependency_1==1&&preload.next==m.draw.descriptorGPUVA+0x100&&
        tiler.index==3&&tiler.dependency_1==1&&tiler.dependency_2==2);
 assert(!memcmp(descriptor+0x6000,baseline+0x6000,2192)&&
        !memcmp(descriptor+0x8000,baseline+0x8000,976));
 m.draw.blend=A5RuntimeBlendCopy;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 assert(!memcmp(descriptor,baseline,sizeof(descriptor)));
 uint16_t indices[]={99,0,1,2,2,1,3};
 m.draw.primitive=A5RuntimeTriangle;m.draw.indexCount=6;m.draw.indexSize=2;
 m.draw.indexBuffer=(A5RuntimeBuffer){0,sizeof(indices),2,(const uint8_t*)indices};
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeOK);
 pan_unpack((struct mali_primitive_packed*)(descriptor+0x128),PRIMITIVE,prim);
 assert(prim.index_type==MALI_INDEX_TYPE_UINT16&&prim.index_count==6&&
        prim.indices>=m.draw.descriptorGPUVA+0x20000&&
        prim.indices+12<=m.draw.descriptorGPUVA+0x30000&&
        !memcmp(descriptor+prim.indices-m.draw.descriptorGPUVA,indices+1,12));
 m.draw.indexCount=m.draw.indexSize=0;m.draw.indexBuffer=(A5RuntimeBuffer){0};
 m.draw.primitive=A5RuntimeTriangleStrip;
 m.fragmentSamplers[0].sAddressMode=A5RuntimeSamplerRepeat;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.fragmentSamplers[0].sAddressMode=A5RuntimeSamplerClampEdge;
 m.fragmentSamplers[0].normalizedCoordinates=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.fragmentSamplers[0].normalizedCoordinates=1;
 m.fragmentSamplers[0].maxAnisotropy=2;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.fragmentSamplers[0].maxAnisotropy=1;
 m.fragmentTextures[3].metalPixelFormat=115;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.fragmentTextures[3].metalPixelFormat=80;
 m.fragmentTextures[3].gpuVA=m.colorAttachments[0].gpuVA;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 m.fragmentTextures[3].gpuVA=0x23000000;
 m.draw.fragmentBuffers[2].bytes=3;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeBounds&&zeroed());
 m.draw.fragmentBuffers[2].bytes=sizeof(bias);
 resources[4].metalIndex=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 resources[4].metalIndex=0;
 attachment[1].attachments[0].destinationRGB=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 attachment[1].attachments[0].destinationRGB=5;
 attachment[1].attachments[0].sourceAlpha=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 attachment[1].attachments[0].sourceAlpha=1;
 attachment[1].attachments[1].blendEnabled=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 attachment[1].attachments[1].blendEnabled=0;
 p.flags=0;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 p.flags=A5MaliProfileSourceOverBlend;
 p.attachmentContractCount=1;
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 p.attachmentContractCount=2;
 pass.fragment.sha256="wrong";
 assert(A5MaliEncodeRuntimeMiscPass(&m,descriptor,sizeof(descriptor))==A5RuntimeUnsupported&&zeroed());
 free(vs);free(fs);
 puts("PASS generic603 native texture copy/source-over descriptors, preload order, bounds; device pixels unverified");
 return 0;
}
