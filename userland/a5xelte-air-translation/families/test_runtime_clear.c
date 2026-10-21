/* SPDX-License-Identifier: MIT
 * Compare actual clear constants against released Mesa pan_pack_color;
 * structural job tests do not assert GPU execution.
 */
#define PAN_ARCH 4
#include "runtime_clear.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "genxml/v4_pack.h"
void a5_test_mesa_clear_pack(unsigned, const double *, uint32_t *);
static uint8_t out[A5RuntimeJobBytes];
int main(void){
 const unsigned metal[9]={80,10,30,55,115,43,23,25,105},bpp[9]={4,1,2,4,8,2,2,2,8};
 const double colors[][4]={{.25,.5,.75,1},{.5/255,1.5/255,2.5/255,3.5/255},{-.25,2,60000,.1}};
 unsigned passed=0;
 for(unsigned f=0;f<9;++f)for(unsigned v=0;v<3;++v){
  A5RuntimeClear clear={.descriptorGPUVA=0x12000000,
   .destination={0x21000000,0x800000,64,128,64*bpp[f],metal[f]}};
  memcpy(clear.color,colors[v],sizeof(clear.color));
  if(metal[f]==23)clear.color[0]=(double)(v*32767);
  assert(A5MaliEncodeRuntimeClear(&clear,out,sizeof(out))==A5RuntimeOK);
  uint32_t expected[4];a5_test_mesa_clear_pack(metal[f],clear.color,expected);
  pan_unpack((struct mali_framebuffer_parameters_packed*)(out+0x320),FRAMEBUFFER_PARAMETERS,fb);
  assert(fb.clear_color_0==expected[0]&&fb.clear_color_1==expected[1]&&fb.clear_color_2==expected[2]&&fb.clear_color_3==expected[3]);
  assert(fb.clean_pixel_write_enable&&!fb.color_preload_enable&&fb.color_write_enable&&fb.color_writeback.base==clear.destination.gpuVA);
  pan_unpack((struct mali_tiler_context_packed*)(out+0x3c0),TILER_CONTEXT,t);
  assert(t.hierarchy_mask==MALI_MIDGARD_TILER_USER&&t.polygon_list_size==516&&t.heap_start==t.heap_end);
  pan_unpack((struct mali_job_header_packed*)out,JOB_HEADER,job);
  assert(job.type==MALI_JOB_TYPE_FRAGMENT&&!job.next);
  ++passed;
 }
 puts("PASS 27 clear constants equal released Mesa pan_pack_color across nine formats; true fragment-only/disabled-tiler descriptors (no GPU claim)");
 assert(passed==27);return 0;
}
