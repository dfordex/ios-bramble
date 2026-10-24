/* SPDX-License-Identifier: MIT
 * Compile beside misc_backend.c against the pinned, assertion-enabled Mesa.
 * The allocator and lowering below are the production functions themselves.
 */
int a5_backend_main(int argc,char **argv);
#define main a5_backend_main
#include "../families/misc_backend.c"
#undef main
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static nir_builder fixture(unsigned count,bool keep_color,bool position)
{
   nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_FRAGMENT,
      pan_get_nir_shader_compiler_options(4,MESA_SHADER_FRAGMENT,false),"FragCoord varying ABI");
   nir_def *sum=nir_imm_vec4(&b,0,0,0,0);
   for(unsigned i=0;i<count;i++){
      nir_def *v=nir_load_input(&b,4,32,nir_imm_int(&b,0),.base=i,
         .io_semantics.location=VARYING_SLOT_VAR0+i,.io_semantics.num_slots=1,
         .dest_type=nir_type_float32);
      if(keep_color || i==0)sum=nir_fadd(&b,sum,v);
   }
   if(position)sum=nir_fadd(&b,sum,nir_load_frag_coord(&b));
   nir_store_output(&b,sum,nir_imm_int(&b,0),.base=0,.write_mask=15,
      .io_semantics.location=FRAG_RESULT_DATA0,.io_semantics.num_slots=1,
      .src_type=nir_type_float32);
   return b;
}
static unsigned position_base(nir_shader *nir)
{
   unsigned found=UINT32_MAX;
   nir_foreach_function_impl(impl,nir){nir_foreach_block(block,impl){nir_foreach_instr(instr,block){
      if(instr->type!=nir_instr_type_intrinsic)continue;
      nir_intrinsic_instr *in=nir_instr_as_intrinsic(instr);
      if(in->intrinsic==nir_intrinsic_load_input &&
         nir_intrinsic_io_semantics(in).location==VARYING_SLOT_POS){
         assert(found==UINT32_MAX || found==nir_intrinsic_base(in));
         found=nir_intrinsic_base(in);
      }
   }}}
   return found;
}
static void positive(unsigned inputs,bool keep_color)
{
   nir_builder b=fixture(inputs,keep_color,true);
   struct a5_fragcoord_lowering layout={0};
   assert(a5_fragcoord_layout(b.shader,&layout));
   assert(layout.base==inputs);
   /* Original declared extent survives removal of inactive generic inputs. */
   NIR_PASS(_,b.shader,nir_opt_dce);
   NIR_PASS(_,b.shader,nir_shader_intrinsics_pass,lower_fragcoord,
      nir_metadata_control_flow,&layout);
   NIR_PASS(_,b.shader,nir_opt_dce);
   nir_validate_shader(b.shader,"noncolliding FragCoord input");
   assert(position_base(b.shader)==inputs);
   struct pan_varying_layout varyings;
   pan_varying_collect_formats(&varyings,b.shader,0x07201000,false,false);
   pan_build_varying_layout_compact(&varyings,b.shader,0x07201000);
   assert(varyings.slots[inputs].location==VARYING_SLOT_POS);
   assert(varyings.slots[inputs].section==PAN_VARYING_SECTION_SPECIAL);
   ralloc_free(b.shader);
}
static void derivative(nir_intrinsic_op op,unsigned bits,struct util_dynarray *binary)
{
   nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_FRAGMENT,
      pan_get_nir_shader_compiler_options(4,MESA_SHADER_FRAGMENT,false),"Midgard derivative ABI");
   nir_def *source=nir_load_input(&b,4,32,nir_imm_int(&b,0),.base=0,
      .io_semantics.location=VARYING_SLOT_VAR0,.io_semantics.num_slots=1,
      .dest_type=nir_type_float32);
   if(bits==16)source=nir_f2f16(&b,source);
   nir_def *value=nir_build_deriv(&b,source,op);
   if(bits==16)value=nir_f2f32(&b,value);
   nir_store_output(&b,value,nir_imm_int(&b,0),.base=0,.write_mask=15,
      .io_semantics.location=FRAG_RESULT_DATA0,.io_semantics.num_slots=1,
      .src_type=nir_type_float32);
   struct lowering ctx={0};
   NIR_PASS(_,b.shader,nir_shader_intrinsics_pass,lower_derivative,
      nir_metadata_control_flow,&ctx);
   assert(!ctx.invalid);
   nir_validate_shader(b.shader,"released Midgard derivative spelling");
   nir_shader_gather_info(b.shader,nir_shader_get_entrypoint(b.shader));
   struct pan_compile_inputs inputs={.gpu_id=0x07201000,.is_blit=true,.no_idvs=true};
   struct pan_shader_info native={0};
   pan_preprocess_nir(b.shader,inputs.gpu_id);
   pan_postprocess_nir(b.shader,&inputs,&native);
   pan_shader_compile(b.shader,&inputs,binary,&native);
   struct a5_dynamic_profile profile={0};struct a5_dynamic_info info={0};
   assert(a5_dynamic_analyze(b.shader,&profile,&info));
   assert(binary->size && !native.tls_size && !native.wls_size);
   ralloc_free(b.shader);
}
int main(void)
{
   glsl_type_singleton_init_or_ref();
   /* Genuine release collector reproduces the old alias assertion. */
   pid_t child=fork();assert(child>=0);
   if(!child){
      struct rlimit no_core={0,0};setrlimit(RLIMIT_CORE,&no_core);
      nir_builder b=fixture(3,true,true);
      struct a5_fragcoord_lowering old={.base=2};
      NIR_PASS(_,b.shader,nir_shader_intrinsics_pass,lower_fragcoord,
         nir_metadata_control_flow,&old);
      NIR_PASS(_,b.shader,nir_opt_dce);
      struct pan_varying_layout varyings;
      pan_varying_collect_formats(&varyings,b.shader,0x07201000,false,false);
      _exit(99);
   }
   int status;assert(waitpid(child,&status,0)==child);
   assert(WIFSIGNALED(status)&&WTERMSIG(status)==SIGABRT);
   for(unsigned i=0;i<8;i++){positive(i,true);positive(i,false);}
   /* A sparse original descriptor extent must not be compacted accidentally. */
   nir_builder sparse=fixture(1,true,true);
   nir_foreach_function_impl(impl,sparse.shader){nir_foreach_block(block,impl){nir_foreach_instr(instr,block){
      if(instr->type==nir_instr_type_intrinsic &&
         nir_instr_as_intrinsic(instr)->intrinsic==nir_intrinsic_load_input)
         nir_intrinsic_set_base(nir_instr_as_intrinsic(instr),7);
   }}}
   struct a5_fragcoord_lowering layout={0};
   assert(a5_fragcoord_layout(sparse.shader,&layout)&&layout.base==8);
   ralloc_free(sparse.shader);
   nir_builder declared=fixture(2,true,true);
   nir_variable *unused=nir_variable_create(declared.shader,nir_var_shader_in,
      glsl_vec4_type(),"declared color without a live load");
   unused->data.location=VARYING_SLOT_VAR0+2;
   unused->data.driver_location=2;
   assert(a5_fragcoord_layout(declared.shader,&layout)&&layout.base==3);
   ralloc_free(declared.shader);
   nir_builder full=fixture(32,true,true);
   assert(!a5_fragcoord_layout(full.shader,&layout));ralloc_free(full.shader);
   nir_builder no_position=fixture(32,true,false);
   assert(a5_fragcoord_layout(no_position.shader,&layout)&&layout.base==32);
   ralloc_free(no_position.shader);
   nir_builder legacy=fixture(0,true,true);
   NIR_PASS(_,legacy.shader,nir_shader_intrinsics_pass,lower_fragcoord,
      nir_metadata_control_flow,NULL);
   assert(position_base(legacy.shader)==0);ralloc_free(legacy.shader);
   const nir_intrinsic_op derivatives[2][3]={
      {nir_intrinsic_ddx,nir_intrinsic_ddx_fine,nir_intrinsic_ddx_coarse},
      {nir_intrinsic_ddy,nir_intrinsic_ddy_fine,nir_intrinsic_ddy_coarse}};
   for(unsigned axis=0;axis<2;axis++)for(unsigned half=0;half<2;half++){
      struct util_dynarray reference=UTIL_DYNARRAY_INIT;
      derivative(derivatives[axis][0],half?16:32,&reference);
      for(unsigned mode=1;mode<3;mode++){
         struct util_dynarray binary=UTIL_DYNARRAY_INIT;
         derivative(derivatives[axis][mode],half?16:32,&binary);
         assert(binary.size==reference.size&&!memcmp(binary.data,reference.data,binary.size));
         util_dynarray_fini(&binary);
      }
      util_dynarray_fini(&reference);
   }
   glsl_type_singleton_decref();
   puts("FragCoord: old Mesa collision reproduced; 16 dense/dead-slot, declared/sparse/bound/legacy cases and 12 actual native derivative compilations PASS");
   return 0;
}
