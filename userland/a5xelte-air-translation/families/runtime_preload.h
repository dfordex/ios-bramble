/* Copyright (C) 2020-2021 Collabora, Ltd.
 * SPDX-License-Identifier: MIT
 * Shared v4 framebuffer preserve path: a real texture-copy TILER job before
 * the application's draw, following released Mesa26.2.4 pan_fb_preload.c.
 * Direct SFBD colour-load fields are deliberately unused.
 */
#ifndef A5_RUNTIME_PRELOAD_H
#define A5_RUNTIME_PRELOAD_H
#include "runtime_encode.h"
#include "genxml/v4_pack.h"
#include <string.h>
typedef struct {unsigned format;const uint8_t*code;unsigned bytes,tag,regs;} A5PreloadShader;
#include "A5MaliPreloadData.inc"
enum {A5PreloadJob=0x1800,A5PreloadRSD=0x1900,A5PreloadPositions=0x1940,
 A5PreloadTexture=0x1980,A5PreloadTextureTable=0x19c0,A5PreloadSampler=0x19e0,
 A5PreloadViewport=0x1a00,A5PreloadVarying=0x1a20,A5PreloadVaryingBuffer=0x1a40,
 A5PreloadCode=0x1c00};
/* These are native descriptor requirements, not just CPU struct alignment.
 * Keep the entire reserved preload region before the blur vertex program. */
_Static_assert(A5PreloadJob % MALI_TILER_JOB_ALIGN == 0,"preload job alignment");
_Static_assert(A5PreloadRSD % MALI_RENDERER_STATE_ALIGN == 0,"preload RSD alignment");
_Static_assert(A5PreloadPositions % 64 == 0,"preload attribute data alignment");
_Static_assert(A5PreloadTexture % MALI_TEXTURE_ALIGN == 0,"preload texture alignment");
_Static_assert((A5PreloadTexture+MALI_TEXTURE_LENGTH) % MALI_SURFACE_WITH_STRIDE_ALIGN == 0,"preload surface alignment");
_Static_assert(A5PreloadTextureTable % 64 == 0,"preload texture table alignment");
_Static_assert(A5PreloadSampler % MALI_SAMPLER_ALIGN == 0,"preload sampler alignment");
_Static_assert(A5PreloadViewport % MALI_VIEWPORT_ALIGN == 0,"preload viewport alignment");
_Static_assert(A5PreloadVarying % MALI_ATTRIBUTE_ALIGN == 0,"preload varying alignment");
_Static_assert(A5PreloadVaryingBuffer % MALI_ATTRIBUTE_BUFFER_ALIGN == 0,"preload varying buffer alignment");
_Static_assert(A5PreloadCode % 64 == 0,"preload native shader alignment");
_Static_assert(A5PreloadJob+MALI_TILER_JOB_LENGTH <= A5PreloadRSD,"preload job/RSD overlap");
_Static_assert(A5PreloadRSD+MALI_RENDERER_STATE_LENGTH <= A5PreloadPositions,"preload RSD/positions overlap");
_Static_assert(A5PreloadPositions+16*sizeof(float) <= A5PreloadTexture,"preload positions/texture overlap");
_Static_assert(A5PreloadTexture+MALI_TEXTURE_LENGTH+MALI_SURFACE_WITH_STRIDE_LENGTH <= A5PreloadTextureTable,"preload texture/table overlap");
_Static_assert(A5PreloadTextureTable+sizeof(uint64_t) <= A5PreloadSampler,"preload table/sampler overlap");
_Static_assert(A5PreloadSampler+MALI_SAMPLER_LENGTH <= A5PreloadViewport,"preload sampler/viewport overlap");
_Static_assert(A5PreloadViewport+MALI_VIEWPORT_LENGTH <= A5PreloadVarying,"preload viewport/varying overlap");
_Static_assert(A5PreloadVarying+MALI_ATTRIBUTE_LENGTH <= A5PreloadVaryingBuffer,"preload varying/buffer overlap");
_Static_assert(A5PreloadVaryingBuffer+MALI_ATTRIBUTE_BUFFER_LENGTH <= A5PreloadCode,"preload buffer/code overlap");
_Static_assert(A5PreloadCode+0x400 <= 0x2000,"preload code/vertex program overlap");

static int a5_runtime_preload(uint8_t*d,uint64_t va,const A5RuntimeImage*im){
 const A5PreloadShader*s=NULL;unsigned fmt,sw=0x688;
 for(unsigned i=0;i<sizeof(a5_preload_shaders)/sizeof(a5_preload_shaders[0]);++i)
  if(a5_preload_shaders[i].format==im->metalPixelFormat)s=a5_preload_shaders+i;
 if(!s||s->bytes>0x400||s->tag!=5||!s->regs||s->regs>4)return A5RuntimeUnsupported;
 switch(im->metalPixelFormat){
 case 80:fmt=MALI_RGBA8_UNORM;sw=0x60a;break;
 case 10:fmt=MALI_R8_UNORM;sw=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9);break;
 case 30:fmt=MALI_RG8_UNORM;sw=MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9);break;
 case 55:fmt=MALI_R32F;sw=MALI_CHANNEL_R|(MALI_CHANNEL_0<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9);break;
 case 115:fmt=MALI_RGBA16F;break;default:return A5RuntimeUnsupported;
 }
 memcpy(d+A5PreloadCode,s->code,s->bytes);
 float coords[16]={0,0,0,1,(float)im->width,0,0,1,0,(float)im->height,0,1,(float)im->width,(float)im->height,0,1};
 memcpy(d+A5PreloadPositions,coords,sizeof(coords));
 pan_pack((struct mali_texture_packed*)(d+A5PreloadTexture),TEXTURE,c){
  c.width=im->width;c.height=im->height;c.array_size=1;c.levels=1;c.format=(fmt<<12)|sw;
  c.dimension=MALI_TEXTURE_DIMENSION_2D;c.texel_ordering=MALI_TEXTURE_LAYOUT_LINEAR;c.swizzle=0x688;
 }
 pan_pack((struct mali_surface_with_stride_packed*)(d+A5PreloadTexture+32),SURFACE_WITH_STRIDE,c){
  c.pointer=im->gpuVA;c.row_stride=im->rowBytes;c.surface_stride=im->rowBytes*im->height;
 }
 uint64_t tex=va+A5PreloadTexture;memcpy(d+A5PreloadTextureTable,&tex,8);
 pan_pack((struct mali_sampler_packed*)(d+A5PreloadSampler),SAMPLER,c){
  c.seamless_cube_map=false;c.normalized_coordinates=false;c.minify_nearest=true;c.magnify_nearest=true;
 }
 pan_pack((struct mali_attribute_packed*)(d+A5PreloadVarying),ATTRIBUTE,c){
  c.buffer_index=0;c.offset_enable=true;c.format=(MALI_RG32F<<12)|(MALI_CHANNEL_R|(MALI_CHANNEL_G<<3)|(MALI_CHANNEL_0<<6)|(MALI_CHANNEL_1<<9));
 }
 pan_pack((struct mali_attribute_buffer_packed*)(d+A5PreloadVaryingBuffer),ATTRIBUTE_BUFFER,c){
  c.pointer=va+A5PreloadPositions;c.stride=16;c.size=64;
 }
 pan_pack((struct mali_viewport_packed*)(d+A5PreloadViewport),VIEWPORT,c){c.scissor_maximum_x=im->width-1;c.scissor_maximum_y=im->height-1;}
 pan_pack((struct mali_renderer_state_packed*)(d+A5PreloadRSD),RENDERER_STATE,c){
  c.shader.shader=va+A5PreloadCode+s->tag;c.shader.varying_count=1;c.shader.texture_count=1;c.shader.sampler_count=1;
  c.properties.work_register_count=4;c.properties.force_early_z=true;
  c.multisample_misc.sample_mask=0xffff;c.multisample_misc.depth_function=MALI_FUNC_ALWAYS;
  c.stencil_mask_misc.alpha_test_compare_function=MALI_FUNC_ALWAYS;c.stencil_mask_misc.write_enable=true;c.stencil_mask_misc.dither_disable=true;
  c.blend_equation.rgb.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.rgb.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.rgb.c=MALI_BLEND_OPERAND_C_ZERO;
  c.blend_equation.alpha.a=MALI_BLEND_OPERAND_A_SRC;c.blend_equation.alpha.b=MALI_BLEND_OPERAND_B_SRC;c.blend_equation.alpha.c=MALI_BLEND_OPERAND_C_ZERO;c.blend_equation.color_mask=15;
 }
 pan_pack((struct mali_job_header_packed*)(d+A5PreloadJob),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=2;c.dependency_1=1;c.next=va+0x100;c.enable_texture_mapper=true;}
 pan_pack((struct mali_invocation_packed*)(d+A5PreloadJob+32),INVOCATION,c){c.invocations=3;c.workgroups_z_shift=32;c.thread_group_split=2;}
 pan_pack((struct mali_primitive_packed*)(d+A5PreloadJob+40),PRIMITIVE,c){c.draw_mode=MALI_DRAW_MODE_TRIANGLE_STRIP;c.index_count=4;c.job_task_split=6;}
 pan_pack((struct mali_draw_packed*)(d+A5PreloadJob+64),DRAW,c){
  c.position=va+A5PreloadPositions;c.viewport=va+A5PreloadViewport;c.varyings=va+A5PreloadVarying;c.varying_buffers=va+A5PreloadVaryingBuffer;
  c.textures=va+A5PreloadTextureTable;c.samplers=va+A5PreloadSampler;c.state=va+A5PreloadRSD;c.thread_storage=va+0x300;
 }
 pan_pack((struct mali_primitive_size_packed*)(d+A5PreloadJob+184),PRIMITIVE_SIZE,c){c.fixed_sized=1;}
 /* Existing application jobs already contain all draw state. Only replace
  * their headers to impose actual preload-before-draw ordering. */
 pan_pack((struct mali_job_header_packed*)d,JOB_HEADER,c){c.type=MALI_JOB_TYPE_VERTEX;c.index=1;c.next=va+A5PreloadJob;}
 pan_pack((struct mali_job_header_packed*)(d+0x100),JOB_HEADER,c){c.type=MALI_JOB_TYPE_TILER;c.index=3;c.dependency_1=1;c.dependency_2=2;c.enable_texture_mapper=true;}
 pan_pack((struct mali_job_header_packed*)(d+0x200),JOB_HEADER,c){c.type=MALI_JOB_TYPE_FRAGMENT;c.index=4;c.enable_texture_mapper=true;}
 return A5RuntimeOK;
}
#endif
