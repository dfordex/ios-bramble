/* SPDX-License-Identifier: MIT
 * Real compiled-shader/descriptor contract tests, no GPU execution assertion.
 */
#define PAN_ARCH 4
#include "runtime_resource_ops.h"
#include "genxml/v4_pack.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t out[A5RuntimeJobBytes];
static void zeroed(void){for(unsigned i=0;i<sizeof(out);i++)assert(!out[i]);}
static A5RuntimeResourceOp request(unsigned format,unsigned n,unsigned type){
 A5RuntimeResourceOp r={.descriptorGPUVA=0x18000000,.source={0x03000000,4096,64,type==0?1:8,64*n,format},
 .destination={0x04000000,4096,64,type==0?1:8,64*n,format},.sourceType=type,.destinationType=type,
 .sourceX=3,.sourceY=0,.destinationX=5,.destinationY=0,.width=48,.height=type==0?1:8};return r;
}
int main(void){
 unsigned formats[]={10,30,43,23,25,55,80,105,115},sizes[]={1,2,2,2,2,4,4,8,8};
 for(unsigned i=0;i<9;i++)for(unsigned dim=0;dim<=2;dim+=2){
 A5RuntimeResourceOp r=request(formats[i],sizes[i],dim);
 assert(A5MaliEncodeRuntimeResourceOp(&r,out,sizeof(out))==A5RuntimeOK);
 pan_unpack((struct mali_job_header_packed*)out,JOB_HEADER,v);
 pan_unpack((struct mali_job_header_packed*)(out+0x1800),JOB_HEADER,p);
 pan_unpack((struct mali_job_header_packed*)(out+0x100),JOB_HEADER,t);
 pan_unpack((struct mali_job_header_packed*)(out+0x200),JOB_HEADER,f);
 assert(v.type==MALI_JOB_TYPE_VERTEX&&v.next==r.descriptorGPUVA+0x1800&&v.index==1);
 assert(p.type==MALI_JOB_TYPE_TILER&&p.next==r.descriptorGPUVA+0x100&&p.index==2&&p.dependency_1==1);
 assert(t.index==3&&t.dependency_1==1&&t.dependency_2==2&&f.index==4);
 pan_unpack((struct mali_texture_packed*)(out+0x600),TEXTURE,tex);
 assert(tex.dimension==(dim?MALI_TEXTURE_DIMENSION_2D:MALI_TEXTURE_DIMENSION_1D)&&tex.width==64&&tex.height==r.source.height);
 pan_unpack((struct mali_surface_with_stride_packed*)(out+0x620),SURFACE_WITH_STRIDE,s);
 assert(s.pointer==r.source.gpuVA&&s.row_stride==r.source.rowBytes);
 pan_unpack((struct mali_framebuffer_parameters_packed*)(out+0x320),FRAMEBUFFER_PARAMETERS,fb);
 assert(fb.color_writeback.base==r.destination.gpuVA&&!fb.color_preload_enable&&!fb.color_load_address);
 assert(fb.color_writeback_format==(sizes[i]==1?MALI_COLOR_FORMAT_R8:sizes[i]==2?MALI_COLOR_FORMAT_1_16B_CHANNEL:sizes[i]==4?MALI_COLOR_FORMAT_1_32B_CHANNEL:MALI_COLOR_FORMAT_2_32B_CHANNELS));
 r.width=64;r.sourceX=r.destinationX=0;assert(A5MaliEncodeRuntimeResourceOp(&r,out,sizeof(out))==A5RuntimeOK);
 pan_unpack((struct mali_job_header_packed*)out,JOB_HEADER,full);assert(full.next==r.descriptorGPUVA+0x100);
 r.source.width=0;assert(A5MaliEncodeRuntimeResourceOp(&r,out,sizeof(out))!=A5RuntimeOK);zeroed();
 }
 A5RuntimeResourceOp m=request(80,4,2);m.operation=A5ResourceGenerateMip;m.destination.width=32;m.destination.height=4;m.destination.rowBytes=128;m.width=32;m.height=4;m.sourceX=m.destinationX=0;
 assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))==A5RuntimeOK);
 pan_unpack((struct mali_renderer_state_packed*)(out+0x540),RENDERER_STATE,fs);assert(fs.shader.shader==m.descriptorGPUVA+0x3005&&fs.shader.texture_count==1);
 m.source.metalPixelFormat=m.destination.metalPixelFormat=43;assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))!=A5RuntimeOK);zeroed();
 m=request(55,4,0);m.destination.gpuVA=m.source.gpuVA;assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))!=A5RuntimeOK);zeroed();
 m=request(55,4,0);m.source.gpuVA=m.descriptorGPUVA+4096;assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))!=A5RuntimeOK);zeroed();
 m=request(55,4,0);m.sourceX=63;assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))!=A5RuntimeOK);zeroed();
 m=request(55,4,0);m.destination.rowBytes=1;assert(A5MaliEncodeRuntimeResourceOp(&m,out,sizeof(out))!=A5RuntimeOK);zeroed();
 puts("PASS 18 real typed copy descriptor contracts (1D/2D), mip topology, raw packing, preload ordering, bounds/alias/unsupported failures zero output; no GPU execution claim");return 0;
}
