/* SPDX-License-Identifier: MIT
 * Local translation experiment: SPIR-V graphics stages to T720 Midgard.
 * SPIR-V files are supplied at runtime; no Apple shader is embedded here.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "compiler/glsl_types.h"
#include "compiler/spirv/nir_spirv.h"
#include "compiler/nir/nir_builder.h"
#include "panfrost/compiler/pan_compiler.h"
#include "panfrost/compiler/midgard/disassemble.h"

#include "misc_resource_lowering.h"
#include "panfrost/compiler/pan_nir.h"
#include "util/format/u_formats.h"

static uint64_t vertex_fingerprint, fragment_fingerprint;
static uint32_t vertex_aux_bytes;
static bool single_target;

#ifdef NDEBUG
#error This bounded compiler requires active NIR validation
#endif

static unsigned io_type_size(const struct glsl_type *type, bool bindless)
{
   return glsl_count_attribute_slots(type, false);
}

static uint32_t *read_spirv(const char *path, size_t *words)
{
   FILE *f = fopen(path, "rb");
   if (!f) return NULL;
   if (fseek(f, 0, SEEK_END)) { fclose(f); return NULL; }
   long size = ftell(f);
   if (size <= 0 || size > 16 * 1024 * 1024 || (size & 3) ||
       fseek(f, 0, SEEK_SET)) { fclose(f); return NULL; }
   uint32_t *data = malloc((size_t)size);
   if (!data) { fclose(f); return NULL; }
   if (fread(data, 1, (size_t)size, f) != (size_t)size) {
      free(data); fclose(f); return NULL;
   }
   fclose(f);
   *words = (size_t)size / 4;
   return data;
}

static uint64_t fnv1a64(const void *data, size_t bytes)
{
   const uint8_t *p = data;
   uint64_t h = UINT64_C(0xcbf29ce484222325);
   for (size_t i = 0; i < bytes; i++)
      h = (h ^ p[i]) * UINT64_C(0x100000001b3);
   return h;
}

static bool lower_fixed_viewport(nir_builder *b,
                                 nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   bool scale = intr->intrinsic == nir_intrinsic_load_viewport_scale;
   bool offset = intr->intrinsic == nir_intrinsic_load_viewport_offset;
   if (!scale && !offset) return false;
   b->cursor = nir_after_instr(&intr->instr);
   /* Stage UBO0 carries actual viewport scale at512 and offset at528. */
   nir_def *v = nir_load_ubo(b, 3, 32, nir_imm_int(b, 0),
      nir_imm_int(b, scale ? 512 : 528), .range=540, .align_mul=4);
   nir_def_replace(&intr->def, v);
   return true;
}

static bool lower_zero_base_vertex(nir_builder *b,
                                   nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   bool base_instance = intr->intrinsic == nir_intrinsic_load_base_instance;
   if (!base_instance && intr->intrinsic != nir_intrinsic_load_raw_vertex_offset_pan)
      return false;
   b->cursor = nir_after_instr(&intr->instr);
   /* Stage UBO0 bytes544/552 carry actual raw vertex offset/baseInstance. */
   nir_def_rewrite_uses(&intr->def, nir_load_ubo(b, 1, 32,
      nir_imm_int(b, 0), nir_imm_int(b, base_instance ? 552 : 544), .range=556, .align_mul=4));
   return true;
}

static bool lower_push_to_ubo(nir_builder *b,
                              nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   if (intr->intrinsic != nir_intrinsic_load_push_constant)
      return false;
   b->cursor = nir_before_instr(&intr->instr);
   if (single_target && vertex_aux_bytes==24 &&
       b->shader->info.stage==MESA_SHADER_FRAGMENT &&
       intr->def.num_components==1 && intr->def.bit_size==32 &&
       nir_src_is_const(intr->src[0]) &&
       (nir_src_as_uint(intr->src[0])==64 || nir_src_as_uint(intr->src[0])==68)) {
      /* Exact RGBA16Float color rules for both original duplicate outputs. */
      nir_def_rewrite_uses(&intr->def,nir_imm_int(b,0x3333)); return true;
   }
   /* Stage-local UBO0 holds exact translated push bytes (up to68).
    * Resource records/sysvals occupy disjoint byte ranges96..556. */
   nir_def *val = nir_load_ubo(b, intr->def.num_components,
                               intr->def.bit_size, nir_imm_int(b, 0),
                               intr->src[0].ssa, .range = vertex_aux_bytes==8 ? 72 : 68,
                               .align_mul = 4);
   nir_def_rewrite_uses(&intr->def, val);
   return true;
}

static bool lower_fragment_position(nir_builder *b,
                                    nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   if (intr->intrinsic != nir_intrinsic_load_frag_coord)
      return false;
   b->cursor = nir_before_instr(&intr->instr);
   /* Midgard obtains fragment position through its position varying. */
   nir_def *val = nir_load_input(b, 4, 32, nir_imm_int(b, 0),
                                 .base = b->shader->num_inputs,
                                 .io_semantics.location = VARYING_SLOT_POS,
                                 .io_semantics.num_slots = 1,
                                 .dest_type = nir_type_float32);
   nir_def_rewrite_uses(&intr->def, val);
   return true;
}

static bool lower_half_quantize(nir_builder *b, nir_alu_instr *alu, void *data)
{
   (void)data;
   if (alu->op != nir_op_fquantize2f16)
      return false;
   b->cursor = nir_before_instr(&alu->instr);
   nir_def *src = nir_ssa_for_alu_src(b, alu, 0);
   nir_def *rounded = nir_f2f32(b, nir_f2f16(b, src));
   nir_def_replace(&alu->def, rounded);
   return true;
}

/* Exact native ordered attachment2 load. This is NOT Vulkan extension
 * support: it requires same-draw ordered native R32F tilebuffer attachment2,
 * one sample and original load/store actions supplied by the caller. */
static bool lower_native_attachment2(nir_builder *b,
                                     nir_intrinsic_instr *intr, void *data)
{
   bool *invalid = data;
   if (intr->intrinsic != nir_intrinsic_image_deref_load) return false;
   nir_deref_instr *d = nir_src_as_deref(intr->src[0]);
   while (d && d->deref_type == nir_deref_type_cast)
      d = nir_deref_instr_parent(d);
   nir_variable *v = d && d->deref_type == nir_deref_type_var ? d->var : NULL;
   if (!v || v->data.descriptor_set || v->data.binding != 3 || v->data.index != 2 ||
       nir_intrinsic_image_dim(intr) != GLSL_SAMPLER_DIM_SUBPASS ||
       nir_intrinsic_image_array(intr) || !nir_src_is_const(intr->src[3]) ||
       nir_src_as_uint(intr->src[3]) || intr->def.num_components != 4 ||
       intr->def.bit_size != 32 || nir_intrinsic_dest_type(intr) != nir_type_float32 ||
       !nir_scalar_is_const(nir_scalar_resolved(intr->src[1].ssa,0)) ||
       !nir_scalar_is_const(nir_scalar_resolved(intr->src[1].ssa,1)) ||
       nir_scalar_as_uint(nir_scalar_resolved(intr->src[1].ssa,0)) ||
       nir_scalar_as_uint(nir_scalar_resolved(intr->src[1].ssa,1))) {
      *invalid=true; return false;
   }
   b->cursor=nir_before_instr(&intr->instr);
   nir_def *value=nir_load_output(b,4,32,nir_imm_int(b,0),
      .base=2, .io_semantics.location=FRAG_RESULT_DATA2,
      .io_semantics.num_slots=1, .dest_type=nir_type_float32);
   nir_def_replace(&intr->def,value);
   return true;
}

static bool single_target_outputs(nir_shader *nir)
{
   nir_intrinsic_instr *first=NULL, *duplicate=NULL;
   nir_foreach_function_impl(impl,nir) {
      nir_foreach_block(block,impl) {
         nir_foreach_instr(instr,block) {
            if (instr->type!=nir_instr_type_intrinsic) continue;
            nir_intrinsic_instr *i=nir_instr_as_intrinsic(instr);
            if (i->intrinsic!=nir_intrinsic_store_output) continue;
            nir_io_semantics sem=nir_intrinsic_io_semantics(i);
            if (vertex_aux_bytes==24) {
               if (sem.location==FRAG_RESULT_DATA0) {if(first)return false;first=i;}
               else if (sem.location==FRAG_RESULT_DATA1) {if(duplicate)return false;duplicate=i;}
               else return false;
            } else {
               if (sem.location!=FRAG_RESULT_DATA2 || first) return false;
               first=i;sem.location=FRAG_RESULT_DATA0;
               nir_intrinsic_set_io_semantics(i,sem);nir_intrinsic_set_base(i,0);
            }
         }
      }
   }
   if (!first) return false;
   if (vertex_aux_bytes==24) {
      if (!duplicate || first->src[0].ssa!=duplicate->src[0].ssa ||
          nir_intrinsic_write_mask(first)!=nir_intrinsic_write_mask(duplicate))
         return false;
      nir_instr_remove(&duplicate->instr);
      nir_builder b=nir_builder_at(nir_before_instr(&first->instr));
      nir_src_rewrite(&first->src[0],nir_f2f16(&b,first->src[0].ssa));
      nir_intrinsic_set_src_type(first,nir_type_float16);
   }
   return true;
}

static int compile_spirv(const char *input, const char *output,
                         mesa_shader_stage stage, bool downsample)
{
   size_t count = 0;
   uint32_t *words = read_spirv(input, &count);
   if (!words || words[0] != 0x07230203) {
      fprintf(stderr, "invalid SPIR-V: %s\n", input);
      free(words);
      return 1;
   }
   const uint64_t expected = stage == MESA_SHADER_VERTEX ? vertex_fingerprint : fragment_fingerprint;
   if (fnv1a64(words, count * 4) != expected) {
      fprintf(stderr, "unsupported SPIR-V module: this local lowering is "
                      "requires the exact selected QuartzCore pair\n");
      free(words);
      return 2;
   }
   const nir_shader_compiler_options *nir_opts =
      pan_get_nir_shader_compiler_options(4, stage, false);
   struct spirv_to_nir_options spirv_opts = {
      .environment = NIR_SPIRV_VULKAN,
      .ubo_addr_format = nir_address_format_32bit_index_offset,
      .ssbo_addr_format = nir_address_format_32bit_index_offset,
      .phys_ssbo_addr_format = nir_address_format_64bit_global,
      .shared_addr_format = nir_address_format_32bit_offset,
      .min_ubo_alignment = 16,
      .min_ssbo_alignment = 16,
   };
   uint32_t values[2] = {64, vertex_aux_bytes};
   struct nir_spirv_specialization_entry entries[2] = {
      {.id=0, .size=4, .data=(uint8_t *)&values[0]},
      {.id=1, .size=4, .data=(uint8_t *)&values[1]},
   };
   struct nir_spirv_specialization spec = {.num_entries=2, .entries=entries};
   if (vertex_aux_bytes == 8) {
      entries[1].data = (uint8_t *)&vertex_aux_bytes;
      if (stage == MESA_SHADER_VERTEX) spec.num_entries=1;
      else {spec.num_entries=1;spec.entries=entries+1;}
   }
   nir_shader *nir = spirv_to_nir(words, count,
      (stage == MESA_SHADER_VERTEX || vertex_aux_bytes == 8) ? &spec : NULL, stage, "main", &spirv_opts, nir_opts);
   free(words);
   if (!nir) {
      fprintf(stderr, "spirv_to_nir failed: %s\n", input);
      return 1;
   }
   fprintf(stderr, "%s: SPIR-V translated to NIR\n", input);
   nir_validate_shader(nir, "SPIR-V to NIR");
   nir_print_shader(nir, stdout);

   NIR_PASS(_, nir, nir_lower_system_values);
   if (stage == MESA_SHADER_FRAGMENT)
      NIR_PASS(_, nir, nir_lower_wpos_center);
   NIR_PASS(_, nir, nir_lower_explicit_io, nir_var_mem_push_const,
            nir_address_format_32bit_offset);

   /* Mirror the essential PanVK lowering contract for graphics I/O. */
   nir_assign_io_var_locations(nir, nir_var_shader_in);
   nir_assign_io_var_locations(nir, nir_var_shader_out);
   NIR_PASS(_, nir, nir_lower_var_copies);
   NIR_PASS(_, nir, nir_lower_indirect_derefs_to_if_else_trees,
            nir_var_shader_in | nir_var_shader_out, UINT32_MAX);
   NIR_PASS(_, nir, nir_lower_io, nir_var_shader_in | nir_var_shader_out,
            io_type_size, nir_lower_io_use_interpolated_input_intrinsics);
   NIR_PASS(_, nir, nir_opt_constant_folding);

   struct pan_compile_inputs inputs = {
      .gpu_id = 0x07201000,
      .is_blit = true,
      .no_idvs = true,
   };
   struct pan_shader_info info = {0};
   struct util_dynarray binary = UTIL_DYNARRAY_INIT;
   nir_shader_gather_info(nir, nir_shader_get_entrypoint(nir));
   struct pan_varying_layout varying_layout;
   if (stage == MESA_SHADER_VERTEX) {
      pan_varying_collect_formats(&varying_layout, nir, inputs.gpu_id,
                                  false, false);
      pan_build_varying_layout_compact(&varying_layout, nir, inputs.gpu_id);
      inputs.varying_layout = &varying_layout;
   }
   pan_preprocess_nir(nir, inputs.gpu_id);
   const struct a5_resource_binding resources[] = {
      {0, nir_descriptor_type_storage_buffer},
      {1, nir_descriptor_type_uniform_buffer},
      {2, nir_descriptor_type_uniform_buffer},
   };
   struct a5_resource_context resource_ctx = {
      .bindings=resources, .count=stage == MESA_SHADER_VERTEX ? (vertex_aux_bytes==8 ? 2 : 3) : (vertex_aux_bytes==8 ? 1 : 0),
   };
   if (stage == MESA_SHADER_FRAGMENT && vertex_aux_bytes==8)
      resource_ctx.bindings=resources+2;
   NIR_PASS(_, nir, nir_shader_intrinsics_pass, a5_lower_resource_descriptor,
            nir_metadata_control_flow, &resource_ctx);
   NIR_PASS(_, nir, nir_lower_explicit_io, nir_var_mem_ubo | nir_var_mem_ssbo,
            nir_address_format_32bit_index_offset);
   NIR_PASS(_, nir, nir_opt_constant_folding);
   NIR_PASS(_, nir, nir_lower_ssbo, NULL);
   NIR_PASS(_, nir, nir_opt_copy_prop);
   NIR_PASS(_, nir, nir_opt_constant_folding);
   NIR_PASS(_, nir, nir_shader_intrinsics_pass, a5_lower_ssbo_sysval,
            nir_metadata_control_flow, &resource_ctx);
   if (resource_ctx.invalid) {
      nir_print_shader(nir, stderr);
      fprintf(stderr, "unsupported reflected path/stroke resource binding\n");
      ralloc_free(nir); return 2;
   }
   if (stage == MESA_SHADER_VERTEX)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_zero_base_vertex,
               nir_metadata_control_flow, NULL);
   /* Driver descriptor/I/O and arithmetic lowering belongs before Panfrost's
    * postprocess boundary (pan_compiler.h). In particular, its algebraic and
    * scalarization passes must see the half-rounding ALU we introduce. */
   NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_push_to_ubo,
            nir_metadata_control_flow, downsample ? &downsample : NULL);
   if (stage == MESA_SHADER_FRAGMENT)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_fragment_position,
               nir_metadata_control_flow, NULL);
   if (stage == MESA_SHADER_FRAGMENT && vertex_aux_bytes==8) {
      bool invalid=false;
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_native_attachment2,
         nir_metadata_control_flow, &invalid);
      if (invalid) {fprintf(stderr,"unsupported native attachment2 load\n");ralloc_free(nir);return 2;}
      enum pipe_format formats[8]={PIPE_FORMAT_B8G8R8A8_UNORM,PIPE_FORMAT_B8G8R8A8_UNORM,PIPE_FORMAT_R32_FLOAT};
      /* R32F is single-channel: raw unpack component reorder is identity.
       * BGRA outputs are not lowered stores because this is not a blend shader. */
      NIR_PASS(_,nir,pan_nir_lower_framebuffer,formats,0,0,false);
   }
   NIR_PASS(_, nir, nir_shader_alu_pass, lower_half_quantize,
            nir_metadata_control_flow, NULL);
   NIR_PASS(_, nir, nir_opt_dce);
   nir_validate_shader(nir, "A5 descriptor/I/O/arithmetic lowering");
   if (single_target && stage==MESA_SHADER_FRAGMENT) {
      bool progress;
      do {progress=false;
         NIR_PASS(progress,nir,nir_opt_algebraic);
         NIR_PASS(progress,nir,nir_opt_constant_folding);
         NIR_PASS(progress,nir,nir_opt_copy_prop);
         NIR_PASS(progress,nir,nir_opt_cse);
      } while (progress);
      if (!single_target_outputs(nir)) {
         fprintf(stderr,"single-target output equivalence failed\n");ralloc_free(nir);return 2;
      }
      /* Native v4 SFBD raw writeback requires the upstream format packer.
       * This is format conversion only: no blend equation is changed. */
      enum pipe_format format[8]={vertex_aux_bytes==24 ?
         PIPE_FORMAT_R16G16B16A16_FLOAT : PIPE_FORMAT_R32_FLOAT};
      NIR_PASS(_,nir,pan_nir_lower_framebuffer,format,0,1,false);
      NIR_PASS(_,nir,nir_opt_dce);
      nir_validate_shader(nir,"Exact single-target portability variant");
   }
   nir_shader_gather_info(nir, nir_shader_get_entrypoint(nir));
   nir->info.num_ubos = stage == MESA_SHADER_VERTEX ? (vertex_aux_bytes==8 ? 3 : 4) : (vertex_aux_bytes==8 ? 4 : 1);
   pan_postprocess_nir(nir, &inputs, &info);
   nir_validate_shader(nir, "Panfrost postprocess");

   /* Only sysval inlining follows postprocess. Midgard's postprocess itself
    * creates sampler LOD sysvals for the T720 erratum and viewport sysvals;
    * these do not exist at the preceding driver-lowering boundary. */
   fprintf(stderr, "%s: NIR after Panfrost lowering\n", input);
   nir_print_shader(nir, stdout);
   if (stage == MESA_SHADER_VERTEX)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_fixed_viewport,
               nir_metadata_control_flow, NULL);
   nir_validate_shader(nir, "A5 final sysval inlining");
   pan_shader_compile(nir, &inputs, &binary, &info);
   for (unsigned i=0;i<info.varyings.formats.count;i++) {
      struct pan_varying_slot *v=&info.varyings.formats.slots[i];
      printf("VARY slot=%u loc=%u type=%u comps=%u section=%u offset=%u\n",i,v->location,v->alu_type,v->ncomps,v->section,v->offset);
   }

   int rc = 1;
   FILE *f = fopen(output, "wb");
   if (f &&
       fwrite(binary.data, 1, binary.size, f) == binary.size &&
       fclose(f) == 0) {
      f = NULL;
      printf("%s: Midgard bytes=%u first_tag=%u textures=%u work_regs=%u "
             "tls=%u wls=%u attributes=%u ubos=%u samplers=%u\n",
             output, binary.size, info.midgard.first_tag,
             info.texture_count, info.work_reg_count, info.tls_size,
             info.wls_size, info.attribute_count,
             info.ubo_count, info.sampler_count);
      disassemble_midgard(stdout, binary.data, binary.size, inputs.gpu_id, false);
      rc = 0;
   }
   if (f) fclose(f);
   util_dynarray_fini(&binary);
   ralloc_free(nir);
   return rc;
}

int main(int argc, char **argv)
{
   if (argc != 8 && (argc!=9 || strcmp(argv[8],"single_target"))) {
      fprintf(stderr, "usage: %s vs.spv fs.spv vs.bin fs.bin vs-fnv fs-fnv aux-bytes\n", argv[0]);
      return 2;
   }
   single_target=argc==9;
   char *end;
   vertex_fingerprint=strtoull(argv[5], &end, 16);
   if (!*argv[5] || *end) return 2;
   fragment_fingerprint=strtoull(argv[6], &end, 16);
   if (!*argv[6] || *end) return 2;
   vertex_aux_bytes=strtoul(argv[7], &end, 10);
   if (!*argv[7] || *end || (vertex_aux_bytes != 8 && vertex_aux_bytes != 16 && vertex_aux_bytes != 24)) return 2;
   if (single_target && vertex_aux_bytes==8) return 2;
   glsl_type_singleton_init_or_ref();
   int rc=compile_spirv(argv[1],argv[3],MESA_SHADER_VERTEX,true);
   if (!rc) rc=compile_spirv(argv[2],argv[4],MESA_SHADER_FRAGMENT,true);
   glsl_type_singleton_decref();
   return rc;
}
