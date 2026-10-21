/* SPDX-License-Identifier: MIT
 * Host-only bounded T720 descriptor fixture for the translated QuartzCore
 * read_surf pair. This is not a device command submission path.
 */
#define PAN_ARCH 4
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"

enum {
   BYTES = 0x3000, HEAP = 0x2000, HEAP_BYTES = 0x1000,
   PSIZ_SWIZZLE = MALI_CHANNEL_R | (MALI_CHANNEL_0 << 3) |
      (MALI_CHANNEL_0 << 6) | (MALI_CHANNEL_1 << 9),
   VERTEX_JOB = 0x000, TILER_JOB = 0x100, FRAGMENT_JOB = 0x200,
   FB = 0x300, VS_RSD = 0x500, FS_RSD = 0x540,
   TEXTURE = 0x600, SURFACE = 0x620, TEX_TABLE = 0x660,
   SAMPLER = 0x680, UBO_DESC = 0x6c0,
   VS_ATTRS = 0x700, VS_ATTR_BUFS = 0x7a0,
   VS_VARYINGS = 0x7c0, VS_VARY_BUFS = 0x7e0,
   FS_VARYINGS = 0x820, FS_VARY_BUFS = 0x840, VIEWPORT = 0x860,
   UBO_DATA = 0x880, FS_SHADER = 0x900, VS_SHADER = 0xe00,
   POS_BUF = 0xf00, PSIZ_BUF = 0xf40,
   POLY = 0x1000, POLY_BODY = 0x1200, POLY_BYTES = 0xa00,
};

static void put32(uint8_t *d, size_t off, uint32_t v)
{
   memcpy(d + off, &v, 4);
}

static void put64(uint8_t *d, size_t off, uint64_t v)
{
   memcpy(d + off, &v, 8);
}

static uint64_t fnv1a64(const uint8_t *p, size_t n)
{
   uint64_t h = UINT64_C(0xcbf29ce484222325);
   for (size_t i = 0; i < n; i++)
      h = (h ^ p[i]) * UINT64_C(0x100000001b3);
   return h;
}

static int read_exact(const char *path, uint8_t *dst, size_t n, uint64_t hash)
{
   FILE *f = fopen(path, "rb");
   if (!f) return 0;
   size_t got = fread(dst, 1, n, f);
   int extra = fgetc(f);
   fclose(f);
   return got == n && extra == EOF && fnv1a64(dst, n) == hash;
}

static int parse_u64(const char *text, uint64_t *out)
{
   char *end = NULL;
   errno = 0;
   unsigned long long val = strtoull(text, &end, 0);
   if (errno || !end || *end || end == text) return 0;
   *out = val;
   return 1;
}

static int valid_va(uint64_t va, uint64_t size)
{
   return va && !(va & 4095) && size && size <= (1ULL << 40) &&
          va <= (1ULL << 40) - size;
}

static int overlap(uint64_t a, uint64_t alen, uint64_t b, uint64_t blen)
{
   return a < b + blen && b < a + alen;
}

static int validate_layout(void)
{
   if (POLY_BODY != POLY + 0x200 || POS_BUF + 64 > POLY)
      return 0;
   struct region { const char *name; unsigned off, len; };
   const struct region r[] = {
      {"vertex_job", VERTEX_JOB, 0xc0}, {"tiler_job", TILER_JOB, 0xc0},
      {"fragment_job", FRAGMENT_JOB, 0x40},
      {"framebuffer", FB, pan_size(FRAMEBUFFER)},
      {"vs_rsd", VS_RSD, pan_size(RENDERER_STATE)},
      {"fs_rsd", FS_RSD, pan_size(RENDERER_STATE)},
      {"texture", TEXTURE, pan_size(TEXTURE)},
      {"surface", SURFACE, pan_size(SURFACE_WITH_STRIDE)},
      {"texture_table", TEX_TABLE, 8},
      {"sampler", SAMPLER, pan_size(SAMPLER)},
      {"ubo_desc", UBO_DESC, pan_size(UNIFORM_BUFFER)},
      {"vs_attrs", VS_ATTRS, 17 * pan_size(ATTRIBUTE)},
      {"vertex_id_buffer", VS_ATTR_BUFS, pan_size(ATTRIBUTE_VERTEX_ID)},
      {"vs_varyings", VS_VARYINGS, 2 * pan_size(ATTRIBUTE)},
      {"vs_varying_buffers", VS_VARY_BUFS, 2 * pan_size(ATTRIBUTE_BUFFER)},
      {"fs_varyings", FS_VARYINGS, pan_size(ATTRIBUTE)},
      {"fs_varying_buffer", FS_VARY_BUFS, pan_size(ATTRIBUTE_BUFFER)},
      {"viewport", VIEWPORT, pan_size(VIEWPORT)},
      {"ubo_data", UBO_DATA, 80},
      {"fs_shader", FS_SHADER, 1232}, {"vs_shader", VS_SHADER, 208},
      /* Body starts at POLY+0x200 and is part of the whole 0xa00 region. */
      {"polygon_list_and_body", POLY, POLY_BYTES},
      {"position_buffer", POS_BUF, 64},
      {"pointsize_buffer", PSIZ_BUF, 16},
      {"tiler_heap", HEAP, HEAP_BYTES},
   };
   for (unsigned i = 0; i < sizeof(r) / sizeof(r[0]); ++i) {
      if (r[i].off + r[i].len > BYTES) {
         fprintf(stderr, "%s exceeds descriptor page\n", r[i].name);
         return 0;
      }
      for (unsigned j = i + 1; j < sizeof(r) / sizeof(r[0]); ++j)
         if (overlap(r[i].off, r[i].len, r[j].off, r[j].len)) {
            fprintf(stderr, "descriptor overlap: %s/%s\n", r[i].name,
                    r[j].name);
            return 0;
         }
   }
   return 1;
}

static void framebuffer(uint8_t *d, uint64_t va, uint64_t dst,
                        unsigned width, unsigned height, unsigned stride)
{
   const size_t fb = FB;
   put32(d, fb + 4, 31);
   put32(d, fb + 8 * 4, 0xb84da201u | (1u << 30));
   put32(d, fb + 9 * 4, 0x00141000u); /* linear BGRA8 writeback */
   put32(d, fb + 10 * 4, 0);
   put32(d, fb + 11 * 4, ((height - 1) << 16) | (width - 1));
   put64(d, fb + 20 * 4, dst);
   put32(d, fb + 22 * 4, stride);
   put64(d, fb + 32 * 4, dst);         /* preload destination */
   put32(d, fb + 34 * 4, stride);
   put32(d, fb + 35 * 4, stride * height);
   put64(d, fb + 25 * 8, va + POLY);
   put64(d, fb + 26 * 8, va + POLY_BODY);
   put64(d, fb + 27 * 8, va + HEAP);
   put64(d, fb + 28 * 8, va + HEAP + HEAP_BYTES);
   unsigned bins = ((width + 1023) / 1024) * ((height + 1023) / 1024);
   put32(d, fb + 48 * 4, 0x200 + bins * 0x200);
   put32(d, fb + 49 * 4, 0x01c7);
   put32(d, POLY_BODY, 0xa0000000u);
}

static void renderer_states(uint8_t *d, uint64_t va)
{
   pan_pack((struct mali_renderer_state_packed *)(d + VS_RSD),
            RENDERER_STATE, cfg) {
      cfg.shader.shader = va + VS_SHADER + 5;
      cfg.shader.attribute_count = 17; /* raw vertex ID special at slot 16 */
      cfg.shader.varying_count = 2;   /* position, point size */
      cfg.properties.work_register_count = 1;
      cfg.properties.force_early_z = true;
      cfg.multisample_misc.sample_mask = 0xffff;
      cfg.multisample_misc.depth_function = MALI_FUNC_ALWAYS;
   }
   pan_pack((struct mali_renderer_state_packed *)(d + FS_RSD),
            RENDERER_STATE, cfg) {
      cfg.shader.shader = va + FS_SHADER + 5;
      cfg.shader.texture_count = 1;
      cfg.shader.sampler_count = 1; /* T720 fetch ABI needs sampler0 */
      cfg.shader.varying_count = 1; /* fragment position */
      cfg.properties.uniform_buffer_count = 1;
      cfg.properties.work_register_count = 6;
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
}

static void resources(uint8_t *d, uint64_t va, uint64_t src,
                      uint64_t pos, uint64_t psiz,
                      unsigned width, unsigned height, unsigned stride,
                      uint32_t color_rule)
{
   pan_pack((struct mali_texture_packed *)(d + TEXTURE), TEXTURE, cfg) {
      cfg.width = width;
      cfg.height = height;
      cfg.array_size = 1;
      cfg.levels = 1;
      cfg.format = (MALI_RGBA8_UNORM << 12) | 0x60a; /* BGRA */
      cfg.dimension = MALI_TEXTURE_DIMENSION_2D;
      cfg.texel_ordering = MALI_TEXTURE_LAYOUT_LINEAR;
      cfg.swizzle = 0x60a;
   }
   pan_pack((struct mali_surface_with_stride_packed *)(d + SURFACE),
            SURFACE_WITH_STRIDE, cfg) {
      cfg.pointer = src;
      cfg.row_stride = stride;
      cfg.surface_stride = stride * height;
   }
   put64(d, TEX_TABLE, va + TEXTURE);
   pan_pack((struct mali_sampler_packed *)(d + SAMPLER), SAMPLER, cfg) {
      cfg.normalized_coordinates = false;
      cfg.seamless_cube_map = false;
      cfg.minify_nearest = true;
      cfg.magnify_nearest = true;
   }
   pan_pack((struct mali_uniform_buffer_packed *)(d + UBO_DESC),
            UNIFORM_BUFFER, cfg) {
      cfg.entries = 5; /* 80-byte host parameter block */
      cfg.pointer = va + UBO_DATA;
   }
   put32(d, UBO_DATA + 0, 1); /* levels */
   put32(d, UBO_DATA + 4, width);
   put32(d, UBO_DATA + 8, height);
   put32(d, UBO_DATA + 64, color_rule);

   /* LD_ATTR16 first selects an ordinary ATTRIBUTE, whose buffer index
    * selects the separate Midgard vertex-ID special BUFFER descriptor. */
   pan_pack((struct mali_attribute_vertex_id_packed *)(d + VS_ATTR_BUFS),
            ATTRIBUTE_VERTEX_ID, cfg) {
      cfg.divisor_r = 0x1f;
      cfg.divisor_p = 0x4;
   }
   pan_pack((struct mali_attribute_packed *)(d + VS_ATTRS + 16 * pan_size(ATTRIBUTE)),
            ATTRIBUTE, cfg) {
      cfg.buffer_index = 0;
      cfg.format = (MALI_R32UI << 12) | PSIZ_SWIZZLE;
   }
   pan_pack((struct mali_attribute_packed *)(d + VS_VARYINGS), ATTRIBUTE, cfg) {
      cfg.buffer_index = 0;
      cfg.offset_enable = true;
      cfg.format = (MALI_SNAP_4 << 12) | 0x688;
   }
   pan_pack((struct mali_attribute_packed *)(d + VS_VARYINGS + 8), ATTRIBUTE, cfg) {
      cfg.buffer_index = 1;
      cfg.offset_enable = true;
      cfg.format = (MALI_R16F << 12) | PSIZ_SWIZZLE;
   }
   pan_pack((struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS),
            ATTRIBUTE_BUFFER, cfg) {
      cfg.pointer = pos;
      cfg.stride = 16;
      cfg.size = 64;
   }
   pan_pack((struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS + pan_size(ATTRIBUTE_BUFFER)),
            ATTRIBUTE_BUFFER, cfg) {
      cfg.pointer = psiz;
      cfg.stride = 2;
      cfg.size = 8;
   }
   pan_pack((struct mali_attribute_packed *)(d + FS_VARYINGS), ATTRIBUTE, cfg) {
      cfg.buffer_index = 0;
      cfg.offset_enable = true;
      cfg.format = (MALI_RGBA32F << 12) | 0x688;
   }
   pan_pack((struct mali_attribute_buffer_packed *)(d + FS_VARY_BUFS),
            ATTRIBUTE_BUFFER, cfg) {
      cfg.pointer = pos;
      cfg.stride = 16;
      cfg.size = 64;
   }
}

static void jobs(uint8_t *d, uint64_t va, uint64_t pos,
                 unsigned width, unsigned height)
{
   pan_pack((struct mali_job_header_packed *)(d + VERTEX_JOB), JOB_HEADER, cfg) {
      cfg.type = MALI_JOB_TYPE_VERTEX;
      cfg.index = 1;
      cfg.next = va + TILER_JOB;
   }
   pan_pack((struct mali_invocation_packed *)(d + VERTEX_JOB + 32),
            INVOCATION, cfg) {
      cfg.invocations = 3; /* four vertex IDs: 0..3 */
      cfg.workgroups_z_shift = 32;
      cfg.thread_group_split = 2;
   }
   pan_pack((struct mali_compute_job_parameters_packed *)(d + VERTEX_JOB +
            MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET), COMPUTE_JOB_PARAMETERS, cfg) {
      cfg.job_task_split = 5;
   }
   pan_pack((struct mali_draw_packed *)(d + VERTEX_JOB + 64), DRAW, cfg) {
      cfg.state = va + VS_RSD;
      cfg.attributes = va + VS_ATTRS;
      cfg.attribute_buffers = va + VS_ATTR_BUFS;
      cfg.varyings = va + VS_VARYINGS;
      cfg.varying_buffers = va + VS_VARY_BUFS;
      cfg.thread_storage = va + FB;
   }
   pan_pack((struct mali_job_header_packed *)(d + TILER_JOB), JOB_HEADER, cfg) {
      cfg.type = MALI_JOB_TYPE_TILER;
      cfg.index = 2;
      cfg.dependency_1 = 1;
      cfg.enable_texture_mapper = true;
   }
   pan_pack((struct mali_invocation_packed *)(d + TILER_JOB + 32),
            INVOCATION, cfg) {
      cfg.invocations = 3;
      cfg.workgroups_z_shift = 32;
      cfg.thread_group_split = 2;
   }
   pan_pack((struct mali_primitive_packed *)(d + TILER_JOB + 40),
            PRIMITIVE, cfg) {
      cfg.draw_mode = MALI_DRAW_MODE_TRIANGLE_STRIP;
      cfg.index_count = 4;
      cfg.job_task_split = 6;
   }
   pan_pack((struct mali_draw_packed *)(d + TILER_JOB + 64), DRAW, cfg) {
      cfg.position = pos;
      cfg.viewport = va + VIEWPORT;
      cfg.varyings = va + FS_VARYINGS;
      cfg.varying_buffers = va + FS_VARY_BUFS;
      cfg.uniform_buffers = va + UBO_DESC;
      cfg.textures = va + TEX_TABLE;
      cfg.samplers = va + SAMPLER;
      cfg.state = va + FS_RSD;
      cfg.fbd = va + FB;
   }
   pan_pack((struct mali_primitive_size_packed *)(d + TILER_JOB + 184),
            PRIMITIVE_SIZE, cfg) {
      cfg.fixed_sized = 1.0f;
   }
   pan_pack((struct mali_viewport_packed *)(d + VIEWPORT), VIEWPORT, cfg) {
      cfg.scissor_maximum_x = width - 1;
      cfg.scissor_maximum_y = height - 1;
   }
   pan_pack((struct mali_job_header_packed *)(d + FRAGMENT_JOB), JOB_HEADER, cfg) {
      cfg.type = MALI_JOB_TYPE_FRAGMENT;
      cfg.index = 3;
      cfg.enable_texture_mapper = true;
   }
   pan_pack((struct mali_fragment_job_payload_packed *)(d + FRAGMENT_JOB + 32),
            FRAGMENT_JOB_PAYLOAD, cfg) {
      cfg.bound_max_x = (width - 1) >> MALI_TILE_SHIFT;
      cfg.bound_max_y = (height - 1) >> MALI_TILE_SHIFT;
      cfg.framebuffer = va + FB;
   }
}

static int validate_descriptor(const uint8_t *d, uint64_t va, uint64_t src,
                               uint64_t dst, uint64_t pos, uint64_t psiz,
                               unsigned width, unsigned height)
{
   pan_unpack((const struct mali_job_header_packed *)(d + VERTEX_JOB),
              JOB_HEADER, vj);
   pan_unpack((const struct mali_job_header_packed *)(d + TILER_JOB),
              JOB_HEADER, tj);
   pan_unpack((const struct mali_job_header_packed *)(d + FRAGMENT_JOB),
              JOB_HEADER, fj);
   pan_unpack((const struct mali_draw_packed *)(d + VERTEX_JOB + 64), DRAW, vd);
   pan_unpack((const struct mali_compute_job_parameters_packed *)(d + VERTEX_JOB +
              MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET), COMPUTE_JOB_PARAMETERS, vp);
   pan_unpack((const struct mali_attribute_packed *)(d + VS_ATTRS + 16 * pan_size(ATTRIBUTE)),
              ATTRIBUTE, vertex_id);
   pan_unpack((const struct mali_attribute_vertex_id_packed *)(d + VS_ATTR_BUFS),
              ATTRIBUTE_VERTEX_ID, vertex_id_buffer);
   pan_unpack((const struct mali_attribute_packed *)(d + VS_VARYINGS), ATTRIBUTE, pos_attr);
   pan_unpack((const struct mali_attribute_packed *)(d + VS_VARYINGS + pan_size(ATTRIBUTE)),
              ATTRIBUTE, ps_attr);
   pan_unpack((const struct mali_draw_packed *)(d + TILER_JOB + 64), DRAW, td);
   pan_unpack((const struct mali_renderer_state_packed *)(d + VS_RSD),
              RENDERER_STATE, vs);
   pan_unpack((const struct mali_renderer_state_packed *)(d + FS_RSD),
              RENDERER_STATE, fs);
   pan_unpack((const struct mali_texture_packed *)(d + TEXTURE), TEXTURE, tex);
   pan_unpack((const struct mali_surface_with_stride_packed *)(d + SURFACE),
              SURFACE_WITH_STRIDE, surface);
   pan_unpack((const struct mali_uniform_buffer_packed *)(d + UBO_DESC),
              UNIFORM_BUFFER, ubo);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS),
              ATTRIBUTE_BUFFER, vb);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS + pan_size(ATTRIBUTE_BUFFER)),
              ATTRIBUTE_BUFFER, pb);
   pan_unpack((const struct mali_fragment_job_payload_packed *)(d + FRAGMENT_JOB + 32),
              FRAGMENT_JOB_PAYLOAD, fp);
   pan_unpack((const struct mali_tiler_context_packed *)(d + FB +
              MALI_FRAMEBUFFER_SECTION_TILER_OFFSET), TILER_CONTEXT, tiler);
   uint64_t table = 0, fb_target = 0;
   uint32_t poly_size = 0, color_rule = 0;
   memcpy(&table, d + TEX_TABLE, 8);
   memcpy(&fb_target, d + FB + 20 * 4, 8);
   memcpy(&poly_size, d + FB + 48 * 4, 4);
   memcpy(&color_rule, d + UBO_DATA + 64, 4);
   int ok = vj.type == MALI_JOB_TYPE_VERTEX && vj.index == 1 &&
            vj.next == va + TILER_JOB &&
            tj.type == MALI_JOB_TYPE_TILER && tj.index == 2 &&
            tj.dependency_1 == 1 &&
            fj.type == MALI_JOB_TYPE_FRAGMENT && fj.index == 3 &&
            vp.job_task_split == 5 &&
            vd.state == va + VS_RSD && td.state == va + FS_RSD &&
            vd.thread_storage == va + FB &&
            vd.attribute_buffers == va + VS_ATTR_BUFS &&
            vertex_id.buffer_index == 0 &&
            vertex_id.format == ((MALI_R32UI << 12) | PSIZ_SWIZZLE) &&
            vertex_id_buffer.type == MALI_ATTRIBUTE_SPECIAL_VERTEX_ID &&
            vertex_id_buffer.divisor_r == 31 && vertex_id_buffer.divisor_p == 4 &&
            vd.attributes == va + VS_ATTRS && td.textures == va + TEX_TABLE &&
            td.uniform_buffers == va + UBO_DESC && td.fbd == va + FB &&
            vs.shader.shader == va + VS_SHADER + 5 &&
            fs.shader.shader == va + FS_SHADER + 5 &&
            fs.shader.texture_count == 1 && fs.shader.sampler_count == 1 &&
            fs.properties.uniform_buffer_count == 1 &&
            tex.width == width && tex.height == height && tex.levels == 1 &&
            surface.pointer == src && table == va + TEXTURE &&
            ubo.pointer == va + UBO_DATA && ubo.entries == 5 &&
            pos_attr.buffer_index == 0 && pos_attr.format == ((MALI_SNAP_4 << 12) | 0x688) &&
            ps_attr.buffer_index == 1 && ps_attr.format == ((MALI_R16F << 12) | PSIZ_SWIZZLE) &&
            vb.pointer == pos && vb.stride == 16 && vb.size == 64 &&
            pb.pointer == psiz && pb.stride == 2 && pb.size == 8 &&
            fp.bound_min_x == 0 && fp.bound_min_y == 0 &&
            fp.bound_max_x == ((width - 1) >> MALI_TILE_SHIFT) &&
            fp.bound_max_y == ((height - 1) >> MALI_TILE_SHIFT) &&
            fp.framebuffer == va + FB && fb_target == dst &&
            tiler.heap_start == va + HEAP &&
            tiler.heap_end == va + HEAP + HEAP_BYTES &&
            tiler.heap_end <= va + BYTES &&
            !overlap(tiler.heap_start, HEAP_BYTES, va + POLY, POLY_BYTES) &&
            poly_size == POLY_BYTES && color_rule == 0x2222;
   if (!ok) fprintf(stderr, "packed descriptor readback mismatch\n");
   return ok;
}

int main(int argc, char **argv)
{
   if (argc != 11) {
      fprintf(stderr, "usage: %s vert.midgard frag.midgard output.bin "
                      "width height source_va dest_va position_va "
                      "pointsize_va descriptor_va\n", argv[0]);
      return 2;
   }
   uint64_t width, height, src, dst, pos, psiz, va;
   if (!validate_layout()) return 1;
   if (!parse_u64(argv[4], &width) || !parse_u64(argv[5], &height) ||
       !parse_u64(argv[6], &src) || !parse_u64(argv[7], &dst) ||
       !parse_u64(argv[8], &pos) || !parse_u64(argv[9], &psiz) ||
       !parse_u64(argv[10], &va) ||
       width != 1080 || height != 1920)
      return 2;
   uint64_t image_bytes = width * height * 4;
   int internal_varyings = pos == va + POS_BUF && psiz == va + PSIZ_BUF;
   if (!valid_va(src, image_bytes) || !valid_va(dst, image_bytes) ||
       !valid_va(va, BYTES) ||
       (!internal_varyings && (!valid_va(pos, 64) || !valid_va(psiz, 16))))
      return 2;
   const uint64_t starts[] = {src, dst, pos, psiz, va};
   const uint64_t sizes[] = {image_bytes, image_bytes, 64, 16, BYTES};
   for (unsigned i = 0; i < 5; i++)
      for (unsigned j = i + 1; j < 5; j++)
         if (!(internal_varyings && i >= 2 && j == 4) &&
             overlap(starts[i], sizes[i], starts[j], sizes[j]))
            return 2;

   uint8_t d[BYTES] = {0};
   if (!read_exact(argv[1], d + VS_SHADER, 208,
                   UINT64_C(0x2e958a2764614f77)) ||
       !read_exact(argv[2], d + FS_SHADER, 1232,
                   UINT64_C(0xa7cb167cf3ff7756))) {
      fprintf(stderr, "shader bytes differ from the tested read_surf pair\n");
      return 2;
   }
   framebuffer(d, va, dst, width, height, width * 4);
   renderer_states(d, va);
   resources(d, va, src, pos, psiz, width, height, width * 4, 0x2222);
   jobs(d, va, pos, width, height);
   if (!validate_descriptor(d, va, src, dst, pos, psiz, width, height))
      return 1;

   FILE *f = fopen(argv[3], "wb");
   if (!f) return 1;
   size_t written = fwrite(d, 1, sizeof(d), f);
   int close_rc = fclose(f);
   if (written != sizeof(d) || close_rc) return 1;
   printf("host descriptor bytes=%u vertex=0x%llx tiler=0x%llx "
          "fragment=0x%llx source=0x%llx target=0x%llx\n",
          BYTES, (unsigned long long)(va + VERTEX_JOB),
          (unsigned long long)(va + TILER_JOB),
          (unsigned long long)(va + FRAGMENT_JOB),
          (unsigned long long)src, (unsigned long long)dst);
   return 0;
}
