/* SPDX-License-Identifier: MIT
 * Copyright (C) 2018 Alyssa Rosenzweig
 * Copyright (C) 2019-2021 Collabora, Ltd.
 * The fixed-function algebra is adapted from Mesa pan_blend.c. License notice:
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to
 * do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * Metal state IR and Midgard-v4 fixed blend lowering. No shader names, profile
 * IDs, function constants or program fingerprints participate in this pass.
 * Algebra follows Mesa26.2.4 pan_blend.c's A + B*C representation.
 */
#ifndef A5_MALI_RENDER_STATE_H
#define A5_MALI_RENDER_STATE_H
#include "A5MaliCompiledRegistry.h"
#include <string.h>
enum { A5MaliStateInvalid=0, A5MaliStateFixed=1, A5MaliStateNeedsShader=2 };
typedef struct { unsigned a,b,c,negateA,negateB,invertC; } A5MaliBlendEquation;
typedef struct {
 unsigned route,writeMask,loadDestination;
 A5MaliBlendEquation rgb,alpha;
 const char *reason;
} A5MaliBlendPlan;
/* Metal factors0..18. C_ZERO=1, C_SRC=2,C_DST=3,C_SRC_ALPHA=5,
 * C_DST_ALPHA=6 are stable released v4 encodings. Constants and dual-source
 * values remain explicit shader-lowering requirements, never dummy success. */
static inline unsigned A5MaliBlendFactorBase(unsigned factor,unsigned alpha){
 if(factor<=1)return 1;
 if(factor<=9){unsigned b=2+(factor-2)/2;
  return alpha?(b==2?3:b==4?5:b):b;}
 return 0;
}
static inline unsigned A5MaliBlendFactorInvert(unsigned f){return f==0||(f>=2&&(f&1));}
static inline unsigned A5MaliBlendC(unsigned b){return b==1?1:b==2?2:b==3?5:b==4?3:b==5?6:0;}
static inline unsigned A5MaliLowerBlendChannel(unsigned operation,unsigned src,unsigned dst,
 unsigned alpha,A5MaliBlendEquation *out){
 memset(out,0,sizeof(*out));
 if(operation>2||src>9||dst>9)return A5MaliStateNeedsShader;
 unsigned s=A5MaliBlendFactorBase(src,alpha),d=A5MaliBlendFactorBase(dst,alpha);
 /* v4 cannot use destination alpha as its source multiplier. */
 if((s==5&&src>1)||(s!=d&&s!=1&&d!=1))return A5MaliStateNeedsShader;
 unsigned si=A5MaliBlendFactorInvert(src)^(s==1),di=A5MaliBlendFactorInvert(dst)^(d==1);
 if(src==0){out->a=1;out->b=3;out->c=A5MaliBlendC(d);out->invertC=di;out->negateB=operation==1;}
 else if(src==1){out->a=2;out->b=3;out->c=A5MaliBlendC(d);out->invertC=di;out->negateB=operation==1;out->negateA=operation==2;}
 else if(dst==0){out->a=1;out->b=2;out->c=A5MaliBlendC(s);out->invertC=si;out->negateB=operation==2;}
 else if(dst==1){out->a=3;out->b=2;out->c=A5MaliBlendC(s);out->invertC=si;out->negateA=operation==1;out->negateB=operation==2;}
 else if(si==di){out->a=1;out->b=operation?0:1;out->c=A5MaliBlendC(s);out->invertC=si;out->negateB=operation==2;}
 else {out->a=3;out->b=operation?1:0;out->c=A5MaliBlendC(s);out->invertC=si;out->negateA=operation==1;out->negateB=operation==2;}
 return A5MaliStateFixed;
}
static inline A5MaliBlendPlan A5MaliLowerRenderState(const A5MaliCompiledAttachmentState *s){
 A5MaliBlendPlan p={0};
 if(!s||s->writeMask>15||s->blendEnabled>1||s->rgbOperation>4||s->alphaOperation>4||
  s->sourceRGB>18||s->destinationRGB>18||s->sourceAlpha>18||s->destinationAlpha>18){p.reason="invalid Metal color attachment state";return p;}
 p.writeMask=((s->writeMask&8)>>3)|((s->writeMask&4)>>1)|((s->writeMask&2)<<1)|((s->writeMask&1)<<3);p.loadDestination=s->writeMask!=15;
 if(!s->blendEnabled){p.rgb=(A5MaliBlendEquation){2,2,1,0,0,0};p.alpha=p.rgb;p.route=A5MaliStateFixed;return p;}
 unsigned r=A5MaliLowerBlendChannel(s->rgbOperation,s->sourceRGB,s->destinationRGB,0,&p.rgb);
 unsigned a=A5MaliLowerBlendChannel(s->alphaOperation,s->sourceAlpha,s->destinationAlpha,1,&p.alpha);
 p.route=r==A5MaliStateFixed&&a==A5MaliStateFixed?A5MaliStateFixed:A5MaliStateNeedsShader;
 if(p.route!=A5MaliStateFixed)p.reason="blend equation requires shader lowering on Midgard-v4";
 /* Destination reads follow the API equation and masked channels, not the
  * mere presence of a blend-enabled bit (ONE/ZERO can remain an overwrite). */
 p.loadDestination|=s->rgbOperation>=3||s->alphaOperation>=3||
  (s->sourceRGB>=6&&s->sourceRGB<=9)||(s->sourceAlpha>=6&&s->sourceAlpha<=9)||
  s->destinationRGB!=0||s->destinationAlpha!=0;
 return p;
}
#endif
