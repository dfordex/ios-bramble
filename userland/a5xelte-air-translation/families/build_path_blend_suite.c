/* SPDX-License-Identifier: MIT
 * Actual native shader + nonzero destination tests. Reuses the independently
 * device-tested geometry only, with real tilebuffer blend shaders supplied by
 * the caller. No expected pixels are written into the GPU output allocation.
 */
#define main a5_copy_geometry_main
#include "build_path_suite.c"
#undef main
#include "runtime_preload.h"
int main(int argc,char **argv) {
 if(argc!=7)return 2;
 int rc=a5_copy_geometry_main(argc,argv);if(rc)return rc;
 int stroke=!strcmp(argv[1],"stroke");
 struct MALI_FRAMEBUFFER_PARAMETERS fb;
 MALI_FRAMEBUFFER_PARAMETERS_unpack((const struct mali_framebuffer_parameters_packed*)(d+FB+MALI_FRAMEBUFFER_SECTION_PARAMETERS_OFFSET),&fb);
 fb.color_preload_enable=false;fb.clean_pixel_write_enable=false;
 fb.color_load_address=fb.color_load_row_stride=fb.color_load_surface_stride=0;
 fb.clear_color_0=fb.clear_color_1=fb.clear_color_2=fb.clear_color_3=0;
 MALI_FRAMEBUFFER_PARAMETERS_pack((struct mali_framebuffer_parameters_packed*)(d+FB+MALI_FRAMEBUFFER_SECTION_PARAMETERS_OFFSET),&fb);
 struct MALI_RENDERER_STATE rs;MALI_RENDERER_STATE_unpack((const struct mali_renderer_state_packed*)(d+FRS),&rs);
 rs.properties.force_early_z=false;rs.multisample_misc.load_destination=true;
 MALI_RENDERER_STATE_pack((struct mali_renderer_state_packed*)(d+FRS),&rs);
 /* Nonzero exactly representable old destination. Stroke source alpha .5
  * and premultiplied RGB(.125,.25,.375) distinguish source-over from copy. */
 for(unsigned i=0;i<1024;++i) {
  if(stroke){const uint16_t v[4]={0x3400,0x3000,0x3800,0x3800};memcpy(d+OUT+i*8,v,8);}
  else f32(OUT+i*4,.25f);
 }
 if(stroke){f32(AUX,.125f);f32(AUX+4,.25f);f32(AUX+8,.375f);f32(AUX+12,.5f);}
 A5RuntimeImage im={base+OUT,stroke?8192u:4096u,32,32,stroke?256u:128u,stroke?115u:55u};
 if(a5_runtime_preload(d,base,&im))return 2;
 FILE*f=fopen(argv[6],"wb");if(!f)return 1;int ok=fwrite(d,1,N,f)==N;return fclose(f)||!ok;
}
