/* SPDX-License-Identifier: MIT
 * Actual path/stroke jobs using released Mesa26.2.4 v4 descriptors. Inline
 * blend variants are compiled from the original validated SPIR-V with Mesa's
 * nir_lower_blend and pan_nir_lower_framebuffer, not replacement fragment code.
 */
#define PAN_ARCH 4
#include "runtime_path_encode.h"
#include <math.h>
#include <string.h>
#include "genxml/v4_pack.h"
#include "runtime_preload.h"
enum {N=0x40000,FB=0x300,VRS=0x500,FRS=0x540,VD=0x600,FD=0x640,
 ATTR=0x700,ATTRBUF=0x800,VV=0x900,FV=0xa00,VBUFS=0xb00,VP=0xc00,
 VS_SYS=0x1000,FS_SYS=0x1400,POLY=0x3000,VS=0x4000,FS=0x6000,
 HEAP=0x10000,HEAP_END=0x20000,ARENA=0x20000,ARENA_END=0x30000,
 POS=0x30000,PSIZ=0x31000,GENERAL=0x32000};
static void u32(uint8_t*d,unsigned o,uint32_t v){memcpy(d+o,&v,4);}
static void u64(uint8_t*d,unsigned o,uint64_t v){memcpy(d+o,&v,8);}
static void f32(uint8_t*d,unsigned o,float v){memcpy(d+o,&v,4);}
static int span(uint64_t a,uint64_t n){return a&&n&&a<(UINT64_C(1)<<40)&&n<=(UINT64_C(1)<<40)-a;}
static int overlap(uint64_t a,uint64_t n,uint64_t b,uint64_t m){return a<b+m&&b<a+n;}
static unsigned swz(unsigned n){return n==1?(MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)):n==2?(MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)):0x688;}
static void at(uint8_t*d,unsigned o,unsigned b,unsigned fmt,unsigned n,unsigned offset){pan_pack((struct mali_attribute_packed*)(d+o),ATTRIBUTE,c){c.buffer_index=b;c.offset_enable=true;c.format=(fmt<<12)|swz(n);c.offset=offset;}}
static void ab(uint8_t*d,uint64_t va,unsigned slot,unsigned off,unsigned stride,unsigned size){pan_pack((struct mali_attribute_buffer_packed*)(d+VBUFS+slot*16),ATTRIBUTE_BUFFER,c){c.pointer=va+off;c.stride=stride;c.size=size;}}
static void ub(uint8_t*d,unsigned table,unsigned slot,uint64_t address,unsigned bytes){pan_pack((struct mali_uniform_buffer_packed*)(d+table+slot*8),UNIFORM_BUFFER,c){c.pointer=address;c.entries=(bytes+15)/16;}}
static int image(const A5RuntimeImage*i,unsigned format){unsigned bpp=format==115?8:4;return i->metalPixelFormat==format&&span(i->gpuVA,i->bytes)&&!(i->gpuVA&63)&&i->width&&i->width<=2048&&i->height&&i->height<=2048&&!(i->rowBytes&15)&&i->rowBytes>=i->width*bpp&&(uint64_t)i->rowBytes*i->height<=i->bytes;}
static int binding(const A5RuntimePathDraw*m,uint8_t*d,unsigned*arena,const A5RuntimeBuffer*b,unsigned need,uint64_t*addr,unsigned*push,unsigned*available){
 if(!need||b->offset>b->bytes||need>b->bytes-b->offset)return 0;
 if(b->cpuBytes){unsigned at=(*arena+63)&~63u;if(at>ARENA_END||need>ARENA_END-at)return 0;memcpy(d+at,b->cpuBytes+b->offset,need);*arena=(at+need+63)&~63u;*addr=m->draw.descriptorGPUVA+at;*push=0;*available=need;return 1;}
 if(!span(b->gpuVA,b->bytes)||(b->gpuVA&15)||overlap(b->gpuVA,b->bytes,m->draw.descriptorGPUVA,N))return 0;
 const A5MaliCompiledProfile*p=m->draw.profile;
 for(unsigned i=0;i<p->passCount;++i){const A5RuntimeImage*im=&m->colorAttachments[p->passes[i].logicalTarget];if(overlap(b->gpuVA,b->bytes,im->gpuVA,im->bytes))return 0;}
 unsigned folded=b->offset&~15u;*addr=b->gpuVA+folded;*push=b->offset&15u;*available=b->bytes-folded;return 1;
}
static int encode(const A5RuntimePathDraw*m,uint8_t*d){
 const A5RuntimeDraw*r=&m->draw;const A5MaliCompiledProfile*p=r->profile;
 if(!p||(p->profileID!=300&&p->profileID!=301&&p->profileID!=302)||!p->passes||m->passIndex>=p->passCount||p->resourceCount>16||p->pushFieldCount>16)return A5RuntimeUnsupported;
 int stroke=p->profileID==302,cubic=p->profileID==301;
 if(p->passCount!=1u)return A5RuntimeUnsupported;
 const A5MaliCompiledPass*pass=p->passes+m->passIndex;unsigned target=stroke?0u:2;
 if(pass->logicalTarget!=target||pass->passID!=(stroke?302u:p->profileID))return A5RuntimeUnsupported;
 if(!span(r->descriptorGPUVA,N)||(r->descriptorGPUVA&4095))return A5RuntimeBounds;
 for(unsigned i=0;i<p->passCount;++i){unsigned t=p->passes[i].logicalTarget;if(t>=8)return A5RuntimeUnsupported;const A5RuntimeImage*im=&m->colorAttachments[t];if(!image(im,stroke?115:55)||p->colorFormats[t]!=im->metalPixelFormat||overlap(im->gpuVA,im->bytes,r->descriptorGPUVA,N))return A5RuntimeBounds;
  for(unsigned j=0;j<i;++j){const A5RuntimeImage*other=&m->colorAttachments[p->passes[j].logicalTarget];if(overlap(im->gpuVA,im->bytes,other->gpuVA,other->bytes)||im->width!=other->width||im->height!=other->height)return A5RuntimeUnsupported;}}
 const A5RuntimeImage*out=&m->colorAttachments[target];
 /* VertexID/InstanceID indirection is the exact device-tested one-quad
  * contract. Increasing it requires matching divisor/invocation encoding. */
 if(r->vertexStart||r->vertexCount!=4||r->primitive!=A5RuntimeTriangleStrip||r->blend!=(stroke?1u:2u))return A5RuntimeUnsupported;
 if(!isfinite(r->viewportX)||!isfinite(r->viewportY)||!isfinite(r->viewportWidth)||!isfinite(r->viewportHeight)||!isfinite(r->viewportNear)||!isfinite(r->viewportFar)||r->viewportX<0||r->viewportY<0||r->viewportWidth<=0||r->viewportHeight<=0||r->viewportWidth>4096-r->viewportX||r->viewportHeight>4096-r->viewportY||r->viewportNear<0||r->viewportNear>r->viewportFar||r->viewportFar>1)return A5RuntimeUnsupported;
 if(!r->scissorWidth||!r->scissorHeight||r->scissorX>=out->width||r->scissorY>=out->height||r->scissorWidth>out->width-r->scissorX||r->scissorHeight>out->height-r->scissorY)return A5RuntimeBounds;
 const A5MaliCompiledShader*vs=&pass->vertex,*fs=&pass->fragment;
 if(!vs->bytes||!fs->bytes||!vs->byteCount||vs->byteCount>FS-VS||!fs->byteCount||fs->byteCount>0x2000||(vs->byteCount&15)||(fs->byteCount&15)||vs->firstTag!=5||fs->firstTag!=5||vs->tlsBytes||vs->wlsBytes||fs->tlsBytes||fs->wlsBytes||!vs->workRegisters||vs->workRegisters>16||!fs->workRegisters||fs->workRegisters>16)return A5RuntimeUnsupported;
 uint64_t va=r->descriptorGPUVA;memcpy(d+VS,vs->bytes,vs->byteCount);memcpy(d+FS,fs->bytes,fs->byteCount);
 for(unsigned i=0;i<4;++i){ub(d,VD,i,va+VS_SYS,576);ub(d,FD,i,va+FS_SYS,576);}
 unsigned arena=ARENA,push[31]={0},seen[31]={0};
 for(unsigned i=0;i<p->resourceCount;++i){const A5MaliCompiledResource*c=p->resources+i;
  if(c->stage!=A5MaliStageVertex||c->kind!=A5MaliResourceBuffer||c->metalIndex>=31||c->windowOffset||(c->flags&A5MaliResourceWrite))return A5RuntimeUnsupported;
  const A5RuntimeBuffer*b=&r->vertexBuffers[c->metalIndex];unsigned storage=!!(c->flags&A5MaliResourceStorage),need=storage?(b->offset<=b->bytes?b->bytes-b->offset:0):c->uniformBytes;uint64_t a;unsigned off,available;
  if(!binding(m,d,&arena,b,need,&a,&off,&available))return A5RuntimeBounds;
  if(storage){if(c->sysvalOffset!=96)return A5RuntimeUnsupported;u64(d,VS_SYS+96,a);u32(d,VS_SYS+104,available);}
  else{if(!c->nativeIndex||c->nativeIndex>=4||!need||need>64)return A5RuntimeUnsupported;ub(d,VD,c->nativeIndex,a,off+need);}
  seen[c->metalIndex]=1;push[c->metalIndex]=off;
 }
 for(unsigned i=0;i<p->pushFieldCount;++i){const A5MaliCompiledPushField*f=p->pushFields+i;
  if(f->bytes!=4||(f->offset&3)||f->offset>76)return A5RuntimeUnsupported;
  if(f->kind==A5MaliPushBindOffset){if(f->stage!=A5MaliStageVertex||f->metalIndex>=31||!seen[f->metalIndex])return A5RuntimeUnsupported;u32(d,VS_SYS+f->offset,push[f->metalIndex]);}
  else if(f->kind==A5MaliPushColorWriteRule&&stroke&&f->stage==A5MaliStageFragment)u32(d,FS_SYS+f->offset,f->value);
  else return A5RuntimeUnsupported;
 }
 f32(d,VS_SYS+512,r->viewportWidth*.5);f32(d,VS_SYS+516,r->viewportHeight*.5);f32(d,VS_SYS+520,(r->viewportFar-r->viewportNear)*.5);f32(d,VS_SYS+528,r->viewportX+r->viewportWidth*.5);f32(d,VS_SYS+532,r->viewportY+r->viewportHeight*.5);f32(d,VS_SYS+536,(r->viewportFar+r->viewportNear)*.5);
 pan_section_pack(d+FB,FRAMEBUFFER,LOCAL_STORAGE,c){c.wls_instances=MALI_LOCAL_STORAGE_NO_WORKGROUP_MEM;}
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){c.bound_max_x=out->width-1;c.bound_max_y=out->height-1;c.internal_format=MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE;c.color_writeback_format=stroke?MALI_COLOR_FORMAT_2_32B_CHANNELS:MALI_COLOR_FORMAT_1_32B_CHANNEL;c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;c.color_write_enable=true;c.color_writeback.base=out->gpuVA;c.color_writeback.row_stride=out->rowBytes;c.swizzle=0x688;c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;}
 unsigned tiles=((out->width+1023)/1024)*((out->height+1023)/1024),header=0x200+(tiles*8/0x200)*0x200,full=0x200+tiles*0x200;if(POLY+full>VS)return A5RuntimeBounds;
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){c.polygon_list=va+POLY;c.polygon_list_body=va+POLY+header;c.polygon_list_size=full;c.hierarchy_mask=0x1c7;c.heap_start=va+HEAP;c.heap_end=va+HEAP_END;}u32(d,POLY+header,0xa0000000);
 unsigned nvar=stroke?5:cubic?4:3;
 pan_pack((struct mali_renderer_state_packed*)(d+VRS),RENDERER_STATE,c){c.shader.shader=va+VS+5;c.shader.attribute_count=18;c.shader.varying_count=nvar+2;c.properties.uniform_buffer_count=4;c.properties.work_register_count=vs->workRegisters;c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;}
 pan_pack((struct mali_renderer_state_packed*)(d+FRS),RENDERER_STATE,c){c.shader.shader=va+FS+5;c.shader.varying_count=nvar+(stroke?0:1);c.properties.uniform_buffer_count=1;c.properties.work_register_count=fs->workRegisters;c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;c.multisample_misc.load_destination=true;c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.write_enable=true;c.stencil_mask_misc.dither_disable=true;c.blend_equation.color_mask=stroke?15:1;c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.rgb.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.rgb.c=MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.alpha.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.alpha.c=MALI_BLEND_OPERAND_C_ZERO;}
 pan_pack((struct mali_attribute_vertex_id_packed*)(d+ATTRBUF),ATTRIBUTE_VERTEX_ID,c){c.divisor_r=31;c.divisor_p=4;}pan_pack((struct mali_attribute_instance_id_packed*)(d+ATTRBUF+32),ATTRIBUTE_INSTANCE_ID,c){c.divisor_r=31;c.divisor_e=1;c.divisor_p=0x7fffffff;}
 at(d,ATTR+16*8,0,MALI_R32UI,1,0);at(d,ATTR+17*8,2,MALI_R32UI,1,0);at(d,VV,0,MALI_SNAP_4,4,0);at(d,VV+8,1,MALI_R16F,1,0);ab(d,va,0,POS,16,64);ab(d,va,1,PSIZ,2,8);ab(d,va,2,GENERAL,32,128);
 unsigned comps[5]={1,1,1,1,1},offs[5]={0,4,8,12,16};if(cubic){comps[0]=comps[1]=2;offs[0]=0;offs[1]=8;offs[2]=16;offs[3]=20;}if(stroke){comps[0]=4;offs[0]=0;offs[1]=16;offs[2]=20;offs[3]=24;offs[4]=28;}
 for(unsigned i=0;i<nvar;++i){unsigned ui=comps[i]==4?MALI_RGBA32UI:comps[i]==2?MALI_RG32UI:MALI_R32UI;at(d,VV+(i+2)*8,2,ui,comps[i],offs[i]);at(d,FV+i*8,2,(stroke&&i)?MALI_R32F:ui,comps[i],offs[i]);}
 if(!stroke){at(d,FV+nvar*8,3,MALI_RGBA32F,4,0);u32(d,VBUFS+3*16,MALI_ATTRIBUTE_SPECIAL_FRAG_COORD);}
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=va+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=va+VRS;c.attributes=va+ATTR;c.attribute_buffers=va+ATTRBUF;c.uniform_buffers=va+VD;c.varyings=va+VV;c.varying_buffers=va+VBUFS;c.thread_storage=va+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){c.draw_mode=MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=4;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=va+POS;c.viewport=va+VP;c.varyings=va+FV;c.varying_buffers=va+VBUFS;c.uniform_buffers=va+FD;c.state=va+FRS;c.fbd=va+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VP),VIEWPORT,c){c.scissor_minimum_x=r->scissorX;c.scissor_minimum_y=r->scissorY;c.scissor_maximum_x=r->scissorX+r->scissorWidth-1;c.scissor_maximum_y=r->scissorY+r->scissorHeight-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_min_x=r->scissorX/16;c.bound_min_y=r->scissorY/16;c.bound_max_x=(r->scissorX+r->scissorWidth-1)/16;c.bound_max_y=(r->scissorY+r->scissorHeight-1)/16;c.framebuffer=va+FB;}
 return a5_runtime_preload(d,va,out);
}
int A5MaliEncodeRuntimePathPass(const A5RuntimePathDraw*m,void*out,size_t n){if(!out||n!=N)return A5RuntimeInvalid;memset(out,0,n);int rc=m?encode(m,out):A5RuntimeInvalid;if(rc)memset(out,0,n);return rc;}
