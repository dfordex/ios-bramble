/* SPDX-License-Identifier: MIT
 * Exact SPIR-V fingerprints for the captured 0187/0186 stock QC pair and
 * 0189 textured fragment with a UV-capable candidate vertex.
 * This contains no shader code. Native output must additionally match the
 * independently recorded SHA-256 receipts before it can be published.
 */
static const struct a5_resource_binding kvert_bindings[] = {
   {0, nir_descriptor_type_uniform_buffer}
};
static const struct a5_resource_binding kfrag_bindings[] = {
   {1, nir_descriptor_type_uniform_buffer},
   {2, nir_descriptor_type_storage_buffer}
};
static const struct a5_spec_value kvert_spec[] = {{0, 64}};
static const struct a5_spec_value kfrag_spec[] = {{1, 168}};
static const struct a5_texture_binding kvert_textures[] = {{0, 0}};
static const struct a5_texture_binding kfrag_textures[] = {{0, 0}};
#define A5_PROFILE_COUNT 4
static const struct a5_resource_binding kvert_bindings_603[] = {
   {0, nir_descriptor_type_uniform_buffer},
   {1, nir_descriptor_type_uniform_buffer}
};
static const struct a5_resource_binding kfrag_bindings_603[] = {
   {2, nir_descriptor_type_uniform_buffer},
   {3, nir_descriptor_type_uniform_buffer},
   {4, nir_descriptor_type_storage_buffer}
};
static const struct a5_spec_value kvert_spec_603[] = {{1, 64}, {2, 16}};
/* The runtime profile accepts only ClampToEdge S/T/R. Address S's shader
 * specialization is 1; the sampled image's dimensions remain a live UBO0
 * input at +356/+360 and cannot be guessed or omitted. */
static const struct a5_spec_value kfrag_spec_603[] = {{0, 1}, {3, 168}, {4, 8}};
static const struct a5_texture_binding kfrag_textures_603[] = {{5, 0}};
static const struct a5_stage_profile kStages[] = {
   {UINT64_C(0x8ba6ee280356bfe2), kvert_bindings, 1,
    kvert_spec, 1, kvert_textures, 0, 4},
   {UINT64_C(0xbbf78fddf7472eee), kfrag_bindings, 2,
    kfrag_spec, 1, kfrag_textures, 0, 72},
   {UINT64_C(0x10b6365fd867f579), kvert_bindings_603, 2,
    kvert_spec_603, 2, kvert_textures, 0, 8},
   {UINT64_C(0x7247c6193a98e09b), kfrag_bindings_603, 3,
    kfrag_spec_603, 3, kfrag_textures_603, 1, 76},
};
