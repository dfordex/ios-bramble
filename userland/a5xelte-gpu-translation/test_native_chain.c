/* SPDX-License-Identifier: MIT
 * Real v4 header layouts: complete bounded preload graph or reject pre-submit.
 */
#include "native_abi.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void word(uint8_t*p,unsigned o,uint32_t v){memcpy(p+o,&v,4);}
static void ptr(uint8_t*p,unsigned o,uint64_t v){memcpy(p+o,&v,8);}
static void header(uint8_t*p,unsigned o,unsigned type,unsigned idx,unsigned dep1,unsigned dep2,uint64_t next){
 word(p,o+16,(idx<<16)|(type<<1)|1);word(p,o+20,dep1|(dep2<<16));ptr(p,o+24,next);
}
static int check(uint8_t*p){return A5NativeCheckJobChain(p,A5NativeJobBytes,A5NativeJobVA,0,0x100,0x200,0);}
int main(void){
 uint8_t*p=calloc(1,A5NativeJobBytes);assert(p);
 header(p,0,5,1,0,0,A5NativeJobVA+0x100);header(p,0x100,7,2,1,0,0);header(p,0x200,9,3,0,0,0);
 assert(check(p)==0);
 header(p,0,5,1,0,0,A5NativeJobVA+A5NativePreloadOffset);
 header(p,A5NativePreloadOffset,7,2,1,0,A5NativeJobVA+0x100);
 header(p,0x100,7,3,1,2,0);header(p,0x200,9,4,0,0,0);assert(check(p)==1);
 ptr(p,A5NativePreloadOffset+24,A5NativeJobVA);assert(check(p)<0);ptr(p,A5NativePreloadOffset+24,A5NativeJobVA+0x100);
 word(p,0x114,1);assert(check(p)<0);word(p,0x114,1|(2<<16));
 word(p,A5NativePreloadOffset+20,0);assert(check(p)<0);word(p,A5NativePreloadOffset+20,1);
 word(p,A5NativePreloadOffset,1);assert(check(p)<0);word(p,A5NativePreloadOffset,0);
 word(p,A5NativePreloadOffset+16,(2<<16)|11);assert(check(p)<0);word(p,A5NativePreloadOffset+16,(2<<16)|15);
 ptr(p,0x118,A5NativeJobVA+A5NativePreloadOffset);assert(check(p)<0);ptr(p,0x118,0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes,A5NativeJobVA,A5NativePreloadOffset,0x100,0x200,0)<0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes,A5NativeJobVA,0,0x100,A5NativeJobBytes,0)<0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes-1,A5NativeJobVA,0,0x100,0x200,0)<0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes,UINT64_MAX,0,0x100,0x200,0)<0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes,A5NativeJobVA,UINT32_MAX,UINT32_MAX,0x200,1)==0);
 assert(A5NativeCheckJobChain(p,A5NativeJobBytes,A5NativeJobVA,0,UINT32_MAX,0x200,1)<0);
 free(p);puts("PASS bounded native preload chain, dependencies, cycle/type/range/dirty-header rejection and clear");return 0;
}
