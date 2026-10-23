/* SPDX-License-Identifier: MIT
 * Exact SPIR-V fingerprints for the captured 0187/0186 stock QC pair and
 * 0189, 0198 and 0204 textured fragments with a UV-capable candidate vertex.
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
#define A5_PROFILE_COUNT 10
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
/* SamplerState SpecId 0 reads bit 0 for pixel coordinates and bits 1/2 for
 * min/mag linear filtering. The runtime profile accepts normalized UVs and
 * nearest/linear filters; all four normalized words 0/2/4/6 compile to the
 * same pinned Midgard program. Address modes are runtime sampler state. */
static const struct a5_spec_value kfrag_spec_603[] = {{0, 0}, {3, 168}, {4, 8}};
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
   /* 0198 texture-function 3 and image-function 29 use the same reflected
    * resource layout, with distinct native fragment programs. */
   {UINT64_C(0x10b6365fd867f579), kvert_bindings_603, 2,
    kvert_spec_603, 2, kvert_textures, 0, 8},
   {UINT64_C(0x0f9fa94b730aaebd), kfrag_bindings_603, 3,
    kfrag_spec_603, 3, kfrag_textures_603, 1, 76},
   {UINT64_C(0x10b6365fd867f579), kvert_bindings_603, 2,
    kvert_spec_603, 2, kvert_textures, 0, 8},
   {UINT64_C(0x3465d73e9b58fb9f), kfrag_bindings_603, 3,
    kfrag_spec_603, 3, kfrag_textures_603, 1, 76},
   /* 0204 coordinate5/image17: reflected Buffer1 is now live for UV clamp,
    * using the existing full reflected168-byte UBO3 binding. */
   {UINT64_C(0x10b6365fd867f579), kvert_bindings_603, 2,
    kvert_spec_603, 2, kvert_textures, 0, 8},
   {UINT64_C(0x82b28a31b9192985), kfrag_bindings_603, 3,
    kfrag_spec_603, 3, kfrag_textures_603, 1, 76},
};
