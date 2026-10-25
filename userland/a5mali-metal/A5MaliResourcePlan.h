/* SPDX-License-Identifier: MIT
 * Logical immutable uploads are packed into bounded physical BOs. Planning
 * contains no shader identity, host pointers, handles or GPU addresses.
 */
#ifndef A5_MALI_RESOURCE_PLAN_H
#define A5_MALI_RESOURCE_PLAN_H
#include <stdint.h>
#include <string.h>
enum { A5MaliUploadLimit=66, A5MaliUploadHeapLimit=4,
       A5MaliUploadHeapBytes=0x800000 };
enum { A5MaliUploadOK=0, A5MaliUploadInvalid=1, A5MaliUploadPressure=2 };
typedef struct { uint32_t bytes,alignment; } A5MaliUploadInput;
typedef struct { uint32_t heap,offset,bytes; } A5MaliUploadSlice;
typedef struct {
 uint32_t count,heapCount,heapBytes[A5MaliUploadHeapLimit];
 A5MaliUploadSlice slices[A5MaliUploadLimit];
} A5MaliUploadPlan;
static inline unsigned A5MaliPlanUploads(const A5MaliUploadInput *input,unsigned count,
 unsigned available,A5MaliUploadPlan *out){
 if(!out)return A5MaliUploadInvalid;memset(out,0,sizeof(*out));
 if(count>A5MaliUploadLimit||available>A5MaliUploadHeapLimit||(!input&&count))return A5MaliUploadInvalid;
 unsigned order[A5MaliUploadLimit];
 for(unsigned i=0;i<count;i++){
  if(!input[i].bytes||input[i].bytes>A5MaliUploadHeapBytes||!input[i].alignment||
   input[i].alignment>4096||(input[i].alignment&(input[i].alignment-1)))return A5MaliUploadInvalid;
  order[i]=i;
 }
 /* Stable first-fit decreasing avoids consuming a BO per API binding. */
 for(unsigned i=1;i<count;i++){unsigned key=order[i],j=i;
  while(j&&input[order[j-1]].bytes<input[key].bytes){order[j]=order[j-1];j--;}order[j]=key;}
 A5MaliUploadPlan p={0};p.count=count;
 for(unsigned n=0;n<count;n++){
  unsigned i=order[n],h,at=0;
  for(h=0;h<p.heapCount;h++){
   at=(p.heapBytes[h]+input[i].alignment-1)&~(input[i].alignment-1);
   if(at<=A5MaliUploadHeapBytes&&input[i].bytes<=A5MaliUploadHeapBytes-at)break;
  }
  if(h==p.heapCount){if(h==available)return A5MaliUploadPressure;p.heapCount++;at=0;}
  p.slices[i]=(A5MaliUploadSlice){h,at,input[i].bytes};p.heapBytes[h]=at+input[i].bytes;
 }
 *out=p;return A5MaliUploadOK;
}
#endif
