#!/usr/bin/env python3
from pathlib import Path
import argparse
import subprocess
import tempfile
parser = argparse.ArgumentParser(description="Exercise the actual A5 UI sampler with faulting reads and lock/reference assertions")
parser.add_argument('kernel_root', type=Path)
args = parser.parse_args()
root = args.kernel_root
s=(root/'osfmk/kern/exception.c').read_text()
start=s.index('void\nsweet_sample_task(');end=s.index('\n}\n',start)+3
function=s[start:end]
stub=r'''
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <assert.h>
#define ARM64_BOARD_CONFIG_A5XELTE 1
#define KERN_SUCCESS 0
#define VM_MAP_NULL NULL
#define THREAD_NULL NULL
typedef unsigned long long u64;
typedef struct regs {u64 pc,lr,sp,fp;bool valid;} arm_saved_state_t;
typedef struct thread {struct thread *next;u64 thread_id,wait_event;int state,wait_result,sched_pri,refs;arm_saved_state_t *regs;} *thread_t;
typedef struct task {thread_t threads;u64 mach_header_vm_address;bool no_map;} *task_t;
typedef void *vm_map_t;
typedef struct region {u64 sr_slide;} *vm_shared_region_t;
typedef int spl_t;
static int tl,thl,refs,reads,mode,lines;static char header[500];
#define queue_iterate(q,t,ty,link) for((t)=*(q);(t);(t)=(t)->next)
static vm_map_t get_task_map(task_t t){return t->no_map?NULL:(void*)t;}
static vm_shared_region_t vm_shared_region_get(task_t t){(void)t;return NULL;}
static void vm_shared_region_deallocate(vm_shared_region_t r){(void)r;}
static void vm_map_reference(vm_map_t m){assert(m&&!tl&&!thl);refs++;}
static void vm_map_deallocate(vm_map_t m){assert(m&&!tl&&!thl);refs--;}
static void task_lock(task_t t){(void)t;assert(!tl&&!thl);tl++;}
static void task_unlock(task_t t){(void)t;assert(tl==1&&!thl);tl--;}
static void thread_reference(thread_t t){assert(tl&&!thl);t->refs++;}
static void thread_deallocate(thread_t t){assert(!tl&&!thl&&t->refs==1);t->refs--;}
static spl_t splsched(void){return 0;}static void splx(spl_t s){(void)s;}
static void thread_lock(thread_t t){(void)t;assert(!tl&&!thl);thl++;}
static void thread_unlock(thread_t t){(void)t;assert(!tl&&thl==1);thl--;}
static arm_saved_state_t *find_user_regs(thread_t t){assert(thl);return t->regs;}
static bool is_saved_state64(arm_saved_state_t *s){return s->valid;}
static u64 get_saved_state_pc(arm_saved_state_t *s){return s->pc;}
static u64 get_saved_state_lr(arm_saved_state_t *s){return s->lr;}
static u64 get_saved_state_sp(arm_saved_state_t *s){return s->sp;}
static u64 get_saved_state_fp(arm_saved_state_t *s){return s->fp;}
static int vm_map_read_user(vm_map_t m,u64 p,void *out,size_t n){
 assert(m&&!tl&&!thl&&n==16);reads++;u64 frame[2]={0,0x1234};
 if(mode==1)return 1;
 if(mode==2)frame[0]=p; /* cyclic frame */
 if(mode==3)frame[0]=p+16; /* infinite ascending chain */
 if(mode==4)frame[0]=p+(8ull<<20)+16; /* escape window */
 memcpy(out,frame,n);return 0;
}
static int capture_printf(const char *fmt,...){
 assert(!tl&&!thl);char b[600];va_list a;va_start(a,fmt);int n=vsnprintf(b,sizeof(b),fmt,a);va_end(a);
 assert(n>0&&n<224&&b[n-1]=='\n');lines++;if(strstr(b,"captured="))strcpy(header,b);return n;
}
#define printf capture_printf
'''
main=r'''
#undef printf
int main(void){
 struct thread threads[64];arm_saved_state_t regs={1,2,0x1000,0x2000,true};
 struct task task={0};int cases=0;
 for(int c=0;c<14;c++){
  memset(threads,0,sizeof(threads));memset(header,0,sizeof(header));
  for(int i=0;i<64;i++){threads[i].next=i<63?&threads[i+1]:NULL;threads[i].thread_id=i+1;threads[i].regs=&regs;}
  task.threads=threads;task.no_map=false;mode=0;reads=lines=0;regs.fp=0x2000;regs.sp=0x1000;regs.valid=true;
  if(c==1)mode=1;
  if(c==2)regs.valid=false;
  if(c==3)regs.fp=0xff0;
  if(c==4)regs.fp=0x2008;
  if(c==5)regs.fp=regs.sp+(8ull<<20)+16;
  if(c==6)mode=2;
  if(c==7)mode=3;
  if(c==8)mode=4;
  if(c==9)task.no_map=true;
  const char *name=c==10?"deleted":"PosterBoard";
  if(c==11){
   for(int i=0;i<64;i++)threads[i].thread_id=~0ull;
   regs.pc=regs.lr=regs.sp=regs.fp=~0ull;
  }else{regs.pc=1;regs.lr=2;}
  if(c==12)regs.fp=regs.sp+(8ull<<20);
  if(c==13)for(int i=0;i<64;i++)threads[i].regs=NULL;
  sweet_sample_task(name,42,&task);
  assert(!tl&&!thl&&!refs);for(int i=0;i<64;i++)assert(!threads[i].refs);
  if(c==9){assert(!lines&&!reads);}
  else {
   int selected=c==10?16:32;
   assert(strstr(header,c==10?"threads=64 captured=16 approximate=1":"threads=64 captured=32 approximate=1"));
   int batches=(c==2||c==3||c==4||c==5||c==11||c==13||c==1)?0:(c==7?2:1);
   assert(lines==1+selected*(1+batches));
  }
  if(c==2||c==3||c==4||c==5||c==11||c==13)assert(!reads);
  if(c==0||c==1||c==6||c==8||c==12)assert(reads==32);
  if(c==10)assert(reads==16);
  if(c==7)assert(reads==32*12);
  cases++;
 }
 printf("PASS actual A5 sampler: %d bounds/reference/lock-scope cases\n",cases);
}
'''
with tempfile.TemporaryDirectory(prefix='a5-ui-sampler-') as folder:
    p=Path(folder)/'sampler.c'
    p.write_text(stub+function+main)
    subprocess.run(['/usr/bin/clang','-std=gnu11','-Wall','-Wextra','-Werror',
                    '-fsanitize=address,undefined','-g',str(p),'-o',str(p.with_suffix(''))],check=True)
    subprocess.run([str(p.with_suffix(''))],check=True)
