#!/usr/bin/env python3
"""Exercise the actual bounded daemon-restart logger with concurrent writers."""
from pathlib import Path
import argparse,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('kernel_root',type=Path);a=p.parse_args()
s=(a.kernel_root/'bsd/dev/mem.c').read_text();start=s.index('static volatile UInt64 a5_backboardd_budgets[4];');end=s.index('\nstatic volatile UInt32 a5_probe_null_chunks;',start)
helper=s[start:end]
stub='''#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
typedef uint32_t UInt32;typedef uint64_t UInt64;
static bool OSCompareAndSwap64(UInt64 old,UInt64 next,volatile UInt64 *p){return __atomic_compare_exchange_n(p,&old,next,false,__ATOMIC_SEQ_CST,__ATOMIC_SEQ_CST);}
'''
main='''
static atomic_uint accepted;
static void *writer(void *arg){UInt32 pid=(UInt32)(uintptr_t)arg;for(unsigned n=0;n<2048;n++)if(a5_backboardd_tee(pid))atomic_fetch_add(&accepted,1);return 0;}
int main(void){assert(!a5_backboardd_tee(0));pthread_t t[12];
for(unsigned i=0;i<12;i++)assert(!pthread_create(&t[i],0,writer,(void*)(uintptr_t)58));
for(unsigned i=0;i<12;i++)pthread_join(t[i],0);assert(accepted==2048);assert(!a5_backboardd_tee(58));
for(UInt32 pid=100;pid<103;pid++){for(unsigned i=0;i<2048;i++)assert(a5_backboardd_tee(pid));assert(!a5_backboardd_tee(pid));}
assert(!a5_backboardd_tee(200));assert(!a5_backboardd_tee(58));return 0;}
'''
with tempfile.TemporaryDirectory(prefix='a5-log-budget-',dir='/private/tmp')as tmp:
 q=Path(tmp);(q/'test.c').write_text(stub+helper+main)
 subprocess.run(['clang','-std=c11','-pthread','-Wall','-Wextra','-Werror',str(q/'test.c'),'-o',str(q/'test')],check=True)
 subprocess.run([str(q/'test')],check=True)
print('PASS 12 concurrent writers;2048 per PID;4 lifetimes;8192 boot-global maximum')
