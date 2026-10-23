/* SPDX-License-Identifier: MIT
 * Real dynamic misc-pass emitter. Code/constants are supplied by authenticated
 * profiles; vertices, uniforms, storage buffers and images are actual bindings.
 */
#define PAN_ARCH 4
#include <stdint.h>
#include "runtime_misc_encode.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"
#include "runtime_preload.h"

enum { SIZE=0x40000, W=32,H=32, FB=0x300,VS_RSD=0x500,FS_RSD=0x540,
 TEX0=0x600,TEX1=0x640,TEX_TABLE=0x680,SAMPLERS=0x6a0,
 VS_UBOS=0x700,FS_UBOS=0x740,ATTRS=0x800,ATTR_BUFS=0x900,
 VS_VARY=0xa00,VS_VARY_BUFS=0xa80,FS_VARY=0xc00,FS_VARY_BUFS=0xc80,
 VIEWPORT=0xe00,VS_SYS=0x1000,FS_SYS=0x1400,
 SSBO_VERT=0x2000,ORDINARY=0x3000,POS=0x30000,PSIZ=0x31000,
 VARY_DATA=0x32000,VS_CODE=0x6000,FS_CODE=0x8000,POLY=0xa000,POLY_BODY=0xa200,
 HEAP=0x10000,HEAP_SIZE=0x10000,SOURCE=0x20000,LUT=0x22000,
 DEST=0x24000,GUARDS=0x28000 };
enum { RG_SWIZZLE=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9),
 A_SWIZZLE=MALI_CHANNEL_0|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_R<<9),
 R_SWIZZLE=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9) };
enum { ARENA=0x20000,ARENA_END=0x30000 };
_Static_assert(MALI_ATTRIBUTE_BUFFER_LENGTH == 16, "v4 attribute table stride");
/* ATTRIBUTE buffer_index counts 16-byte descriptors, not 32-byte allocations.
 * Keep the deliberately padded special InstanceID at physical slot2. */
static void u32(uint8_t*d,unsigned o,uint32_t v){memcpy(d+o,&v,4);}
static void u64(uint8_t*d,unsigned o,uint64_t v){memcpy(d+o,&v,8);}
static void f32(uint8_t*d,unsigned o,float v){memcpy(d+o,&v,4);}
static void ubo(uint8_t*d,unsigned table,unsigned index,uint64_t address,unsigned bytes){
 pan_pack((struct mali_uniform_buffer_packed*)(d+table+index*8),UNIFORM_BUFFER,c){
  c.pointer=address;c.entries=(bytes+15)/16;
 }
}
static void attr(uint8_t*d,unsigned at,unsigned buffer,unsigned format,unsigned swizzle,unsigned off){
 pan_pack((struct mali_attribute_packed*)(d+at),ATTRIBUTE,c){
  c.buffer_index=buffer;c.offset_enable=true;c.format=(format<<12)|swizzle;c.offset=off;
 }
}
static void buf(uint8_t*d,unsigned at,uint64_t address,unsigned stride,unsigned bytes){
 pan_pack((struct mali_attribute_buffer_packed*)(d+at),ATTRIBUTE_BUFFER,c){
  c.pointer=address;c.stride=stride;c.size=bytes;
 }
}
static void framebuffer(uint8_t*d,uint64_t VA,unsigned format,const A5RuntimeImage*out){
 u32(d,FB+4,31); /* released v4 local storage, TLS/WLS bothzero */
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){
  c.internal_format=format==2?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:
     MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
  c.swizzle=format==0?0x60a:0x688;
  c.color_writeback_format=format==2?MALI_COLOR_FORMAT_2_32B_CHANNELS:
     format==1?MALI_COLOR_FORMAT_R8:format==3?MALI_COLOR_FORMAT_R8G8:MALI_COLOR_FORMAT_R8G8B8A8;
  c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;
  c.color_write_enable=true;
  c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
  c.bound_max_x=out->width-1;c.bound_max_y=out->height-1;
  c.color_writeback.base=out->gpuVA;c.color_writeback.row_stride=out->rowBytes;

 }
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){
  c.polygon_list=VA+POLY;c.polygon_list_body=VA+POLY_BODY;
  c.heap_start=VA+HEAP;c.heap_end=VA+HEAP+HEAP_SIZE;
  c.polygon_list_size=0x200+0x200*((out->width+1023)/1024)*((out->height+1023)/1024);c.hierarchy_mask=0x1c7;
 }
 u32(d,POLY_BODY,0xa0000000);
}
static void renderer(uint8_t*d,uint64_t VA,int home,int clear,int generic_color,int generic_textured,int textured_color,unsigned vs_regs,unsigned fs_regs,unsigned blend){
 pan_pack((struct mali_renderer_state_packed*)(d+VS_RSD),RENDERER_STATE,c){
  c.shader.shader=VA+VS_CODE+5;c.shader.attribute_count=generic_color?2:home||generic_textured?3:18;
  c.shader.varying_count=generic_color?3:home||generic_textured?4:clear?2:7;
  c.properties.uniform_buffer_count=generic_color?2:3;c.properties.work_register_count=vs_regs;
  c.properties.force_early_z=true;c.multisample_misc.sample_mask=0xffff;
  c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
 }
 pan_pack((struct mali_renderer_state_packed*)(d+FS_RSD),RENDERER_STATE,c){
  c.shader.shader=VA+FS_CODE+5;c.shader.texture_count=home?2:generic_textured?1:0;
  c.shader.sampler_count=home?2:generic_textured?1:0;c.shader.varying_count=textured_color?2:generic_color||generic_textured?1:home?1:clear?0:5;
  c.properties.uniform_buffer_count=generic_textured?5:generic_color?3:clear?1:4;c.properties.work_register_count=fs_regs;
  c.properties.force_early_z=true;c.multisample_misc.sample_mask=0xffff;
  c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
  c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;
  c.stencil_mask_misc.write_enable=true;c.stencil_mask_misc.dither_disable=true;
  c.multisample_misc.load_destination=!!blend;
  c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;
  c.blend_equation.rgb.b=blend?MALI_BLEND_OPERAND_B_DEST:MALI_BLEND_OPERAND_B_SRC;
  c.blend_equation.rgb.c=blend?MALI_BLEND_OPERAND_C_SRC_ALPHA:MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.rgb.invert_c=!!blend;
  c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;
  c.blend_equation.alpha.b=blend?MALI_BLEND_OPERAND_B_DEST:MALI_BLEND_OPERAND_B_SRC;
  c.blend_equation.alpha.c=blend?MALI_BLEND_OPERAND_C_SRC_ALPHA:MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.alpha.invert_c=!!blend;
  c.blend_equation.color_mask=0xf;
 }
}
static int span(uint64_t a,uint64_t n){return a&&n&&a<(UINT64_C(1)<<40)&&n<=(UINT64_C(1)<<40)-a;}
static int overlap(uint64_t a,uint64_t n,uint64_t b,uint64_t m){return a<b+m&&b<a+n;}
static unsigned bpp(unsigned f){return f==80?4:f==115?8:(f==1||f==10)?1:f==30?2:0;}
static int valid_image(const A5RuntimeImage*i){unsigned n=bpp(i->metalPixelFormat);
 return n&&span(i->gpuVA,i->bytes)&&!(i->gpuVA&63)&&i->width&&i->width<=2048&&i->height&&i->height<=2048&&
 i->rowBytes>=i->width*n&&!(i->rowBytes&15)&&(uint64_t)i->rowBytes*i->height<=i->bytes;
}
/* The 603 native fragment was compiled with SamplerState specID0=0:
 * normalized UVs. Words 0/2/4/6 (nearest/linear min/mag) yield identical
 * native code. The runtime sampler supplies filtering and clamp-to-edge
 * addressing. One source mip means every valid LOD resolves to level0. */
static int textured_sampler(const A5RuntimeSampler*s){
 return s->valid==1&&s->normalizedCoordinates==1&&s->maxAnisotropy==1&&
  !s->compareEnabled&&s->minFilter<=A5RuntimeSamplerLinear&&
  s->magFilter<=A5RuntimeSamplerLinear&&s->mipFilter<=A5RuntimeSamplerMipLinear&&
  s->sAddressMode==A5RuntimeSamplerClampEdge&&
  s->tAddressMode==A5RuntimeSamplerClampEdge&&
  s->rAddressMode==A5RuntimeSamplerClampEdge&&
  isfinite(s->lodMinClamp)&&isfinite(s->lodMaxClamp)&&
  s->lodMinClamp>=0&&s->lodMaxClamp>=s->lodMinClamp;
}
static int textured_image(uint8_t*d,const A5RuntimeMiscDraw*m){
 const A5RuntimeImage*im=&m->fragmentTextures[3];const A5RuntimeSampler*s=&m->fragmentSamplers[0];
 uint64_t VA=m->draw.descriptorGPUVA;
 if(!textured_sampler(s)||!valid_image(im)||
    (im->metalPixelFormat!=80&&im->metalPixelFormat!=30&&im->metalPixelFormat!=10&&im->metalPixelFormat!=1)||
    (m->draw.profile->profileID==603&&im->metalPixelFormat!=80)||
    (m->draw.profile->profileID==606&&im->metalPixelFormat!=1)||
    (uint64_t)im->rowBytes*im->height>INT32_MAX||
    overlap(im->gpuVA,im->bytes,VA,SIZE))return A5RuntimeUnsupported;
 for(unsigned i=0;i<m->draw.profile->passCount;++i){
  const A5RuntimeImage*dest=&m->colorAttachments[m->draw.profile->passes[i].logicalTarget];
  if(overlap(im->gpuVA,im->bytes,dest->gpuVA,dest->bytes))return A5RuntimeUnsupported;
 }
 const unsigned format=im->metalPixelFormat==80?MALI_RGBA8_UNORM:
  im->metalPixelFormat==30?MALI_RG8_UNORM:MALI_R8_UNORM;
 const unsigned swizzle=im->metalPixelFormat==80?0x60a:
  im->metalPixelFormat==30?RG_SWIZZLE:im->metalPixelFormat==1?A_SWIZZLE:R_SWIZZLE;
 pan_pack((struct mali_texture_packed*)(d+TEX0),TEXTURE,c){
  c.width=im->width;c.height=im->height;c.array_size=1;c.levels=1;
  c.format=(format<<12)|swizzle;c.dimension=MALI_TEXTURE_DIMENSION_2D;
  c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;
 }
 pan_pack((struct mali_surface_with_stride_packed*)(d+TEX0+32),SURFACE_WITH_STRIDE,c){
  c.pointer=im->gpuVA;c.row_stride=im->rowBytes;c.surface_stride=im->rowBytes*im->height;
 }
 u64(d,TEX_TABLE,VA+TEX0);
 pan_pack((struct mali_sampler_packed*)(d+SAMPLERS),SAMPLER,c){
  c.normalized_coordinates=true;c.seamless_cube_map=false;
  c.minify_nearest=s->minFilter==A5RuntimeSamplerNearest;
  c.magnify_nearest=s->magFilter==A5RuntimeSamplerNearest;
  c.mipmap_mode=MALI_MIPMAP_MODE_NEAREST;
  c.wrap_mode_s=MALI_WRAP_MODE_CLAMP_TO_EDGE;
  c.wrap_mode_t=MALI_WRAP_MODE_CLAMP_TO_EDGE;
  c.wrap_mode_r=MALI_WRAP_MODE_CLAMP_TO_EDGE;
  c.minimum_lod=0;c.maximum_lod=0;
 }
 /* The normalized-coordinate native shader samples interpolated UV directly.
  * It does not read synthetic texture dimensions from FS_SYS. */
 return A5RuntimeOK;
}
/* Admit only the captured, host-compiled native VS/FS pairs below. This is
 * an encoder contract, not evidence that a stock iOS draw uses the pair.
 * Inactive Metal attributes 1/2 are still part of the original 4QC layout;
 * native attr slots 0/1 are the surviving position and half4 colour inputs.
 * The captured FS constant blob and FB1 uniform are dead in this exact code.
 */
static int generic_color_contract(const A5MaliCompiledProfile*p){
 if((p->profileID!=600&&p->profileID!=601&&p->profileID!=602)||p->flags||p->passCount!=1||
    p->passes[0].passID!=p->profileID||p->passes[0].logicalTarget||
    p->colorFormats[0]!=80||p->attributeCount!=4||!p->attributes||
    p->layoutCount!=1||!p->layouts||p->resourceCount!=1||!p->resources||
    p->pushFieldCount!=2||!p->pushFields||p->attachmentContractCount!=1||
    !p->attachmentContracts)return 0;
 if(!p->vertexName||strcmp(p->vertexName,p->profileID==602?"fixed_vert_lph_spc":"std_vert0_lph")||
    !p->fragmentName||strcmp(p->fragmentName,p->profileID==600?"fixed_frag_lph_cpf":"fixed_frag_lph_cph"))return 0;
 for(unsigned i=1;i<8;++i)if(p->colorFormats[i])return 0;
 static const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
 for(unsigned i=0;i<4;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
  if(a->index!=i||a->format!=formats[i]||a->offset!=offsets[i]||a->bufferIndex!=1)return 0;
 }
 const A5MaliCompiledVertexLayout*l=p->layouts;
 if(l->index!=1||l->stride!=48||l->stepFunction!=1||l->stepRate!=1)return 0;
 const A5MaliCompiledResource*r=p->resources;
 if(r->stage!=A5MaliStageVertex||r->kind!=A5MaliResourceBuffer||
    r->metalIndex!=2||r->bindingIndex||r->nativeIndex!=1||
    r->flags!=A5MaliResourceRead||r->windowOffset||r->uniformBytes!=64||
    r->sysvalOffset||r->pushOffset)return 0;
 const A5MaliCompiledPushField*vs=p->pushFields,*fs=vs+1;
 if(vs->stage!=A5MaliStageVertex||vs->kind!=A5MaliPushBindOffset||
    vs->metalIndex!=2||vs->offset||vs->bytes!=4||vs->value||
    fs->stage!=A5MaliStageFragment||fs->kind!=A5MaliPushColorWriteRule||
    fs->metalIndex||fs->offset!=68||fs->bytes!=4||fs->value!=0x2222)return 0;
 for(unsigned i=0;i<8;++i){
  const A5MaliCompiledAttachmentState*a=&p->attachmentContracts[0].attachments[i];
  /* Unattached Metal slots retain their descriptor defaults even though
   * colorFormats[1..7] are zero and no native MRT is generated. */
  if(a->writeMask!=15||a->blendEnabled||a->rgbOperation||
     a->alphaOperation||a->sourceRGB!=1||a->destinationRGB||
     a->sourceAlpha!=1||a->destinationAlpha)return 0;
 }
 const A5MaliCompiledPass*pass=p->passes;
 return pass->vertex.sha256&&pass->fragment.sha256&&
  !strcmp(pass->vertex.sha256,"3cdf2b0db0b9992ce887242e7cac282cd70c3f8051e3ace3e791a0b676193a79")&&
  !strcmp(pass->fragment.sha256,"e66041333f6452510cda4d0ee1f1c1edf443a12007a989871a1546791deb0834")&&
  pass->vertex.byteCount==1808&&pass->fragment.byteCount==848&&
  pass->vertex.workRegisters==8&&pass->fragment.workRegisters==6;
}
/* This is a separate, actually compiled texture specialization. Its vertex
 * reads original Metal attr0/attr1/attr3, exports UV in VAR0 and colour in
 * VAR1. Texture3/Sampler0 uses FB2 bias. Profile606 additionally reads
 * FragmentBuffer1.float4@112 to clamp UV; prior603..605 leave FB1 dead.
 * The translator's synthetic blob remains dead in all pinned native pairs. */
static int generic_textured_contract(const A5MaliCompiledProfile*p){
 const int coord5=p->profileID==606;
 if((p->profileID!=603&&p->profileID!=604&&p->profileID!=605&&!coord5)||
    p->flags!=A5MaliProfileSourceOverBlend||p->passCount!=1||!p->passes||
    p->passes[0].passID!=p->profileID||p->passes[0].logicalTarget||
    !p->vertexName||strcmp(p->vertexName,"fixed_vert_lph_spc")||
    !p->fragmentName||strcmp(p->fragmentName,"fixed_frag_lph_cph")||
    p->colorFormats[0]!=80||p->attributeCount!=4||!p->attributes||
    p->layoutCount!=1||!p->layouts||p->resourceCount!=(coord5?6u:5u)||!p->resources||
    p->pushFieldCount!=(coord5?5u:4u)||!p->pushFields||p->attachmentContractCount!=2||
    !p->attachmentContracts)return 0;
 for(unsigned i=1;i<8;++i)if(p->colorFormats[i])return 0;
 static const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
 for(unsigned i=0;i<4;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
  if(a->index!=i||a->format!=formats[i]||a->offset!=offsets[i]||a->bufferIndex!=1)return 0;
 }
 const A5MaliCompiledVertexLayout*l=p->layouts;
 if(l->index!=1||l->stride!=48||l->stepFunction!=1||l->stepRate!=1)return 0;
 static const A5MaliCompiledResource expected[]={
  {1,1,2,0,1,1,0,64,0,0},
  {1,1,3,1,2,1,0,16,0,4},
  {2,1,1,2,3,1,0,128,0,64},
  {2,1,2,3,4,1,0,8,0,68},
  {2,2,3,5,0,1,0,0,0,0},
  {2,3,0,5,0,1,0,0,0,0}
 };
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*a=&p->resources[i],*b=&expected[i+(!coord5&&i>=2)];
  if(a->stage!=b->stage||a->kind!=b->kind||a->metalIndex!=b->metalIndex||
     a->bindingIndex!=b->bindingIndex||a->nativeIndex!=b->nativeIndex||
     a->flags!=b->flags||a->windowOffset!=b->windowOffset||
     a->uniformBytes!=b->uniformBytes||a->sysvalOffset!=b->sysvalOffset||
     a->pushOffset!=b->pushOffset)return 0;
 }
 static const A5MaliCompiledPushField pushes[]={
  {1,1,2,0,4,0},{1,1,3,4,4,0},{2,1,1,64,4,0},
  {2,1,2,68,4,0},{2,2,0,72,4,0x2222}
 };
 for(unsigned i=0;i<p->pushFieldCount;++i){const A5MaliCompiledPushField*a=&p->pushFields[i],*b=&pushes[i+(!coord5&&i>=2)];
  if(a->stage!=b->stage||a->kind!=b->kind||a->metalIndex!=b->metalIndex||
     a->offset!=b->offset||a->bytes!=b->bytes||a->value!=b->value)return 0;
 }
 for(unsigned contract=0;contract<2;++contract){
  for(unsigned i=0;i<8;++i){
   const A5MaliCompiledAttachmentState*a=&p->attachmentContracts[contract].attachments[i];
   const int source_over=contract==1&&i==0;
   if(a->writeMask!=15||a->blendEnabled!=source_over||a->rgbOperation||a->alphaOperation||
      a->sourceRGB!=1||a->destinationRGB!=(source_over?5:0)||
      a->sourceAlpha!=1||a->destinationAlpha!=(source_over?5:0))return 0;
  }
 }
 const A5MaliCompiledPass*pass=p->passes;
 const char*fragmentHash=p->profileID==603?
  "e4cf4d31a87bde096cc7cc57a12818f79296e3998d22d9c6c5139a9887f30047":
  p->profileID==604?
  "90d93347ca8bb50eef500ac2296e71dfb8298a58bd24d903f913295560798424":
  p->profileID==605?
  "48bccbbdd2b788137ff228c7677e87a574ccfcd29f324a7bc44015bc15f3e2ce":
  "5f1a9b4a037cb93f756bd3259f717d45c1a6622ee15d6504917c1582bf630e36";
 const unsigned fragmentBytes=p->profileID==603?880:p->profileID==604?1120:896;
 const unsigned fragmentRegs=p->profileID==604?6:5;
 return pass->vertex.sha256&&pass->fragment.sha256&&
  !strcmp(pass->vertex.sha256,"e0c51d2171b28c891677cdb1f1c98032bee0f03bb64af694a8321d711159fc96")&&
  !strcmp(pass->fragment.sha256,fragmentHash)&&
  pass->vertex.byteCount==2192&&pass->fragment.byteCount==fragmentBytes&&
  pass->vertex.workRegisters==8&&pass->fragment.workRegisters==fragmentRegs;
}
/* Dynamic code is compiled from the pinned source library by the root worker.
 * Its module fingerprint is deliberately not enumerated here. This independent
 * encoder gate admits only resource/packing semantics this emitter implements. */
static int dynamic_textured_contract(const A5MaliCompiledProfile*p){
 if(p->profileID!=A5MaliDynamicProfileID||
    !(p->flags&A5MaliProfileDynamicStages)||
    (p->flags&~(A5MaliProfileDynamicStages|A5MaliProfileDynamicColorVarying|A5MaliProfileSourceOverBlend))||
    !(p->flags&A5MaliProfileSourceOverBlend)||p->passCount!=1||!p->passes||
    p->passes[0].passID!=p->profileID||p->passes[0].logicalTarget||
    !p->vertexName||!p->vertexName[0]||!p->fragmentName||!p->fragmentName[0]||
    p->colorFormats[0]!=80||p->viewportWidth||p->viewportHeight||
    p->attributeCount!=4||!p->attributes||p->layoutCount!=1||!p->layouts||
    !p->resourceCount||p->resourceCount>16||!p->resources||
    !p->pushFieldCount||p->pushFieldCount>16||!p->pushFields||
    p->attachmentContractCount!=2||!p->attachmentContracts)return 0;
 for(unsigned i=1;i<8;++i)if(p->colorFormats[i])return 0;
 static const unsigned formats[]={31,29,29,27},offsets[]={0,16,24,32};
 for(unsigned i=0;i<4;++i){const A5MaliCompiledVertexAttribute*a=p->attributes+i;
  if(a->index!=i||a->format!=formats[i]||a->offset!=offsets[i]||a->bufferIndex!=1)return 0;
 }
 const A5MaliCompiledVertexLayout*l=p->layouts;
 if(l->index!=1||l->stride!=48||l->stepFunction!=1||l->stepRate!=1)return 0;
 unsigned textures=0,samplers=0;uint32_t bindings[2]={0},slots[2]={0};
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*r=p->resources+i;
  if((r->stage!=1&&r->stage!=2)||r->flags!=A5MaliResourceRead||r->windowOffset||r->sysvalOffset)return 0;
  unsigned st=r->stage-1;
  if(r->kind==A5MaliResourceBuffer){
   if(r->metalIndex>=31||r->bindingIndex>=7||r->nativeIndex!=r->bindingIndex+1||
      !r->uniformBytes||r->uniformBytes>4096||r->pushOffset>76||(r->pushOffset&3)||
      (bindings[st]&(1u<<r->bindingIndex))||(slots[st]&(1u<<r->metalIndex)))return 0;
   bindings[st]|=1u<<r->bindingIndex;slots[st]|=1u<<r->metalIndex;
  }else if(r->kind==A5MaliResourceTexture){
   if(r->stage!=2||r->metalIndex!=3||r->nativeIndex||r->uniformBytes||r->pushOffset||textures++)return 0;
  }else if(r->kind==A5MaliResourceSampler){
   if(r->stage!=2||r->metalIndex||r->nativeIndex||r->uniformBytes||r->pushOffset||samplers++)return 0;
  }else return 0;
 }
 if(textures!=1||samplers!=1)return 0;
 uint32_t used[2]={0};
 for(unsigned i=0;i<p->pushFieldCount;++i){const A5MaliCompiledPushField*f=p->pushFields+i;
  if((f->stage!=1&&f->stage!=2)||f->bytes!=4||f->offset>76||(f->offset&3)||
     (used[f->stage-1]&(1u<<(f->offset/4))))return 0;
  used[f->stage-1]|=1u<<(f->offset/4);
  if(f->kind==A5MaliPushBindOffset){
   unsigned match=0;
   for(unsigned j=0;j<p->resourceCount;++j){const A5MaliCompiledResource*r=p->resources+j;
    if(r->stage==f->stage&&r->kind==A5MaliResourceBuffer&&r->metalIndex==f->metalIndex&&r->pushOffset==f->offset)match++;
   }
   if(match!=1||f->value)return 0;
  }else if(f->kind!=A5MaliPushColorWriteRule||f->stage!=2||f->value!=0x2222||f->metalIndex)return 0;
 }
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*r=p->resources+i;
  if(r->kind==A5MaliResourceBuffer&&!(used[r->stage-1]&(1u<<(r->pushOffset/4))))return 0;
 }
 for(unsigned c=0;c<2;++c)for(unsigned i=0;i<8;++i){
  const A5MaliCompiledAttachmentState*a=&p->attachmentContracts[c].attachments[i];
  unsigned over=c==1&&i==0;
  if(a->writeMask!=15||a->blendEnabled!=over||a->rgbOperation||a->alphaOperation||
     a->sourceRGB!=1||a->sourceAlpha!=1||a->destinationRGB!=(over?5u:0u)||
     a->destinationAlpha!=(over?5u:0u))return 0;
 }
 return 1;
}
int A5MaliDynamicRuntimeProfileSupported(const A5MaliCompiledProfile*p){
 return p&&dynamic_textured_contract(p);
}
static unsigned dynamic_ubo_count(const A5MaliCompiledProfile*p,unsigned stage){
 unsigned count=1;
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*r=p->resources+i;
  if(r->stage==stage&&r->kind==A5MaliResourceBuffer&&r->nativeIndex>=count)count=r->nativeIndex+1;
 }
 return count;
}
static int bind_buffer(const A5RuntimeMiscDraw*m,uint8_t*d,unsigned*arena,
 const A5RuntimeBuffer*b,unsigned need,uint64_t*addr,unsigned*push,unsigned*available){
 if(!need||b->offset>b->bytes||need>b->bytes-b->offset)return 0;
 if(b->cpuBytes){
  unsigned at=(*arena+63)&~63u;if(at>ARENA_END||need>ARENA_END-at)return 0;
  memcpy(d+at,b->cpuBytes+b->offset,need);*arena=(at+need+63)&~63u;
  *addr=m->draw.descriptorGPUVA+at;*push=0;*available=need;return 1;
 }
 if(!span(b->gpuVA,b->bytes)||(b->gpuVA&15)||overlap(b->gpuVA,b->bytes,m->draw.descriptorGPUVA,SIZE))return 0;
 for(unsigned i=0;i<m->draw.profile->passCount;++i){const A5RuntimeImage*im=&m->colorAttachments[m->draw.profile->passes[i].logicalTarget];
  if(overlap(b->gpuVA,b->bytes,im->gpuVA,im->bytes))return 0;
 }
 unsigned folded=b->offset&~15u;*addr=b->gpuVA+folded;*push=b->offset&15u;*available=b->bytes-folded;return 1;
}
static int resources(uint8_t*d,const A5RuntimeMiscDraw*m,int home,int clear,int generic_color,int generic_textured,unsigned*outArena){
 const A5RuntimeDraw*r=&m->draw;const A5MaliCompiledProfile*p=r->profile;uint64_t VA=r->descriptorGPUVA;
 unsigned arena=ARENA,pushes[2][31]={{0}},seen[2][31]={{0}};
 for(unsigned i=0;i<8;++i){ubo(d,VS_UBOS,i,VA+VS_SYS,576);ubo(d,FS_UBOS,i,VA+FS_SYS,576);}
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*c=p->resources+i;
  if(c->stage!=A5MaliStageVertex&&c->stage!=A5MaliStageFragment)return A5RuntimeUnsupported;
  if(c->kind!=A5MaliResourceBuffer)continue;
  if(c->metalIndex>=31||c->windowOffset||(c->flags&A5MaliResourceWrite))return A5RuntimeUnsupported;
  unsigned st=c->stage==A5MaliStageFragment;
  const A5RuntimeBuffer*b=st?&r->fragmentBuffers[c->metalIndex]:&r->vertexBuffers[c->metalIndex];
  unsigned storage=!!(c->flags&A5MaliResourceStorage),need=storage?(b->offset<=b->bytes?b->bytes-b->offset:0):c->uniformBytes;
  uint64_t addr;unsigned push,available;
  if(!bind_buffer(m,d,&arena,b,need,&addr,&push,&available))return A5RuntimeBounds;
  if(storage){
   if(c->sysvalOffset<96||c->sysvalOffset>336||(c->sysvalOffset&15))return A5RuntimeUnsupported;
   u64(d,(st?FS_SYS:VS_SYS)+c->sysvalOffset,addr);u32(d,(st?FS_SYS:VS_SYS)+c->sysvalOffset+8,available);
  }else{
   if(!c->nativeIndex||c->nativeIndex>=8||!c->uniformBytes||c->uniformBytes>4096)return A5RuntimeUnsupported;
   ubo(d,st?FS_UBOS:VS_UBOS,c->nativeIndex,addr,push+need);
  }
  seen[st][c->metalIndex]=1;pushes[st][c->metalIndex]=push;
 }
 for(unsigned i=0;i<p->pushFieldCount;++i){const A5MaliCompiledPushField*f=p->pushFields+i;
  if((f->stage!=A5MaliStageVertex&&f->stage!=A5MaliStageFragment)||f->bytes!=4||(f->offset&3)||f->offset>76)return A5RuntimeUnsupported;
  unsigned st=f->stage==A5MaliStageFragment,value=f->value;
  if(f->kind==A5MaliPushBindOffset){if(f->metalIndex>=31||!seen[st][f->metalIndex])return A5RuntimeUnsupported;value=pushes[st][f->metalIndex];}
  else if(f->kind!=A5MaliPushColorWriteRule)return A5RuntimeUnsupported;
  u32(d,(st?FS_SYS:VS_SYS)+f->offset,value);
 }
 /* These stock AIR vertex programs preserve Metal clip-space Y.
  * Metal2Vulkan requires a negative-height viewport at the binding boundary:
  * NDC +1 is the top row, while the texture/scissor origins stay unchanged.
  * Apply this once to all nine misc profiles; the vertex programs do not
  * independently negate their final position Y. */
 float yScale=(float)(-r->viewportHeight*.5);
 for(unsigned st=0;st<2;++st){unsigned o=st?FS_SYS:VS_SYS;
  f32(d,o+512,(float)(r->viewportWidth*.5));f32(d,o+516,yScale);f32(d,o+520,(float)((r->viewportFar-r->viewportNear)*.5));
  f32(d,o+528,(float)(r->viewportX+r->viewportWidth*.5));f32(d,o+532,(float)(r->viewportY+r->viewportHeight*.5));f32(d,o+536,(float)((r->viewportFar+r->viewportNear)*.5));
 }
 if(home||generic_color||generic_textured){
  uint64_t vertex;unsigned push,available;
  if(!bind_buffer(m,d,&arena,&r->vertexBuffers[1],r->vertexCount*48,&vertex,&push,&available))return A5RuntimeBounds;
  vertex+=push;unsigned low=(unsigned)(vertex&63);vertex&=~UINT64_C(63);
  attr(d,ATTRS,0,MALI_RGBA32F,0x688,low);
  if(generic_color)attr(d,ATTRS+8,0,MALI_RGBA16F,0x688,low+32);
  else{attr(d,ATTRS+8,0,MALI_RG32F,RG_SWIZZLE,low+16);attr(d,ATTRS+16,0,MALI_RGBA16F,0x688,low+32);}
  buf(d,ATTR_BUFS,vertex,48,r->vertexCount*48+low);
  if(generic_textured){int rc=textured_image(d,m);if(rc)return rc;}
  if(home)for(unsigned t=0;t<2;++t){const A5RuntimeImage*im=&m->fragmentTextures[t+3];unsigned tex=t?TEX1:TEX0;
   if(!valid_image(im)||im->metalPixelFormat!=80)return A5RuntimeUnsupported;
   for(unsigned i=0;i<p->passCount;++i){const A5RuntimeImage*dest=&m->colorAttachments[p->passes[i].logicalTarget];
    if(overlap(im->gpuVA,im->bytes,dest->gpuVA,dest->bytes))return A5RuntimeUnsupported;
   }
   if(overlap(im->gpuVA,im->bytes,VA,SIZE))return A5RuntimeUnsupported;
   pan_pack((struct mali_texture_packed*)(d+tex),TEXTURE,c){c.width=im->width;c.height=im->height;c.array_size=1;c.levels=1;c.format=(MALI_RGBA8_UNORM<<12)|0x60a;c.dimension=MALI_TEXTURE_DIMENSION_2D;c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;}
   pan_pack((struct mali_surface_with_stride_packed*)(d+tex+32),SURFACE_WITH_STRIDE,c){c.pointer=im->gpuVA;c.row_stride=im->rowBytes;c.surface_stride=im->rowBytes*im->height;}
   u64(d,TEX_TABLE+t*8,VA+tex);
   /* Exact AIR constexpr sampler: linear, normalized clamp-to-edge, LOD0..0.25. */
   pan_pack((struct mali_sampler_packed*)(d+SAMPLERS+t*32),SAMPLER,c){c.normalized_coordinates=true;c.seamless_cube_map=false;c.minify_nearest=false;c.magnify_nearest=false;c.maximum_lod=.25f;}
   unsigned q=FS_SYS+352+32*t;u32(d,q,1);u32(d,q+4,im->width);u32(d,q+8,im->height);f32(d,q+20,.25f);
  }
 }else{
  pan_pack((struct mali_attribute_vertex_id_packed*)(d+ATTR_BUFS),ATTRIBUTE_VERTEX_ID,c){c.divisor_r=31;c.divisor_p=4;}
  pan_pack((struct mali_attribute_instance_id_packed*)(d+ATTR_BUFS+32),ATTRIBUTE_INSTANCE_ID,c){c.divisor_p=0x7fffffff;c.divisor_r=31;c.divisor_e=1;}
  attr(d,ATTRS+16*8,0,MALI_R32UI,R_SWIZZLE,0);attr(d,ATTRS+17*8,2,MALI_R32UI,R_SWIZZLE,0);
 }
 attr(d,VS_VARY,0,MALI_SNAP_4,0x688,0);buf(d,VS_VARY_BUFS,VA+POS,16,r->vertexCount*16);
 attr(d,VS_VARY+8,1,MALI_R16F,R_SWIZZLE,0);buf(d,VS_VARY_BUFS+16,VA+PSIZ,2,r->vertexCount*2);
 if(home||generic_textured){
  attr(d,VS_VARY+16,2,MALI_RGBA32UI,0x688,0);buf(d,VS_VARY_BUFS+32,VA+VARY_DATA,16,r->vertexCount*16);
  attr(d,VS_VARY+24,3,MALI_RG32UI,RG_SWIZZLE,0);buf(d,VS_VARY_BUFS+48,VA+VARY_DATA+0x1000,8,r->vertexCount*8);
  if(generic_textured){
   /* Textured VS: hardware VAR0 is UV, VAR1 is colour; FS reads VAR0. */
   attr(d,VS_VARY+16,2,MALI_RG32UI,RG_SWIZZLE,0);
   buf(d,VS_VARY_BUFS+32,VA+VARY_DATA,8,r->vertexCount*8);
   attr(d,VS_VARY+24,3,MALI_RGBA32UI,0x688,0);
   buf(d,VS_VARY_BUFS+48,VA+VARY_DATA+0x1000,16,r->vertexCount*16);
   attr(d,FS_VARY,0,MALI_RG32F,RG_SWIZZLE,0);
   buf(d,FS_VARY_BUFS,VA+VARY_DATA,8,r->vertexCount*8);
   if(p->profileID==604||(p->flags&A5MaliProfileDynamicColorVarying)){
    /* The texture-function-3 fragment reads both UV (VAR0) and the
     * interpolated half4 vertex colour (VAR1, promoted to float4). */
    attr(d,FS_VARY+8,1,MALI_RGBA32F,0x688,0);
    buf(d,FS_VARY_BUFS+16,VA+VARY_DATA+0x1000,16,r->vertexCount*16);
   }
  }else{
   attr(d,FS_VARY,0,MALI_RG32F,RG_SWIZZLE,0);
   buf(d,FS_VARY_BUFS,VA+VARY_DATA+0x1000,8,r->vertexCount*8);
  }
 }else if(generic_color){
  attr(d,VS_VARY+16,2,MALI_RGBA32UI,0x688,0);
  buf(d,VS_VARY_BUFS+32,VA+VARY_DATA,16,r->vertexCount*16);
  attr(d,FS_VARY,0,MALI_RGBA32F,0x688,0);
  buf(d,FS_VARY_BUFS,VA+VARY_DATA,16,r->vertexCount*16);
 }else if(!clear){
  for(unsigned i=0;i<5;++i){unsigned off=VARY_DATA+i*0x1000,stride=i?4:8;
   attr(d,VS_VARY+(i+2)*8,i+2,i?MALI_R32UI:MALI_RG32UI,i?R_SWIZZLE:RG_SWIZZLE,0);buf(d,VS_VARY_BUFS+(i+2)*16,VA+off,stride,r->vertexCount*stride);
   attr(d,FS_VARY+i*8,i,i?MALI_R32UI:MALI_RG32F,i?R_SWIZZLE:RG_SWIZZLE,0);buf(d,FS_VARY_BUFS+i*16,VA+off,stride,r->vertexCount*stride);
  }
 }
 *outArena=arena;
 return A5RuntimeOK;
}

/* The index values are validated on the immutable commit-time snapshot. Mali
 * JM consumes the arena copy directly; no external index GPU allocation or
 * unchecked buffer handle enters the native queue. The VS runs vertices
 * 0..maxIndex and the tiler indexes its position/varying arrays directly. */
static int index_data(uint8_t*d,const A5RuntimeDraw*r,unsigned arena,uint64_t*gpuVA){
 *gpuVA=0;
 if(!r->indexCount)return r->indexSize?A5RuntimeUnsupported:A5RuntimeOK;
 if((r->indexSize!=2&&r->indexSize!=4)||r->indexCount<3||
    r->indexCount>A5RuntimeMaxIndices)return A5RuntimeUnsupported;
 const A5RuntimeBuffer*b=&r->indexBuffer;
 unsigned need=r->indexCount*r->indexSize;
 if(!b->cpuBytes||b->offset>b->bytes||need>b->bytes-b->offset||
    (b->offset&(r->indexSize-1)))return A5RuntimeBounds;
 uint32_t max=0;
 for(unsigned i=0;i<r->indexCount;++i){
  uint32_t index=0;
  memcpy(&index,b->cpuBytes+b->offset+i*r->indexSize,r->indexSize);
  if(index>=r->vertexCount)return A5RuntimeBounds;
  if(index>max)max=index;
 }
 if(max+1!=r->vertexCount)return A5RuntimeUnsupported;
 unsigned at=(arena+63)&~63u;
 if(at>ARENA_END||need>ARENA_END-at)return A5RuntimeBounds;
 memcpy(d+at,b->cpuBytes+b->offset,need);
 *gpuVA=r->descriptorGPUVA+at;
 return A5RuntimeOK;
}

static void jobs(uint8_t*d,uint64_t VA,const A5RuntimeDraw*r,uint64_t indexVA){
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=VA+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=VA+VS_RSD;c.attributes=VA+ATTRS;c.attribute_buffers=VA+ATTR_BUFS;c.uniform_buffers=VA+VS_UBOS;c.varyings=VA+VS_VARY;c.varying_buffers=VA+VS_VARY_BUFS;c.thread_storage=VA+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){
  c.draw_mode=r->primitive==A5RuntimeTriangle?MALI_DRAW_MODE_TRIANGLES:MALI_DRAW_MODE_TRIANGLE_STRIP;
  c.index_count=r->indexCount?r->indexCount:r->vertexCount;
  c.index_type=r->indexCount?(r->indexSize==2?MALI_INDEX_TYPE_UINT16:MALI_INDEX_TYPE_UINT32):MALI_INDEX_TYPE_NONE;
  c.indices=indexVA;c.job_task_split=6;
 }
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=VA+POS;c.viewport=VA+VIEWPORT;c.varyings=VA+FS_VARY;c.varying_buffers=VA+FS_VARY_BUFS;c.uniform_buffers=VA+FS_UBOS;c.textures=VA+TEX_TABLE;c.samplers=VA+SAMPLERS;c.state=VA+FS_RSD;c.fbd=VA+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VIEWPORT),VIEWPORT,c){c.scissor_minimum_x=r->scissorX;c.scissor_minimum_y=r->scissorY;c.scissor_maximum_x=r->scissorX+r->scissorWidth-1;c.scissor_maximum_y=r->scissorY+r->scissorHeight-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_min_x=r->scissorX/16;c.bound_min_y=r->scissorY/16;c.bound_max_x=(r->scissorX+r->scissorWidth-1)/16;c.bound_max_y=(r->scissorY+r->scissorHeight-1)/16;c.framebuffer=VA+FB;}
}
static int encode(const A5RuntimeMiscDraw*m,uint8_t*d){
 const A5RuntimeDraw*r=&m->draw;const A5MaliCompiledProfile*p=r->profile;
 if(!p||!(p->profileID==200||p->profileID==202||p->profileID==204||p->profileID==206||p->profileID==207||p->profileID==600||p->profileID==601||p->profileID==602||p->profileID==603||p->profileID==604||p->profileID==605||p->profileID==606||p->profileID==A5MaliDynamicProfileID)||
  p->passCount<1||p->passCount>2||!p->passes||m->passIndex>=p->passCount||p->resourceCount>16||p->pushFieldCount>16)return A5RuntimeUnsupported;
 const A5MaliCompiledPass*pass=p->passes+m->passIndex;
 int home=p->profileID==206,clear=p->profileID==207,generic_color=p->profileID==600||p->profileID==601||p->profileID==602;
 int dynamic=p->profileID==A5MaliDynamicProfileID;
 int generic_textured=p->profileID==603||p->profileID==604||p->profileID==605||p->profileID==606||dynamic;
 if(generic_color&&!generic_color_contract(p))return A5RuntimeUnsupported;
 if(generic_textured&&!(dynamic?dynamic_textured_contract(p):generic_textured_contract(p)))return A5RuntimeUnsupported;
 if(pass->logicalTarget>=2||p->passCount!=1||pass->logicalTarget!=(clear?1u:0u))return A5RuntimeUnsupported;
 if(!span(r->descriptorGPUVA,SIZE)||(r->descriptorGPUVA&4095))return A5RuntimeBounds;
 for(unsigned i=0;i<p->passCount;++i){unsigned target=p->passes[i].logicalTarget;if(target>=2)return A5RuntimeUnsupported;
  const A5RuntimeImage*im=&m->colorAttachments[target];
  if(!valid_image(im)||im->metalPixelFormat!=p->colorFormats[target]||overlap(im->gpuVA,im->bytes,r->descriptorGPUVA,SIZE))return A5RuntimeBounds;
  for(unsigned j=0;j<i;++j){const A5RuntimeImage*other=&m->colorAttachments[p->passes[j].logicalTarget];
   if(overlap(im->gpuVA,im->bytes,other->gpuVA,other->bytes)||im->width!=other->width||im->height!=other->height)return A5RuntimeUnsupported;
  }
 }
 const A5RuntimeImage*out=&m->colorAttachments[pass->logicalTarget];
 unsigned drawCount=r->indexCount?r->indexCount:r->vertexCount;
 if(r->vertexStart||!r->vertexCount||(!r->indexCount&&r->vertexCount<3)||
   r->vertexCount>A5RuntimeMaxVertices||(r->indexCount&&r->indexCount<3)||
   (r->indexCount&&p->profileID!=602&&!generic_textured)||
   (!r->indexCount&&r->indexSize)||r->indexCount>A5RuntimeMaxIndices||
   (r->primitive!=A5RuntimeTriangle&&r->primitive!=A5RuntimeTriangleStrip)||
   (r->primitive==A5RuntimeTriangle&&drawCount%3)||r->blend>A5RuntimeBlendPremultipliedSourceOver||
   (r->blend&&(!(p->flags&A5MaliProfileSourceOverBlend)||
     (out->metalPixelFormat==115&&!(p->flags&A5MaliProfileInlineSourceOver))))||
   ((p->flags&A5MaliProfileInlineSourceOver)&&r->blend!=A5RuntimeBlendPremultipliedSourceOver))return A5RuntimeUnsupported;
 if(generic_color&&r->blend!=A5RuntimeBlendCopy)return A5RuntimeUnsupported;
 if(!isfinite(r->viewportX)||!isfinite(r->viewportY)||!isfinite(r->viewportWidth)||!isfinite(r->viewportHeight)||
   !isfinite(r->viewportNear)||!isfinite(r->viewportFar)||r->viewportWidth<=0||r->viewportHeight<=0||
   r->viewportX<0||r->viewportY<0||r->viewportWidth>4096-r->viewportX||r->viewportHeight>4096-r->viewportY||
   r->viewportNear<0||r->viewportNear>r->viewportFar||r->viewportFar>1)return A5RuntimeUnsupported;
 if(!r->scissorWidth||!r->scissorHeight||r->scissorX>=out->width||r->scissorY>=out->height||
   r->scissorWidth>out->width-r->scissorX||r->scissorHeight>out->height-r->scissorY)return A5RuntimeBounds;
 const A5MaliCompiledShader*vs=&pass->vertex,*fs=&pass->fragment;
 if(!vs->bytes||!fs->bytes||!vs->byteCount||vs->byteCount>0x1000||!fs->byteCount||fs->byteCount>0x1000||
   (vs->byteCount&15)||(fs->byteCount&15)||vs->firstTag!=5||fs->firstTag!=5||vs->tlsBytes||vs->wlsBytes||
   fs->tlsBytes||fs->wlsBytes||!vs->workRegisters||vs->workRegisters>16||!fs->workRegisters||fs->workRegisters>16)return A5RuntimeUnsupported;
 memcpy(d+VS_CODE,vs->bytes,vs->byteCount);memcpy(d+FS_CODE,fs->bytes,fs->byteCount);
 unsigned fmt=out->metalPixelFormat==115?2:out->metalPixelFormat==10?1:out->metalPixelFormat==30?3:0;
 framebuffer(d,r->descriptorGPUVA,fmt,out);renderer(d,r->descriptorGPUVA,home,clear,generic_color,generic_textured,p->profileID==604||!!(p->flags&A5MaliProfileDynamicColorVarying),vs->workRegisters,fs->workRegisters,
  p->flags&A5MaliProfileInlineSourceOver?0:r->blend);
 if(dynamic){
  struct MALI_RENDERER_STATE rs;
  MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+VS_RSD),&rs);
  rs.properties.uniform_buffer_count=dynamic_ubo_count(p,A5MaliStageVertex);
  MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+VS_RSD),&rs);
  MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
  rs.properties.uniform_buffer_count=dynamic_ubo_count(p,A5MaliStageFragment);
  MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
 }
 if(p->flags&A5MaliProfileInlineSourceOver){
  /* Inline blend shader reads the preloaded tilebuffer. Fixed-function RSD
   * remains copy, never applies the equation a second time. */
  struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
  rs.multisample_misc.load_destination=true;MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
 }
 unsigned arena=0;
 int rc=resources(d,m,home,clear,generic_color,generic_textured,&arena);if(rc)return rc;
 uint64_t indexVA=0;rc=index_data(d,r,arena,&indexVA);if(rc)return rc;
 jobs(d,r->descriptorGPUVA,r,indexVA);
 return a5_runtime_preload(d,r->descriptorGPUVA,&m->colorAttachments[pass->logicalTarget]);
}
int A5MaliEncodeRuntimeMiscPass(const A5RuntimeMiscDraw*m,void*out,size_t n){
 if(!out||n!=SIZE)return A5RuntimeInvalid;memset(out,0,n);
 int rc=m?encode(m,out):A5RuntimeInvalid;if(rc)memset(out,0,n);return rc;
}
