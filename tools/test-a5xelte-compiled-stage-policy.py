#!/usr/bin/env python3
"""Validate actual stage publications and actual kernel cache preflight policy.

Uses private stage bytes, production provider ABI validation and the staged
kernel's real stream/parser functions. No filesystem installer/device executes.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import zlib


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('installer','stage','request','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    a=parser.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
    spec=importlib.util.spec_from_file_location('embed',Path(__file__).with_name('a5xelte-metal-bundle-embed.py'))
    embed=importlib.util.module_from_spec(spec);spec.loader.exec_module(embed)
    files,dirs=embed.compiled_stage_entries(a.stage,a.request,out/'validate')
    source=a.installer.read_text()
    structs=source[source.index('struct a5metal_install_file {'):source.index('#if __has_include')]
    functions=source[source.index('#define A5METAL_INSTALL_CHUNK'):source.index('static int\na5metal_install_mkdir')]
    data=['#define A5METAL_COMPILED_DIRECTORIES_PRESENT 1']
    for i,(_path,raw,_mode,_uid,_gid) in enumerate(files):
        packed=zlib.compress(raw,9)
        data.append(f'static const unsigned char payload_{i}[]={{'+','.join(str(b)for b in packed)+'};')
    data.append('static struct a5metal_install_directory a5metal_install_compiled_directories[]={')
    data.extend('{'+embed.c_string(path)+f',0{mode:o},{uid},{gid}'+'},' for path,mode,uid,gid in dirs)
    data.append('};\nstatic struct a5metal_install_file a5metal_install_files[]={')
    for i,(path,raw,mode,uid,gid) in enumerate(files):
        data.append('{'+embed.c_string(path)+f',payload_{i},{len(raw)},0{mode:o},{len(zlib.compress(raw,9))},{uid},{gid}'+'},')
    data.append('};')
    pre='''#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <errno.h>
#include <zlib.h>
#define MAXPATHLEN 1024
#ifndef __unused
#define __unused __attribute__((unused))
#endif
#define KHEAP_DEFAULT 0
#define Z_WAITOK 0
#define Z_ZERO 0
#define MIN(a,b) ((a)<(b)?(a):(b))
#define kheap_alloc(heap,size,flags) calloc(1,(size))
#define kheap_free(heap,address,size) ((void)(size),free(address))
'''
    test=r'''
int main(void){
(void)a5metal_install_stream_rewind;
unsigned char*buffer=malloc(A5METAL_INSTALL_CHUNK);assert(buffer);
a5metal_install_apps_enabled=false;assert(!a5metal_install_preflight(buffer));
assert(a5metal_install_compiled_path(A5METAL_COMPILED_ROOT,true));
assert(!a5metal_install_compiled_path(A5METAL_COMPILED_ROOT,false));
const char*bad[]={NULL,"","/private/var/tmp/a5mali-shader-compiled.evil","/private/var/tmp/a5mali-shader-compiled/../bad","/private/var/tmp/a5mali-shader-compiled/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/receipt.json"};
for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++)assert(!a5metal_install_compiled_path(bad[i],true)&&!a5metal_install_compiled_path(bad[i],false));
struct a5metal_install_file saved=a5metal_install_files[0];
a5metal_install_files[0].path="/private/var/tmp/a5mali-shader-compiled/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/receipt.json";
assert(a5metal_install_preflight(buffer));a5metal_install_files[0]=saved;
char path[1024];snprintf(path,sizeof(path),"%s/extra",saved.path);a5metal_install_files[0].path=path;
assert(a5metal_install_preflight(buffer));a5metal_install_files[0]=saved;
const unsigned badmodes[]={0644,0755,04744,017777};
for(unsigned i=0;i<sizeof(badmodes)/sizeof(badmodes[0]);i++){a5metal_install_files[0].mode=badmodes[i];assert(a5metal_install_preflight(buffer));}a5metal_install_files[0]=saved;
a5metal_install_files[0].uid=501;assert(a5metal_install_preflight(buffer));a5metal_install_files[0]=saved;
a5metal_install_files[0].gid=20;assert(a5metal_install_preflight(buffer));a5metal_install_files[0]=saved;
struct a5metal_install_directory dir=a5metal_install_compiled_directories[1];
a5metal_install_compiled_directories[1].path="/private/var/tmp/a5mali-shader-compiled/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
assert(a5metal_install_preflight(buffer));a5metal_install_compiled_directories[1]=dir;
a5metal_install_compiled_directories[1].mode=0777;assert(a5metal_install_preflight(buffer));a5metal_install_compiled_directories[1]=dir;
a5metal_install_compiled_directories[1].uid=501;assert(a5metal_install_preflight(buffer));a5metal_install_compiled_directories[1]=dir;
a5metal_install_compiled_directories[1].gid=20;assert(a5metal_install_preflight(buffer));a5metal_install_compiled_directories[1]=dir;
a5metal_install_compiled_directories[0].path="/Applications";assert(a5metal_install_preflight(buffer));a5metal_install_compiled_directories[0].path=A5METAL_COMPILED_ROOT;
unsigned char*corrupt=malloc(saved.compressed_size);memcpy(corrupt,saved.data,saved.compressed_size);corrupt[0]^=1;
a5metal_install_files[0].data=corrupt;assert(a5metal_install_preflight(buffer));a5metal_install_files[0]=saved;free(corrupt);
assert(!a5metal_install_preflight(buffer));free(buffer);
puts("PASS actual kernel compiled-stage preflight: app gate off, exact paths/triples/parents, root0444/0755 metadata, corrupted streams rejected; no filesystem writes");return 0;}
'''
    c=out/'kernel-policy.c';c.write_text(pre+structs+'\n'+'\n'.join(data)+'\n'+functions+test)
    binary=out/'kernel-policy'
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(c),'-lz','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
    # Packaging must reject corruption and altered request identity, not merely
    # rely on the destination reader to discover it after installation.
    negative=out/'negative'/a.stage.name
    if negative.exists():shutil.rmtree(negative)
    shutil.copytree(a.stage,negative)
    native=negative/'stage.midgard';raw=native.read_bytes();native.chmod(0o644)
    native.write_bytes(bytes([raw[0]^1])+raw[1:]);native.chmod(0o444)
    try:embed.compiled_stage_entries(negative,a.request,out/'validate-negative')
    except ValueError:pass
    else:raise AssertionError('corrupt stage accepted')
    badrequest=out/'changed-request.json';request=json.loads(a.request.read_text());request['owner_uid']^=1
    badrequest.write_text(json.dumps(request))
    try:embed.compiled_stage_entries(a.stage,badrequest,out/'validate-negative')
    except ValueError:pass
    else:raise AssertionError('changed request identity accepted')
    print('PASS exact publication/hash/canonical-request packaging rejection tests')

if __name__=='__main__':main()
