/* SPDX-License-Identifier: MIT */
#include A5_FRAME_PIXEL_HEADER
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <vector>

int main()
{
    /* Source and panel have different strides; no comparison of padding. */
    const uint32_t w=1080,h=1920,srcStride=4352,dstStride=4320;
    std::vector<uint8_t> src((uint64_t)srcStride*h,0);
    std::vector<uint8_t> dst((uint64_t)dstStride*h,0);
    A5FramePixels p={};
    assert(a5frame_pixels(src.data(),src.size(),w,h,srcStride,
        dst.data(),dst.size(),dstStride,&p));
    assert(p.samples==4096&&!p.rgbNonzero&&!p.alphaNonzero&&!p.rgbMismatch);
    for(uint32_t iy=0;iy<64;iy++)for(uint32_t ix=0;ix<64;ix++){
        uint32_t y=(uint64_t)iy*(h-1)/63,x=(uint64_t)ix*(w-1)/63;
        const uint32_t value=0xff102030;
        __builtin_memcpy(src.data()+(uint64_t)y*srcStride+4*x,&value,4);
        __builtin_memcpy(dst.data()+(uint64_t)y*dstStride+4*x,&value,4);
    }
    assert(a5frame_pixels(src.data(),src.size(),w,h,srcStride,
        dst.data(),dst.size(),dstStride,&p));
    assert(p.rgbNonzero==4096&&p.alphaNonzero==4096&&!p.rgbMismatch&&!p.alphaMismatch);
    dst[0]^=1;dst[3]=0;
    assert(a5frame_pixels(src.data(),src.size(),w,h,srcStride,
        dst.data(),dst.size(),dstStride,&p));
    assert(p.rgbMismatch==1&&p.alphaMismatch==1);
    assert(!a5frame_pixels(src.data(),8,w,h,srcStride,nullptr,0,0,&p));
    assert(!a5frame_pixels(src.data(),src.size(),w,h,1,nullptr,0,0,&p));
    assert(!a5frame_pixels(src.data(),src.size(),0,h,srcStride,nullptr,0,0,&p));
    assert(!a5frame_pixels(src.data(),src.size(),UINT32_MAX,h,srcStride,nullptr,0,0,&p));
    assert(!a5frame_pixels(src.data(),src.size(),w,h,srcStride,dst.data(),1,dstStride,&p));
    assert(!a5frame_pixels(nullptr,src.size(),w,h,srcStride,nullptr,0,0,&p));
    assert(!a5frame_pixels(src.data(),src.size(),w,h,srcStride,nullptr,0,0,nullptr));
    uint32_t one=0xff000000;
    assert(a5frame_pixels(&one,4,1,1,4,nullptr,0,0,&p));
    assert(p.samples==1&&!p.rgbNonzero&&p.alphaNonzero==1);
    puts("frame pixel sampling: black/opaque/color, source-panel strides, RGB/alpha differences and invalid spans PASS (host memory only)");
}
