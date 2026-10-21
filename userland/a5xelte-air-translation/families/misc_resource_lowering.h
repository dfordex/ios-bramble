/* SPDX-License-Identifier: MIT
 * Vulkan descriptor -> Midgard resource ABI for the authenticated QC families.
 * See Mesa26.2.4 pan_nir_lower_sysvals.c (SSBO address/size) and
 * pan_cmdstream.c:panfrost_upload_ssbo_sysval. No SSBO is turned into a UBO:
 * actual SSBO loads become global GPU loads via nir_lower_ssbo.
 *
 * Each stage binds UBO0 for push data plus resource sysvals. Vulkan binding N
 * maps UBOs to hardware UBO N+1; SSBO N's descriptor record is at UBO0 byte
 * 96+16*N: GPUVA:u64, byte_size:u32, reserved:u32. Callers must validate every
 * buffer window and populate each record from the actual mapped resource.
 * Runtime binding/job submission is outside this host compilation proof.
 */
#ifndef A5_MISC_RESOURCE_LOWERING_H
#define A5_MISC_RESOURCE_LOWERING_H

struct a5_resource_binding {
   unsigned binding;
   nir_descriptor_type type;
};

struct a5_resource_context {
   const struct a5_resource_binding *bindings;
   unsigned count;
   bool invalid;
};

static const struct a5_resource_binding *
a5_find_binding(struct a5_resource_context *ctx, unsigned binding)
{
   for (unsigned i = 0; i < ctx->count; ++i)
      if (ctx->bindings[i].binding == binding) return &ctx->bindings[i];
   return NULL;
}

static bool
a5_lower_resource_descriptor(nir_builder *b, nir_intrinsic_instr *intr,
                             void *data)
{
   struct a5_resource_context *ctx = data;
   bool index = intr->intrinsic == nir_intrinsic_vulkan_resource_index;
   bool desc = intr->intrinsic == nir_intrinsic_load_vulkan_descriptor;
   if (!index && !desc) return false;
   nir_descriptor_type type = nir_intrinsic_desc_type(intr);
   if ((type != nir_descriptor_type_uniform_buffer &&
        type != nir_descriptor_type_storage_buffer) ||
       intr->def.num_components != 2 || intr->def.bit_size != 32) {
      fprintf(stderr,"a5 descriptor type=%u components=%u bits=%u\n",type,
              intr->def.num_components,intr->def.bit_size);
      ctx->invalid = true; return false;
   }
   b->cursor = nir_before_instr(&intr->instr);
   if (desc) {
      nir_def_rewrite_uses(&intr->def, intr->src[0].ssa);
      return true;
   }
   unsigned binding = nir_intrinsic_binding(intr);
   const struct a5_resource_binding *expected = a5_find_binding(ctx, binding);
   if (!expected || expected->type != type || nir_intrinsic_desc_set(intr) ||
       !nir_src_is_const(intr->src[0]) || nir_src_as_uint(intr->src[0])) {
      fprintf(stderr,"a5 descriptor binding=%u unsupported\n",binding);
      ctx->invalid = true; return false;
   }
   unsigned hardware = binding + (type == nir_descriptor_type_uniform_buffer);
   nir_def_rewrite_uses(&intr->def,
      nir_vec2(b, nir_imm_int(b, hardware), nir_imm_int(b, 0)));
   return true;
}

static bool
a5_lower_ssbo_sysval(nir_builder *b, nir_intrinsic_instr *intr, void *data)
{
   struct a5_resource_context *ctx = data;
   bool address = intr->intrinsic == nir_intrinsic_load_ssbo_address;
   bool size = intr->intrinsic == nir_intrinsic_get_ssbo_size;
   if (!address && !size) return false;
   if (!nir_src_is_const(intr->src[0])) {
      fprintf(stderr,"a5 SSBO binding index is not constant\n");
      ctx->invalid = true; return false;
   }
   unsigned binding = nir_src_as_uint(intr->src[0]);
   const struct a5_resource_binding *resource = a5_find_binding(ctx, binding);
   if (!resource || resource->type != nir_descriptor_type_storage_buffer ||
       binding >= 16) {
      fprintf(stderr,"a5 SSBO sysval binding=%u unsupported\n",binding);
      ctx->invalid = true; return false;
   }
   unsigned offset = 96 + 16 * binding + (size ? 8 : 0);
   b->cursor = nir_before_instr(&intr->instr);
   nir_def *value = nir_load_ubo(b, 1, address ? 64 : 32,
      nir_imm_int(b, 0), nir_imm_int(b, offset),
      .range_base = offset, .range = address ? 8 : 4,
      .align_mul = address ? 8 : 4);
   if (address)
      value = nir_iadd(b, value, nir_u2u64(b, intr->src[1].ssa));
   nir_def_rewrite_uses(&intr->def, value);
   return true;
}

#endif
