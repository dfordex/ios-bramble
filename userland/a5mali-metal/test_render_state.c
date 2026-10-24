/* SPDX-License-Identifier: MIT
 * Independent scalar Metal oracle versus emitted A+B*C coefficients. */
#include "A5MaliRenderState.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static double factor(unsigned f,unsigned ch,const double*s,const double*d){
 switch(f){case 0:return 0;case 1:return 1;case 2:return s[ch];case 3:return 1-s[ch];
 case 4:return s[3];case 5:return 1-s[3];case 6:return d[ch];case 7:return 1-d[ch];
 case 8:return d[3];case 9:return 1-d[3];default:assert(0);return 0;}
}
static double evaluate(const A5MaliBlendEquation*e,unsigned ch,const double*s,const double*d){
 double a=e->a==1?0:e->a==2?s[ch]:d[ch];
 double b=e->b==0?s[ch]-d[ch]:e->b==1?s[ch]+d[ch]:e->b==2?s[ch]:d[ch];
 double c=e->c==1?0:e->c==2?s[ch]:e->c==3?d[ch]:e->c==5?s[3]:d[3];
 if(e->invertC)c=1-c;if(e->negateA)a=-a;if(e->negateB)b=-b;return a+b*c;
}
int main(void){unsigned fixed=0,shader=0,comparisons=0;
 const double colors[][4]={{.13,.57,.91,.29},{.83,.21,.46,.72},{0,1,0,1},{1,0,1,0}};
 for(unsigned rgbOp=0;rgbOp<5;rgbOp++)for(unsigned sf=0;sf<19;sf++)for(unsigned df=0;df<19;df++)
 for(unsigned alpha=0;alpha<2;alpha++){
  A5MaliBlendEquation e;unsigned route=A5MaliLowerBlendChannel(rgbOp,sf,df,alpha,&e);
  if(route!=A5MaliStateFixed){shader++;continue;}fixed++;
  for(unsigned x=0;x<4;x++)for(unsigned y=0;y<4;y++)for(unsigned ch=alpha?3:0;ch<(alpha?4:3);ch++){
   double src=colors[x][ch]*factor(sf,ch,colors[x],colors[y]);
   double dst=colors[y][ch]*factor(df,ch,colors[x],colors[y]);
   double expected=rgbOp==0?src+dst:rgbOp==1?src-dst:dst-src;
   assert(fabs(expected-evaluate(&e,ch,colors[x],colors[y]))<1e-12);comparisons++;
  }
 }
 for(unsigned mask=0;mask<16;mask++){
  A5MaliCompiledAttachmentState state={mask,0,0,0,1,0,1,0};
  A5MaliBlendPlan p=A5MaliLowerRenderState(&state);assert(p.route==A5MaliStateFixed);
  for(unsigned ch=0;ch<4;ch++)assert(!!(p.writeMask&(1u<<ch))==!!(mask&(8u>>ch)));
  assert(p.loadDestination==(mask!=15));
 }
 A5MaliCompiledAttachmentState invalid={16,0,0,0,1,0,1,0};assert(A5MaliLowerRenderState(&invalid).route==A5MaliStateInvalid);
 invalid.writeMask=15;invalid.sourceRGB=19;assert(A5MaliLowerRenderState(&invalid).route==A5MaliStateInvalid);
 printf("Metal state: %u fixed channel states, %u explicit shader routes, %u independent scalar comparisons, all16 channel masks PASS\n",fixed,shader,comparisons);
}
