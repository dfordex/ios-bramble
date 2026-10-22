#!/usr/bin/env python3
"""Compile/test the actual staged kernel installer preflight with a private payload.

This exercises real stream/parser/policy functions with host allocation shims.
No filesystem installer code executes and no device is accessed. Apple payload
bytes remain only in the supplied private input/output paths, outside Git.
"""
import argparse,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--installer',type=Path,required=True);p.add_argument('--payload',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
s=a.installer.read_text();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
structs=s[s.index('struct a5metal_install_file {'):s.index('#if __has_include')]
functions=s[s.index('#define A5METAL_INSTALL_CHUNK'):s.index('static int\na5metal_install_mkdir')]
# Only metadata tables become mutable for negative tests; program/file bytes
# retain the exact private generated include and are never written to Git.
payload=a.payload.read_text().replace('static const struct a5metal_install_file a5metal_install_files[]','static struct a5metal_install_file a5metal_install_files[]').replace('static const struct a5metal_install_directory a5metal_install_directories[]','static struct a5metal_install_directory a5metal_install_directories[]')
include=out/'payload.inc';include.write_text(payload)
pre='''#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <string.h>\n#include <stdio.h>\n#include <assert.h>\n#include <errno.h>\n#include <zlib.h>\n#define MAXPATHLEN 1024\n#ifndef __unused\n#define __unused __attribute__((unused))\n#endif\n#define KHEAP_DEFAULT 0\n#define Z_WAITOK 0\n#define Z_ZERO 0\n#define MIN(a,b) ((a)<(b)?(a):(b))\n#define kheap_alloc(heap,size,flags) calloc(1,(size))\n#define kheap_free(heap,address,size) ((void)(size),free(address))\n'''
test=r'''
int main(void){
unsigned char*buffer=malloc(A5METAL_INSTALL_CHUNK);assert(buffer);
a5metal_install_apps_enabled=true;assert(a5metal_install_preflight(buffer)==0);
unsigned nf=sizeof(a5metal_install_files)/sizeof(a5metal_install_files[0]);
unsigned nd=sizeof(a5metal_install_directories)/sizeof(a5metal_install_directories[0]);
assert(nf==60&&nd==225);
const char*bad[]={NULL,"","/","Applications/PosterBoard.app/Info.plist","/Applications/Other.app/Info.plist","/Applications/PosterBoard.app.evil/Info.plist","/Applications/PosterBoard.app/../Bad","/Applications/PosterBoard.app/./Bad","/Applications/PosterBoard.app//Bad","/Applications/PosterBoard.app/Bad/"};
for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++)assert(!a5metal_install_app_path(bad[i],false));
assert(a5metal_install_app_path("/Applications",true));assert(!a5metal_install_app_path("/Applications",false));
struct a5metal_install_file saved=a5metal_install_files[13];
a5metal_install_files[13].path="/Applications/Other.app/Info.plist";assert(a5metal_install_preflight(buffer)!=0);a5metal_install_files[13]=saved;
a5metal_install_files[13].path="/Applications/PosterBoard.app/MissingParent/file";assert(a5metal_install_preflight(buffer)!=0);a5metal_install_files[13]=saved;
a5metal_install_files[13].mode=017777;assert(a5metal_install_preflight(buffer)!=0);a5metal_install_files[13]=saved;
a5metal_install_files[13].size=A5METAL_INSTALL_FILE_MAX+1;assert(a5metal_install_preflight(buffer)!=0);a5metal_install_files[13]=saved;
struct a5metal_install_directory sd=a5metal_install_directories[1];
a5metal_install_directories[1].path="/Applications/Other.app";assert(a5metal_install_preflight(buffer)!=0);a5metal_install_directories[1]=sd;
a5metal_install_directories[1].mode=017777;assert(a5metal_install_preflight(buffer)!=0);a5metal_install_directories[1]=sd;
/* Gate-off must skip app file data and directory metadata entirely. */
a5metal_install_apps_enabled=false;a5metal_install_files[13].data=NULL;a5metal_install_files[13].size=UINT32_MAX;a5metal_install_directories[1].path="/Applications/Other.app";assert(a5metal_install_preflight(buffer)==0);a5metal_install_files[13]=saved;a5metal_install_directories[1]=sd;a5metal_install_apps_enabled=true;
unsigned ci=0;while(ci<nf&&!a5metal_install_files[ci].compressed_size)ci++;assert(ci<nf);struct a5metal_install_file compressed=a5metal_install_files[ci];
unsigned char*corrupt=malloc(compressed.compressed_size);memcpy(corrupt,compressed.data,compressed.compressed_size);corrupt[0]^=1;a5metal_install_files[ci].data=corrupt;assert(a5metal_install_preflight(buffer)!=0);a5metal_install_files[ci]=compressed;free(corrupt);
/* Empty raw files are valid; the nonnull sentinel is not a byte to install. */
a5metal_install_files[13].size=0;a5metal_install_files[13].compressed_size=0;assert(a5metal_install_preflight(buffer)==0);struct a5metal_install_stream stream;assert(!a5metal_install_stream_start(&stream,&a5metal_install_files[13]));unsigned count=999;const unsigned char*data=NULL;assert(!a5metal_install_stream_next(&stream,buffer,&data,&count)&&!count);assert(!a5metal_install_stream_rewind(&stream));assert(!a5metal_install_stream_next(&stream,buffer,&data,&count)&&!count);a5metal_install_stream_end(&stream);a5metal_install_files[13]=saved;
assert(a5metal_install_preflight(buffer)==0);assert(a5metal_install_files[13].uid==saved.uid&&a5metal_install_files[13].gid==saved.gid&&a5metal_install_files[13].mode==saved.mode);
free(buffer);puts("PASS actual kernel preflight:60 real streams/225dirs, six-bundle scope, modes/parents, corrupt stream rejection, empty files, app-gate-off legacy-only; no filesystem write claim");return 0;}
'''
source=out/'test.c';source.write_text(pre+structs+'\n#include "payload.inc"\n'+functions+test)
exe=out/'test';subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(source),'-lz','-o',str(exe)],check=True);subprocess.run([str(exe)],check=True)
