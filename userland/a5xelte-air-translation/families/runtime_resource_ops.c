/* SPDX-License-Identifier: MIT
 * Actual GPU resource jobs, released Mesa26.2.4 v4 descriptors and RAW packing.
 * No Apple shaders, fixture data, expected pixels, or CPU rendering.
 */
#define PAN_ARCH 4
#include "runtime_resource_ops.h"
#include "genxml/v4_pack.h"
#include <string.h>
typedef struct{unsigned kind,bits,dim;const uint8_t*code;unsigned bytes,tag,regs,ubos,attributes,varyings;}A5ResourceShader;
#include "A5MaliResourceOpsData.inc"
enum{FB=0x300,VRS=0x500,FRS=0x540,TEX=0x600,TT=0x640,SAMP=0x660,
 VUBO=0x700,FUBO=0x740,ATTR=0x800,ABUF=0x840,VV=0x880,VB=0x8c0,
 FV=0x940,FVB=0x980,VP=0x9c0,VERTICES=0x1000,VSYS=0x1100,FSYS=0x1200,
 PJ=0x1800,PRS=0x1900,PPOS=0x1940,PTEX=0x1980,PTT=0x19c0,PSAMP=0x19e0,
 PVP=0x1a00,PV=0x1a20,PVB=0x1a40,PCODE=0x1c00,
 VCODE=0x2000,FCODE=0x3000,POLY=0x10000,HEAP=0x18000,HEAP_END=0x28000,
 POS=0x38000,PSIZ=0x39000,UV=0x39400,
 RG=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9),
 R=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)};
#define ALIGNED(offset,kind) _Static_assert((offset)%MALI_##kind##_ALIGN==0,#offset " native alignment")
ALIGNED(VRS,RENDERER_STATE);ALIGNED(FRS,RENDERER_STATE);ALIGNED(TEX,TEXTURE);ALIGNED(SAMP,SAMPLER);
ALIGNED(PJ,TILER_JOB);ALIGNED(PRS,RENDERER_STATE);ALIGNED(PTEX,TEXTURE);ALIGNED(PSAMP,SAMPLER);
ALIGNED(PVP,VIEWPORT);ALIGNED(PV,ATTRIBUTE);ALIGNED(PVB,ATTRIBUTE_BUFFER);
_Static_assert(MALI_ATTRIBUTE_BUFFER_LENGTH==16,"released v4 table stride");
_Static_assert(PJ+MALI_TILER_JOB_LENGTH<=PRS,"preload job overlap");
_Static_assert(PRS+MALI_RENDERER_STATE_LENGTH<=PPOS,"preload state overlap");
_Static_assert(PPOS+64<=PTEX,"preload positions overlap");
_Static_assert(PTEX+MALI_TEXTURE_LENGTH+MALI_SURFACE_WITH_STRIDE_LENGTH<=PTT,"preload texture overlap");
_Static_assert(PSAMP+MALI_SAMPLER_LENGTH<=PVP,"preload sampler overlap");
_Static_assert(PCODE+1024<=VCODE,"preload code overlap");
static void p32(uint8_t*d,unsigned p,uint32_t n){memcpy(d+p,&n,4);}
static void p64(uint8_t*d,unsigned p,uint64_t n){memcpy(d+p,&n,8);}
static int span(uint64_t a,uint64_t n){return a&&n&&a<(UINT64_C(1)<<40)&&n<=(UINT64_C(1)<<40)-a;}
static int overlap(uint64_t a,uint64_t n,uint64_t b,uint64_t m){return a<b+m&&b<a+n;}
static unsigned bpp(unsigned fmt){switch(fmt){case 10:return 1;case 30:case 43:case 23:case 25:return 2;case 80:case 55:return 4;case 105:case 115:return 8;default:return 0;}}
static int image(const A5RuntimeImage*i,unsigned type,unsigned n){return n&&span(i->gpuVA,i->bytes)&&!(i->gpuVA&63)&&i->width&&i->width<=4096&&i->height&&i->height<=4096&&
 (type==A5ResourceTexture2D||(type==A5ResourceTexture1D&&i->height==1))&&
 i->rowBytes>=i->width*n&&!(i->rowBytes&15)&&(uint64_t)i->rowBytes*i->height<=i->bytes&&i->bytes<=32u*1024*1024;}
static const A5ResourceShader*shader(unsigned kind,unsigned bits,unsigned dim){
 for(unsigned i=0;i<sizeof(a5_resource_shaders)/sizeof(a5_resource_shaders[0]);i++){
  const A5ResourceShader*s=&a5_resource_shaders[i];if(s->kind==kind&&s->bits==bits&&s->dim==dim&&s->bytes&&s->bytes<=4096&&!(s->bytes&15)&&s->tag==5&&s->regs&&s->regs<=16)return s;
 }return NULL;
}
static void attrib(uint8_t*d,unsigned p,unsigned buffer,unsigned fmt,unsigned sw,unsigned off){
 pan_pack((struct mali_attribute_packed*)(d+p),ATTRIBUTE,c){c.buffer_index=buffer;c.offset_enable=true;c.format=(fmt<<12)|sw;c.offset=off;}}
static void buf(uint8_t*d,unsigned p,uint64_t va,unsigned stride,unsigned bytes){
 pan_pack((struct mali_attribute_buffer_packed*)(d+p),ATTRIBUTE_BUFFER,c){c.pointer=va;c.stride=stride;c.size=bytes;}}
static void tex(uint8_t*d,unsigned p,unsigned table,uint64_t va,const A5RuntimeImage*im,unsigned type,unsigned bits,int mip){
 unsigned fmt=mip?MALI_RGBA8_UNORM:bits==8?MALI_R8_UNORM:bits==16?MALI_R16UI:bits==32?MALI_R32UI:MALI_RG32UI;
 pan_pack((struct mali_texture_packed*)(d+p),TEXTURE,c){c.width=im->width;c.height=im->height;c.array_size=1;c.levels=1;
 c.format=(fmt<<12)|(mip?0x60a:bits==64?RG:R);c.dimension=type==A5ResourceTexture1D?MALI_TEXTURE_DIMENSION_1D:MALI_TEXTURE_DIMENSION_2D;
 c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;}
 pan_pack((struct mali_surface_with_stride_packed*)(d+p+32),SURFACE_WITH_STRIDE,c){c.pointer=im->gpuVA;c.row_stride=im->rowBytes;c.surface_stride=im->rowBytes*im->height;}
 p64(d,table,va+p);
}
static void samp(uint8_t*d,unsigned p){pan_pack((struct mali_sampler_packed*)(d+p),SAMPLER,c){c.normalized_coordinates=false;c.seamless_cube_map=false;c.minify_nearest=true;c.magnify_nearest=true;}}
static void rs(uint8_t*d,unsigned p,uint64_t code,const A5ResourceShader*s,int vs){
 pan_pack((struct mali_renderer_state_packed*)(d+p),RENDERER_STATE,c){
 c.shader.shader=code+s->tag;c.shader.attribute_count=vs?2:0;c.shader.varying_count=vs?3:1;c.shader.texture_count=vs?0:1;c.shader.sampler_count=vs?0:1;
 c.properties.uniform_buffer_count=1;c.properties.work_register_count=s->regs;c.properties.force_early_z=true;
 c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
 c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.write_enable=!vs;c.stencil_mask_misc.dither_disable=true;
 c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.rgb.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.rgb.c=MALI_BLEND_OPERAND_C_ZERO;
 c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.alpha.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.alpha.c=MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.color_mask=15;}}
static void tiler(uint8_t*d,unsigned off,uint64_t va,uint64_t pos,unsigned vp,unsigned vary,unsigned varyingbuf,unsigned rsd,unsigned textures,unsigned sampler,unsigned ubos,unsigned index){
 pan_pack((struct mali_job_header_packed*)(d+off),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=index;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+off+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+off+40),PRIMITIVE,c){c.draw_mode=MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=4;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+off+64),DRAW,c){c.position=pos;c.viewport=va+vp;c.varyings=va+vary;c.varying_buffers=va+varyingbuf;
 c.state=va+rsd;c.textures=va+textures;c.samplers=va+sampler;c.uniform_buffers=va+ubos;c.thread_storage=va+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+off+184),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
}
static int encode(const A5RuntimeResourceOp*r,uint8_t*d){
 unsigned n=bpp(r->source.metalPixelFormat),bits=n*8,dim=r->sourceType==A5ResourceTexture1D?1:2;
 if(!span(r->descriptorGPUVA,A5RuntimeJobBytes)||(r->descriptorGPUVA&4095)||!image(&r->source,r->sourceType,n)||!image(&r->destination,r->destinationType,n)||
 r->source.metalPixelFormat!=r->destination.metalPixelFormat||
 overlap(r->source.gpuVA,r->source.bytes,r->destination.gpuVA,r->destination.bytes)||
 overlap(r->source.gpuVA,r->source.bytes,r->descriptorGPUVA,A5RuntimeJobBytes)||overlap(r->destination.gpuVA,r->destination.bytes,r->descriptorGPUVA,A5RuntimeJobBytes))return A5RuntimeBounds;
 if(r->operation>A5ResourceGenerateMip)return A5RuntimeUnsupported;
 int mip=r->operation==A5ResourceGenerateMip;
 if(!r->width||!r->height||r->destinationX>=r->destination.width||r->destinationY>=r->destination.height||r->width>r->destination.width-r->destinationX||r->height>r->destination.height-r->destinationY)return A5RuntimeBounds;
 if(mip){
 if(r->source.metalPixelFormat!=80||r->sourceType!=A5ResourceTexture2D||r->destinationType!=A5ResourceTexture2D||r->sourceX||r->sourceY||r->destinationX||r->destinationY||
 r->width!=r->destination.width||r->height!=r->destination.height||r->destination.width!=(r->source.width>1?r->source.width/2:1)||r->destination.height!=(r->source.height>1?r->source.height/2:1))return A5RuntimeUnsupported;
 }else if(r->sourceX>=r->source.width||r->sourceY>=r->source.height||r->width>r->source.width-r->sourceX||r->height>r->source.height-r->sourceY)return A5RuntimeBounds;
 const A5ResourceShader*vs=shader(0,0,2),*fs=shader(mip?2:1,bits,dim);if(!vs||!fs)return A5RuntimeUnsupported;
 uint64_t va=r->descriptorGPUVA;memcpy(d+VCODE,vs->code,vs->bytes);memcpy(d+FCODE,fs->code,fs->bytes);
 float x0=2.0f*r->destinationX/r->destination.width-1,x1=2.0f*(r->destinationX+r->width)/r->destination.width-1;
 float y0=2.0f*r->destinationY/r->destination.height-1,y1=2.0f*(r->destinationY+r->height)/r->destination.height-1;
 float sx=mip?0:r->sourceX,sy=mip?0:r->sourceY,sw=r->width,sh=r->height;
 float v[24]={x0,y0,0,1,sx,sy,x1,y0,0,1,sx+sw,sy,x0,y1,0,1,sx,sy+sh,x1,y1,0,1,sx+sw,sy+sh};memcpy(d+VERTICES,v,sizeof(v));
 float viewport[8]={r->destination.width*.5f,r->destination.height*.5f,.5f,0,r->destination.width*.5f,r->destination.height*.5f,.5f,0};memcpy(d+VSYS,viewport,sizeof(viewport));
 p32(d,FSYS,r->source.width);p32(d,FSYS+4,r->source.height);p32(d,FSYS+8,r->destination.width);p32(d,FSYS+12,r->destination.height);
 pan_pack((struct mali_uniform_buffer_packed*)(d+VUBO),UNIFORM_BUFFER,c){c.pointer=va+VSYS;c.entries=2;}
 pan_pack((struct mali_uniform_buffer_packed*)(d+FUBO),UNIFORM_BUFFER,c){c.pointer=va+FSYS;c.entries=1;}
 tex(d,TEX,TT,va,&r->source,r->sourceType,bits,mip);samp(d,SAMP);
 pan_section_pack(d+FB,FRAMEBUFFER,LOCAL_STORAGE,c){c.wls_instances=MALI_LOCAL_STORAGE_NO_WORKGROUP_MEM;}
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){c.internal_format=(mip||bits==8)?MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8:MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE;
 c.color_writeback_format=mip?MALI_COLOR_FORMAT_R8G8B8A8:bits==8?MALI_COLOR_FORMAT_R8:bits==16?MALI_COLOR_FORMAT_1_16B_CHANNEL:bits==32?MALI_COLOR_FORMAT_1_32B_CHANNEL:MALI_COLOR_FORMAT_2_32B_CHANNELS;
 c.swizzle=mip?0x60a:bits==8?R:0x688;c.color_write_enable=true;c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
 c.bound_max_x=r->destination.width-1;c.bound_max_y=r->destination.height-1;c.color_writeback.base=r->destination.gpuVA;c.color_writeback.row_stride=r->destination.rowBytes;}
 unsigned tiles=((r->destination.width+1023)/1024)*((r->destination.height+1023)/1024),header=0x200+((tiles*8)/0x200)*0x200,full=0x200+tiles*0x200;
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){c.polygon_list=va+POLY;c.polygon_list_body=va+POLY+header;c.polygon_list_size=full;c.hierarchy_mask=0x1c7;c.heap_start=va+HEAP;c.heap_end=va+HEAP_END;}p32(d,POLY+header,0xa0000000);
 rs(d,VRS,va+VCODE,vs,1);rs(d,FRS,va+FCODE,fs,0);
 attrib(d,ATTR,0,MALI_RGBA32F,0x688,0);attrib(d,ATTR+8,0,MALI_RG32F,RG,16);buf(d,ABUF,va+VERTICES,24,96);
 attrib(d,VV,0,MALI_SNAP_4,0x688,0);attrib(d,VV+8,1,MALI_R16F,R,0);attrib(d,VV+16,2,MALI_RG32UI,RG,0);
 buf(d,VB,va+POS,16,64);buf(d,VB+16,va+PSIZ,2,8);buf(d,VB+32,va+UV,8,32);
 attrib(d,FV,0,MALI_RG32F,RG,0);buf(d,FVB,va+UV,8,32);
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=va+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=va+VRS;c.attributes=va+ATTR;c.attribute_buffers=va+ABUF;c.uniform_buffers=va+VUBO;c.varyings=va+VV;c.varying_buffers=va+VB;c.thread_storage=va+FB;}
 tiler(d,0x100,va,va+POS,VP,FV,FVB,FRS,TT,SAMP,FUBO,2);
 pan_pack((struct mali_viewport_packed*)(d+VP),VIEWPORT,c){c.scissor_minimum_x=r->destinationX;c.scissor_minimum_y=r->destinationY;c.scissor_maximum_x=r->destinationX+r->width-1;c.scissor_maximum_y=r->destinationY+r->height-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_min_x=r->destinationX/16;c.bound_min_y=r->destinationY/16;c.bound_max_x=(r->destinationX+r->width-1)/16;c.bound_max_y=(r->destinationY+r->height-1)/16;c.framebuffer=va+FB;}
 if(!mip&&(r->destinationX||r->destinationY||r->width!=r->destination.width||r->height!=r->destination.height)){
  const A5ResourceShader*ps=shader(1,bits,r->destinationType==A5ResourceTexture1D?1:2);if(!ps||ps->bytes>1024)return A5RuntimeUnsupported;
  memcpy(d+PCODE,ps->code,ps->bytes);rs(d,PRS,va+PCODE,ps,0);
  float p[16]={0,0,0,1,r->destination.width,0,0,1,0,r->destination.height,0,1,r->destination.width,r->destination.height,0,1};memcpy(d+PPOS,p,sizeof(p));
  tex(d,PTEX,PTT,va,&r->destination,r->destinationType,bits,0);samp(d,PSAMP);
  attrib(d,PV,0,MALI_RG32F,RG,0);buf(d,PVB,va+PPOS,16,64);
  pan_pack((struct mali_viewport_packed*)(d+PVP),VIEWPORT,c){c.scissor_maximum_x=r->destination.width-1;c.scissor_maximum_y=r->destination.height-1;}
  tiler(d,PJ,va,va+PPOS,PVP,PV,PVB,PRS,PTT,PSAMP,FUBO,2);
  pan_pack((struct mali_job_header_packed*)(d+PJ),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.next=va+0x100;c.enable_texture_mapper=true;}
  pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=va+PJ;}
  pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=3;c.dependency_1=1;c.dependency_2=2;c.enable_texture_mapper=true;}
  pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=4;c.enable_texture_mapper=true;}
 }
 return A5RuntimeOK;
}
int A5MaliEncodeRuntimeResourceOp(const A5RuntimeResourceOp*r,void*out,size_t n){if(!out||n!=A5RuntimeJobBytes)return A5RuntimeInvalid;memset(out,0,n);int rc=r?encode(r,out):A5RuntimeInvalid;if(rc)memset(out,0,n);return rc;}
