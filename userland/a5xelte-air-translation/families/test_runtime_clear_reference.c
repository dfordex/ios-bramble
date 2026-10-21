/* SPDX-License-Identifier: MIT
 * Host-only adapter to the unmodified external released Mesa reference.
 */
#define PAN_ARCH 4
#include "pan_format.h"
#include "pan_util.h"
#include <assert.h>
void a5_test_mesa_clear_pack(unsigned, const double *, uint32_t *);
void a5_test_mesa_clear_pack(unsigned metal,const double*values,uint32_t*packed){
 struct pan_blendable_format formats[PIPE_FORMAT_COUNT]={0};enum pipe_format pipe;
 switch(metal){
 case 80:pipe=PIPE_FORMAT_B8G8R8A8_UNORM;break;
 case 10:pipe=PIPE_FORMAT_R8_UNORM;break;
 case 30:pipe=PIPE_FORMAT_R8G8_UNORM;break;
 case 55:pipe=PIPE_FORMAT_R32_FLOAT;break;
 case 115:pipe=PIPE_FORMAT_R16G16B16A16_FLOAT;break;
 default:assert(0);return;
 }
 if(metal==80||metal==10||metal==30)formats[pipe].internal=MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
 union pipe_color_union color;for(unsigned i=0;i<4;++i)color.f[i]=(float)values[i];
 pan_pack_color(formats,packed,&color,pipe,false);
}
