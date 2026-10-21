/* SPDX-License-Identifier: MIT
 * Original resource-operation shaders compiled by released Mesa26.2.4.
 * Copy samples integer bit-pattern views, then uses released v4 RAW framebuffer
 * packing. It never converts integer/float payloads through float arithmetic.
 * BGRA mip generation is a genuine four-texel center-scaled bilinear filter.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "compiler/glsl_types.h"
#include "compiler/nir/nir_builder.h"
#include "panfrost/compiler/pan_compiler.h"
#include "panfrost/compiler/pan_nir.h"
#include "util/format/u_formats.h"
static bool sysval(nir_builder*b,nir_intrinsic_instr*i,void*u){
 (void)u;b->cursor=nir_after_instr(&i->instr);nir_def*v=NULL;
 if(i->intrinsic==nir_intrinsic_load_viewport_scale||i->intrinsic==nir_intrinsic_load_viewport_offset)
  v=nir_load_ubo(b,3,32,nir_imm_int(b,0),nir_imm_int(b,i->intrinsic==nir_intrinsic_load_viewport_scale?0:16),.align_mul=16,.range=32);
 else if(i->intrinsic==nir_intrinsic_load_sampler_lod_parameters)v=nir_imm_vec3(b,0,INFINITY,0);
 if(!v)return false;nir_def_replace(&i->def,v);return true;
}
static nir_def*fetch(nir_builder*b,nir_def*coord,unsigned dim,bool integer){
 nir_tex_instr*t=nir_tex_instr_create(b->shader,2);t->dest_type=integer?nir_type_uint32:nir_type_float32;
 t->texture_index=0;t->sampler_index=0;t->sampler_dim=dim==1?GLSL_SAMPLER_DIM_1D:GLSL_SAMPLER_DIM_2D;t->op=nir_texop_txf;
 t->src[0]=nir_tex_src_for_ssa(nir_tex_src_coord,coord);t->coord_components=dim;
 t->src[1]=nir_tex_src_for_ssa(nir_tex_src_lod,nir_imm_int(b,0));
 nir_def_init(&t->instr,&t->def,4,32);nir_builder_instr_insert(b,&t->instr);return &t->def;
}
int main(int argc,char**argv){
 if(argc!=5)return 2;unsigned kind=strtoul(argv[1],NULL,10),bits=strtoul(argv[2],NULL,10),dim=strtoul(argv[3],NULL,10);
 /* kind0=quadVS,1=bitwise copyFS,2=BGRA mipFS */
 if(kind>2||(dim!=1&&dim!=2)||(kind==1&&bits!=8&&bits!=16&&bits!=32&&bits!=64)||(kind==2&&(bits!=32||dim!=2)))return 2;
 glsl_type_singleton_init_or_ref();mesa_shader_stage stage=kind?MESA_SHADER_FRAGMENT:MESA_SHADER_VERTEX;
 nir_builder b=nir_builder_init_simple_shader(stage,pan_get_nir_shader_compiler_options(4,stage,false),"a5_resource_%u_%u_%u",kind,bits,dim);
 if(!kind){
  nir_def*pos=nir_load_input(&b,4,32,nir_imm_int(&b,0),.base=0,.dest_type=nir_type_float32,.io_semantics.location=VERT_ATTRIB_GENERIC0,.io_semantics.num_slots=1);
  nir_def*uv=nir_load_input(&b,2,32,nir_imm_int(&b,0),.base=1,.dest_type=nir_type_float32,.io_semantics.location=VERT_ATTRIB_GENERIC1,.io_semantics.num_slots=1);
  nir_store_output(&b,pos,nir_imm_int(&b,0),.base=0,.src_type=nir_type_float32,.io_semantics.location=VARYING_SLOT_POS,.io_semantics.num_slots=1,.write_mask=15);
  nir_store_output(&b,nir_imm_float(&b,1),nir_imm_int(&b,0),.base=1,.src_type=nir_type_float32,.io_semantics.location=VARYING_SLOT_PSIZ,.io_semantics.num_slots=1,.write_mask=1);
  nir_store_output(&b,uv,nir_imm_int(&b,0),.base=2,.src_type=nir_type_float32,.io_semantics.location=VARYING_SLOT_VAR0,.io_semantics.num_slots=1,.write_mask=3);
 }else{
  nir_def*bary=nir_load_barycentric(&b,nir_intrinsic_load_barycentric_pixel,INTERP_MODE_SMOOTH);
  nir_def*uv=nir_load_interpolated_input(&b,2,32,bary,nir_imm_int(&b,0),.base=0,.dest_type=nir_type_float32,.io_semantics.location=VARYING_SLOT_VAR0,.io_semantics.num_slots=1);
  nir_def*coord=nir_f2i32(&b,dim==1?nir_channel(&b,uv,0):uv),*value;
  if(kind==1){
   value=fetch(&b,coord,dim,bits!=8);
   unsigned n=bits==64?2:1;value=nir_channels(&b,value,n==2?3:1);
   if(bits==16)value=nir_u2u16(&b,value);
   nir_store_output(&b,value,nir_imm_int(&b,0),.base=0,.src_type=bits==8?nir_type_float32:bits==16?nir_type_uint16:nir_type_uint32,.io_semantics.location=FRAG_RESULT_DATA0,.io_semantics.num_slots=1,.write_mask=(1<<n)-1);
  }else{
   nir_def*size=nir_load_ubo(&b,2,32,nir_imm_int(&b,0),nir_imm_int(&b,0),.align_mul=16,.range=16);
   nir_def*dst=nir_load_ubo(&b,2,32,nir_imm_int(&b,0),nir_imm_int(&b,8),.align_mul=8,.range=16);
   /* Actual Metal M4 mip generation and released util_blitter's linear scaled
    * blit use pixel centers. A fixed 2x2 average silently drops odd edges and
    * samples the wrong row at 97x3 -> 48x1. Keep the four real fetches, but
    * derive their weights from each actual source/destination level extent. */
   nir_def*location=nir_fadd_imm(&b,nir_fmul(&b,nir_fadd_imm(&b,nir_i2f32(&b,coord),.5),nir_fdiv(&b,nir_u2f32(&b,size),nir_u2f32(&b,dst))),-.5);
   nir_def*lo=nir_ffloor(&b,location),*fraction=nir_fsub(&b,location,lo);
   nir_def*base=nir_f2i32(&b,lo),*hi=nir_iadd_imm(&b,size,-1),*samples[2][2];
   for(unsigned y=0;y<2;y++)for(unsigned x=0;x<2;x++){
    nir_def*at=nir_imin(&b,nir_imax(&b,nir_iadd(&b,base,nir_imm_ivec2(&b,x,y)),nir_imm_ivec2(&b,0,0)),hi);
    samples[y][x]=fetch(&b,at,2,false);
   }
   nir_def*wx=nir_channel(&b,fraction,0),*wy=nir_channel(&b,fraction,1);
   nir_def*top=nir_fadd(&b,nir_fmul(&b,samples[0][0],nir_fsub(&b,nir_imm_float(&b,1),wx)),nir_fmul(&b,samples[0][1],wx));
   nir_def*bottom=nir_fadd(&b,nir_fmul(&b,samples[1][0],nir_fsub(&b,nir_imm_float(&b,1),wx)),nir_fmul(&b,samples[1][1],wx));
   value=nir_fadd(&b,nir_fmul(&b,top,nir_fsub(&b,nir_imm_float(&b,1),wy)),nir_fmul(&b,bottom,wy));
   nir_store_output(&b,value,nir_imm_int(&b,0),.base=0,.src_type=nir_type_float32,.io_semantics.location=FRAG_RESULT_DATA0,.io_semantics.num_slots=1,.write_mask=15);
  }
 }
 nir_shader_gather_info(b.shader,nir_shader_get_entrypoint(b.shader));if(kind)BITSET_SET(b.shader->info.textures_used,0);
 struct pan_compile_inputs in={.gpu_id=0x07201000,.is_blit=true,.no_idvs=true};struct pan_shader_info info={0};struct util_dynarray binary=UTIL_DYNARRAY_INIT;
 struct pan_varying_layout varying_layout;
 if(!kind){pan_varying_collect_formats(&varying_layout,b.shader,in.gpu_id,false,false);pan_build_varying_layout_compact(&varying_layout,b.shader,in.gpu_id);in.varying_layout=&varying_layout;}
 pan_preprocess_nir(b.shader,in.gpu_id);
 if(kind==1&&bits!=8){const enum pipe_format formats[8]={bits==8?PIPE_FORMAT_R8_UINT:bits==16?PIPE_FORMAT_R16_UINT:bits==32?PIPE_FORMAT_R32_UINT:PIPE_FORMAT_R32G32_UINT};NIR_PASS(_,b.shader,pan_nir_lower_framebuffer,formats,1,1,false);}
 pan_postprocess_nir(b.shader,&in,&info);NIR_PASS(_,b.shader,nir_shader_intrinsics_pass,sysval,nir_metadata_control_flow,NULL);
 nir_validate_shader(b.shader,"resource operation native sysvals");pan_shader_compile(b.shader,&in,&binary,&info);
 if(!binary.size||binary.size>4096||info.tls_size||info.wls_size)return 2;
 FILE*f=fopen(argv[4],"wb");if(!f)return 2;int ok=fwrite(binary.data,1,binary.size,f)==binary.size&&!fclose(f);
 printf("kind=%u bits=%u dim=%u bytes=%u tag=%u regs=%u tls=%u wls=%u textures=%u samplers=%u ubos=%u attributes=%u varyings=%u\n",kind,bits,dim,binary.size,info.midgard.first_tag,info.work_reg_count,info.tls_size,info.wls_size,info.texture_count,info.sampler_count,info.ubo_count,info.attribute_count,info.varyings.formats.count);
 util_dynarray_fini(&binary);ralloc_free(b.shader);glsl_type_singleton_decref();return !ok;
}
