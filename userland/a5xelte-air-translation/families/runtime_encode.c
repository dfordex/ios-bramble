/* SPDX-License-Identifier: MIT
 * Runtime emitter using released Mesa26.2.4 v4 packing. No fixture includes.
 * pan_blend.c supplies source-over; pan_tiler.c supplies flat-list sizing.
 */
#define PAN_ARCH 4
#include "runtime_encode.h"
#include <string.h>
#include <math.h>
#include "genxml/v4_pack.h"
#include "runtime_preload.h"

enum { FB=0x300,VRS=0x500,FRS=0x540,TEX=0x600,TT=0x660,SAMP=0x680,
 VUBO=0x700,FUBO=0x740,ATTR=0x800,ABUF=0x840,VV=0x880,VB=0x8c0,
 FV=0x940,FVB=0x980,VP=0x9c0,VPUSH=0x1000,FPUSH=0x1400,
 VCODE=0x2000,FCODE=0x4000,ARENA=0xc000,ARENA_END=0x10000,
 POLY=0x10000,POLY_END=0x18000,HEAP=0x18000,HEAP_END=0x28000,
 TLS=0x28000,TLS_END=0x38000,POS=0x38000,PSIZ=0x39000,UV=0x39400,
 RG=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9),
 R=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9) };
_Static_assert(MALI_ATTRIBUTE_BUFFER_LENGTH==16,"released v4 table stride");
static void put32(uint8_t*d,unsigned o,uint32_t x){memcpy(d+o,&x,4);}
static void put64(uint8_t*d,unsigned o,uint64_t x){memcpy(d+o,&x,8);}
static int span(uint64_t a,uint64_t n){return a&&n&&a<(UINT64_C(1)<<40)&&n<=(UINT64_C(1)<<40)-a;}
static int overlaps(uint64_t a,uint64_t n,uint64_t b,uint64_t m){return a<b+m&&b<a+n;}
static unsigned align16(unsigned n){return(n+15)&~15u;}
static int image(const A5RuntimeImage*i,unsigned bytes){
 return span(i->gpuVA,i->bytes)&&!(i->gpuVA&63)&&i->width&&i->width<=2048&&
 i->height&&i->height<=2048&&i->rowBytes>=i->width*bytes&&!(i->rowBytes&15)&&
 (uint64_t)i->rowBytes*i->height<=i->bytes;
}
static void ub(uint8_t*d,unsigned t,unsigned i,uint64_t a,unsigned n){
 pan_pack((struct mali_uniform_buffer_packed*)(d+t+i*8),UNIFORM_BUFFER,c){c.pointer=a;c.entries=(n+15)/16;}
}
static void attr(uint8_t*d,unsigned p,unsigned b,unsigned f,unsigned sw,unsigned o){
 pan_pack((struct mali_attribute_packed*)(d+p),ATTRIBUTE,c){c.buffer_index=b;c.offset_enable=true;c.format=(f<<12)|sw;c.offset=o;}
}
static void ab(uint8_t*d,unsigned p,uint64_t a,unsigned stride,unsigned n){
 pan_pack((struct mali_attribute_buffer_packed*)(d+p),ATTRIBUTE_BUFFER,c){c.pointer=a;c.stride=stride;c.size=n;}
}
/* CPU bytes are exact immutable commit snapshots. Rebase the copied window;
 * no user uniform or vertex value is synthesized. */
static int binding(const A5RuntimeDraw*r,uint8_t*d,unsigned*arena,
 const A5RuntimeBuffer*b,unsigned required,uint64_t*address,unsigned*push){
 if(!required||b->offset>b->bytes||required>b->bytes-b->offset)return 0;
 if(b->cpuBytes){
  unsigned at=(*arena+63)&~63u;if(at>ARENA_END||required>ARENA_END-at)return 0;
  memcpy(d+at,b->cpuBytes+b->offset,required);*arena=align16(at+required);
  *address=r->descriptorGPUVA+at;*push=0;return 1;
 }
 if(!span(b->gpuVA,b->bytes)||(b->gpuVA&15)||
    overlaps(b->gpuVA,b->bytes,r->descriptorGPUVA,A5RuntimeJobBytes)||
    overlaps(b->gpuVA,b->bytes,r->destination.gpuVA,r->destination.bytes))return 0;
 *address=b->gpuVA+(b->offset&~15u);*push=b->offset&15u;return 1;
}
static int encode(const A5RuntimeDraw*r,uint8_t*d){
 const A5MaliCompiledProfile*p=r->profile;
 if(!p||!(p->profileID==99||(p->profileID>=100&&p->profileID<=108))||
    p->passCount!=1||!p->passes||p->passes[0].logicalTarget||p->resourceCount>16||p->pushFieldCount>16)
  return A5RuntimeUnsupported;
 const A5MaliCompiledPass*pass=p->passes;
 const A5MaliCompiledShader*vs=&pass->vertex,*fs=&pass->fragment;
 if(!vs->bytes||!fs->bytes||!vs->byteCount||vs->byteCount>FCODE-VCODE||
    !fs->byteCount||fs->byteCount>ARENA-FCODE||(vs->byteCount&15)||(fs->byteCount&15)||
    vs->firstTag!=5||fs->firstTag!=5||!vs->workRegisters||vs->workRegisters>16||
    !fs->workRegisters||fs->workRegisters>16||vs->tlsBytes||vs->wlsBytes||fs->wlsBytes||
    (fs->tlsBytes!=0&&fs->tlsBytes!=32&&fs->tlsBytes!=64))return A5RuntimeUnsupported;
 if(!span(r->descriptorGPUVA,A5RuntimeJobBytes)||(r->descriptorGPUVA&4095)||
    !image(&r->source,4)||r->source.metalPixelFormat!=80||
    !(r->destination.metalPixelFormat==80||r->destination.metalPixelFormat==115)||
    !image(&r->destination,r->destination.metalPixelFormat==115?8:4)||
    p->colorFormats[0]!=r->destination.metalPixelFormat||
    overlaps(r->source.gpuVA,r->source.bytes,r->destination.gpuVA,r->destination.bytes)||
    overlaps(r->source.gpuVA,r->source.bytes,r->descriptorGPUVA,A5RuntimeJobBytes)||
    overlaps(r->destination.gpuVA,r->destination.bytes,r->descriptorGPUVA,A5RuntimeJobBytes))return A5RuntimeBounds;
 /* Disabled secondary attachments are validated by pipeline/API contracts;
  * this native pass writes only its authenticated logicalTarget0. */
 if((p->flags&A5MaliProfileFixedViewport) &&
    (r->viewportX!=0||r->viewportY!=0||r->viewportWidth!=1080||r->viewportHeight!=1920||
     r->viewportNear!=0||r->viewportFar!=1))return A5RuntimeUnsupported;
 if(!isfinite(r->viewportX)||!isfinite(r->viewportY)||!isfinite(r->viewportWidth)||!isfinite(r->viewportHeight)||
    !isfinite(r->viewportNear)||!isfinite(r->viewportFar)||r->viewportX<0||r->viewportY<0||
    r->viewportWidth<=0||r->viewportHeight<=0||r->viewportWidth>4096-r->viewportX||
    r->viewportHeight>4096-r->viewportY||r->viewportNear<0||r->viewportFar>1||
    r->viewportNear>r->viewportFar||r->vertexStart||r->vertexCount<3||
    r->vertexCount>A5RuntimeMaxVertices||
    (r->primitive!=A5RuntimeTriangle&&r->primitive!=A5RuntimeTriangleStrip)||
    (r->primitive==A5RuntimeTriangle&&r->vertexCount%3)||r->blend>A5RuntimeBlendPremultipliedSourceOver||
    (r->blend&&(!(p->flags&A5MaliProfileSourceOverBlend)||r->destination.metalPixelFormat==115)))return A5RuntimeUnsupported;
 if(!r->scissorWidth||!r->scissorHeight||r->scissorX>=r->destination.width||
    r->scissorY>=r->destination.height||r->scissorWidth>r->destination.width-r->scissorX||
    r->scissorHeight>r->destination.height-r->scissorY)return A5RuntimeBounds;
 unsigned arena=ARENA;uint64_t va=r->descriptorGPUVA;
 /* UBO0 is stage-local: released Panfrost viewport sysval values, not an
  * altered caller MVP. 576 bytes keep both vec3 records padded/aligned. */
 float scale[3]={(float)(r->viewportWidth*.5),(float)(r->viewportHeight*.5),
                 (float)((r->viewportFar-r->viewportNear)*.5)};
 float offset[3]={(float)(r->viewportX+r->viewportWidth*.5),
                  (float)(r->viewportY+r->viewportHeight*.5),
                  (float)((r->viewportFar+r->viewportNear)*.5)};
 memcpy(d+VPUSH+512,scale,sizeof(scale));memcpy(d+VPUSH+528,offset,sizeof(offset));
 uint32_t pushes[2][31]={{0}};unsigned seen[2][31]={{0}};
 /* Holes reference valid zeroed descriptor-local sysvals, not arbitrary VA. */
 for(unsigned i=0;i<8;++i){ub(d,VUBO,i,va+VPUSH,576);ub(d,FUBO,i,va+FPUSH,80);}
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*c=p->resources+i;
  if(c->stage!=A5MaliStageVertex&&c->stage!=A5MaliStageFragment)return A5RuntimeUnsupported;
  unsigned st=c->stage==A5MaliStageFragment;
  if(c->kind!=A5MaliResourceBuffer)continue;
  if(c->metalIndex>=31||c->nativeIndex>=8||!c->nativeIndex||c->windowOffset||
     c->flags&A5MaliResourceStorage||!c->uniformBytes||c->uniformBytes>4096)return A5RuntimeUnsupported;
  const A5RuntimeBuffer*b=st?&r->fragmentBuffers[c->metalIndex]:&r->vertexBuffers[c->metalIndex];
  uint64_t addr;unsigned push;
  if(!binding(r,d,&arena,b,c->uniformBytes,&addr,&push))return A5RuntimeBounds;
  ub(d,st?FUBO:VUBO,c->nativeIndex,addr,push+c->uniformBytes);
  pushes[st][c->metalIndex]=push;seen[st][c->metalIndex]=1;
 }
 for(unsigned i=0;i<p->pushFieldCount;++i){const A5MaliCompiledPushField*f=p->pushFields+i;
  if((f->stage!=A5MaliStageVertex&&f->stage!=A5MaliStageFragment)||f->bytes!=4||
     f->offset>76||(f->offset&3))return A5RuntimeUnsupported;
  unsigned st=f->stage==A5MaliStageFragment,value=f->value;
  if(f->kind==A5MaliPushBindOffset){
   if(f->metalIndex>=31||!seen[st][f->metalIndex])return A5RuntimeUnsupported;
   value=pushes[st][f->metalIndex];
  }else if(f->kind!=A5MaliPushColorWriteRule)return A5RuntimeUnsupported;
  put32(d,(st?FPUSH:VPUSH)+f->offset,value);
 }
 uint64_t vertices;unsigned vertexOffset;
 if(!binding(r,d,&arena,&r->vertexBuffers[1],r->vertexCount*48,&vertices,&vertexOffset))return A5RuntimeBounds;
 uint64_t vertexAddress=vertices+vertexOffset;
 unsigned vertexLow=(unsigned)(vertexAddress&63);
 uint64_t vertexBase=vertexAddress&~UINT64_C(63);
 memcpy(d+VCODE,vs->bytes,vs->byteCount);memcpy(d+FCODE,fs->bytes,fs->byteCount);
 /* Source is genuine BGRA memory: format swizzle decodes its byte order. */
 pan_pack((struct mali_texture_packed*)(d+TEX),TEXTURE,c){
  c.width=r->source.width;c.height=r->source.height;c.array_size=1;c.levels=1;
  c.format=(MALI_RGBA8_UNORM<<12)|0x60a;c.dimension=MALI_TEXTURE_DIMENSION_2D;
  c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;
 }
 pan_pack((struct mali_surface_with_stride_packed*)(d+TEX+32),SURFACE_WITH_STRIDE,c){
  c.pointer=r->source.gpuVA;c.row_stride=r->source.rowBytes;c.surface_stride=r->source.rowBytes*r->source.height;
 }
 put64(d,TT,va+TEX);
 pan_pack((struct mali_sampler_packed*)(d+SAMP),SAMPLER,c){
  c.normalized_coordinates=true;c.seamless_cube_map=false;c.minify_nearest=true;c.magnify_nearest=true;
 }
 put32(d,FPUSH,1);put32(d,FPUSH+4,r->source.width);put32(d,FPUSH+8,r->source.height);
 pan_section_pack(d+FB,FRAMEBUFFER,LOCAL_STORAGE,c){
  c.tls_size=fs->tlsBytes==64?2:fs->tlsBytes==32?1:0;
  c.tls_base_pointer=fs->tlsBytes?va+TLS:0;c.wls_instances=MALI_LOCAL_STORAGE_NO_WORKGROUP_MEM;
 }
 unsigned raw=r->destination.metalPixelFormat==115;
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){
  c.internal_format=raw?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
  c.color_writeback_format=raw?MALI_COLOR_FORMAT_2_32B_CHANNELS:MALI_COLOR_FORMAT_R8G8B8A8;
  c.swizzle=raw?0x688:0x60a;c.color_write_enable=true;
  c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
  c.bound_max_x=r->destination.width-1;c.bound_max_y=r->destination.height-1;
  c.color_writeback.base=r->destination.gpuVA;c.color_writeback.row_stride=r->destination.rowBytes;

 }
 /* The already device-verified T720 flat tile encoding0x1c7 selects1024x1024
  * bins. Unlike a hardcoded32x32 fixture, size both lists from actual FB dimensions
  * using released pan_tiler.c pan_flat_size (no hierarchy on T720). */
 unsigned tiles=((r->destination.width+1023)/1024)*((r->destination.height+1023)/1024);
 unsigned header=0x200+((tiles*8)/0x200)*0x200,full=0x200+tiles*0x200;
 if(header+full>POLY_END-POLY)return A5RuntimeBounds;
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){
  c.polygon_list=va+POLY;c.polygon_list_body=va+POLY+header;c.polygon_list_size=full;
  c.hierarchy_mask=0x1c7;c.heap_start=va+HEAP;c.heap_end=va+HEAP_END;
 }
 put32(d,POLY+header,0xa0000000);
 pan_pack((struct mali_renderer_state_packed*)(d+VRS),RENDERER_STATE,c){
  c.shader.shader=va+VCODE+vs->firstTag;c.shader.attribute_count=2;c.shader.varying_count=3;
  c.properties.uniform_buffer_count=3;c.properties.work_register_count=vs->workRegisters;c.properties.force_early_z=true;
  c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
 }
 pan_pack((struct mali_renderer_state_packed*)(d+FRS),RENDERER_STATE,c){
  c.shader.shader=va+FCODE+fs->firstTag;c.shader.texture_count=1;c.shader.sampler_count=1;c.shader.varying_count=1;
  c.properties.uniform_buffer_count=5;c.properties.work_register_count=fs->workRegisters;c.properties.force_early_z=true;
  c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;c.multisample_misc.load_destination=!!r->blend;
  c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.write_enable=true;c.stencil_mask_misc.dither_disable=true;
  c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;
  c.blend_equation.rgb.b=r->blend?MALI_BLEND_OPERAND_B_DEST:MALI_BLEND_OPERAND_B_SRC;
  c.blend_equation.alpha.b=c.blend_equation.rgb.b;
  c.blend_equation.rgb.c=r->blend?MALI_BLEND_OPERAND_C_SRC_ALPHA:MALI_BLEND_OPERAND_C_ZERO;
  c.blend_equation.alpha.c=c.blend_equation.rgb.c;c.blend_equation.rgb.invert_c=!!r->blend;
  c.blend_equation.alpha.invert_c=!!r->blend;c.blend_equation.color_mask=15;
 }
 attr(d,ATTR,0,MALI_RGBA32F,0x688,vertexLow);attr(d,ATTR+8,0,MALI_RG32F,RG,vertexLow+16);
 ab(d,ABUF,vertexBase,48,r->vertexCount*48+vertexLow);
 attr(d,VV,0,MALI_SNAP_4,0x688,0);attr(d,VV+8,1,MALI_R16F,R,0);attr(d,VV+16,2,MALI_RG32UI,RG,0);
 ab(d,VB,va+POS,16,r->vertexCount*16);ab(d,VB+16,va+PSIZ,2,r->vertexCount*2);ab(d,VB+32,va+UV,8,r->vertexCount*8);
 attr(d,FV,0,MALI_RG32F,RG,0);ab(d,FVB,va+UV,8,r->vertexCount*8);
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=va+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=va+VRS;c.attributes=va+ATTR;c.attribute_buffers=va+ABUF;c.uniform_buffers=va+VUBO;c.varyings=va+VV;c.varying_buffers=va+VB;c.thread_storage=va+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=r->vertexCount-1;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){c.draw_mode=r->primitive==A5RuntimeTriangle?MALI_DRAW_MODE_TRIANGLES:MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=r->vertexCount;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=va+POS;c.viewport=va+VP;c.varyings=va+FV;c.varying_buffers=va+FVB;c.uniform_buffers=va+FUBO;c.textures=va+TT;c.samplers=va+SAMP;c.state=va+FRS;c.fbd=va+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VP),VIEWPORT,c){c.scissor_minimum_x=r->scissorX;c.scissor_minimum_y=r->scissorY;c.scissor_maximum_x=r->scissorX+r->scissorWidth-1;c.scissor_maximum_y=r->scissorY+r->scissorHeight-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_min_x=r->scissorX/16;c.bound_min_y=r->scissorY/16;c.bound_max_x=(r->scissorX+r->scissorWidth-1)/16;c.bound_max_y=(r->scissorY+r->scissorHeight-1)/16;c.framebuffer=va+FB;}
 return a5_runtime_preload(d,va,&r->destination);
}
int A5MaliEncodeRuntimeDraw(const A5RuntimeDraw*r,void*out,size_t n){
 if(!out||n!=A5RuntimeJobBytes)return A5RuntimeInvalid;
 memset(out,0,n);int rc=r?encode(r,out):A5RuntimeInvalid;
 if(rc)memset(out,0,n);return rc;
}
