#!/usr/bin/env python3
"""Run actual XNU eMMC command/PIO/strategy functions against a strict MMIO model."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('kernel_root', type=Path)
args = ap.parse_args()
source = (args.kernel_root / 'bsd/dev/a5xelte_emmc.c').read_text()
constants = source[source.index('#define EMMC_CTRL'):source.index('static vm_offset_t emmc_regs;')]
limits = source[source.index('#define A5_EMMC_MAX_BLOCKS'):source.index('static uint64_t emmc_log_first_lba')]
functions = source[source.index('static int\nemmc_command('):source.index('static uint32_t\nemmc_le32(')]
strategy = source[source.index('static void\nemmc_strategy('):source.index('static int\nemmc_ioctl(')]
stub = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#define A5_EMMC_POLL_LIMIT 128u
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
typedef uintptr_t vm_offset_t;
static uint64_t emmc_first_lba=1000, emmc_nsectors=128;
static bool emmc_writable=true, emmc_ready=true;
static vm_offset_t emmc_regs;
static int a5xelte_emmc_lock, locked;
static uint32_t emmc_secsize=512;
static uint8_t emmc_bounce[512], disk[128*512], initial[128*512];
struct buf {uint32_t count,resid,flags;int64_t block;int error,done,mapped;uint8_t *data;};
typedef struct buf *buf_t;typedef char *caddr_t;
#define B_READ 1
static uint32_t buf_count(buf_t b){return b->count;}
static uint32_t buf_resid(buf_t b){return b->resid;}
static uint32_t buf_flags(buf_t b){return b->flags;}
static int64_t buf_blkno(buf_t b){return b->block;}
static void buf_setresid(buf_t b,uint32_t v){b->resid=v;}
static void buf_seterror(buf_t b,int v){b->error=v;}
static int buf_map(buf_t b,caddr_t *p){assert(!b->mapped);b->mapped=1;*p=(char*)b->data;return 0;}
static void buf_unmap(buf_t b){assert(b->mapped);b->mapped=0;}
static void buf_biodone(buf_t b){assert(!b->mapped&&!locked);b->done++;}
static void lck_mtx_lock(int *l){(void)l;assert(!locked);locked=1;}
static void lck_mtx_unlock(int *l){(void)l;assert(locked);locked=0;}
static uint64_t mach_absolute_time(void){static uint64_t t;return ++t;}
static void absolutetime_to_nanoseconds(uint64_t t,uint64_t *n){*n=t;}
static int legacy_reads,legacy_writes;
static int emmc_read_sector(uint32_t l,uint8_t *p){assert(locked&&l>=1000&&l<1128);legacy_reads++;memcpy(p,disk+(l-1000)*512,512);return 0;}
static int emmc_write_sector(uint32_t l,const uint8_t *p){assert(locked&&emmc_writable&&l>=1000&&l<1128);legacy_writes++;memcpy(disk+(l-1000)*512,p,512);return 0;}
'''
model = r'''
static uint32_t arg,opcode,byte_count,moved,start,ctrl,intmask,width=2,ver=0x270a;
static unsigned mode,ncmd,commands[64],command_args[64];
static uint32_t emmc_rd(uint32_t off){
 if(off==EMMC_HCON)return width<<7;
 if(off==EMMC_VERID)return ver;
 if(off==EMMC_PWREN||off==EMMC_CLKENA)return 1;
 if(off==EMMC_CTRL)return mode==8?CTRL_FIFO_RESET:ctrl&~CTRL_FIFO_RESET;
 if(off==EMMC_INTMASK)return intmask;
 if(off==EMMC_CLKSEL)return 1u<<16;
 if(off==EMMC_STATUS){
  if(mode==7&&(opcode==18||opcode==25||opcode==12)&&moved==byte_count)return 1u<<9;
  if(opcode!=18)return 0;
  if(mode==11)return 65u<<17;
  uint32_t left=byte_count-moved;if(mode==10&&moved>=512)left=0;
  return MIN(left/(2u<<width),64u)<<17;
 }
 if(off==EMMC_RINTSTS){
  if(opcode==23){if(mode==2)return 0;if(mode==12)return 1u<<1;return INT_CMD_DONE;}
  if(opcode==12)return mode==6?1u<<1:INT_CMD_DONE;
  if(mode==3||mode==6||(mode==13&&moved>=512))return 1u<<7;
  return INT_CMD_DONE|(moved==byte_count&&mode!=4?INT_DATA_OVER:0)|(opcode==18?INT_RXDR:INT_TXDR);
 }
 if(off==EMMC_RESP0)return opcode==23&&mode==1?1u<<22:opcode==25&&mode==9?1u<<26:0;
 if(off==EMMC_TCBCNT)return mode==5?byte_count-512:byte_count;
 if(off==0x200||off==0x204){
  assert(opcode==18&&moved+4<=byte_count&&start+moved+4<=sizeof(disk));
  uint32_t v;memcpy(&v,disk+start+moved,4);moved+=4;return v;
 }
 assert(!"unexpected MMIO read");return 0;
}
static void emmc_wr(uint32_t off,uint32_t value){
 if(off==EMMC_CTRL){ctrl=value;return;}
 if(off==EMMC_INTMASK){intmask=value;return;}
 if(off==EMMC_RINTSTS||off==EMMC_TMOUT)return;
 if(off==EMMC_CMDARG){arg=value;return;}
 if(off==EMMC_BLKSIZ){assert(value==512);return;}
 if(off==EMMC_BYTCNT){byte_count=value;return;}
 if(off==EMMC_CMD){
  assert(locked&&ncmd<64);opcode=value&63u;commands[ncmd]=opcode;command_args[ncmd++]=arg;
  assert(value&CMD_HOLD);
  if(opcode==12){assert(value&CMD_STOP);assert(!(value&CMD_WAIT_DATA));return;}
  assert(value&CMD_WAIT_DATA);
  if(opcode==23){assert(arg>=2&&arg<=32);return;}
  assert(opcode==18||opcode==25);assert(value&CMD_DATA);
  assert((bool)(value&CMD_WRITE)==(opcode==25));
  start=(arg-1000u)*512u;moved=0;
  assert(start+byte_count<=sizeof(disk));return;
 }
 if(off==0x200||off==0x204){
  assert(opcode==25&&moved+4<=byte_count&&start+moved+4<=sizeof(disk));
  memcpy(disk+start+moved,&value,4);moved+=4;return;
 }
 assert(!"unexpected MMIO write");
}
static void reset(unsigned m){
 mode=m;ncmd=opcode=arg=byte_count=moved=ctrl=0;intmask=0x1234;width=2;ver=0x270a;
 emmc_first_lba=1000;emmc_nsectors=128;emmc_multi_blocks=32;emmc_io_poisoned=false;
 emmc_writable=emmc_ready=true;legacy_reads=legacy_writes=0;locked=0;emmc_secsize=512;
 for(unsigned i=0;i<sizeof(disk);i++)disk[i]=(uint8_t)(i*37u+i/512u);
 memcpy(initial,disk,sizeof(disk));
}
'''
main = r'''
int main(void){
 unsigned cases=0;uint8_t area[65536+2],*p=area+1;
 for(unsigned w=0;w<2;w++)for(unsigned blocks=2;blocks<=32;blocks++){
  reset(0);locked=1;assert(!emmc_transfer_blocks(1003,p,blocks,w));locked=0;
  assert(ncmd==2&&commands[0]==23&&command_args[0]==blocks&&commands[1]==(w?25u:18u));
  if(w){assert(!memcmp(disk+1536,p,blocks*512));assert(!memcmp(disk,initial,1536));assert(!memcmp(disk+1536+blocks*512,initial+1536+blocks*512,sizeof(disk)-1536-blocks*512));}
  else assert(!memcmp(p,initial+1536,blocks*512));
  assert(intmask==0x1234&&!emmc_io_poisoned);cases++;
 }
 reset(0);width=1;locked=1;assert(!emmc_transfer_blocks(1000,p,8,false));locked=0;assert(!memcmp(p,disk,4096));cases++;
 for(unsigned m=1;m<=12;m++){
  reset(m);locked=1;int e=emmc_transfer_blocks(1000,p,2,m==9);locked=0;
  assert(e);if(m==1){assert(e==ENOTSUP&&ncmd==1&&!emmc_io_poisoned);}
  if(m==2||m==8||m==12)assert(emmc_io_poisoned);
  if(m==3||m==4||m==5||m==6||m==7||m==9||m==10||m==11){assert(commands[ncmd-1]==12);assert(emmc_io_poisoned==(m==6||m==7));}
  assert(emmc_multi_blocks==1&&intmask==0x1234);cases++;
 }
 for(unsigned c=0;c<8;c++){
  reset(0);uint32_t l=1000,b=2;uint8_t *out=p;bool w=false;
  if(c==0)l=999;if(c==1)l=1127;if(c==2)b=1;if(c==3)b=33;if(c==4)out=NULL;
  if(c==5){w=true;emmc_writable=false;}if(c==6)emmc_io_poisoned=true;
  if(c==7){emmc_first_lba=UINT32_MAX-1;emmc_nsectors=10;l=UINT32_MAX-1;b=3;}
  locked=1;assert(emmc_transfer_blocks(l,out,b,w));locked=0;assert(!ncmd);cases++;
 }
 for(unsigned w=0;w<2;w++){
  reset(0);memset(p,0xa5,65536);struct buf bp={.count=65536,.flags=w?0:B_READ,.data=p};
  emmc_strategy(&bp);assert(!bp.error&&!bp.resid&&bp.done==1&&!bp.mapped);
  assert(ncmd==8&&!legacy_reads&&!legacy_writes);assert(!memcmp(p,disk,65536));cases++;
 }
 reset(0);memset(p,0x5a,4100);struct buf bp={.count=4100,.data=p};emmc_strategy(&bp);
 assert(!bp.error&&!bp.resid&&bp.done==1&&legacy_reads==1&&legacy_writes==1);
 assert(!memcmp(disk,p,4100)&&!memcmp(disk+4100,initial+4100,sizeof(disk)-4100));cases++;
 reset(1);bp=(struct buf){.count=4096,.flags=B_READ,.data=p};emmc_strategy(&bp);
 assert(!bp.error&&!bp.resid&&legacy_reads==8&&ncmd==1);assert(!memcmp(p,disk,4096));cases++;
 reset(3);bp=(struct buf){.count=4096,.data=p};emmc_strategy(&bp);
 assert(bp.error==EIO&&bp.resid==4096&&bp.done==1&&!legacy_writes&&!legacy_reads);cases++;
 reset(13);memset(p,0xc3,4096);bp=(struct buf){.count=4096,.data=p};emmc_strategy(&bp);
 assert(bp.error==EIO&&bp.resid==4096&&bp.done==1&&!legacy_writes&&!legacy_reads);
 assert(moved==512&&commands[ncmd-1]==12&&!emmc_io_poisoned);
 assert(!memcmp(disk,p,512)&&!memcmp(disk+512,initial+512,sizeof(disk)-512));cases++;
 reset(0);bp=(struct buf){.count=1024,.block=127,.data=p};emmc_strategy(&bp);
 assert(bp.error==EINVAL&&bp.resid==1024&&bp.done==1&&!ncmd);cases++;
 printf("PASS actual eMMC CMD/PIO/strategy: %u cases\n",cases);
}
'''
with tempfile.TemporaryDirectory(prefix='a5-emmc-test-') as td:
    td = Path(td)
    path = td / 'test.c'
    path.write_text(stub + constants + limits + model + functions + strategy + main)
    exe = td / 'test'
    subprocess.run(['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra',
                    '-Werror', '-Wno-unused-variable', '-fsanitize=address,undefined',
                    str(path), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
