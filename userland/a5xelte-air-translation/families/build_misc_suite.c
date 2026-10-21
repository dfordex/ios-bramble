/* SPDX-License-Identifier: MIT
 * Real translated-QC host fixture builder. One selected logical RT per SFBD
 * case, including explicit replay for proven identical side-effect-free MRT.
 * Uses released Mesa26.2.4 v4 packing and native SSBO/global-address sysvals.
 */
#define PAN_ARCH 4
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"

enum { SIZE=0x40000, W=32,H=32, FB=0x300,VS_RSD=0x500,FS_RSD=0x540,
 TEX0=0x600,TEX1=0x640,TEX_TABLE=0x680,SAMPLERS=0x6a0,
 VS_UBOS=0x700,FS_UBOS=0x740,ATTRS=0x800,ATTR_BUFS=0x900,
 VS_VARY=0xa00,VS_VARY_BUFS=0xa80,FS_VARY=0xc00,FS_VARY_BUFS=0xc80,
 VIEWPORT=0xe00,VS_SYS=0x1000,FS_SYS=0x1400,MVP=0x1800,TEXMAT=0x1900,
 FRAG_DATA=0x1a00,SSBO_VERT=0x2000,ORDINARY=0x3000,POS=0x3100,PSIZ=0x3180,
 VARY_DATA=0x3200,VS_CODE=0x6000,FS_CODE=0x8000,POLY=0xa000,POLY_BODY=0xa200,
 HEAP=0x10000,HEAP_SIZE=0x10000,SOURCE=0x20000,LUT=0x22000,
 DEST=0x24000,GUARDS=0x28000 };
enum { RG_SWIZZLE=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9),
 R_SWIZZLE=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9) };
static const uint64_t VA=0x02000000;
static void u32(uint8_t*d,unsigned o,uint32_t v){memcpy(d+o,&v,4);}
static void u64(uint8_t*d,unsigned o,uint64_t v){memcpy(d+o,&v,8);}
static void f32(uint8_t*d,unsigned o,float v){memcpy(d+o,&v,4);}
static void half(uint8_t*d,unsigned o,uint16_t v){memcpy(d+o,&v,2);}
static void ubo(uint8_t*d,unsigned table,unsigned index,unsigned off,unsigned bytes){
 pan_pack((struct mali_uniform_buffer_packed*)(d+table+index*8),UNIFORM_BUFFER,c){
  c.pointer=VA+off;c.entries=(bytes+15)/16;
 }
}
static void attr(uint8_t*d,unsigned at,unsigned buffer,unsigned format,unsigned swizzle,unsigned off){
 pan_pack((struct mali_attribute_packed*)(d+at),ATTRIBUTE,c){
  c.buffer_index=buffer;c.offset_enable=true;c.format=(format<<12)|swizzle;c.offset=off;
 }
}
static void buf(uint8_t*d,unsigned at,unsigned off,unsigned stride,unsigned bytes){
 pan_pack((struct mali_attribute_buffer_packed*)(d+at),ATTRIBUTE_BUFFER,c){
  c.pointer=VA+off;c.stride=stride;c.size=bytes;
 }
}
static int shader(const char*p,uint8_t*d,unsigned off){
 FILE*f=fopen(p,"rb");if(!f)return 0;
 size_t n=fread(d+off,1,0x1000,f);int extra=fgetc(f);fclose(f);
 return n&&!(n&15)&&extra==EOF;
}
static void framebuffer(uint8_t*d,unsigned format,unsigned pixel_bytes){
 u32(d,FB+4,31); /* released v4 local storage, TLS/WLS bothzero */
 pan_section_pack(d+FB,FRAMEBUFFER,PARAMETERS,c){
  c.internal_format=format==2?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:
     MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
  c.swizzle=format==0?0x60a:0x688;
  c.color_writeback_format=format==2?MALI_COLOR_FORMAT_2_32B_CHANNELS:
     format==1?MALI_COLOR_FORMAT_R8:format==3?MALI_COLOR_FORMAT_R8G8:MALI_COLOR_FORMAT_R8G8B8A8;
  c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;
  c.color_write_enable=true;c.color_preload_enable=true;
  c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
  c.bound_max_x=W-1;c.bound_max_y=H-1;
  c.color_writeback.base=VA+DEST;c.color_writeback.row_stride=W*pixel_bytes;
  c.color_load_address=VA+DEST;c.color_load_row_stride=W*pixel_bytes;
  c.color_load_surface_stride=W*H*pixel_bytes;
 }
 pan_section_pack(d+FB,FRAMEBUFFER,TILER,c){
  c.polygon_list=VA+POLY;c.polygon_list_body=VA+POLY_BODY;
  c.heap_start=VA+HEAP;c.heap_end=VA+HEAP+HEAP_SIZE;
  c.polygon_list_size=0x400;c.hierarchy_mask=0x1c7;
 }
 u32(d,POLY_BODY,0xa0000000);
}
static void renderer(uint8_t*d,int home,int clear,unsigned vs_regs,unsigned fs_regs){
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
  c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;
  c.blend_equation.rgb.b=MALI_BLEND_OPERAND_B_SRC;
  c.blend_equation.rgb.c=MALI_BLEND_OPERAND_C_ZERO;
  c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;
  c.blend_equation.alpha.b=MALI_BLEND_OPERAND_B_SRC;
  c.blend_equation.alpha.c=MALI_BLEND_OPERAND_C_ZERO;
  c.blend_equation.color_mask=0xf;
 }
}
static void resources(uint8_t*d,int home,int clear,unsigned rule,unsigned target){
 for(unsigned i=0;i<8;++i){ubo(d,VS_UBOS,i,VS_SYS,576);ubo(d,FS_UBOS,i,FS_SYS,576);}
 ubo(d,VS_UBOS,home?1:2,MVP,64);
 if(home){ubo(d,VS_UBOS,2,TEXMAT,16);ubo(d,FS_UBOS,3,FRAG_DATA,16);}
 else if(!clear)ubo(d,FS_UBOS,3,FRAG_DATA,16);
 /* Actual Vulkan push field locations, including BOTH MRT color rules. */
 u32(d,FS_SYS+(home?68:clear?64:72),rule);
 if(!home)u32(d,FS_SYS+(clear?68:76),rule);
 if(!home&&!clear&&rule==2)u32(d,FS_SYS+76,0x22);
 if(!home&&!clear&&rule==0x22)u32(d,FS_SYS+72,2);
 (void)target;
 for(unsigned i=0;i<2;++i){
  unsigned o=i?FS_SYS:VS_SYS;
  f32(d,o+512,16);f32(d,o+516,16);f32(d,o+520,.5f);
  f32(d,o+528,16);f32(d,o+532,16);f32(d,o+536,.5f);
 }
 f32(d,MVP,2.0f/W);f32(d,MVP+20,2.0f/H);f32(d,MVP+40,1);
 f32(d,MVP+48,-1);f32(d,MVP+52,-1);f32(d,MVP+60,1);
 f32(d,TEXMAT,1);f32(d,TEXMAT+4,1);
 if(home){
  /* Actual fragment uniform half4add(0), halfopacity1. */
  half(d,FRAG_DATA+8,0x3c00);
  for(unsigned i=0;i<4;++i){unsigned o=ORDINARY+i*48;
   f32(d,o,(i&1)?W:0);f32(d,o+4,(i&2)?H:0);f32(d,o+12,1);
   f32(d,o+16,(i&1)?1:0);f32(d,o+20,(i&2)?1:0);
   for(unsigned c=0;c<4;++c)half(d,o+32+c*2,0x3c00);
  }
  attr(d,ATTRS,0,MALI_RGBA32F,0x688,0);
  attr(d,ATTRS+8,0,MALI_RG32F,RG_SWIZZLE,16);
  attr(d,ATTRS+16,0,MALI_RGBA16F,0x688,32);
  buf(d,ATTR_BUFS,ORDINARY,48,192);
  for(unsigned t=0;t<2;++t){unsigned tex=t?TEX1:TEX0;unsigned width=t?2:W,height=t?1:H;
   pan_pack((struct mali_texture_packed*)(d+tex),TEXTURE,c){
    c.width=width;c.height=height;c.array_size=1;c.levels=1;
    c.format=(MALI_RGBA8_UNORM<<12)|0x688;c.dimension=MALI_TEXTURE_DIMENSION_2D;
    c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;
   }
   pan_pack((struct mali_surface_with_stride_packed*)(d+tex+32),SURFACE_WITH_STRIDE,c){
    c.pointer=VA+(t?LUT:SOURCE);c.row_stride=width*4;c.surface_stride=width*height*4;
   }
   u64(d,TEX_TABLE+t*8,VA+tex);
   pan_pack((struct mali_sampler_packed*)(d+SAMPLERS+t*32),SAMPLER,c){
    c.normalized_coordinates=true;c.seamless_cube_map=false;
    c.minify_nearest=false;c.magnify_nearest=false;c.maximum_lod=.25f;
   }
   unsigned s=FS_SYS+352+32*t;u32(d,s,1);u32(d,s+4,width);u32(d,s+8,height);f32(d,s+20,.25f);
  }
  for(unsigned y=0;y<H;++y)for(unsigned x=0;x<W;++x){unsigned on=((x/7+y/5)&1);
   u32(d,SOURCE+4*(y*W+x),on?0xffffffff:0xff000000);
  }
  u32(d,LUT,0xff404040);u32(d,LUT+4,0xffc0c0c0);
 }else{
  /* Actual read-only SSBO with draw0 rectangle; no forced shaderoutputs. */
  u64(d,VS_SYS+96,VA+SSBO_VERT);u32(d,VS_SYS+104,clear?16:24);
  if(clear){f32(d,SSBO_VERT,0);f32(d,SSBO_VERT+4,0);f32(d,SSBO_VERT+8,W);f32(d,SSBO_VERT+12,H);}
  else{
   f32(d,SSBO_VERT,0);f32(d,SSBO_VERT+4,H);f32(d,SSBO_VERT+8,W);f32(d,SSBO_VERT+12,H);
   u32(d,SSBO_VERT+16,0);u32(d,SSBO_VERT+20,W);
   u64(d,FS_SYS+96+3*16,VA+SOURCE);u32(d,FS_SYS+104+3*16,W*H);
   const uint16_t tint[4]={0x3400,0x3800,0x3a00,0x3c00};memcpy(d+FRAG_DATA,tint,8);
   for(unsigned y=0;y<H;++y)for(unsigned x=0;x<W;++x)d[SOURCE+y*W+x]=(x/7+y/5)&1;
  }
  /* Released pan_encoder.h: VertexID no-op modulo and InstanceID divide
   * bylargeconstant toforce0 for this one-instance draw. */
  pan_pack((struct mali_attribute_vertex_id_packed*)(d+ATTR_BUFS),ATTRIBUTE_VERTEX_ID,c){c.divisor_r=31;c.divisor_p=4;}
  pan_pack((struct mali_attribute_instance_id_packed*)(d+ATTR_BUFS+32),ATTRIBUTE_INSTANCE_ID,c){c.divisor_p=0x7fffffff;c.divisor_r=31;c.divisor_e=1;}
  attr(d,ATTRS+16*8,0,MALI_R32UI,R_SWIZZLE,0);
  attr(d,ATTRS+17*8,1,MALI_R32UI,R_SWIZZLE,0);
 }
 /* Actual stage-specific varying formats: VSrawU32, FSsmoothfloat32. */
 attr(d,VS_VARY,0,MALI_SNAP_4,0x688,0);buf(d,VS_VARY_BUFS,POS,16,64);
 attr(d,VS_VARY+8,1,MALI_R16F,R_SWIZZLE,0);buf(d,VS_VARY_BUFS+32,PSIZ,2,8);
 if(home){
  attr(d,VS_VARY+16,2,MALI_RGBA32UI,0x688,0);buf(d,VS_VARY_BUFS+64,VARY_DATA,16,64);
  attr(d,VS_VARY+24,3,MALI_RG32UI,RG_SWIZZLE,0);buf(d,VS_VARY_BUFS+96,VARY_DATA+128,8,32);
  attr(d,FS_VARY,0,MALI_RG32F,RG_SWIZZLE,0);buf(d,FS_VARY_BUFS,VARY_DATA+128,8,32);
 }else if(!clear){
  for(unsigned i=0;i<5;++i){unsigned off=VARY_DATA+i*128;
   attr(d,VS_VARY+(i+2)*8,i+2,i?MALI_R32UI:MALI_RG32UI,i?R_SWIZZLE:RG_SWIZZLE,0);
   buf(d,VS_VARY_BUFS+(i+2)*32,off,i?4:8,i?16:32);
   attr(d,FS_VARY+i*8,i,i?MALI_R32UI:MALI_RG32F,i?R_SWIZZLE:RG_SWIZZLE,0);
   buf(d,FS_VARY_BUFS+i*32,off,i?4:8,i?16:32);
  }
 }
}
static void jobs(uint8_t*d){
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=VA+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=VA+VS_RSD;c.attributes=VA+ATTRS;c.attribute_buffers=VA+ATTR_BUFS;c.uniform_buffers=VA+VS_UBOS;c.varyings=VA+VS_VARY;c.varying_buffers=VA+VS_VARY_BUFS;c.thread_storage=VA+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){c.draw_mode=MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=4;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=VA+POS;c.viewport=VA+VIEWPORT;c.varyings=VA+FS_VARY;c.varying_buffers=VA+FS_VARY_BUFS;c.uniform_buffers=VA+FS_UBOS;c.textures=VA+TEX_TABLE;c.samplers=VA+SAMPLERS;c.state=VA+FS_RSD;c.fbd=VA+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VIEWPORT),VIEWPORT,c){c.scissor_maximum_x=W-1;c.scissor_maximum_y=H-1;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_max_x=1;c.bound_max_y=1;c.framebuffer=VA+FB;}
}
static int validate(uint8_t*d,int home,int clear,unsigned fmt){
 pan_unpack((struct mali_job_header_packed*)d,JOB_HEADER,v);
 pan_unpack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,t);
 pan_unpack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,f);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(d+FB+32),FRAMEBUFFER_PARAMETERS,p);
 pan_unpack((struct mali_tiler_context_packed*)(d+FB+192),TILER_CONTEXT,h);
 pan_unpack((struct mali_renderer_state_packed*)(d+VS_RSD),RENDERER_STATE,vs);
 pan_unpack((struct mali_renderer_state_packed*)(d+FS_RSD),RENDERER_STATE,fs);
 if(v.type!=MALI_JOB_TYPE_VERTEX||v.next!=VA+0x100||t.type!=MALI_JOB_TYPE_TILER||t.dependency_1!=1||f.type!=MALI_JOB_TYPE_FRAGMENT)return 0;
 if(p.color_writeback.base!=VA+DEST||p.bound_max_x!=31||p.bound_max_y!=31||!p.color_write_enable||!p.color_preload_enable)return 0;
 unsigned want=fmt==2?MALI_COLOR_FORMAT_2_32B_CHANNELS:fmt==1?MALI_COLOR_FORMAT_R8:fmt==3?MALI_COLOR_FORMAT_R8G8:MALI_COLOR_FORMAT_R8G8B8A8;
 if(p.color_writeback_format!=want||p.internal_format!=(fmt==2?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8))return 0;
 if(h.heap_start!=VA+HEAP||h.heap_end!=VA+HEAP+HEAP_SIZE||h.polygon_list!=VA+POLY||h.polygon_list_size>0xa00)return 0;
 if(vs.shader.shader!=VA+VS_CODE+5||fs.shader.shader!=VA+FS_CODE+5||vs.shader.attribute_count!=(home?3:18)||vs.properties.uniform_buffer_count!=3||fs.properties.uniform_buffer_count!=(clear?1:4))return 0;
 if(home){
  if(fs.shader.texture_count!=2||fs.shader.sampler_count!=2)return 0;
  pan_unpack((struct mali_attribute_packed*)(d+ATTRS+8),ATTRIBUTE,a);
  if(a.format!=((MALI_RG32F<<12)|RG_SWIZZLE)||a.offset!=16)return 0;
 }else{
  pan_unpack((struct mali_attribute_vertex_id_packed*)(d+ATTR_BUFS),ATTRIBUTE_VERTEX_ID,a);
  pan_unpack((struct mali_attribute_instance_id_packed*)(d+ATTR_BUFS+32),ATTRIBUTE_INSTANCE_ID,b);
  if(a.type!=MALI_ATTRIBUTE_SPECIAL_VERTEX_ID||a.divisor_r!=31||a.divisor_p!=4||b.type!=MALI_ATTRIBUTE_SPECIAL_INSTANCE_ID||b.divisor_p!=0x7fffffff||b.divisor_e!=1||b.divisor_r!=31)return 0;
 }
 return 1;
}
int main(int argc,char**argv){
 if(argc!=9){fprintf(stderr,"usage: builder home|clear|blit format0..3 target0..1 VS FS OUT vsregs fsregs\n");return 2;}
 int home=!strcmp(argv[1],"home"),clear=!strcmp(argv[1],"clear"),blit=!strcmp(argv[1],"blit");
 unsigned fmt=(unsigned)atoi(argv[2]),target=(unsigned)atoi(argv[3]);
 if((!home&&!clear&&!blit)||fmt>3||target>1||(home&&(fmt||target)))return 2;
 uint8_t*d=calloc(1,SIZE);if(!d)return 1;
 memset(d+POS,0xa5,0xb00);memset(d+DEST,0x6d,0x2000);memset(d+GUARDS,0xa5,SIZE-GUARDS);
 if(!shader(argv[4],d,VS_CODE)||!shader(argv[5],d,FS_CODE)){fprintf(stderr,"shader size invalid\n");return 2;}
 unsigned pixelbytes=fmt==2?8:fmt==1?1:fmt==3?2:4;
 framebuffer(d,fmt,pixelbytes);renderer(d,home,clear,(unsigned)atoi(argv[7]),(unsigned)atoi(argv[8]));
 resources(d,home,clear,fmt==2?0x3333:fmt==1?2:fmt==3?0x22:0x2222,target);jobs(d);
 if(!validate(d,home,clear,fmt)){fprintf(stderr,"packed descriptor readback rejected\n");return 2;}
 FILE*f=fopen(argv[6],"wb");if(!f)return 1;size_t n=fwrite(d,1,SIZE,f);int rc=fclose(f);free(d);
 if(n!=SIZE||rc)return 1;
 printf("misc fixture bytes=%u output=0x%x bytes=%u nativeformat=%u target=%u heap=0x%x..0x%x\n",SIZE,DEST,W*H*pixelbytes,fmt,target,HEAP,HEAP+HEAP_SIZE);
 return 0;
}
