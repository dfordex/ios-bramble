/* Copyright (C) 2020-2021 Collabora, Ltd.
 * SPDX-License-Identifier: MIT
 *
 * T720 texture-copy shader generator for the a5xelte lab test. The NIR
 * construction and compiler pipeline follow Mesa's pan_fb_preload.c.
 * This file builds against Mesa; no Mesa host executable enters this repo.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "compiler/nir/nir_builder.h"
#include "compiler/nir/nir_builder_opcodes.h"
#include "panfrost/compiler/pan_compiler.h"
#include "panfrost/compiler/midgard/disassemble.h"

static bool lower_sampler_parameters(nir_builder *b,
                                      nir_intrinsic_instr *intr, void *data)
{
   (void)data;
   if (intr->intrinsic != nir_intrinsic_load_sampler_lod_parameters)
      return false;
   const nir_const_value c[4] = {
      nir_const_value_for_float(0.0f, 32),
      nir_const_value_for_float(INFINITY, 32),
      nir_const_value_for_float(0.0f, 32),
   };
   b->cursor = nir_after_instr(&intr->instr);
   nir_def_rewrite_uses(&intr->def, nir_build_imm(b, 3, 32, c));
   return true;
}

int main(int argc, char **argv)
{
   if (argc != 2) {
      fprintf(stderr, "usage: %s output.bin\n", argv[0]);
      return 2;
   }
   nir_builder b = nir_builder_init_simple_shader(
      MESA_SHADER_FRAGMENT,
      pan_get_nir_shader_compiler_options(4, MESA_SHADER_FRAGMENT, false),
      "a5_t720_copy_16x16");
   nir_def *barycentric = nir_load_barycentric(
      &b, nir_intrinsic_load_barycentric_pixel, INTERP_MODE_SMOOTH);
   nir_def *coord = nir_load_interpolated_input(
      &b, 2, 32, barycentric, nir_imm_int(&b, 0),
      .base = 0, .dest_type = nir_type_float32,
      .io_semantics.location = VARYING_SLOT_VAR0,
      .io_semantics.num_slots = 1);
   nir_tex_instr *tex = nir_tex_instr_create(b.shader, 1);
   tex->op = nir_texop_txl;
   tex->dest_type = nir_type_float32;
   tex->texture_index = 0;
   tex->sampler_index = 0;
   tex->sampler_dim = GLSL_SAMPLER_DIM_2D;
   tex->src[0] = nir_tex_src_for_ssa(nir_tex_src_coord, coord);
   tex->coord_components = 2;
   nir_def_init(&tex->instr, &tex->def, 4, 32);
   nir_builder_instr_insert(&b, &tex->instr);
   nir_store_output(&b, &tex->def, nir_imm_int(&b, 0),
                    .base = 0, .src_type = nir_type_float32,
                    .io_semantics.location = FRAG_RESULT_DATA0,
                    .io_semantics.num_slots = 1, .write_mask = 15);
   struct pan_compile_inputs inputs = {
      .gpu_id = 0x07201000,
      .is_blit = true,
      .no_idvs = true,
   };
   struct pan_shader_info info = {0};
   struct util_dynarray binary = UTIL_DYNARRAY_INIT;
   nir_shader_gather_info(b.shader, nir_shader_get_entrypoint(b.shader));
   BITSET_SET(b.shader->info.textures_used, 0);
   pan_preprocess_nir(b.shader, inputs.gpu_id);
   pan_postprocess_nir(b.shader, &inputs, &info);
   NIR_PASS(_, b.shader, nir_shader_intrinsics_pass,
            lower_sampler_parameters, nir_metadata_control_flow, NULL);
   pan_shader_compile(b.shader, &inputs, &binary, &info);
   FILE *f = fopen(argv[1], "wb");
   if (!f) {
      fprintf(stderr, "open failed\n");
      return 1;
   }
   size_t written = fwrite(binary.data, 1, binary.size, f);
   int closed = fclose(f);
   if (written != binary.size || closed) {
      fprintf(stderr, "write failed\n");
      return 1;
   }
   printf("T720 shader bytes=%u textures=%u work_regs=%u\n",
          binary.size, info.texture_count, info.work_reg_count);
   disassemble_midgard(stdout, binary.data, binary.size, inputs.gpu_id, false);
   util_dynarray_fini(&binary);
   ralloc_free(b.shader);
   return 0;
}
