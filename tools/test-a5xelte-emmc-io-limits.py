#!/usr/bin/env python3
"""Extract actual XNU eMMC ioctl and HFS journal limit selection; no hardware I/O."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('kernel_root', type=Path)
p.add_argument('--output', type=Path)
a = p.parse_args()
out = a.output or Path(tempfile.mkdtemp(prefix='a5-emmc-io-limits-'))
out.mkdir(parents=True, exist_ok=True)
src = (a.kernel_root / 'bsd/dev/a5xelte_emmc.c').read_text()
limits = src[src.index('#define A5_EMMC_MAX_BLOCKS'):src.index('#define A5_EMMC_R1_ERRORS')]
ioctl = src[src.index('static int\nemmc_ioctl('):src.index('static int\nemmc_psize(')]
hfs = (a.kernel_root / 'bsd/sweet_hfs/core/hfs_journal.c').read_text()
selection = hfs[hfs.index('static void\nget_io_info('):hfs.index('\n\njournal *\njournal_create(')]
stub = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/disk.h>
#ifndef DKIOCSETBLOCKSIZE
#define DKIOCSETBLOCKSIZE _IOW('d',24,uint32_t)
#endif
#ifndef DK_FEATURE_FORCE_UNIT_ACCESS
#define DK_FEATURE_FORCE_UNIT_ACCESS 0x00000001
#endif
#ifndef TEST_PAGE_SIZE
#define TEST_PAGE_SIZE 4096
#endif
#define PAGE_SIZE TEST_PAGE_SIZE
struct proc;
static uint32_t emmc_secsize=512;
static uint64_t emmc_nsectors=1024;
static bool emmc_writable;
'''
adapter = r'''
#define JOURNAL_DO_FUA_WRITES 1
#define JOURNAL_USE_UNMAP 2
#define JOURNAL_FEATURE_BARRIER 4
struct vnode{};struct vfs_context{};
typedef int64_t off_t;
typedef struct {uint32_t flags;uint32_t max_read_size,max_write_size;const char *jdev_name;} journal;
static const char *vnode_getname_printable(struct vnode *v){(void)v;return "host-test";}
static void vnode_putname_printable(const char *n){(void)n;}
static int VNOP_IOCTL(struct vnode*v,unsigned long cmd,caddr_t d,int f,struct vfs_context*c){
 (void)v;(void)f;(void)c;return emmc_ioctl(0,cmd,d,0,NULL);
}
'''
test = r'''
static uint64_t query(unsigned long cmd){uint64_t v=UINT64_MAX;assert(!emmc_ioctl(0,cmd,(caddr_t)&v,0,NULL));return v;}
int main(void){unsigned cases=0;
 for(unsigned ro=0;ro<2;ro++)for(uint32_t size=512;size<=4096;size*=2){
  emmc_writable=!ro;assert(!emmc_ioctl(0,DKIOCSETBLOCKSIZE,(caddr_t)&size,0,NULL));
  uint64_t blocks=16384/size,segments=(16384+PAGE_SIZE-1)/PAGE_SIZE;
  assert(query(DKIOCGETMAXBLOCKCOUNTREAD)==blocks);
  assert(query(DKIOCGETMAXBLOCKCOUNTWRITE)==(ro?0:blocks));
  assert(query(DKIOCGETMAXBYTECOUNTREAD)==16384);
  assert(query(DKIOCGETMAXBYTECOUNTWRITE)==(ro?0:16384));
  assert(query(DKIOCGETMAXSEGMENTCOUNTREAD)==segments);
  assert(query(DKIOCGETMAXSEGMENTCOUNTWRITE)==(ro?0:segments));
  assert(query(DKIOCGETMAXSEGMENTBYTECOUNTREAD)==16384);
  assert(query(DKIOCGETMAXSEGMENTBYTECOUNTWRITE)==(ro?0:16384));
  journal j={0};get_io_info(NULL,size,&j,NULL);
  assert(j.max_read_size==16384);
  /* HFS substitutes its historical128KiB default if writes are disallowed.
   * Driver writes still report0 and emmc_open/strategy enforce EROFS. */
  assert(j.max_write_size==(ro?128*1024:16384));
  uint32_t bad=768;assert(emmc_ioctl(0,DKIOCSETBLOCKSIZE,(caddr_t)&bad,0,NULL)==EINVAL);
  assert(emmc_secsize==size);cases++;
 }
 assert(A5_EMMC_MAX_BLOCKS==32);assert(!emmc_ioctl(0,DKIOCSYNCHRONIZE,NULL,0,NULL));
 assert(!emmc_ioctl(0,DKIOCSYNCHRONIZECACHE,NULL,0,NULL));
 printf("PASS actual ioctl + HFS get_io_info: %u logical-block/ro-rw cases, page=%u;32-sector transfer unchanged\n",cases,PAGE_SIZE);
}
'''
logs=[]
for page in (4096, 16384):
    path = out / f'test-{page}.c'
    path.write_text(stub + limits + ioctl + adapter + selection + test)
    exe = out / f'test-{page}'
    subprocess.run(['clang', '-std=c11', '-D_DARWIN_C_SOURCE', f'-DTEST_PAGE_SIZE={page}', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-fsanitize=address,undefined', str(path), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe)], capture_output=True, text=True, check=True)
    logs.append(result.stdout.strip())
    print(logs[-1])
proof = {'actual_ioctl_extracted': True, 'actual_hfs_get_io_info_extracted': True, 'logical_block_sizes': [512, 1024, 2048, 4096], 'readonly_and_writable': True, 'tested_page_sizes': [4096, 16384], 'read_max_bytes': 16384, 'writable_max_bytes': 16384, 'readonly_write_limits': 0, 'hardware_transfer_blocks': 32, 'hardware_runtime_verified': False, 'source_sha256': hashlib.sha256(src.encode()).hexdigest(), 'hfs_source_sha256': hashlib.sha256(hfs.encode()).hexdigest()}
(out / 'result.json').write_text(json.dumps(proof, indent=2) + '\n')
