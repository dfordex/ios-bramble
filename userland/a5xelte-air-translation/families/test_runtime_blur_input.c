/* SPDX-License-Identifier: MIT
 * Exercise the source-format boundary with actual authenticated fixture data.
 */
int fixture_builder_main(int argc,char**argv);
#define main fixture_builder_main
#include "build_runtime_blur_fixture.c"
#undef main
int main(int argc,char**argv){
 if(argc!=2)return 2;FILE*f=fopen(argv[1],"rb");assert(f);
 assert(fread(legacy,1,sizeof(legacy),f)==sizeof(legacy)&&fgetc(f)==EOF);fclose(f);
 assert(legacy_source_is_rgba(legacy));
 rgba_source_to_bgra(out,legacy+0xa000);
 /* Green/alpha are invariant; reconstructed RGBA matches the original input.
  * The nonconstant checker must contain actual red/blue disagreements. */
 unsigned different=0;
 for(unsigned i=0;i<4096;++i){
  const uint8_t*a=legacy+0xa000+4*i,*b=out+4*i;
  assert(b[0]==a[2]&&b[1]==a[1]&&b[2]==a[0]&&b[3]==a[3]);different+=a[0]!=a[2];
 }
 assert(different>1024);
 pan_unpack((const struct mali_texture_packed*)(legacy+0x600),TEXTURE,t);
 t.format=(MALI_RGBA8_UNORM<<12)|0x60a; /* AlreadyBGRA must not be converted twice. */
 MALI_TEXTURE_pack((struct mali_texture_packed*)(legacy+0x600),&t);
 assert(!legacy_source_is_rgba(legacy));
 t.format=(MALI_RGBA8_UNORM<<12)|0x688;MALI_TEXTURE_pack((struct mali_texture_packed*)(legacy+0x600),&t);
 pan_unpack((const struct mali_surface_with_stride_packed*)(legacy+0x620),SURFACE_WITH_STRIDE,s);
 s.row_stride=512;MALI_SURFACE_WITH_STRIDE_pack((struct mali_surface_with_stride_packed*)(legacy+0x620),&s);
 assert(!legacy_source_is_rgba(legacy));
 puts("PASS actual RGBA source->BGRA runtime contract: R/B swap only; G/A invariant; reject alreadyBGRA or wrongstride; no output pixels generated");return 0;
}
