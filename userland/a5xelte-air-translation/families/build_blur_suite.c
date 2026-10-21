/* SPDX-License-Identifier: MIT
 * Host-only bounded T720 descriptor fixture for the translated QuartzCore
 * blur family pairs. Input shader bytes are supplied from private staging.
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
#include "../downsample_reference.h"
static unsigned g_kind, g_rgba16, g_fs_bytes, g_fs_regs, g_tls_bytes;

enum {
   BYTES = 0x40000, SRC_BYTES = 0x4000, DST_BYTES = 0x2000,
   SOURCE = 0xa000, DESTINATION = 0xe000,
   HEAP = 0x8000, HEAP_BYTES = 0x2000, GUARDS = 0x20000,
   TLS = 0x10000, TLS_BYTES = 0x10000,
   PRIVATE_BYTES = BYTES,
   PSIZ_SWIZZLE = MALI_CHANNEL_R | (MALI_CHANNEL_0 << 3) |
      (MALI_CHANNEL_0 << 6) | (MALI_CHANNEL_1 << 9),
   RG_SWIZZLE = MALI_CHANNEL_R | (MALI_CHANNEL_G << 3) |
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
   VS_SHADER = 0x2000, VS_BYTES = 2048,
   FS_SHADER = 0x3000,
   POLY = 0x6000, POLY_BODY = 0x6200, POLY_BYTES = 0x2000,
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
   const unsigned r[][2] = {{0,0x2000},{VS_SHADER,VS_BYTES},
      {FS_SHADER,g_fs_bytes},{POLY,POLY_BYTES},{HEAP,HEAP_BYTES},
      {SOURCE,SRC_BYTES},{DESTINATION,DST_BYTES},{TLS,TLS_BYTES},
      {GUARDS,PRIVATE_BYTES-GUARDS}};
   if (!g_fs_bytes || g_fs_bytes > 0x3000 || g_fs_regs > 16 || !g_fs_regs ||
       (g_tls_bytes != 0 && g_tls_bytes != 32 && g_tls_bytes != 64)) return 0;
   for (unsigned i=0;i<sizeof(r)/sizeof(r[0]);i++) {
      if (r[i][0]+r[i][1]>PRIVATE_BYTES) return 0;
      for (unsigned j=i+1;j<sizeof(r)/sizeof(r[0]);j++)
         if (overlap(r[i][0],r[i][1],r[j][0],r[j][1])) return 0;
   }
   return 1;
}

static void framebuffer(uint8_t *d, uint64_t va, uint64_t dst,
                        unsigned width, unsigned height, unsigned stride)
{
   /* Released pan_desc.c pan_emit_tls + v4 pan_emit_fbd. Actual SHADER_PRESENT
    * must equal3; scratch additionally covers4 core IDs x256 threads x64B. */
   pan_section_pack(d+FB, FRAMEBUFFER, LOCAL_STORAGE, cfg) {
      cfg.tls_size = g_tls_bytes == 64 ? 2 : g_tls_bytes == 32 ? 1 : 0;
      cfg.tls_base_pointer = g_tls_bytes ? va+TLS : 0;
      cfg.wls_instances = MALI_LOCAL_STORAGE_NO_WORKGROUP_MEM;
   }
   pan_section_pack(d+FB, FRAMEBUFFER, PARAMETERS, cfg) {
      cfg.internal_format = g_rgba16 ? MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE : MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8;
      cfg.color_writeback_format = g_rgba16 ? MALI_COLOR_FORMAT_2_32B_CHANNELS : MALI_COLOR_FORMAT_R8G8B8A8;
      cfg.swizzle = g_rgba16 ? 0x688 : 0x60a;
      cfg.color_write_enable = true;
      cfg.color_preload_enable = true;
      cfg.clean_pixel_write_enable = true;
      cfg.color_block_format = MALI_BLOCK_FORMAT_LINEAR;
      cfg.tie_break_rule = MALI_TIE_BREAK_RULE_MINUS_180_IN_0_OUT;
      cfg.bound_max_x = width-1; cfg.bound_max_y=height-1;
      cfg.color_writeback.base=dst;
      cfg.color_writeback.row_stride=stride;
      cfg.color_load_address=dst;
      cfg.color_load_row_stride=stride;
      cfg.color_load_surface_stride=stride*height;
   }
   pan_section_pack(d+FB, FRAMEBUFFER, TILER, cfg) {
      cfg.polygon_list_size=0x400; cfg.hierarchy_mask=0x1c7;
      cfg.polygon_list=va+POLY; cfg.polygon_list_body=va+POLY_BODY;
      cfg.heap_start=va+HEAP; cfg.heap_end=va+HEAP+HEAP_BYTES;
   }
   put32(d,POLY_BODY,0xa0000000u);
}

static void renderer_states(uint8_t *d, uint64_t va)
{
   pan_pack((struct mali_renderer_state_packed *)(d + VS_RSD),
            RENDERER_STATE, cfg) {
      cfg.shader.shader = va + VS_SHADER + 5;
      cfg.shader.attribute_count = 2; /* actual compiler attributes_read_count */
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
      cfg.properties.work_register_count = g_fs_regs;
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
      /* Match released pan_format.c: two-channel formats use RG01,
       * four-channel/SNAP_4 use RGBA. Do not request nonexistent B/A. */
      unsigned swizzle = (format == MALI_RG32F || format == MALI_RG32UI) ?
         RG_SWIZZLE : 0x688;
      cfg.format = (format << 12) | swizzle;
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
      cfg.format = (MALI_RGBA8_UNORM << 12) | 0x688;
      cfg.dimension = MALI_TEXTURE_DIMENSION_2D;
      cfg.texel_ordering = MALI_TEXTURE_LAYOUT_LINEAR;
      cfg.swizzle = 0x688;
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
   /* Released Panfrost stores highp VS varyings as U32 and reads smooth
    * FS varyings as F32. Match each descriptor to its stage instruction. */
   attribute(d, VS_VARYINGS + 16, 2, MALI_RG32UI, 0);
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
   pan_pack((struct mali_compute_job_parameters_packed *)(d + VERTEX_JOB +
            MALI_COMPUTE_JOB_SECTION_PARAMETERS_OFFSET), COMPUTE_JOB_PARAMETERS, cfg) {
      cfg.job_task_split = 5;
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

/* Coefficients sum to1/2; symmetric pairs therefore have exact alpha1.
 * All weights are nonzero dyadic values, not a disabled filter. */
static const unsigned pair_weights[6][7] = {
   {4,4}, {2,2,4}, {2,2,2,2}, {1,1,1,1,4},
   {1,1,1,1,2,2}, {1,1,1,1,1,1,2}
};
static uint16_t half(float x) { _Float16 h=(_Float16)x; uint16_t b; memcpy(&b,&h,2); return b; }
static unsigned channel(int x,int y,unsigned c)
{
   if(x<0)x=0; if(y<0)y=0; if(x>63)x=63; if(y>63)y=63;
   const unsigned b=(x/7)&1, g=(y/7)&1;
   return c==0 ? b^g : c==1 ? g : c==2 ? b : 1;
}
static void filter_data(uint8_t *d)
{
   memset(d+FILTER_DATA,0,96);
   ubo(d,FS_UBO_DESC,3,UINT64_C(0x02000000)+FILTER_DATA,96);
   put32(d,FS_PUSH+72,g_rgba16 ? 0x3333 : 0x2222);
   if(g_kind==0) {
      for(unsigned i=0;i<4;i++) {
         put_float(d,FILTER_DATA+i*8,((i&1)?1.5f:0.5f)/64.0f);
         put_float(d,FILTER_DATA+i*8+4,((i&2)?1.5f:0.5f)/64.0f);
      }
   } else if(g_kind==7) {
      for(unsigned i=0;i<4;i++) {
         put_float(d,FILTER_DATA+i*8,((i&1)?0.5f:-0.5f)/64.0f);
         put_float(d,FILTER_DATA+i*8+4,((i&2)?0.5f:-0.5f)/64.0f);
      }
      uint16_t w=half(.25f);memcpy(d+FILTER_DATA+64,&w,2);
   } else {
      unsigned pairs=g_kind+1;
      for(unsigned i=0;i<pairs;i++) {
         put_float(d,FILTER_DATA+i*8,(i+.5f)/64.0f);
         put_float(d,FILTER_DATA+i*8+4,.5f/64.0f);
         uint16_t w=half(pair_weights[g_kind-1][i]/16.0f);
         memcpy(d+FILTER_DATA+64+i*2,&w,2);
      }
   }
   /* Actual NarrowBlurUniforms divide field. Enable its real normalization
    * branch; exact alpha1 makes the division exact without deleting it. */
   uint16_t divide=half(1),edr=half(.5f);
   memcpy(d+FILTER_DATA+80,&divide,2);memcpy(d+EDR_DATA,&edr,2);
}
static unsigned oracle_numerator(unsigned x,unsigned y,unsigned c,unsigned *den)
{
   unsigned n=0;
   if(g_kind==0) {
      for(int j=-1;j<=2;j++)for(int i=-1;i<=2;i++)
         n+=channel(2*(int)x+i,2*(int)y+j,c);
      *den=32;
   } else if(g_kind==7) {
      for(int j=0;j<2;j++)for(int i=0;i<2;i++)
         n+=channel(2*x+i,2*y+j,c);
      *den=8;
   } else {
      for(unsigned i=0;i<g_kind+1;i++)
         n+=pair_weights[g_kind-1][i]*(channel(2*(int)x-(int)i,2*y,c)+
              channel(2*x+(int)i+1,2*y+1,c));
      *den=32;
   }
   return n;
}
static int write_file(const char *name,const void *data,unsigned bytes)
{
   FILE *f=fopen(name,"wb");if(!f)return 0;
   unsigned n=fwrite(data,1,bytes,f);int e=fclose(f);return n==bytes&&!e;
}
static int validate_descriptor(const uint8_t *d,uint64_t va)
{
   pan_unpack((const struct mali_job_header_packed *)(d),JOB_HEADER,v);
   pan_unpack((const struct mali_job_header_packed *)(d+0x100),JOB_HEADER,t);
   pan_unpack((const struct mali_job_header_packed *)(d+0x200),JOB_HEADER,f);
   pan_unpack((const struct mali_draw_packed *)(d+64),DRAW,vd);
   pan_unpack((const struct mali_draw_packed *)(d+0x140),DRAW,td);
   pan_unpack((const struct mali_local_storage_packed *)(d+FB),LOCAL_STORAGE,ls);
   pan_unpack((const struct mali_framebuffer_parameters_packed *)(d+FB+32),FRAMEBUFFER_PARAMETERS,fb);
   pan_unpack((const struct mali_tiler_context_packed *)(d+FB+192),TILER_CONTEXT,tiler);
   pan_unpack((const struct mali_renderer_state_packed *)(d+FS_RSD),RENDERER_STATE,rs);
   pan_unpack((const struct mali_texture_packed *)(d+TEXTURE),TEXTURE,tx);
   pan_unpack((const struct mali_uniform_buffer_packed *)(d+FS_UBO_DESC+24),UNIFORM_BUFFER,filter);
   pan_unpack((const struct mali_fragment_job_payload_packed *)(d+0x220),FRAGMENT_JOB_PAYLOAD,frag);
   return v.type==MALI_JOB_TYPE_VERTEX&&v.next==va+0x100&&
      t.type==MALI_JOB_TYPE_TILER&&t.dependency_1==1&&f.type==MALI_JOB_TYPE_FRAGMENT&&
      vd.thread_storage==va+FB&&td.fbd==va+FB&&
      rs.shader.shader==va+FS_SHADER+5&&rs.properties.work_register_count==g_fs_regs&&
      filter.pointer==va+FILTER_DATA&&filter.entries==6&&
      tx.swizzle==0x688&&tx.format==((MALI_RGBA8_UNORM<<12)|0x688)&&
      ls.tls_size==(g_tls_bytes==64?2:g_tls_bytes==32?1:0)&&
      ls.tls_base_pointer==(g_tls_bytes?va+TLS:0)&&
      fb.color_writeback.base==va+DESTINATION&&
      fb.color_writeback.row_stride==32*(g_rgba16?8:4)&&
      fb.color_writeback_format==(g_rgba16?MALI_COLOR_FORMAT_2_32B_CHANNELS:MALI_COLOR_FORMAT_R8G8B8A8)&&
      fb.internal_format==(g_rgba16?MALI_COLOR_BUFFER_INTERNAL_FORMAT_RAW_VALUE:MALI_COLOR_BUFFER_INTERNAL_FORMAT_R8G8B8A8)&&
      fb.swizzle==(g_rgba16?0x688:0x60a)&&
      tiler.heap_start==va+HEAP&&tiler.heap_end==va+HEAP+HEAP_BYTES&&
      frag.bound_max_x==1&&frag.bound_max_y==1&&frag.framebuffer==va+FB;
}
int main(int argc,char **argv)
{
   if(argc!=12) {fprintf(stderr,"usage: %s VS FS PAYLOAD EXPECTED KIND RGBA16 FS_BYTES FS_REGS TLS_BYTES VS_FNV FS_FNV\n",argv[0]);return 2;}
   uint64_t p[7];
   for(unsigned i=0;i<7;i++)if(!parse_u64(argv[5+i],p+i))return 2;
   g_kind=p[0];g_rgba16=p[1];g_fs_bytes=p[2];g_fs_regs=p[3];g_tls_bytes=p[4];
   const uint64_t va=0x02000000;
   if(g_kind>7||g_rgba16>1||!valid_va(va,PRIVATE_BYTES)||!validate_layout())return 2;
   uint8_t *d=calloc(1,BYTES);uint8_t expected[8192]={0};if(!d)return 1;
   if(!read_exact(argv[1],d+VS_SHADER,VS_BYTES,p[5])||!read_exact(argv[2],d+FS_SHADER,g_fs_bytes,p[6])) {free(d);return 2;}
   framebuffer(d,va,va+DESTINATION,32,32,32*(g_rgba16?8:4));
   renderer_states(d,va);resources(d,va,va+SOURCE);filter_data(d);
   jobs(d,va,va+POS_BUF,32,32);
   for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++)for(unsigned c=0;c<4;c++)
      d[SOURCE+(y*64+x)*4+c]=255*channel(x,y,c);
   memset(d+DESTINATION,0xa5,DST_BYTES);memset(d+GUARDS,0x6d,BYTES-GUARDS);
   for(unsigned y=0;y<32;y++)for(unsigned x=0;x<32;x++) {
      for(unsigned c=0;c<4;c++) {
         unsigned den,n=oracle_numerator(x,y,c,&den);
         if(g_rgba16) {uint16_t h=half(c==3?1.0f:(float)n/den);memcpy(expected+(y*32+x)*8+c*2,&h,2);}
         else expected[(y*32+x)*4+(c==0?2:c==2?0:c)]=c==3?255:(n*255+den/2)/den;
      }
   }
   unsigned outbytes=32*32*(g_rgba16?8:4);
   int ok=validate_descriptor(d,va)&&write_file(argv[3],d,BYTES)&&write_file(argv[4],expected,outbytes);
   free(d);if(!ok)return 1;
   printf("blur fixture %u output=%u tls_per_thread=%u scratch=%u core_id_range<=4 packed_readback=PASS\n",g_kind,outbytes,g_tls_bytes,TLS_BYTES);
   return 0;
}
