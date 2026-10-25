/* SPDX-License-Identifier: MIT */
#include "A5MaliResourcePlan.h"
#include <assert.h>
#include <stdio.h>
static void verify(const A5MaliUploadInput*in,unsigned n,unsigned available){
 A5MaliUploadPlan p;assert(A5MaliPlanUploads(in,n,available,&p)==A5MaliUploadOK);
 assert(p.count==n&&p.heapCount<=available);
 for(unsigned i=0;i<n;i++){
  A5MaliUploadSlice a=p.slices[i];assert(a.heap<p.heapCount&&a.bytes==in[i].bytes&&!(a.offset&(in[i].alignment-1)));
  assert(a.offset<=p.heapBytes[a.heap]&&a.bytes<=p.heapBytes[a.heap]-a.offset);
  assert(p.heapBytes[a.heap]<=A5MaliUploadHeapBytes);
  for(unsigned j=0;j<i;j++){A5MaliUploadSlice b=p.slices[j];if(a.heap==b.heap)assert(a.offset>=b.offset+b.bytes||b.offset>=a.offset+a.bytes);}
 }
}
int main(void){
 A5MaliUploadInput inputs[A5MaliUploadLimit];
 for(unsigned i=0;i<A5MaliUploadLimit;i++)inputs[i]=(A5MaliUploadInput){i+1,64};
 verify(inputs,A5MaliUploadLimit,1); /* 66 logical bindings, one physical BO. */
 A5MaliUploadPlan p;assert(A5MaliPlanUploads(inputs,A5MaliUploadLimit,0,&p)==A5MaliUploadPressure&&!p.count&&!p.heapCount);
 inputs[0]=(A5MaliUploadInput){0x800000,4096};inputs[1]=(A5MaliUploadInput){0x7fffff,64};
 inputs[2]=(A5MaliUploadInput){1,64};verify(inputs,3,3);
 assert(A5MaliPlanUploads(inputs,3,2,&p)==A5MaliUploadPressure&&!p.count&&!p.heapCount);
 inputs[0].bytes=UINT32_MAX;assert(A5MaliPlanUploads(inputs,1,4,&p)==A5MaliUploadInvalid);
 inputs[0]=(A5MaliUploadInput){4096,3};assert(A5MaliPlanUploads(inputs,1,4,&p)==A5MaliUploadInvalid);
 assert(A5MaliPlanUploads(NULL,0,0,&p)==A5MaliUploadOK&&!p.count);
 unsigned seed=41;
 for(unsigned iteration=0;iteration<10000;iteration++){
  for(unsigned i=0;i<16;i++){seed=seed*1664525u+1013904223u;inputs[i]=(A5MaliUploadInput){1+(seed&0x3ffff),1u<<((seed>>20)%13)};}
  verify(inputs,16,4);
 }
 puts("resource planner:66 logical/one BO, deterministic bounds/alignment/nonoverlap, pressure cleanup,10000 mixed plans PASS");
}
