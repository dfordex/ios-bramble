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
static void renderer(uint8_t*d,uint64_t VA,int home,int clear,unsigned vs_regs,unsigned fs_regs,unsigned blend){
 pan_pack((struct mali_renderer_state_packed*)(d+VS_RSD),RENDERER_STATE,c){
  c.shader.shader=VA+VS_CODE+5;c.shader.attribute_count=home?3:18;
  c.shader.varying_count=home?4:clear?2:7;
  c.properties.uniform_buffer_count=3;c.properties.work_register_count=vs_regs;
  c.properties.force_early_z=true;c.multisample_misc.sample_mask=0xffff;
  c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
 }
 pan_pack((struct mali_renderer_state_packed*)(d+FS_RSD),RENDERER_STATE,c){
  c.shader.shader=VA+FS_CODE+5;c.shader.texture_count=home?2:0;
  c.shader.sampler_count=home?2:0;c.shader.varying_count=home?1:clear?0:5;
  c.properties.uniform_buffer_count=clear?1:4;c.properties.work_register_count=fs_regs;
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
static unsigned bpp(unsigned f){return f==80?4:f==115?8:f==10?1:f==30?2:0;}
static int valid_image(const A5RuntimeImage*i){unsigned n=bpp(i->metalPixelFormat);
 return n&&span(i->gpuVA,i->bytes)&&!(i->gpuVA&63)&&i->width&&i->width<=2048&&i->height&&i->height<=2048&&
 i->rowBytes>=i->width*n&&!(i->rowBytes&15)&&(uint64_t)i->rowBytes*i->height<=i->bytes;
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
static int resources(uint8_t*d,const A5RuntimeMiscDraw*m,int home,int clear){
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
 for(unsigned st=0;st<2;++st){unsigned o=st?FS_SYS:VS_SYS;
  f32(d,o+512,(float)(r->viewportWidth*.5));f32(d,o+516,(float)(r->viewportHeight*.5));f32(d,o+520,(float)((r->viewportFar-r->viewportNear)*.5));
  f32(d,o+528,(float)(r->viewportX+r->viewportWidth*.5));f32(d,o+532,(float)(r->viewportY+r->viewportHeight*.5));f32(d,o+536,(float)((r->viewportFar+r->viewportNear)*.5));
 }
 if(home){
  uint64_t vertex;unsigned push,available;
  if(!bind_buffer(m,d,&arena,&r->vertexBuffers[1],r->vertexCount*48,&vertex,&push,&available))return A5RuntimeBounds;
  vertex+=push;unsigned low=(unsigned)(vertex&63);vertex&=~UINT64_C(63);
  attr(d,ATTRS,0,MALI_RGBA32F,0x688,low);attr(d,ATTRS+8,0,MALI_RG32F,RG_SWIZZLE,low+16);attr(d,ATTRS+16,0,MALI_RGBA16F,0x688,low+32);
  buf(d,ATTR_BUFS,vertex,48,r->vertexCount*48+low);
  for(unsigned t=0;t<2;++t){const A5RuntimeImage*im=&m->fragmentTextures[t+3];unsigned tex=t?TEX1:TEX0;
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
 if(home){
  attr(d,VS_VARY+16,2,MALI_RGBA32UI,0x688,0);buf(d,VS_VARY_BUFS+32,VA+VARY_DATA,16,r->vertexCount*16);
  attr(d,VS_VARY+24,3,MALI_RG32UI,RG_SWIZZLE,0);buf(d,VS_VARY_BUFS+48,VA+VARY_DATA+0x1000,8,r->vertexCount*8);
  attr(d,FS_VARY,0,MALI_RG32F,RG_SWIZZLE,0);buf(d,FS_VARY_BUFS,VA+VARY_DATA+0x1000,8,r->vertexCount*8);
 }else if(!clear){
  for(unsigned i=0;i<5;++i){unsigned off=VARY_DATA+i*0x1000,stride=i?4:8;
   attr(d,VS_VARY+(i+2)*8,i+2,i?MALI_R32UI:MALI_RG32UI,i?R_SWIZZLE:RG_SWIZZLE,0);buf(d,VS_VARY_BUFS+(i+2)*16,VA+off,stride,r->vertexCount*stride);
   attr(d,FS_VARY+i*8,i,i?MALI_R32UI:MALI_RG32F,i?R_SWIZZLE:RG_SWIZZLE,0);buf(d,FS_VARY_BUFS+i*16,VA+off,stride,r->vertexCount*stride);
  }
 }
 return A5RuntimeOK;
}

static void jobs(uint8_t*d,uint64_t VA,const A5RuntimeDraw*r){
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=VA+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=VA+VS_RSD;c.attributes=VA+ATTRS;c.attribute_buffers=VA+ATTR_BUFS;c.uniform_buffers=VA+VS_UBOS;c.varyings=VA+VS_VARY;c.varying_buffers=VA+VS_VARY_BUFS;c.thread_storage=VA+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){c.draw_mode=r->primitive==A5RuntimeTriangle?MALI_DRAW_MODE_TRIANGLES:MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=r->vertexCount;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=VA+POS;c.viewport=VA+VIEWPORT;c.varyings=VA+FS_VARY;c.varying_buffers=VA+FS_VARY_BUFS;c.uniform_buffers=VA+FS_UBOS;c.textures=VA+TEX_TABLE;c.samplers=VA+SAMPLERS;c.state=VA+FS_RSD;c.fbd=VA+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VIEWPORT),VIEWPORT,c){c.scissor_minimum_x=r->scissorX;c.scissor_minimum_y=r->scissorY;c.scissor_maximum_x=r->scissorX+r->scissorWidth-1;c.scissor_maximum_y=r->scissorY+r->scissorHeight-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_min_x=r->scissorX/16;c.bound_min_y=r->scissorY/16;c.bound_max_x=(r->scissorX+r->scissorWidth-1)/16;c.bound_max_y=(r->scissorY+r->scissorHeight-1)/16;c.framebuffer=VA+FB;}
}
static int encode(const A5RuntimeMiscDraw*m,uint8_t*d){
 const A5RuntimeDraw*r=&m->draw;const A5MaliCompiledProfile*p=r->profile;
 if(!p||!(p->profileID==200||p->profileID==202||p->profileID==204||p->profileID==206||p->profileID==207)||
  p->passCount<1||p->passCount>2||!p->passes||m->passIndex>=p->passCount||p->resourceCount>16||p->pushFieldCount>16)return A5RuntimeUnsupported;
 const A5MaliCompiledPass*pass=p->passes+m->passIndex;
 int home=p->profileID==206,clear=p->profileID==207;
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
 if(r->vertexStart||r->vertexCount<3||r->vertexCount>A5RuntimeMaxVertices||
   (r->primitive!=A5RuntimeTriangle&&r->primitive!=A5RuntimeTriangleStrip)||
   (r->primitive==A5RuntimeTriangle&&r->vertexCount%3)||r->blend>A5RuntimeBlendPremultipliedSourceOver||
   (r->blend&&(!(p->flags&A5MaliProfileSourceOverBlend)||
     (out->metalPixelFormat==115&&!(p->flags&A5MaliProfileInlineSourceOver))))||
   ((p->flags&A5MaliProfileInlineSourceOver)&&r->blend!=A5RuntimeBlendPremultipliedSourceOver))return A5RuntimeUnsupported;
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
 framebuffer(d,r->descriptorGPUVA,fmt,out);renderer(d,r->descriptorGPUVA,home,clear,vs->workRegisters,fs->workRegisters,
  p->flags&A5MaliProfileInlineSourceOver?0:r->blend);
 if(p->flags&A5MaliProfileInlineSourceOver){
  /* Inline blend shader reads the preloaded tilebuffer. Fixed-function RSD
   * remains copy, never applies the equation a second time. */
  struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
  rs.multisample_misc.load_destination=true;MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+FS_RSD),&rs);
 }
 int rc=resources(d,m,home,clear);if(rc)return rc;jobs(d,r->descriptorGPUVA,r);return a5_runtime_preload(d,r->descriptorGPUVA,&m->colorAttachments[pass->logicalTarget]);
}
int A5MaliEncodeRuntimeMiscPass(const A5RuntimeMiscDraw*m,void*out,size_t n){
 if(!out||n!=SIZE)return A5RuntimeInvalid;memset(out,0,n);
 int rc=m?encode(m,out):A5RuntimeInvalid;if(rc)memset(out,0,n);return rc;
}
