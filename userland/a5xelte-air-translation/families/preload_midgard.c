/* Copyright (C) 2020-2021 Collabora, Ltd.
 * SPDX-License-Identifier: MIT
 * Released Mesa26.2.4 pan_fb_preload.c's v4 colour preload NIR contract:
 * interpolated screen coordinates -> unnormalized nearest texture -> tilebuffer.
 * This shader has no Apple input, constants, uniform state, or CPU pixel loop.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "compiler/glsl_types.h"
#include "compiler/nir/nir_builder.h"
#include "panfrost/compiler/pan_compiler.h"
#include "misc_native_rt.h"
static bool lod(nir_builder*b,nir_intrinsic_instr*i,void*u){
 (void)u;if(i->intrinsic!=nir_intrinsic_load_sampler_lod_parameters)return false;
 b->cursor=nir_after_instr(&i->instr);nir_def_rewrite_uses(&i->def,nir_imm_vec3(b,0,INFINITY,0));return true;
}
int main(int argc,char**argv){
 if(argc!=3)return 2;unsigned format=strtoul(argv[1],NULL,10);
 if(format!=80&&format!=10&&format!=30&&format!=55&&format!=115)return 2;
 glsl_type_singleton_init_or_ref();
 nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_FRAGMENT,
  pan_get_nir_shader_compiler_options(4,MESA_SHADER_FRAGMENT,false),"a5_v4_colour_preload_%u",format);
 nir_def*bary=nir_load_barycentric(&b,nir_intrinsic_load_barycentric_pixel,INTERP_MODE_SMOOTH);
 nir_def*coord=nir_load_interpolated_input(&b,2,32,bary,nir_imm_int(&b,0),.base=0,
  .dest_type=nir_type_float32,.io_semantics.location=VARYING_SLOT_VAR0,.io_semantics.num_slots=1);
 nir_tex_instr*t=nir_tex_instr_create(b.shader,1);t->dest_type=nir_type_float32;
 t->texture_index=t->sampler_index=0;t->sampler_dim=GLSL_SAMPLER_DIM_2D;t->op=nir_texop_txl;
 t->src[0]=nir_tex_src_for_ssa(nir_tex_src_coord,coord);t->coord_components=2;
 nir_def_init(&t->instr,&t->def,4,32);nir_builder_instr_insert(&b,&t->instr);
 nir_store_output(&b,&t->def,nir_imm_int(&b,0),.base=0,.src_type=nir_type_float32,
  .io_semantics.location=FRAG_RESULT_DATA0,.io_semantics.num_slots=1,.write_mask=15);
 nir_shader_gather_info(b.shader,nir_shader_get_entrypoint(b.shader));BITSET_SET(b.shader->info.textures_used,0);
 struct pan_compile_inputs in={.gpu_id=0x07201000,.is_blit=true,.no_idvs=true};
 struct pan_shader_info info={0};struct util_dynarray binary=UTIL_DYNARRAY_INIT;
 pan_preprocess_nir(b.shader,in.gpu_id);
 if(format==115)a5_lower_native_rgba16(b.shader);
 else if(format==55){const enum pipe_format f[8]={PIPE_FORMAT_R32_FLOAT};NIR_PASS(_,b.shader,pan_nir_lower_framebuffer,f,1,1,false);}
 pan_postprocess_nir(b.shader,&in,&info);
 NIR_PASS(_,b.shader,nir_shader_intrinsics_pass,lod,nir_metadata_control_flow,NULL);
 nir_validate_shader(b.shader,"released v4 preload");pan_shader_compile(b.shader,&in,&binary,&info);
 if(!binary.size||binary.size>1024||info.tls_size||info.wls_size)return 2;
 FILE*f=fopen(argv[2],"wb");if(!f)return 2;int ok=fwrite(binary.data,1,binary.size,f)==binary.size&&!fclose(f);
 printf("format=%u bytes=%u tag=%u regs=%u tls=%u wls=%u textures=%u samplers=%u\n",format,binary.size,info.midgard.first_tag,info.work_reg_count,info.tls_size,info.wls_size,info.texture_count,info.sampler_count);
 util_dynarray_fini(&binary);ralloc_free(b.shader);glsl_type_singleton_decref();return !ok;
}
