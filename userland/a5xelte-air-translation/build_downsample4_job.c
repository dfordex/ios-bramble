/* SPDX-License-Identifier: MIT
 * Host-only bounded T720 descriptor fixture for the translated QuartzCore
 * downsample_4 pair. Input shader bytes are supplied from private staging.
 * Fixed fixture: 64x64 source, 32x32 destination, actual 1080x1920 shader
 * viewport preserved through the MVP. Generated binary stays outside Git.
 */
#define PAN_ARCH 4
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "genxml/v4_pack.h"
#include "downsample_reference.h"

enum {
   BYTES = 0x4000, SRC_BYTES = 0x4000, DST_BYTES = 0x1000,
   SOURCE = 0x4000, DESTINATION = 0x8000,
   HEAP = 0x9000, HEAP_BYTES = 0x1000, GUARDS = 0xa000,
   PRIVATE_BYTES = 0xc000,
   PSIZ_SWIZZLE = MALI_CHANNEL_R | (MALI_CHANNEL_0 << 3) |
      (MALI_CHANNEL_0 << 6) | (MALI_CHANNEL_1 << 9),
   VERTEX_JOB = 0, TILER_JOB = 0x100, FRAGMENT_JOB = 0x200,
   FB = 0x300, VS_RSD = 0x500, FS_RSD = 0x540,
   TEXTURE = 0x600, SURFACE = 0x620, TEX_TABLE = 0x660,
   SAMPLER = 0x680, VS_UBO_DESC = 0x6c0, FS_UBO_DESC = 0x6e0,
   VS_ATTRS = 0x740, VS_ATTR_BUFS = 0x780,
   VS_VARYINGS = 0x7c0, VS_VARY_BUFS = 0x800,
   FS_VARYINGS = 0x880, FS_VARY_BUFS = 0x8a0, VIEWPORT = 0x8e0,
   FS_PUSH = 0x900, VS_PUSH = 0x980,
   MVP_DATA = 0xa00, TEXMAT_DATA = 0xa40, FILTER_DATA = 0xa80,
   EDR_DATA = 0xb00, VERTEX_DATA = 0xc00,
   POS_BUF = 0xd00, PSIZ_BUF = 0xd40, UV_BUF = 0xd80,
   VS_SHADER = 0x1800, VS_BYTES = 2048,
   FS_SHADER = 0x2000, FS_BYTES = 3472,
   POLY = 0x3000, POLY_BODY = 0x3200, POLY_BYTES = 0xa00,
   SRC_WIDTH = A5DownsampleSourceWidth, SRC_HEIGHT = A5DownsampleSourceHeight,
   DST_WIDTH = A5DownsampleDestinationWidth,
   DST_HEIGHT = A5DownsampleDestinationHeight,
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
   struct region { const char *name; unsigned off, len; };
   const struct region r[] = {
      {"vertex_job", VERTEX_JOB, 0xc0}, {"tiler_job", TILER_JOB, 0xc0},
      {"fragment_job", FRAGMENT_JOB, 0x40}, {"framebuffer", FB, 0x100},
      {"vs_rsd", VS_RSD, pan_size(RENDERER_STATE)},
      {"fs_rsd", FS_RSD, pan_size(RENDERER_STATE)},
      {"texture", TEXTURE, pan_size(TEXTURE)},
      {"surface", SURFACE, pan_size(SURFACE_WITH_STRIDE)},
      {"texture_table", TEX_TABLE, 8}, {"sampler", SAMPLER, pan_size(SAMPLER)},
      {"vs_ubos", VS_UBO_DESC, 3 * pan_size(UNIFORM_BUFFER)},
      {"fs_ubos", FS_UBO_DESC, 5 * pan_size(UNIFORM_BUFFER)},
      {"vs_attrs", VS_ATTRS, 4 * pan_size(ATTRIBUTE)},
      {"vs_attr_buffer", VS_ATTR_BUFS, 32},
      {"vs_varyings", VS_VARYINGS, 3 * pan_size(ATTRIBUTE)},
      {"vs_varying_buffers", VS_VARY_BUFS, 3 * pan_size(ATTRIBUTE_BUFFER)},
      {"fs_varyings", FS_VARYINGS, pan_size(ATTRIBUTE)},
      {"fs_varying_buffer", FS_VARY_BUFS, 32},
      {"viewport", VIEWPORT, pan_size(VIEWPORT)},
      {"fragment_push", FS_PUSH, 80}, {"vertex_push", VS_PUSH, 80},
      {"mvp", MVP_DATA, 64}, {"texmat", TEXMAT_DATA, 16},
      {"filter", FILTER_DATA, 80}, {"edr", EDR_DATA, 16},
      {"vertices", VERTEX_DATA, 4 * 48},
      {"position_buffer", POS_BUF, 64}, {"pointsize_buffer", PSIZ_BUF, 16},
      {"texcoord_buffer", UV_BUF, 32},
      {"vs_shader", VS_SHADER, VS_BYTES}, {"fs_shader", FS_SHADER, FS_BYTES},
      {"polygon_list_and_body", POLY, POLY_BYTES},
   };
   for (unsigned i = 0; i < sizeof(r) / sizeof(r[0]); ++i) {
      if (r[i].off + r[i].len > BYTES) return 0;
      for (unsigned j = i + 1; j < sizeof(r) / sizeof(r[0]); ++j)
         if (overlap(r[i].off, r[i].len, r[j].off, r[j].len)) {
            fprintf(stderr, "descriptor overlap: %s/%s\n",r[i].name,r[j].name);
            return 0;
         }
   }
   /* These are separate ranges of the caller's pinned private mapping. Only
    * the descriptor is emitted here; the kernel initializes source/destination,
    * zeroes the real tiler heap and places guard words after its exclusive end. */
   const struct region windows[] = {
      {"descriptor", 0, BYTES}, {"source", SOURCE, SRC_BYTES},
      {"destination", DESTINATION, DST_BYTES}, {"tiler_heap", HEAP, HEAP_BYTES},
      {"guards", GUARDS, PRIVATE_BYTES - GUARDS},
   };
   if ((HEAP & 4095) || !HEAP_BYTES || (HEAP_BYTES & 4095) ||
       HEAP + HEAP_BYTES != GUARDS) return 0;
   for (unsigned i = 0; i < sizeof(windows) / sizeof(windows[0]); ++i) {
      if (windows[i].off + windows[i].len > PRIVATE_BYTES) return 0;
      for (unsigned j = i + 1; j < sizeof(windows) / sizeof(windows[0]); ++j)
         if (overlap(windows[i].off, windows[i].len,
                     windows[j].off, windows[j].len)) return 0;
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
      cfg.shader.attribute_count = 4; /* real interleaved QC attribute layout */
      cfg.shader.varying_count = 3; /* position, point size, texcoord0 */
      cfg.properties.uniform_buffer_count = 3;
      cfg.properties.work_register_count = 8;
      cfg.properties.force_early_z = true;
      cfg.multisample_misc.sample_mask = 0xffff;
      cfg.multisample_misc.depth_function = MALI_FUNC_ALWAYS;
   }
   pan_pack((struct mali_renderer_state_packed *)(d + FS_RSD),
            RENDERER_STATE, cfg) {
      cfg.shader.shader = va + FS_SHADER + 5;
      cfg.shader.texture_count = 1;
      cfg.shader.sampler_count = 1; /* T720 fetch ABI needs sampler0 */
      cfg.shader.varying_count = 1; /* perspective texcoord0 */
      cfg.properties.uniform_buffer_count = 5;
      cfg.properties.work_register_count = 7;
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

static void put_float(uint8_t *d, unsigned off, float v)
{
   memcpy(d + off, &v, sizeof(v));
}

static void ubo(uint8_t *d, unsigned table, unsigned index,
                uint64_t pointer, unsigned bytes)
{
   pan_pack((struct mali_uniform_buffer_packed *)(d + table + index * 8),
            UNIFORM_BUFFER, cfg) {
      cfg.pointer = pointer;
      cfg.entries = (bytes + 15) / 16;
   }
}

static void attribute(uint8_t *d, unsigned at, unsigned buffer,
                      unsigned format, unsigned offset)
{
   pan_pack((struct mali_attribute_packed *)(d + at), ATTRIBUTE, cfg) {
      cfg.buffer_index = buffer;
      cfg.offset_enable = true;
      cfg.format = (format << 12) | 0x688;
      cfg.offset = offset;
   }
}

static void attr_buffer(uint8_t *d, unsigned at, uint64_t pointer,
                        unsigned stride, unsigned bytes)
{
   pan_pack((struct mali_attribute_buffer_packed *)(d + at),
            ATTRIBUTE_BUFFER, cfg) {
      cfg.pointer = pointer; cfg.stride = stride; cfg.size = bytes;
   }
}

static void resources(uint8_t *d, uint64_t va, uint64_t src)
{
   pan_pack((struct mali_texture_packed *)(d + TEXTURE), TEXTURE, cfg) {
      cfg.width = SRC_WIDTH; cfg.height = SRC_HEIGHT;
      cfg.array_size = 1; cfg.levels = 1;
      cfg.format = (MALI_RGBA8_UNORM << 12) | 0x60a;
      cfg.dimension = MALI_TEXTURE_DIMENSION_2D;
      cfg.texel_ordering = MALI_TEXTURE_LAYOUT_LINEAR;
      cfg.swizzle = 0x60a;
   }
   pan_pack((struct mali_surface_with_stride_packed *)(d + SURFACE),
            SURFACE_WITH_STRIDE, cfg) {
      cfg.pointer = src; cfg.row_stride = SRC_WIDTH * 4;
      cfg.surface_stride = SRC_WIDTH * SRC_HEIGHT * 4;
   }
   put64(d, TEX_TABLE, va + TEXTURE);
   pan_pack((struct mali_sampler_packed *)(d + SAMPLER), SAMPLER, cfg) {
      cfg.normalized_coordinates = true;
      cfg.seamless_cube_map = false;
      cfg.minify_nearest = true; cfg.magnify_nearest = true;
   }
   /* Stage-local metadata: sampler LOD min/max/bias at16..27 are zero;
    * bindings are at offset0 in each external Metal buffer. */
   put32(d, FS_PUSH, 1); put32(d, FS_PUSH + 4, SRC_WIDTH);
   put32(d, FS_PUSH + 8, SRC_HEIGHT);
   put32(d, FS_PUSH + 72, A5DownsampleColorWriteRule);
   ubo(d, VS_UBO_DESC, 0, va + VS_PUSH, 80);
   ubo(d, VS_UBO_DESC, 1, va + MVP_DATA, 64);
   ubo(d, VS_UBO_DESC, 2, va + TEXMAT_DATA, 16);
   ubo(d, FS_UBO_DESC, 0, va + FS_PUSH, 80);
   /* Unused holes still point to valid zero-filled data, never arbitrary VA. */
   ubo(d, FS_UBO_DESC, 1, va + VS_PUSH, 80);
   ubo(d, FS_UBO_DESC, 2, va + VS_PUSH, 80);
   ubo(d, FS_UBO_DESC, 3, va + FILTER_DATA, 80);
   ubo(d, FS_UBO_DESC, 4, va + EDR_DATA, 16);

   /* Column-major MVP: actual translated viewport stays1080x1920. */
   put_float(d, MVP_DATA, 2.0f / 1080.0f);
   put_float(d, MVP_DATA + 20, 2.0f / 1920.0f);
   put_float(d, MVP_DATA + 40, 1.0f);
   put_float(d, MVP_DATA + 48, -1.0f);
   put_float(d, MVP_DATA + 52, -1.0f);
   put_float(d, MVP_DATA + 60, 1.0f);
   put_float(d, TEXMAT_DATA, 1.0f / SRC_WIDTH);
   put_float(d, TEXMAT_DATA + 4, 1.0f / SRC_HEIGHT);

   /* Actual AIR tap order: (-,-),(+,-),(-,+),(+,+), half a source texel. */
   const uint32_t negative = A5DownsampleTapNegativeFloat;
   const uint32_t positive = A5DownsampleTapPositiveFloat;
   const uint32_t offsets[4][2] = {
      {negative, negative}, {positive, negative},
      {negative, positive}, {positive, positive},
   };
   for (unsigned i = 0; i < 4; ++i) {
      put32(d, FILTER_DATA + i * 8, offsets[i][0]);
      put32(d, FILTER_DATA + i * 8 + 4, offsets[i][1]);
   }
   const uint16_t weights[4] = {A5DownsampleWeight0Half, A5DownsampleWeight1Half,
      A5DownsampleWeight2Half, A5DownsampleWeight3Half};
   memcpy(d + FILTER_DATA + 64, weights, sizeof(weights));
   const uint16_t edr = A5DownsampleEDRHalf;
   memcpy(d + EDR_DATA, &edr, sizeof(edr));

   for (unsigned i = 0; i < 4; ++i) {
      unsigned off = VERTEX_DATA + i * 48;
      put_float(d, off, (i & 1) ? DST_WIDTH : 0);
      put_float(d, off + 4, (i & 2) ? DST_HEIGHT : 0);
      put_float(d, off + 12, 1.0f);
      put_float(d, off + 16, (i & 1) ? SRC_WIDTH : 0);
      put_float(d, off + 20, (i & 2) ? SRC_HEIGHT : 0);
   }
   attribute(d, VS_ATTRS, 0, MALI_RGBA32F, 0);
   attribute(d, VS_ATTRS + 8, 0, MALI_RG32F, 16);
   attribute(d, VS_ATTRS + 16, 0, MALI_RG32F, 24);
   attribute(d, VS_ATTRS + 24, 0, MALI_RGBA16F, 32);
   attr_buffer(d, VS_ATTR_BUFS, va + VERTEX_DATA, 48, 192);
   attribute(d, VS_VARYINGS, 0, MALI_SNAP_4, 0);
   pan_pack((struct mali_attribute_packed *)(d + VS_VARYINGS + 8), ATTRIBUTE, cfg) {
      cfg.buffer_index = 1;
      cfg.offset_enable = true;
      cfg.format = (MALI_R16F << 12) | PSIZ_SWIZZLE;
   }
   attribute(d, VS_VARYINGS + 16, 2, MALI_RG32F, 0);
   attr_buffer(d, VS_VARY_BUFS, va + POS_BUF, 16, 64);
   attr_buffer(d, VS_VARY_BUFS + pan_size(ATTRIBUTE_BUFFER), va + PSIZ_BUF, 2, 8);
   attr_buffer(d, VS_VARY_BUFS + 2 * pan_size(ATTRIBUTE_BUFFER), va + UV_BUF, 8, 32);
   attribute(d, FS_VARYINGS, 0, MALI_RG32F, 0);
   attr_buffer(d, FS_VARY_BUFS, va + UV_BUF, 8, 32);
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
   pan_pack((struct mali_draw_packed *)(d + VERTEX_JOB + 64), DRAW, cfg) {
      cfg.state = va + VS_RSD;
      cfg.attributes = va + VS_ATTRS;
      cfg.attribute_buffers = va + VS_ATTR_BUFS;
      cfg.uniform_buffers = va + VS_UBO_DESC;
      cfg.varyings = va + VS_VARYINGS;
      cfg.varying_buffers = va + VS_VARY_BUFS;
      /* Midgard local-storage descriptors reside in the framebuffer even
       * when this shader requires zero TLS/WLS bytes. */
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
      cfg.uniform_buffers = va + FS_UBO_DESC;
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
      /* Fragment bounds are inclusive tile indices, unlike pixel scissors. */
      cfg.bound_max_x = (width - 1) >> MALI_TILE_SHIFT;
      cfg.bound_max_y = (height - 1) >> MALI_TILE_SHIFT;
      cfg.framebuffer = va + FB;
   }
}

static int validate_descriptor(const uint8_t *d, uint64_t va)
{
   pan_unpack((const struct mali_job_header_packed *)(d + VERTEX_JOB), JOB_HEADER, vj);
   pan_unpack((const struct mali_job_header_packed *)(d + TILER_JOB), JOB_HEADER, tj);
   pan_unpack((const struct mali_job_header_packed *)(d + FRAGMENT_JOB), JOB_HEADER, fj);
   pan_unpack((const struct mali_draw_packed *)(d + VERTEX_JOB + 64), DRAW, vd);
   pan_unpack((const struct mali_draw_packed *)(d + TILER_JOB + 64), DRAW, td);
   pan_unpack((const struct mali_renderer_state_packed *)(d + VS_RSD), RENDERER_STATE, vs);
   pan_unpack((const struct mali_renderer_state_packed *)(d + FS_RSD), RENDERER_STATE, fs);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + VS_ATTR_BUFS), ATTRIBUTE_BUFFER, ab);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS + pan_size(ATTRIBUTE_BUFFER)), ATTRIBUTE_BUFFER, ps);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + VS_VARY_BUFS + 2 * pan_size(ATTRIBUTE_BUFFER)), ATTRIBUTE_BUFFER, uv);
   pan_unpack((const struct mali_attribute_packed *)(d + VS_VARYINGS), ATTRIBUTE, pos_attr);
   pan_unpack((const struct mali_attribute_packed *)(d + VS_VARYINGS + 8), ATTRIBUTE, ps_attr);
   pan_unpack((const struct mali_attribute_buffer_packed *)(d + FS_VARY_BUFS), ATTRIBUTE_BUFFER, fi);
   pan_unpack((const struct mali_uniform_buffer_packed *)(d + VS_UBO_DESC + 8), UNIFORM_BUFFER, matrix);
   pan_unpack((const struct mali_uniform_buffer_packed *)(d + FS_UBO_DESC + 24), UNIFORM_BUFFER, filter);
   pan_unpack((const struct mali_uniform_buffer_packed *)(d + FS_UBO_DESC + 32), UNIFORM_BUFFER, edr);
   pan_unpack((const struct mali_surface_with_stride_packed *)(d + SURFACE), SURFACE_WITH_STRIDE, surface);
   pan_unpack((const struct mali_texture_packed *)(d + TEXTURE), TEXTURE, tex);
   pan_unpack((const struct mali_sampler_packed *)(d + SAMPLER), SAMPLER, sampler);
   pan_unpack((const struct mali_viewport_packed *)(d + VIEWPORT), VIEWPORT, viewport);
   pan_unpack((const struct mali_fragment_job_payload_packed *)(d + FRAGMENT_JOB + 32),
              FRAGMENT_JOB_PAYLOAD, fragment);
   pan_unpack((const struct mali_tiler_context_packed *)(d + FB +
              MALI_FRAMEBUFFER_SECTION_TILER_OFFSET), TILER_CONTEXT, tiler);
   const unsigned formats[] = {MALI_RGBA32F, MALI_RG32F, MALI_RG32F, MALI_RGBA16F};
   const unsigned offsets[] = {0, 16, 24, 32};
   for (unsigned i = 0; i < 4; ++i) {
      pan_unpack((const struct mali_attribute_packed *)(d + VS_ATTRS + i * 8), ATTRIBUTE, attr);
      if (attr.buffer_index || attr.offset != offsets[i] ||
          attr.format != ((formats[i] << 12) | 0x688)) return 0;
   }
   const unsigned vs_offsets[] = {VS_PUSH, MVP_DATA, TEXMAT_DATA};
   const unsigned vs_sizes[] = {5, 4, 1};
   const unsigned fs_offsets[] = {FS_PUSH, VS_PUSH, VS_PUSH, FILTER_DATA, EDR_DATA};
   const unsigned fs_sizes[] = {5, 5, 5, 5, 1};
   for (unsigned i = 0; i < 3; ++i) {
      pan_unpack((const struct mali_uniform_buffer_packed *)(d + VS_UBO_DESC + i * 8), UNIFORM_BUFFER, u);
      if (u.pointer != va + vs_offsets[i] || u.entries != vs_sizes[i]) return 0;
   }
   for (unsigned i = 0; i < 5; ++i) {
      pan_unpack((const struct mali_uniform_buffer_packed *)(d + FS_UBO_DESC + i * 8), UNIFORM_BUFFER, u);
      if (u.pointer != va + fs_offsets[i] || u.entries != fs_sizes[i]) return 0;
   }
   uint64_t target = 0;
   uint32_t dimensions[3], write_rule = 0;
   uint16_t edr_half = 0, weight3 = 0;
   memcpy(&target, d + FB + 20 * 4, 8);
   memcpy(dimensions, d + FS_PUSH, sizeof(dimensions));
   memcpy(&write_rule, d + FS_PUSH + 72, 4);
   memcpy(&edr_half, d + EDR_DATA, 2);
   memcpy(&weight3, d + FILTER_DATA + 70, 2);
   return vj.type == MALI_JOB_TYPE_VERTEX && vj.next == va + TILER_JOB &&
      tj.type == MALI_JOB_TYPE_TILER && tj.dependency_1 == 1 &&
      fj.type == MALI_JOB_TYPE_FRAGMENT && vd.attributes == va + VS_ATTRS &&
      vd.attribute_buffers == va + VS_ATTR_BUFS && vd.uniform_buffers == va + VS_UBO_DESC &&
      vd.thread_storage == va + FB && vd.fbd == va + FB &&
      td.thread_storage == va + FB && td.fbd == va + FB &&
      td.uniform_buffers == va + FS_UBO_DESC && td.position == va + POS_BUF &&
      vs.shader.shader == va + VS_SHADER + 5 && vs.shader.attribute_count == 4 &&
      vs.shader.varying_count == 3 && vs.properties.work_register_count == 8 &&
      vs.properties.uniform_buffer_count == 3 && fs.shader.shader == va + FS_SHADER + 5 &&
      fs.properties.uniform_buffer_count == 5 && fs.properties.work_register_count == 7 &&
      fs.shader.texture_count == 1 && fs.shader.sampler_count == 1 &&
      matrix.pointer == va + MVP_DATA && matrix.entries == 4 &&
      filter.pointer == va + FILTER_DATA && filter.entries == 5 &&
      edr.pointer == va + EDR_DATA && edr.entries == 1 &&
      ab.pointer == va + VERTEX_DATA && ab.stride == 48 && ab.size == 192 &&
      pos_attr.buffer_index == 0 && pos_attr.format == ((MALI_SNAP_4 << 12) | 0x688) &&
      ps_attr.buffer_index == 1 && ps_attr.format == ((MALI_R16F << 12) | PSIZ_SWIZZLE) &&
      ps.pointer == va + PSIZ_BUF && ps.stride == 2 && ps.size == 8 &&
      uv.pointer == va + UV_BUF && uv.stride == 8 && fi.pointer == uv.pointer &&
      surface.pointer == va + SOURCE && surface.row_stride == 256 &&
      tex.width == SRC_WIDTH && tex.height == SRC_HEIGHT && tex.levels == 1 &&
      sampler.normalized_coordinates && sampler.minify_nearest && sampler.magnify_nearest &&
      viewport.scissor_maximum_x == DST_WIDTH - 1 &&
      viewport.scissor_maximum_y == DST_HEIGHT - 1 &&
      fragment.bound_min_x == 0 && fragment.bound_min_y == 0 &&
      fragment.bound_max_x == ((DST_WIDTH - 1) >> MALI_TILE_SHIFT) &&
      fragment.bound_max_y == ((DST_HEIGHT - 1) >> MALI_TILE_SHIFT) &&
      fragment.framebuffer == va + FB && target == va + DESTINATION &&
      tiler.heap_start == va + HEAP &&
      tiler.heap_end == va + HEAP + HEAP_BYTES &&
      tiler.heap_start < tiler.heap_end &&
      tiler.heap_end <= va + PRIVATE_BYTES &&
      tiler.polygon_list == va + POLY && tiler.polygon_list_body == va + POLY_BODY &&
      tiler.polygon_list_size <= POLY_BYTES &&
      !overlap(tiler.heap_start, HEAP_BYTES, va, BYTES) &&
      !overlap(tiler.heap_start, HEAP_BYTES, surface.pointer, SRC_BYTES) &&
      !overlap(tiler.heap_start, HEAP_BYTES, target, DST_BYTES) &&
      dimensions[0] == 1 && dimensions[1] == SRC_WIDTH && dimensions[2] == SRC_HEIGHT &&
      write_rule == A5DownsampleColorWriteRule && edr_half == A5DownsampleEDRHalf &&
      weight3 == A5DownsampleWeight3Half;
}

int main(int argc, char **argv)
{
   if (argc != 5) {
      fprintf(stderr, "usage: %s vert.midgard frag.midgard output.bin descriptor_va\n", argv[0]);
      return 2;
   }
   uint64_t va;
   if (!validate_layout() || !parse_u64(argv[4], &va) ||
       !valid_va(va, PRIVATE_BYTES)) return 2;
   uint8_t d[BYTES] = {0};
   if (!read_exact(argv[1], d + VS_SHADER, VS_BYTES, UINT64_C(0x9614671d6cd46fb1)) ||
       !read_exact(argv[2], d + FS_SHADER, FS_BYTES, UINT64_C(0xe4eeb225fe017513))) {
      fprintf(stderr, "shader bytes differ from the translated downsample_4 pair\n");
      return 2;
   }
   framebuffer(d, va, va + DESTINATION, DST_WIDTH, DST_HEIGHT, DST_WIDTH * 4);
   renderer_states(d, va);
   resources(d, va, va + SOURCE);
   jobs(d, va, va + POS_BUF, DST_WIDTH, DST_HEIGHT);
   if (!validate_descriptor(d, va)) {
      fprintf(stderr, "packed downsample descriptor readback mismatch\n");
      return 1;
   }
   FILE *f = fopen(argv[3], "wb");
   if (!f) return 1;
   size_t n = fwrite(d, 1, sizeof(d), f);
   int close_rc = fclose(f);
   if (n != sizeof(d) || close_rc) return 1;
   printf("downsample4 fixture bytes=%u base=0x%llx source=+0x4000 dest=+0x8000 "
          "heap=+0x9000..+0xa000 guards=+0xa000..+0xc000 "
          "jobs=+0,+0x100,+0x200 fixed_viewport=1080x1920 output=32x32\n",
          BYTES, (unsigned long long)va);
   return 0;
}
