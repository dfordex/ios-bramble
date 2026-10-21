/* SPDX-License-Identifier: MIT */
#ifndef A5_RUNTIME_PATH_ENCODE_H
#define A5_RUNTIME_PATH_ENCODE_H
#include "runtime_encode.h"
#ifdef __cplusplus
extern "C" {
#endif
enum { A5RuntimePathBlendCoverageAdd = 2 };
typedef struct {
    A5RuntimeDraw draw;
    uint32_t passIndex;
    A5RuntimeImage colorAttachments[8];
} A5RuntimePathDraw;
/* Actual SSBO-driven one-quad path draws. Rect/cubic write ONLY logical RT2
 * with genuine inline R32Float destination-load + addition. Stroke writes
 * only its actual source-over RT0; disabled RT1/RT2 remain untouched.
 * Geometry/uniforms are actual application binds, never fixture values.
 * MSAA, instancing/baseVertex, other blend modes and ordered path_blit are
 * rejected. The caller implements actual attachment load/store actions. */
int A5MaliEncodeRuntimePathPass(const A5RuntimePathDraw *,void *,size_t);
#ifdef __cplusplus
}
#endif
#endif
