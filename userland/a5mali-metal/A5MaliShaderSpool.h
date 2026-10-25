/* SPDX-License-Identifier: MIT
 * Secure per-UID lanes: function demand never competes with pipeline receipts.
 * Opening is component-by-component; no caller-controlled path is accepted.
 */
#ifndef A5_MALI_SHADER_SPOOL_H
#define A5_MALI_SHADER_SPOOL_H
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
static inline int A5MaliOpenShaderLane(int root,uid_t uid,unsigned functions,int create){
 if(functions>1){errno=EINVAL;return -1;}
 char owner[32];snprintf(owner,sizeof(owner),"%u",uid);
 if(create&&mkdirat(root,owner,0700)&&errno!=EEXIST)return -1;
 int dir=openat(root,owner,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);struct stat st;
 if(dir<0)return -1;
 if(fstat(dir,&st)||!S_ISDIR(st.st_mode)||st.st_uid!=uid||(st.st_mode&07777)!=0700){close(dir);errno=EPERM;return -1;}
 if(!functions)return dir;
 if(create&&mkdirat(dir,"functions",0700)&&errno!=EEXIST){close(dir);return -1;}
 int lane=openat(dir,"functions",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(dir);
 if(lane<0)return -1;
 if(fstat(lane,&st)||!S_ISDIR(st.st_mode)||st.st_uid!=uid||(st.st_mode&07777)!=0700){close(lane);errno=EPERM;return -1;}
 return lane;
}
#endif
