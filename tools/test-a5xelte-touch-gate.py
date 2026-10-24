#!/usr/bin/env python3
"""Run the actual touch probe/contact gate with MMIO and delivery observations.

No device access. Patch round-trip checks preserve the existing controller,
PMIC, recovery and polling functions exactly.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def function(source, signature):
    start = source.index(signature)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path)
    args = parser.parse_args()
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix='a5-touch-gate-'))
    work.mkdir(parents=True, exist_ok=True)
    assert not list(work.iterdir()), 'fresh work directory required'
    root = Path(__file__).resolve().parents[1]
    patch = root / 'xnu/patches/0207-a5xelte-touch-enable-independent-logging.patch'
    source = args.source.read_text()
    replica = work / 'bsd/dev/a5xelte_touch.c'
    replica.parent.mkdir(parents=True)
    shutil.copyfile(args.source, replica)
    subprocess.run(['patch', '-R', '-p1', '-d', str(work), '-i', str(patch)], check=True)
    before = replica.read_text()
    for signature in ('static bool\na5touch_power_on(', 'static void\na5touch_start_early(',
                      'static bool\na5touch_controller_init(void)\n{',
                      'static void\na5touch_log_thread(', 'static bool\na5touch_recover('):
        assert function(source, signature) == function(before, signature), signature
    subprocess.run(['patch', '-p1', '-d', str(work), '-i', str(patch)], check=True)
    assert replica.read_text() == source
    probe = function(source, 'void\na5xelte_touch_probe(void)\n{')
    packet = function(source, 'static bool\na5touch_report_packet(const uint8_t packet[34], unsigned *lines)\n{')
    harness = work / 'gate.c'
    harness.write_text('''#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <assert.h>
typedef uintptr_t vm_offset_t;
static int touch_arg,log_arg,probe_arg=1,trial_arg;
static unsigned maps,reads,power_calls,start_calls,trial_calls,deliveries,contact_logs,markers;
static bool a5_touch_log_contacts,a5_touch_active[5];
static uint16_t a5_touch_x[5],a5_touch_y[5];
static int gate_printf(const char *format,...){
 if(strstr(format,"contact slot="))contact_logs++;
 if(strstr(format,"enabled=%d contact_log=%d"))markers++;
 return 0;
}
#define printf gate_printf
static bool PE_parse_boot_argn(const char *key,void *out,unsigned size){
 assert(size==sizeof(int));int value;
 if(!strcmp(key,"a5touch")){if(touch_arg<0)return false;value=touch_arg;}
 else if(!strcmp(key,"a5touchlog"))value=log_arg;
 else if(!strcmp(key,"a5touchprobe"))value=probe_arg;
 else if(!strcmp(key,"a5touchbus"))value=trial_arg;
 else return false;
 *(int*)out=value;return true;
}
static vm_offset_t ml_io_map(vm_offset_t address,unsigned size){maps++;assert(size==0x1000);return address;}
static uint32_t a5touch_read(vm_offset_t base,uint32_t offset){
 (void)base;reads++;return offset==0x904?(1u<<9):offset==0x900?(1u<<27):0;
}
static bool a5touch_power_on(vm_offset_t base){(void)base;power_calls++;return true;}
static void a5touch_start_early(vm_offset_t a,vm_offset_t b){(void)a;(void)b;start_calls++;}
static void a5touch_chip_code_trial(vm_offset_t base){(void)base;trial_calls++;}
static uint16_t a5touch_le16(const uint8_t *p){return (uint16_t)(p[0]|(p[1]<<8));}
static void sweet_hid_touch(int slot,int down,int x,int y){
 assert(slot==0);assert(x==12&&y==34);assert(down==0||down==1);deliveries++;
}
''' + probe + '\n' + packet + '''
int main(void){
 unsigned cases=0;
 for(int enabled=-1;enabled<=1;enabled++)for(int log=0;log<=1;log++){
  touch_arg=enabled;log_arg=log;maps=reads=power_calls=start_calls=trial_calls=markers=0;
  a5xelte_touch_probe();assert(markers==1);assert(a5_touch_log_contacts==(log!=0));
  if(enabled==0){assert(!maps&&!reads&&!power_calls&&!start_calls&&!trial_calls);}
  else {assert(maps&&reads);assert(power_calls==1&&start_calls==1&&!trial_calls);}
  cases++;
 }
 touch_arg=1;log_arg=0;probe_arg=0;maps=reads=power_calls=start_calls=trial_calls=0;
 a5xelte_touch_probe();assert(!maps&&!reads&&!power_calls&&!start_calls&&!trial_calls);
 probe_arg=1;trial_arg=1;a5xelte_touch_probe();assert(trial_calls==1&&!power_calls&&!start_calls);
 touch_arg=0;maps=reads=power_calls=start_calls=trial_calls=0;
 a5xelte_touch_probe();assert(!maps&&!reads&&!power_calls&&!start_calls&&!trial_calls);
 for(int log=0;log<=1;log++){
  uint8_t bytes[34]={0};unsigned lines=0;deliveries=contact_logs=0;
  memset(a5_touch_active,0,sizeof(a5_touch_active));a5_touch_log_contacts=log!=0;
  bytes[1]=8;bytes[2]=1;bytes[4]=12;bytes[6]=34;bytes[9]=1;
  assert(a5touch_report_packet(bytes,&lines));assert(deliveries==1);
  assert(contact_logs==(unsigned)log&&lines==(unsigned)log);
  bytes[0]=0x20;assert(a5touch_report_packet(bytes,&lines));assert(deliveries==2);
 }
 fprintf(stderr,"PASS actual touch gate: %u default/on/off x log cases; disabled no MMIO; explicit trial preserved; quiet HID contacts delivered; PMIC/controller/poll/recovery unchanged\\n",cases);
 return 0;
}
''')
    binary = work / 'gate'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-std=c11', '-Wall', '-Wextra',
                    '-Werror', str(harness), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    main()
