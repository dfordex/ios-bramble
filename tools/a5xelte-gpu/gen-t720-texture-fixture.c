/* SPDX-License-Identifier: MIT
 * Offline Mali-T720 (Midgard v4) 16x16 texture/tiler descriptor fixture.
 * Build this against Mesa 26.2.4's generated genxml/v4_pack.h. Nothing here
 * writes a device. All pointers refer to the 16 KiB private test mapping at
 * 0x02000000 used by A5XELTEGPU.cpp, never an iOS IOSurface or scanout.
 */
#define PAN_ARCH 4
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"

#define VA 0x02000000ULL
#define LEN 0x1000
#define OFF_TILER 0x300
#define OFF_SHADER 0x500
#define OFF_RSD 0x600
#define OFF_TEXTURE 0x700
#define OFF_SURFACE 0x720
#define OFF_TEX_TABLE 0x740
#define OFF_SAMPLER 0x780
#define OFF_VARYING 0x800
#define OFF_VARYING_BUFFER 0x820
#define OFF_COORDS 0x880
#define OFF_VIEWPORT 0x900
#define OFF_SOURCE 0xa00
#define OFF_FB 0x100

int main(int argc, char **argv)
{
   if (argc != 3) {
      fprintf(stderr, "usage: %s shader.bin descriptor-page.bin\n", argv[0]);
      return 2;
   }
   unsigned char d[LEN] = {0};
   FILE *in = fopen(argv[1], "rb");
   if (!in) return 1;
   size_t shader_len = fread(d + OFF_SHADER, 1, OFF_RSD - OFF_SHADER, in);
   int oversized = fgetc(in) != EOF;
   fclose(in);
   if (oversized || shader_len != 112) {
      fprintf(stderr, "expected 112-byte Midgard shader\n");
      return 1;
   }

   pan_pack((struct mali_job_header_packed *)(d + OFF_TILER), JOB_HEADER, cfg) {
      cfg.type = MALI_JOB_TYPE_TILER;
      cfg.index = 1;
      cfg.enable_texture_mapper = true;
   }
   /* pan_pack_work_groups_compute(1,4,1,1,1,1,true,false): the four
    * vertices share one primitive strip. See pan_encoder.h in Mesa.
    */
   pan_pack((struct mali_invocation_packed *)(d + OFF_TILER + 32), INVOCATION, cfg) {
      cfg.invocations = 3;
      cfg.workgroups_z_shift = 32;
      cfg.thread_group_split = 2;
   }
   pan_pack((struct mali_primitive_packed *)(d + OFF_TILER + 40), PRIMITIVE, cfg) {
      cfg.draw_mode = MALI_DRAW_MODE_TRIANGLE_STRIP;
      cfg.index_count = 4;
      cfg.job_task_split = 6;
   }
   pan_pack((struct mali_draw_packed *)(d + OFF_TILER + 64), DRAW, cfg) {
      cfg.position = VA + OFF_COORDS;
      cfg.viewport = VA + OFF_VIEWPORT;
      cfg.varyings = VA + OFF_VARYING;
      cfg.varying_buffers = VA + OFF_VARYING_BUFFER;
      cfg.textures = VA + OFF_TEX_TABLE;
      cfg.samplers = VA + OFF_SAMPLER;
      cfg.state = VA + OFF_RSD;
      cfg.fbd = VA + OFF_FB;
   }
   pan_pack((struct mali_primitive_size_packed *)(d + OFF_TILER + 184), PRIMITIVE_SIZE, cfg) {
      cfg.fixed_sized = 1.0f;
   }
   pan_pack((struct mali_renderer_state_packed *)(d + OFF_RSD), RENDERER_STATE, cfg) {
      /* Mesa compiler reported first_tag=5, texture=1, sampler=1,
       * varying=1, work_registers=2 for t720-copy-16x16.bin.
       */
      cfg.shader.shader = VA + OFF_SHADER + 5;
      cfg.shader.texture_count = 1;
      cfg.shader.sampler_count = 1;
      cfg.shader.varying_count = 1;
      cfg.properties.work_register_count = 2;
      cfg.properties.force_early_z = true;
      cfg.multisample_misc.sample_mask = 0xffff;
      cfg.multisample_misc.depth_function = MALI_FUNC_ALWAYS;
      cfg.stencil_mask_misc.alpha_test_compare_function = MALI_FUNC_ALWAYS;
      cfg.stencil_mask_misc.write_enable = true;
      cfg.stencil_mask_misc.dither_disable = true;
      cfg.blend_equation.rgb.a = MALI_BLEND_OPERAND_A_SRC;
      cfg.blend_equation.rgb.b = MALI_BLEND_OPERAND_B_SRC;
      cfg.blend_equation.rgb.c = MALI_BLEND_OPERAND_C_ZERO;
      cfg.blend_equation.alpha.a = MALI_BLEND_OPERAND_A_SRC;
      cfg.blend_equation.alpha.b = MALI_BLEND_OPERAND_B_SRC;
      cfg.blend_equation.alpha.c = MALI_BLEND_OPERAND_C_ZERO;
      cfg.blend_equation.color_mask = 0xf;
   }
   pan_pack((struct mali_texture_packed *)(d + OFF_TEXTURE), TEXTURE, cfg) {
      cfg.width = 16;
      cfg.height = 16;
      cfg.array_size = 1;
      cfg.format = (MALI_RGBA8_UNORM << 12) | 0x688; /* RGBA */
      cfg.dimension = MALI_TEXTURE_DIMENSION_2D;
      cfg.texel_ordering = MALI_TEXTURE_LAYOUT_LINEAR;
      cfg.swizzle = 0x688;
   }
   pan_pack((struct mali_surface_with_stride_packed *)(d + OFF_SURFACE), SURFACE_WITH_STRIDE, cfg) {
      cfg.pointer = VA + OFF_SOURCE;
      cfg.row_stride = 64;
      cfg.surface_stride = 1024;
   }
   *(uint64_t *)(d + OFF_TEX_TABLE) = VA + OFF_TEXTURE;
   pan_pack((struct mali_sampler_packed *)(d + OFF_SAMPLER), SAMPLER, cfg) {
      cfg.normalized_coordinates = false;
      cfg.seamless_cube_map = false;
      cfg.minify_nearest = true;
      cfg.magnify_nearest = true;
   }
   pan_pack((struct mali_attribute_packed *)(d + OFF_VARYING), ATTRIBUTE, cfg) {
      cfg.buffer_index = 0;
      cfg.offset_enable = true; /* required on Midgard v4 */
      cfg.format = (MALI_RGB32F << 12) | 0xa88; /* RGB1 */
   }
   pan_pack((struct mali_attribute_buffer_packed *)(d + OFF_VARYING_BUFFER), ATTRIBUTE_BUFFER, cfg) {
      cfg.pointer = VA + OFF_COORDS;
      cfg.stride = 16;
      cfg.size = 64;
   }
   const float rect[16] = {0,0,0,1, 16,0,0,1, 0,16,0,1, 16,16,0,1};
   memcpy(d + OFF_COORDS, rect, sizeof(rect));
   pan_pack((struct mali_viewport_packed *)(d + OFF_VIEWPORT), VIEWPORT, cfg) {
      cfg.scissor_maximum_x = 15;
      cfg.scissor_maximum_y = 15;
   }
   /* All texels are opaque red; the first hardware test checks 256 samples.
    * A second patterned test is required before using this for arbitrary UI.
    */
   for (unsigned i = 0; i < 256; ++i)
      ((uint32_t *)(d + OFF_SOURCE))[i] = 0xff0000ff;

   FILE *out = fopen(argv[2], "wb");
   if (!out) return 1;
   size_t written = fwrite(d, 1, sizeof(d), out);
   int err = fclose(out);
   if (written != sizeof(d) || err) return 1;
   fprintf(stderr, "T720 descriptor page=%zu shader=%zu tiler=0x%x texture=0x%x\n",
           sizeof(d), shader_len, OFF_TILER, OFF_TEXTURE);
   return 0;
}
