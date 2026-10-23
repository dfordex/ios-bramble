#!/usr/bin/env python3
"""ASan/UBSan tests of the actual bounded TCC extension-provider source."""
from pathlib import Path
import argparse
import subprocess
import tempfile
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('kernel_root', type=Path, nargs='?')
args = parser.parse_args()
if args.kernel_root:
    code = (args.kernel_root / 'bsd/kern/a5xelte_sandbox_extensions.inc').read_text()
else:
    patch = (Path(__file__).resolve().parents[1] /
             'xnu/patches/0202-a5xelte-tcc-generic-extensions.patch').read_text()
    added = patch.split('+++ b/bsd/kern/a5xelte_sandbox_extensions.inc\n', 1)[1]
    code = '\n'.join(line[1:] for line in added.splitlines() if line.startswith('+')) + '\n'

code='\n'.join(l for l in code.splitlines() if not l.startswith('#include'))
stub=r'''
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <limits.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>
#include <pthread.h>
#include <sys/time.h>
#define ARM64_BOARD_CONFIG_A5XELTE 1
#define LCK_GRP_DECLARE(n,s) int n
#define LCK_MTX_DECLARE(n,g) pthread_mutex_t n = PTHREAD_MUTEX_INITIALIZER
#define lck_mtx_lock pthread_mutex_lock
#define lck_mtx_unlock pthread_mutex_unlock
struct cs_blob {const char *identity;};
struct vnode {const char *path;};typedef struct vnode *vnode_t;
struct proc {int pid,version;uint64_t uid;bool platform;struct cs_blob blob;struct vnode vnode;};typedef struct proc *proc_t;
static struct proc procs[5];static int fail_copyin,fail_copyout,fail_copyinstr,vrefs;static uint64_t seconds=10,randseq;
static struct cs_blob *csproc_get_blob(proc_t p){return &p->blob;}
static const char *csblob_get_identity(struct cs_blob *b){return b->identity;}
static int csproc_get_platform_binary(proc_t p){return p->platform;}
static vnode_t proc_getexecutablevnode(proc_t p){vrefs++;return &p->vnode;}
static int vn_getpath(vnode_t v,char *out,int *n){if(!v->path)return EINVAL;if((size_t)*n<=strlen(v->path))return ENAMETOOLONG;strcpy(out,v->path);return 0;}
static void vnode_put(vnode_t v){(void)v;vrefs--;}
static proc_t proc_find(int pid){for(int i=0;i<5;i++)if(procs[i].pid==pid)return &procs[i];return NULL;}
static void proc_rele(proc_t p){(void)p;}
static int proc_pid(proc_t p){return p->pid;}static int proc_pidversion(proc_t p){return p->version;}static uint64_t proc_uniqueid(proc_t p){return p->uid;}
static int copyin(user_addr_t p,void *out,size_t n){if(fail_copyin){fail_copyin--;return EFAULT;}if(p<4096)return EFAULT;memcpy(out,(void*)p,n);return 0;}
static int copyout(const void *src,user_addr_t p,size_t n){if(fail_copyout){fail_copyout--;return EFAULT;}if(p<4096)return EFAULT;memcpy((void*)p,src,n);return 0;}
static int copyinstr(user_addr_t p,char*out,size_t n,size_t*copied){if(fail_copyinstr)return EFAULT;if(p<4096)return EFAULT;size_t len=strnlen((char*)p,n);if(len>=n)return ENAMETOOLONG;memcpy(out,(char*)p,len+1);*copied=len+1;return 0;}
static void microuptime(struct timeval *t){t->tv_sec=seconds;t->tv_usec=0;}
static void read_random(void *p,unsigned n){unsigned char *b=p;uint64_t v=__sync_add_and_fetch(&randseq,1);for(unsigned i=0;i<n;i++)b[i]=(unsigned char)(v>>(8*(i%8)));}
'''
main=r'''
#define PTR(x) ((user_addr_t)(x))
static char cls[]="com.apple.tcc.kTCCServicePhotos";
static int checks;
#define CHECK(x) do { assert(x); checks++; } while(0)
static void reset(void){memset(a5_sb_extensions,0,sizeof(a5_sb_extensions));a5_sb_generation=0;a5_sb_log_count=48;fail_copyin=fail_copyout=fail_copyinstr=0;seconds=10;}
static struct a5_sb_issue_args issueargs(char *token){return (struct a5_sb_issue_args){PTR(cls),3,0,0,PTR(token),0,0};}
static int issue(proc_t p,char*token){struct a5_sb_issue_args a=issueargs(token);return a5_sb_issue(p,PTR(&a));}
static int consume(proc_t p,char*token,uint64_t*handle){struct a5_sb_consume_args a={PTR(token),72,PTR(handle)};return a5_sb_consume(p,PTR(&a));}
static int release(proc_t p,uint64_t handle){struct a5_sb_release_args a={handle,0,0};return a5_sb_release(p,PTR(&a));}
static unsigned used(void){unsigned n=0;for(unsigned i=0;i<A5_SB_SLOTS;i++)n+=a5_sb_extensions[i].state!=0;return n;}
struct race {proc_t p;char *token;int error;uint64_t h;};
static void *raceconsume(void *arg){struct race *r=arg;r->error=consume(r->p,r->token,&r->h);return NULL;}
int main(void){
 const char *path="/System/Library/PrivateFrameworks/TCC.framework/Support/tccd";
 for(int i=0;i<5;i++)procs[i]=(struct proc){100+i,1,1000+i,true,{"com.apple.tccd"},{path}};
 proc_t issuer=&procs[0],client=&procs[1],other=&procs[2];char token[72],old[72];uint64_t h=0,h2=0;reset();
 CHECK(!issue(issuer,token));CHECK(!memcmp(token,"A5TCC1:",7)&&token[71]==0);CHECK(!consume(client,token,&h)&&h>0);CHECK(!consume(client,token,&h2)&&h==h2);
 CHECK(consume(other,token,&h2)==EPERM);CHECK(release(other,h)==EPERM);CHECK(!release(client,h));CHECK(used()==1);CHECK(!release(client,h));CHECK(used()==0);CHECK(release(client,h)==ENOENT);CHECK(consume(client,token,&h)==ENOENT);
 struct a5_sb_issue_args a=issueargs(token);CHECK(a5_sb_issue(issuer,0)==EFAULT);fail_copyin=1;CHECK(a5_sb_issue(issuer,PTR(&a))==EFAULT);fail_copyinstr=1;CHECK(a5_sb_issue(issuer,PTR(&a))==EFAULT);fail_copyinstr=0;
 a.type=0;CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);a=issueargs(token);a.resource=1;CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);a=issueargs(token);a.flags=2;CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);a.flags=0x20000;CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);
 a=issueargs(token);a.extension_class=PTR("com.apple.app-sandbox.read-write");CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);char longclass[96];memset(longclass,'x',sizeof(longclass));a.extension_class=PTR(longclass);CHECK(a5_sb_issue(issuer,PTR(&a))==ENAMETOOLONG);a.extension_class=PTR("com.apple.tcc.kTCCService../Photos");CHECK(a5_sb_issue(issuer,PTR(&a))==ENOTSUP);
 issuer->blob.identity="com.apple.other";CHECK(issue(issuer,token)==EPERM);issuer->blob.identity="com.apple.tccd";issuer->platform=false;CHECK(issue(issuer,token)==EPERM);issuer->platform=true;issuer->vnode.path="/tmp/tccd";CHECK(issue(issuer,token)==EPERM);issuer->vnode.path=path;
 reset();fail_copyout=1;CHECK(issue(issuer,token)==EFAULT);CHECK(!used());CHECK(!issue(issuer,token));fail_copyout=1;CHECK(consume(client,token,&h)==EFAULT);CHECK(a5_sb_extensions[0].state==A5_SB_ISSUED&&!a5_sb_extensions[0].consumer);CHECK(!consume(client,token,&h));fail_copyout=1;CHECK(consume(client,token,&h2)==EFAULT);CHECK(a5_sb_extensions[0].refs==1);CHECK(!release(client,h));
 reset();a=issueargs(token);a.flags=0x30000;a.pid=client->pid;a.pidversion=client->version;CHECK(!a5_sb_issue(issuer,PTR(&a)));CHECK(consume(other,token,&h)==EPERM);client->version++;CHECK(consume(client,token,&h)==EPERM);client->version--;CHECK(!consume(client,token,&h));CHECK(!release(client,h));a.pidversion++;CHECK(a5_sb_issue(issuer,PTR(&a))==ESRCH);a.pid=99999;CHECK(a5_sb_issue(issuer,PTR(&a))==ESRCH);a.pid=UINT64_MAX;CHECK(a5_sb_issue(issuer,PTR(&a))==EINVAL);
 reset();CHECK(!issue(issuer,token));memcpy(old,token,72);token[10]='?';CHECK(consume(client,token,&h)==EINVAL);memcpy(token,old,72);token[10]=token[10]=='0'?'1':'0';CHECK(consume(client,token,&h)==ENOENT);memcpy(token,old,72);struct a5_sb_consume_args c={PTR(token),71,PTR(&h)};CHECK(a5_sb_consume(client,PTR(&c))==EINVAL);c.length=72;c.handle=0;CHECK(a5_sb_consume(client,PTR(&c))==EFAULT);seconds+=A5_SB_PENDING_SECONDS;CHECK(consume(client,token,&h)==ENOENT);CHECK(!used());
 reset();CHECK(!issue(issuer,token));a5_sb_proc_exit(issuer);CHECK(!used());CHECK(!issue(issuer,token));CHECK(!consume(client,token,&h));a5_sb_proc_exit(issuer);CHECK(used()==1);a5_sb_proc_exit(client);CHECK(!used());CHECK(consume(client,token,&h)==ENOENT);
 reset();for(unsigned i=0;i<A5_SB_ISSUER_LIMIT;i++)CHECK(!issue(issuer,token));CHECK(issue(issuer,token)==ENOSPC);a5_sb_proc_exit(issuer);CHECK(!used());
 reset();for(unsigned i=0;i<A5_SB_CONSUMER_LIMIT;i++){CHECK(!issue(issuer,token));CHECK(!consume(client,token,&h));}CHECK(!issue(issuer,token));CHECK(consume(client,token,&h)==ENOSPC);a5_sb_proc_exit(client);a5_sb_proc_exit(issuer);CHECK(!used());
 reset();CHECK(!issue(issuer,token));CHECK(!consume(client,token,&h));seconds+=A5_SB_PENDING_SECONDS+1;CHECK(!release(client,h));CHECK(!used());
 reset();CHECK(!issue(issuer,token));struct race r[2]={{client,token,0,0},{other,token,0,0}};pthread_t threads[2];for(int i=0;i<2;i++)pthread_create(&threads[i],NULL,raceconsume,&r[i]);for(int i=0;i<2;i++)pthread_join(threads[i],NULL);CHECK((r[0].error==0)+(r[1].error==0)==1);for(int i=0;i<2;i++)if(!r[i].error)CHECK(!release(r[i].p,r[i].h));CHECK(!used());CHECK(vrefs==0);

 reset();a=issueargs(token);a.flags=0x10000;a.pid=client->pid;CHECK(!a5_sb_issue(issuer,PTR(&a)));client->version++;CHECK(consume(client,token,&h)==EPERM);client->version--;CHECK(!consume(client,token,&h));CHECK(!release(client,h));
 reset();CHECK(a5_sb_consume(client,0)==EFAULT);CHECK(a5_sb_release(client,0)==EFAULT);CHECK(!issue(issuer,token));fail_copyin=1;CHECK(consume(client,token,&h)==EFAULT);CHECK(!consume(client,token,&h));fail_copyin=1;CHECK(release(client,h)==EFAULT);struct a5_sb_release_args badrelease={h,1,0};CHECK(a5_sb_release(client,PTR(&badrelease))==EINVAL);CHECK(!release(client,h));
 reset();for(unsigned i=0;i<A5_SB_SLOTS;i++)CHECK(!issue(&procs[i/A5_SB_ISSUER_LIMIT],token));CHECK(used()==A5_SB_SLOTS);CHECK(issue(&procs[4],token)==ENOSPC);seconds+=A5_SB_PENDING_SECONDS;CHECK(!issue(&procs[4],token));CHECK(used()==1);a5_sb_proc_exit(&procs[4]);CHECK(!used());
 printf("PASS actual TCC extension provider: %d checks (ABI, permissions, faults, lifecycle, quota, concurrent claim)\n",checks);
}
'''
with tempfile.TemporaryDirectory(prefix='a5-tcc-extensions-') as directory:
    p=Path(directory)/'extensions.c';p.write_text(stub+code+main)
    subprocess.run(['/usr/bin/clang','-std=gnu11','-Wall','-Wextra','-Werror','-Wno-unused-variable','-fsanitize=address,undefined','-g','-pthread',str(p),'-o',str(p.with_suffix(''))],check=True)
    subprocess.run([str(p.with_suffix(''))],check=True)
