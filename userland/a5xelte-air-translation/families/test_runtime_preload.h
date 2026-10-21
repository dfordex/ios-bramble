/* SPDX-License-Identifier: MIT */
#ifndef A5_TEST_RUNTIME_PRELOAD_H
#define A5_TEST_RUNTIME_PRELOAD_H
#include "runtime_preload.h"
#include <assert.h>
static void check_preload(const uint8_t*d,uint64_t va,const A5RuntimeImage*im){
 pan_unpack((const struct mali_job_header_packed*)d,JOB_HEADER,vs);
 pan_unpack((const struct mali_job_header_packed*)(d+0x1800),JOB_HEADER,pre);
 pan_unpack((const struct mali_job_header_packed*)(d+0x100),JOB_HEADER,main);
 pan_unpack((const struct mali_job_header_packed*)(d+0x200),JOB_HEADER,frag);
 pan_unpack((const struct mali_draw_packed*)(d+A5PreloadJob+MALI_TILER_JOB_SECTION_DRAW_OFFSET),DRAW,draw);
 assert(draw.samplers==va+A5PreloadSampler&&draw.samplers%MALI_SAMPLER_ALIGN==0);
 assert(draw.state%MALI_RENDERER_STATE_ALIGN==0&&draw.varyings%MALI_ATTRIBUTE_ALIGN==0&&draw.varying_buffers%MALI_ATTRIBUTE_BUFFER_ALIGN==0&&draw.viewport%MALI_VIEWPORT_ALIGN==0);
 assert(vs.index==1&&vs.next==va+0x1800&&pre.type==MALI_JOB_TYPE_TILER&&pre.index==2&&pre.dependency_1==1&&pre.next==va+0x100);
 assert(main.index==3&&main.dependency_1==1&&main.dependency_2==2&&frag.index==4);
 pan_unpack((const struct mali_surface_with_stride_packed*)(d+0x19a0),SURFACE_WITH_STRIDE,s);
 assert(s.pointer==im->gpuVA&&s.row_stride==im->rowBytes&&s.surface_stride==im->rowBytes*im->height);
 pan_unpack((const struct mali_sampler_packed*)(d+A5PreloadSampler),SAMPLER,samp);
 assert(!samp.normalized_coordinates&&samp.minify_nearest&&samp.magnify_nearest);
 pan_unpack((const struct mali_renderer_state_packed*)(d+0x1900),RENDERER_STATE,rs);
 assert(rs.shader.shader==va+0x1c05&&rs.shader.texture_count==1&&rs.shader.sampler_count==1&&rs.shader.varying_count==1&&!rs.multisample_misc.load_destination);
 const A5PreloadShader*p=NULL;for(unsigned i=0;i<sizeof(a5_preload_shaders)/sizeof(a5_preload_shaders[0]);++i)if(a5_preload_shaders[i].format==im->metalPixelFormat)p=a5_preload_shaders+i;
 assert(p&&!memcmp(d+0x1c00,p->code,p->bytes));
 pan_section_unpack(d+0x300,FRAMEBUFFER,PARAMETERS,fb);
 assert(!fb.color_preload_enable&&!fb.color_load_address&&!fb.color_load_row_stride&&!fb.color_load_surface_stride&&!fb.clean_pixel_write_enable);
 float positions[16];memcpy(positions,d+0x1940,64);assert(positions[4]==im->width&&positions[9]==im->height&&positions[12]==im->width&&positions[13]==im->height);
}
#endif
