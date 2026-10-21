/* SPDX-License-Identifier: MIT
 * Native v4 RAW64 framebuffer conversion, following Mesa26.2.4
 * pan_nir_lower_framebuffer.c:pan_pack_pure_16/pan_lower_fb_store and
 * pan_desc.c:pan_sfbd_raw_format. This preserves actual half4 shader values,
 * packing RG/BA into two32-bit words for RAW_VALUE/2_32B_CHANNELS SFBD.
 */
#ifndef A5_MISC_NATIVE_RT_H
#define A5_MISC_NATIVE_RT_H
#include "panfrost/compiler/pan_nir.h"
#include "util/format/u_formats.h"

static bool
a5_half_color_store(nir_builder *b,nir_intrinsic_instr *intr,void *unused)
{
   (void)unused;
   if(intr->intrinsic!=nir_intrinsic_store_output)return false;
   nir_io_semantics sem=nir_intrinsic_io_semantics(intr);
   if(sem.location!=FRAG_RESULT_DATA0)return false;
   b->cursor=nir_before_instr(&intr->instr);
   nir_def *half=nir_f2f16(b,intr->src[0].ssa);
   nir_src_rewrite(&intr->src[0],half);
   nir_intrinsic_set_src_type(intr,nir_type_float16);
   return true;
}

static void
a5_lower_native_rgba16(nir_shader *shader)
{
   const enum pipe_format formats[8]={PIPE_FORMAT_R16G16B16A16_FLOAT};
   NIR_PASS(_,shader,nir_shader_intrinsics_pass,a5_half_color_store,
            nir_metadata_control_flow,NULL);
   /* nr_samples=1 enables the released store-conversion path; inputs->is_blend
    * staysfalse so ordinary fragment varying loads remain ordinary loads.
    * No blending equation or different logical fragment function is installed. */
   NIR_PASS(_,shader,pan_nir_lower_framebuffer,formats,1,1,false);
   nir_validate_shader(shader,"native RGBA16 RAW64 packing");
}
#endif
