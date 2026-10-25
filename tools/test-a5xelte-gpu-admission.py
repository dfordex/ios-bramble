#!/usr/bin/env python3
"""Exercise the actual pre-START admission waiter with deterministic scheduling."""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--kernel-source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
s=(a.kernel_source/'iokit/Kernel/arm/A5XELTEGPU.cpp').read_text();start=s.index('bool\na5g3d_queue_acquire_runtime_wait(');end=s.index('bool\na5g3d_queue_release(',start)
pre=r'''
#include <cstdint>
#include <cassert>
#include <string>
#include <cstdio>
struct IOService{};struct IOBufferMemoryDescriptor{};using vm_offset_t=uintptr_t;
static volatile uint32_t gA5G3DQueueState;static uint64_t ticks;static unsigned sleeps,releaseAt,attempts;static bool unavailable;static uint32_t afterSleep=0;static std::string report;
static constexpr int kMillisecondScale=1;
static uint64_t mach_absolute_time(){return ticks;}
static void clock_interval_to_deadline(unsigned ms,int,uint64_t*out){*out=ticks+ms*1000;}
static void absolutetime_to_nanoseconds(uint64_t value,uint64_t*out){*out=value*1000;}
static void IOSleep(unsigned ms){ticks+=ms*1000;if(++sleeps==releaseAt)gA5G3DQueueState=afterSleep;}
static bool a5g3d_queue_acquire_runtime(IOService**,uint64_t*t,IOBufferMemoryDescriptor**,vm_offset_t*){
 ++attempts;if(unavailable||gA5G3DQueueState)return false;gA5G3DQueueState=3;*t=42;return true;}
template<class...T>static void IOLog(const char*,const char*status,T...){report=status;}
'''
body=r'''
int main(){IOService*o=nullptr;IOBufferMemoryDescriptor*b=nullptr;vm_offset_t gpu=0;uint64_t token=0;
 assert(a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&token==42&&!sleeps);
 gA5G3DQueueState=3;sleeps=0;releaseAt=7;token=0;
 assert(a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&sleeps==7&&token==42&&report=="acquired");
 /* Actual runtime AS0 transitions its reservation3 to active GPU1. */
 gA5G3DQueueState=1;sleeps=0;releaseAt=7;token=0;
 assert(a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&sleeps==7&&token==42&&report=="acquired");
 /* A terminal fault during another owner's job must never be retried. */
 gA5G3DQueueState=1;sleeps=0;releaseAt=3;afterSleep=2;
 assert(!a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&sleeps==3&&report=="poisoned");afterSleep=0;
 gA5G3DQueueState=2;sleeps=0;assert(!a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&!sleeps&&report=="poisoned");
 gA5G3DQueueState=0;unavailable=true;assert(!a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&!sleeps&&report=="unavailable");unavailable=false;
 gA5G3DQueueState=3;releaseAt=0;sleeps=0;uint64_t start=ticks;
 assert(!a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&ticks-start==2000000&&sleeps==2000&&report=="deadline");
 gA5G3DQueueState=1;releaseAt=0;sleeps=0;start=ticks;
 assert(!a5g3d_queue_acquire_runtime_wait(&o,&token,&b,&gpu)&&ticks-start==2000000&&sleeps==2000&&report=="deadline");
 puts("PASS actual GPU admission: immediate acquisition, CPU-staging and active-GPU contention recovery, terminal poison, unavailable rejection and both bounded deadlines; no job retry");}
'''
source=a.output/'test.cpp';source.write_text(pre+s[start:end]+body);exe=a.output/'test'
subprocess.run(['clang++','-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(source),'-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
