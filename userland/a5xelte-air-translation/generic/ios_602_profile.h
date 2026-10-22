/* SPDX-License-Identifier: MIT
 * Exact SPIR-V fingerprints for the captured 0187/0186 stock QC pair.
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
static const struct a5_stage_profile kStages[] = {
   {UINT64_C(0x8ba6ee280356bfe2), kvert_bindings, 1,
    kvert_spec, 1, kvert_textures, 0, 4},
   {UINT64_C(0xbbf78fddf7472eee), kfrag_bindings, 2,
    kfrag_spec, 1, kfrag_textures, 0, 72},
};
