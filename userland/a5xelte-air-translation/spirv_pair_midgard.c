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
   /* Proof only: the actual display pipeline must supply a dynamic viewport. */
   nir_def *v = scale ? nir_imm_vec3(b, 540.0f, 960.0f, 0.5f)
                      : nir_imm_vec3(b, 540.0f, 960.0f, 0.5f);
   nir_def_rewrite_uses(&intr->def, v);
   return true;
}

static bool lower_zero_base_vertex(nir_builder *b,
                                   nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   if (intr->intrinsic != nir_intrinsic_load_raw_vertex_offset_pan)
      return false;
   b->cursor = nir_after_instr(&intr->instr);
   /* Valid only for this local draw proof with baseVertex = 0. */
   nir_def_rewrite_uses(&intr->def, nir_imm_int(b, 0));
   return true;
}

static bool lower_single_texture(nir_builder *b, nir_instr *instr, void *data)
{
   (void)data;
   if (instr->type != nir_instr_type_tex)
      return false;
   nir_tex_instr *tex = nir_instr_as_tex(instr);
   if (tex->op == nir_texop_query_levels || tex->op == nir_texop_txs) {
      b->cursor = nir_before_instr(instr);
      /* Midgard backend has no query_levels/txs opcode. The host supplies
       * identical dynamic values in resource UBO 0: levels @0, width @4,
       * height @8. This fixture queries only LOD 0. */
      unsigned offset = tex->op == nir_texop_query_levels ? 0 : 4;
      nir_def *value = nir_load_ubo(b, tex->def.num_components,
                                     tex->def.bit_size, nir_imm_int(b, 0),
                                     nir_imm_int(b, offset), .range = 12,
                                     .align_mul = 4);
      nir_def_rewrite_uses(&tex->def, value);
      return true;
   }
   int idx = nir_tex_instr_src_index(tex, nir_tex_src_texture_deref);
   if (idx < 0) return false;
   /* This local fixture has exactly one Texture(0) descriptor. */
   nir_tex_instr_remove_src(tex, idx);
   tex->texture_index = 0;
   return true;
}

static bool lower_push_to_ubo(nir_builder *b,
                              nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   if (intr->intrinsic != nir_intrinsic_load_push_constant)
      return false;
   b->cursor = nir_before_instr(&intr->instr);
   /* Host binding contract: UBO slot 0 contains the 68-byte push block.
    * The translated ColorWriteRule is at byte offset 64. */
   nir_def *val = nir_load_ubo(b, intr->def.num_components,
                               intr->def.bit_size, nir_imm_int(b, 0),
                               intr->src[0].ssa, .range = 68,
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
                                 .base = 0,
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

static int compile_spirv(const char *input, const char *output,
                         mesa_shader_stage stage)
{
   size_t count = 0;
   uint32_t *words = read_spirv(input, &count);
   if (!words || words[0] != 0x07230203) {
      fprintf(stderr, "invalid SPIR-V: %s\n", input);
      free(words);
      return 1;
   }
   const uint64_t expected = stage == MESA_SHADER_VERTEX
      ? UINT64_C(0xd515e04707a0c008)
      : UINT64_C(0xe391471dbd037a34);
   if (fnv1a64(words, count * 4) != expected) {
      fprintf(stderr, "unsupported SPIR-V module: this local lowering is "
                      "only for the translated QuartzCore read_surf pair\n");
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
   nir_shader *nir = spirv_to_nir(words, count, NULL, stage, "main",
                                  &spirv_opts, nir_opts);
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
   NIR_PASS(_, nir, nir_shader_instructions_pass, lower_single_texture,
            nir_metadata_control_flow, NULL);
   NIR_PASS(_, nir, nir_opt_dce);
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
   if (stage == MESA_SHADER_VERTEX)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_zero_base_vertex,
               nir_metadata_control_flow, NULL);
   pan_postprocess_nir(nir, &inputs, &info);
   NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_push_to_ubo,
            nir_metadata_control_flow, NULL);
   if (stage == MESA_SHADER_FRAGMENT)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_fragment_position,
               nir_metadata_control_flow, NULL);
   NIR_PASS(_, nir, nir_shader_alu_pass, lower_half_quantize,
            nir_metadata_control_flow, NULL);
   fprintf(stderr, "%s: NIR after Panfrost lowering\n", input);
   nir_print_shader(nir, stdout);
   if (stage == MESA_SHADER_VERTEX)
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_fixed_viewport,
               nir_metadata_control_flow, NULL);
   pan_shader_compile(nir, &inputs, &binary, &info);

   int rc = 1;
   FILE *f = fopen(output, "wb");
   if (f && binary.size &&
       fwrite(binary.data, 1, binary.size, f) == binary.size &&
       fclose(f) == 0) {
      f = NULL;
      printf("%s: Midgard bytes=%u first_tag=%u textures=%u work_regs=%u\n",
             output, binary.size, info.midgard.first_tag,
             info.texture_count, info.work_reg_count);
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
   if (argc != 5) {
      fprintf(stderr, "usage: %s vert.spv frag.spv vert.bin frag.bin\n", argv[0]);
      return 2;
   }
   glsl_type_singleton_init_or_ref();
   int rc = compile_spirv(argv[1], argv[3], MESA_SHADER_VERTEX);
   if (!rc) rc = compile_spirv(argv[2], argv[4], MESA_SHADER_FRAGMENT);
   glsl_type_singleton_decref();
   return rc;
}
