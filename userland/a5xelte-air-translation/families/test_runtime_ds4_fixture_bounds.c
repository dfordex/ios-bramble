/* SPDX-License-Identifier: MIT
 * Decode actual emitted DS4 GPU descriptors and reject any reachable external
 * address. A physical fixture has exactly one mapped BO02000000..02040000.
 * This validates the preload job as well as the application draw/writeback.
 */
#define PAN_ARCH 4
#include "runtime_encode.h"
#include "genxml/v4_pack.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned char bytes[A5RuntimeJobBytes];
static int bad;
static int range(const char *name,uint64_t address,uint64_t count){
 const uint64_t base=0x02000000,end=base+A5RuntimeJobBytes;
 if(!count||address<base||address>=end||count>end-address){
  fprintf(stderr,"unmapped fixture GPU range %s:0x%llx+0x%llx\n",name,
   (unsigned long long)address,(unsigned long long)count);bad=1;return 0;
 }return 1;
}
static void draw(unsigned off){
 pan_unpack((struct mali_draw_packed*)(bytes+off),DRAW,d);
 range("draw-state",d.state,MALI_RENDERER_STATE_LENGTH);
 if(d.attributes)range("draw-attributes",d.attributes,MALI_ATTRIBUTE_LENGTH);
 if(d.attribute_buffers)range("draw-attribute-buffers",d.attribute_buffers,MALI_ATTRIBUTE_BUFFER_LENGTH);
 if(d.uniform_buffers)range("draw-UBO-table",d.uniform_buffers,8*8);
 if(d.position)range("draw-positions",d.position,64);
 if(d.viewport)range("draw-viewport",d.viewport,MALI_VIEWPORT_LENGTH);
 if(d.varyings)range("draw-varyings",d.varyings,MALI_ATTRIBUTE_LENGTH);
 if(d.varying_buffers)range("draw-varying-buffers",d.varying_buffers,MALI_ATTRIBUTE_BUFFER_LENGTH);
 if(d.textures)range("draw-texture-table",d.textures,8);
 if(d.samplers)range("draw-sampler",d.samplers,MALI_SAMPLER_LENGTH);
 if(d.thread_storage)range("draw-thread-storage",d.thread_storage,MALI_FRAMEBUFFER_LENGTH);
}
int main(int argc,char **argv){
 if(argc!=2)return 2;FILE *f=fopen(argv[1],"rb");if(!f)return 2;
 if(fread(bytes,1,sizeof(bytes),f)!=sizeof(bytes)||fgetc(f)!=EOF)return 2;fclose(f);
 draw(64);draw(0x140);draw(0x1840);
 pan_unpack((struct mali_job_header_packed*)bytes,JOB_HEADER,vertex);
 pan_unpack((struct mali_job_header_packed*)(bytes+0x1800),JOB_HEADER,pre);
 pan_unpack((struct mali_job_header_packed*)(bytes+0x100),JOB_HEADER,app);
 if(vertex.next!=0x02001800||pre.next!=0x02000100||pre.index!=2||
    app.dependency_2!=2){fputs("preload dependency chain changed\n",stderr);bad=1;}
 const unsigned surfaces[]={0x620,0x19a0};
 for(unsigned i=0;i<2;++i){
  pan_unpack((struct mali_surface_with_stride_packed*)(bytes+surfaces[i]),SURFACE_WITH_STRIDE,s);
  range(i?"preload-destination-texture":"application-source-texture",s.pointer,s.surface_stride);
  if(s.pointer!=(i?0x0203e000:0x0203a000)||s.row_stride!=(i?128:256)||s.surface_stride!=(i?4096:16384))bad=1;
 }
 pan_section_unpack(bytes+0x300,FRAMEBUFFER,PARAMETERS,fb);
 range("framebuffer-writeback",fb.color_writeback.base,fb.color_writeback.row_stride*32);
 if(fb.color_writeback.base!=0x0203e000||fb.color_preload_enable||fb.color_load_address||
    fb.color_load_row_stride||fb.color_load_surface_stride||fb.clean_pixel_write_enable)bad=1;
 pan_section_unpack(bytes+0x300,FRAMEBUFFER,TILER,t);
 range("tiler-polygon-list",t.polygon_list,t.polygon_list_size);
 range("tiler-polygon-body",t.polygon_list_body,512);
 range("tiler-heap",t.heap_start,t.heap_end-t.heap_start);
 for(unsigned stage=0;stage<2;++stage)for(unsigned slot=0;slot<8;++slot){
  pan_unpack((struct mali_uniform_buffer_packed*)(bytes+(stage?0x740:0x700)+slot*8),UNIFORM_BUFFER,u);
  range("uniform-buffer",u.pointer,u.entries*16);
 }
 const unsigned buffers[]={0x840,0x8c0,0x8d0,0x8e0,0x980,0x1a40};
 for(unsigned i=0;i<sizeof(buffers)/sizeof(*buffers);++i){
  pan_unpack((struct mali_attribute_buffer_packed*)(bytes+buffers[i]),ATTRIBUTE_BUFFER,a);
  range("attribute-or-varying-buffer",a.pointer,a.size);
 }
 const unsigned tables[]={0x660,0x19c0};
 for(unsigned i=0;i<2;++i){uint64_t address;memcpy(&address,bytes+tables[i],8);
  range("texture-descriptor",address,MALI_TEXTURE_LENGTH+MALI_SURFACE_WITH_STRIDE_LENGTH);
  if(address!=(i?0x02001980:0x02000600))bad=1;
 }
 pan_unpack((struct mali_fragment_job_payload_packed*)(bytes+0x220),FRAGMENT_JOB_PAYLOAD,fragment);
 range("fragment-framebuffer",fragment.framebuffer,MALI_FRAMEBUFFER_LENGTH);
 const unsigned states[]={0x500,0x540,0x1900};
 for(unsigned i=0;i<3;++i){
  pan_unpack((struct mali_renderer_state_packed*)(bytes+states[i]),RENDERER_STATE,r);
  range("native-shader",r.shader.shader&~UINT64_C(15),16);
 }
 pan_unpack((struct mali_primitive_packed*)(bytes+0x128),PRIMITIVE,p);
 unsigned width=p.index_type==MALI_INDEX_TYPE_UINT16?2:p.index_type==MALI_INDEX_TYPE_UINT32?4:0;
 if(!width||p.index_count!=6)bad=1;
 else range("index-stream",p.indices,p.index_count*width);
 if(bad)return 1;
 puts("PASS actual DS4 preload/draw/FB/UBO/code/index GPU ranges all inside single mapped fixture BO; direct SFBD load aliases zero");return 0;
}
