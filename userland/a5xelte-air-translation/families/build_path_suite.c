/* SPDX-License-Identifier: MIT
 * Isolated real path/stroke shader tests, native v4 SFBD single-target variants.
 * Shader bytes remain caller-supplied/private; no Apple code is embedded.
 */
#define PAN_ARCH 4
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"
enum {N=0x40000,FB=0x300,VRS=0x500,FRS=0x540,VD=0x600,FD=0x640,
 VA=0x700,VB=0x800,VV=0x900,FV=0xa00,B=0xb00,VP=0xc00,
 POLY=0x3000,BODY=0x3200,VS=0x4000,FS=0x6000,
 SSBO=0x10000,MVP=0x11000,AUX=0x12000,PUSH=0x13000,FPUSH=0x14000,
 POS=0x18000,PSIZ=0x18100,GENERAL=0x18200,OUT=0x20000,HEAP=0x24000,
 HEAP_END=0x28000,GUARD=0x30000,W=32,H=32};
static uint8_t d[N];static const uint64_t base=0x02000000;
static void u32(unsigned o,uint32_t v){memcpy(d+o,&v,4);}static void u64(unsigned o,uint64_t v){memcpy(d+o,&v,8);}static void f32(unsigned o,float v){memcpy(d+o,&v,4);}
static unsigned file(const char *p,unsigned off){FILE*f=fopen(p,"rb");if(!f)return 0;unsigned n=fread(d+off,1,0x2000,f);int extra=fgetc(f);fclose(f);return extra==EOF?n:0;}
static void ub(unsigned table,unsigned slot,unsigned off,unsigned bytes){pan_pack((struct mali_uniform_buffer_packed*)(d+table+slot*8),UNIFORM_BUFFER,c){c.pointer=base+off;c.entries=(bytes+15)/16;}}
static unsigned swz(unsigned comps){return comps==1?(MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)):comps==2?(MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9)):0x688;}
static void at(unsigned off,unsigned buf,unsigned fmt,unsigned comps,unsigned offset){pan_pack((struct mali_attribute_packed*)(d+off),ATTRIBUTE,c){c.buffer_index=buf;c.offset_enable=true;c.format=(fmt<<12)|swz(comps);c.offset=offset;}}
static void ab(unsigned slot,unsigned off,unsigned stride,unsigned size){pan_pack((struct mali_attribute_buffer_packed*)(d+B+slot*pan_size(ATTRIBUTE_BUFFER)),ATTRIBUTE_BUFFER,c){c.pointer=base+off;c.stride=stride;c.size=size;}}
int main(int argc,char **argv){
 if(argc!=7){fprintf(stderr,"usage: build_path_suite rect|cubic|stroke VS FS vsregs fsregs payload\n");return 2;}
 int stroke=!strcmp(argv[1],"stroke"),cubic=!strcmp(argv[1],"cubic");if(!stroke&&!cubic&&strcmp(argv[1],"rect"))return 2;
 unsigned vsregs=strtoul(argv[4],NULL,10),fsregs=strtoul(argv[5],NULL,10);if(!vsregs||vsregs>16||!fsregs||fsregs>16)return 2;
 if(!file(argv[2],VS)||!file(argv[3],FS))return 2;
 unsigned comps[5]={1,1,1,1,1},offsets[5]={0,4,8,12,16};unsigned nvar=3;
 if(cubic){nvar=4;comps[0]=comps[1]=2;offsets[0]=0;offsets[1]=8;offsets[2]=16;offsets[3]=20;}
 if(stroke){nvar=5;comps[0]=4;offsets[0]=0;offsets[1]=16;offsets[2]=20;offsets[3]=24;offsets[4]=28;}
 unsigned stride=stroke?256:128;
 /* Native SFBD: one actual raw color plane, typed upstream shader packing. */
 u32(FB+4,31);
 pan_pack((struct mali_framebuffer_parameters_packed*)(d+FB+MALI_FRAMEBUFFER_SECTION_PARAMETERS_OFFSET),FRAMEBUFFER_PARAMETERS,c){
  c.bound_max_x=31;c.bound_max_y=31;c.internal_format=MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE;
  c.color_writeback_format=stroke?MALI_COLOR_FORMAT_2_32B_CHANNELS:MALI_COLOR_FORMAT_1_32B_CHANNEL;
  c.color_block_format=MALI_BLOCK_FORMAT_LINEAR;c.color_write_enable=true;c.clean_pixel_write_enable=true;
  c.color_writeback.base=base+OUT;c.color_writeback.row_stride=stride;c.swizzle=0x688;
  c.tie_break_rule=MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
 }
 u64(FB+25*8,base+POLY);u64(FB+26*8,base+BODY);u64(FB+27*8,base+HEAP);u64(FB+28*8,base+HEAP_END);u32(FB+48*4,0x400);u32(FB+49*4,0x1c7);u32(BODY,0xa0000000);
 pan_pack((struct mali_renderer_state_packed*)(d+VRS),RENDERER_STATE,c){c.shader.shader=base+VS+5;c.shader.attribute_count=18;c.shader.varying_count=nvar+2;c.properties.uniform_buffer_count=4;c.properties.work_register_count=vsregs;c.properties.force_early_z=true;c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;}
 pan_pack((struct mali_renderer_state_packed*)(d+FRS),RENDERER_STATE,c){c.shader.shader=base+FS+5;c.shader.varying_count=nvar+(stroke?0:1);c.properties.uniform_buffer_count=1;c.properties.work_register_count=fsregs;c.properties.force_early_z=true;c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.write_enable=true;c.stencil_mask_misc.dither_disable=true;c.blend_equation.color_mask=stroke?15:1;c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.rgb.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.rgb.c=MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.alpha.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.alpha.c=MALI_BLEND_OPERAND_C_ZERO;}
 ub(VD,0,PUSH,576);ub(VD,1,PUSH,576);ub(VD,2,MVP,64);ub(VD,3,AUX,32);ub(FD,0,FPUSH,80);
 u64(PUSH+96,base+SSBO);u32(PUSH+104,4096);
 f32(PUSH+512,16);f32(PUSH+516,16);f32(PUSH+520,.5);f32(PUSH+528,16);f32(PUSH+532,16);f32(PUSH+536,.5);
 f32(MVP,stroke?1.0f/16:1);f32(MVP+20,stroke?1.0f/16:1);f32(MVP+40,1);f32(MVP+60,1);
 if(stroke){f32(MVP+48,-1);f32(MVP+52,-1);f32(SSBO,8);f32(SSBO+4,16);f32(SSBO+8,24);f32(SSBO+12,16);f32(AUX,.25);f32(AUX+4,.5);f32(AUX+8,.75);f32(AUX+12,1);f32(AUX+16,4);f32(AUX+20,0);}
 else{f32(AUX,32);f32(AUX+4,32);if(cubic){f32(SSBO,1);f32(SSBO+4,.5);f32(SSBO+8+16,2);f32(SSBO+8+20,2);f32(SSBO+8+24,-.5);f32(SSBO+8+28,-.5);}else{f32(SSBO,-.5);f32(SSBO+4,-.5);f32(SSBO+8,.5);f32(SSBO+12,.5);f32(SSBO+16,1);}}
 pan_pack((struct mali_attribute_vertex_id_packed*)(d+VB),ATTRIBUTE_VERTEX_ID,c){c.divisor_r=31;c.divisor_p=4;}
 pan_pack((struct mali_attribute_instance_id_packed*)(d+VB+32),ATTRIBUTE_INSTANCE_ID,c){c.divisor_r=31;c.divisor_e=1;c.divisor_p=0x7fffffff;}
 at(VA+16*8,0,MALI_R32UI,1,0);at(VA+17*8,2,MALI_R32UI,1,0);
 at(VV,0,MALI_SNAP_4,4,0);at(VV+8,1,MALI_R16F,1,0);ab(0,POS,16,64);ab(1,PSIZ,2,8);ab(2,GENERAL,32,128);
 for(unsigned i=0;i<nvar;i++){unsigned ui=comps[i]==4?MALI_RGBA32UI:comps[i]==2?MALI_RG32UI:MALI_R32UI;at(VV+(i+2)*8,2,ui,comps[i],offsets[i]);unsigned fmt=ui;if(stroke&&i)fmt=MALI_R32F;at(FV+i*8,2,fmt,comps[i],offsets[i]);}
 if(!stroke){at(FV+nvar*8,3,MALI_RGBA32F,4,0);u32(B+3*pan_size(ATTRIBUTE_BUFFER),MALI_ATTRIBUTE_SPECIAL_FRAG_COORD);}
 pan_pack((struct mali_job_header_packed*)(d),JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=base+0x100;}
 pan_pack((struct mali_invocation_packed*)(d+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_compute_job_parameters_packed*)(d+MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET),COMPUTE_JOB_PARAMETERS,c){c.job_task_split=5;}
 pan_pack((struct mali_draw_packed*)(d+64),DRAW,c){c.state=base+VRS;c.attributes=base+VA;c.attribute_buffers=base+VB;c.uniform_buffers=base+VD;c.varyings=base+VV;c.varying_buffers=base+B;c.thread_storage=base+FB;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+0x120),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+0x128),PRIMITIVE,c){c.draw_mode=MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=4;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+0x140),DRAW,c){c.position=base+POS;c.viewport=base+VP;c.varyings=base+FV;c.varying_buffers=base+B;c.uniform_buffers=base+FD;c.state=base+FRS;c.fbd=base+FB;}
 pan_pack((struct mali_primitive_size_packed*)(d+0x1b8),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 pan_pack((struct mali_viewport_packed*)(d+VP),VIEWPORT,c){c.scissor_maximum_x=31;c.scissor_maximum_y=31;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=3;c.enable_texture_mapper=true;}
 pan_pack((struct mali_fragment_job_payload_packed*)(d+0x220),FRAGMENT_JOB_PAYLOAD,c){c.bound_max_x=1;c.bound_max_y=1;c.framebuffer=base+FB;}
 memset(d+OUT,0x5a,8192);for(unsigned i=0;i<4096;i+=4)u32(GUARD+i,0xa5c00000+i);
 FILE*f=fopen(argv[6],"wb");if(!f)return 1;int ok=fwrite(d,1,N,f)==N;return fclose(f)||!ok;
}
