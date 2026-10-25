/* SPDX-License-Identifier: MIT
 * Register the three already-installed Apple bundles using their actual
 * manifests, signed entitlements and MobileContainerManager containers.
 * No global database rebuild, unregister, cache deletion or process restart.
 */
#import "A5StockApps.h"
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

@interface NSObject(A5StockAppSPI)
+ (id)defaultWorkspace;
+ (id)applicationProxyForIdentifier:(NSString*)identifier;
+ (id)containerWithIdentifier:(NSString*)identifier createIfNecessary:(BOOL)create existed:(BOOL*)existed error:(NSError**)error;
- (BOOL)registerApplication:(NSURL*)url;
- (BOOL)registerApplicationDictionary:(NSDictionary*)dictionary;
- (id)appState;
- (BOOL)isValid;
- (NSURL*)bundleURL;
- (NSURL*)url;
@end
static const struct {const char *bundle,*identifier,*executable,*infoSHA,*codeSHA;} selected[]={
 {"Preferences.app","com.apple.Preferences","Preferences","3f96ed0b7644825cbe21543727312ce82d3237d1eb30467152c1edd7b217d71b","b59b3d088da681224777adbd88f8102f6ef1d8c1ef5a5c27d9a44fe0cd7907cc"},
 {"MobileTimer.app","com.apple.mobiletimer","MobileTimer","002918f6ecc7f4f7d370ff61486adcc1ac018c5874fadc9d47bbc5453dac36a8","876148f5db65ce8df7e4b7251fba51a7fa37b0cc3cbcefd08eeaf454074bef98"},
 {"MobileSafari.app","com.apple.mobilesafari","MobileSafari","559dbc066cee0e08f40d2c5d0bd3f4b1761d070723e94004f04388a67b7a05dc","d647374621c73fd37f8989e846cf4522a52d66a156338e9cd9643f6e957774cd"}};
static Class runtimeClass(NSString *name){
#ifdef A5_STOCK_APPS_HOST_TEST
 extern Class A5StockAppsTestClass(NSString *);
 return A5StockAppsTestClass(name);
#else
 return NSClassFromString(name);
#endif
}
static NSString *physicalPath(NSString *logical){
#ifdef A5_STOCK_APPS_HOST_TEST
 return [@A5_STOCK_APPS_TEST_ROOT stringByAppendingString:logical];
#else
 return logical;
#endif
}
static NSData *regularFile(NSString *logical,NSUInteger bound){
 int fd=open(physicalPath(logical).fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
 if(fd<0)return nil;struct stat before,after;
 if(fstat(fd,&before)||!S_ISREG(before.st_mode)||before.st_size<=0||
    (uint64_t)before.st_size>bound){close(fd);return nil;}
 NSMutableData *bytes=[NSMutableData dataWithLength:(NSUInteger)before.st_size];
 uint8_t *p=bytes.mutableBytes;size_t left=bytes.length;
 while(left){ssize_t n=read(fd,p,left);if(n<0&&errno==EINTR)continue;
  if(n<=0){close(fd);return nil;}p+=n;left-=n;}
 uint8_t extra;BOOL stable=!fstat(fd,&after)&&before.st_dev==after.st_dev&&
  before.st_ino==after.st_ino&&before.st_size==after.st_size&&
  before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&
  before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec&&read(fd,&extra,1)==0;
 close(fd);return stable?bytes:nil;
}
/* The restored 20H392 bundles are fixed inputs. Bind privilege-bearing
 * metadata to their independently verified originals, including Clock's
 * mobile-owned executable. An altered binary cannot supply new group rights. */
static BOOL originalBytes(NSData *data,const char *expected){
 if(!data)return NO;unsigned char digest[CC_SHA256_DIGEST_LENGTH];
 CC_SHA256(data.bytes,(CC_LONG)data.length,digest);char hex[65];
 for(unsigned i=0;i<sizeof(digest);i++)snprintf(hex+2*i,3,"%02x",digest[i]);
 return !strcmp(hex,expected);
}
static uint32_t le32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint32_t be32(const uint8_t *p){return (uint32_t)p[3]|(uint32_t)p[2]<<8|(uint32_t)p[1]<<16|(uint32_t)p[0]<<24;}
static NSDictionary *entitlements(NSData *data,NSString *identifier){
 const uint8_t*b=data.bytes;NSUInteger size=data.length;
 if(size<32||le32(b)!=0xfeedfacf||le32(b+4)!=0x0100000c)return nil;
 unsigned count=le32(b+16),commands=le32(b+20);if(count>4096||commands>size-32)return nil;
 NSUInteger end=32+commands,pos=32;const uint8_t*signature=NULL;unsigned length=0;
 for(unsigned i=0;i<count;i++){
  if(pos>end||end-pos<8)return nil;unsigned cmd=le32(b+pos),n=le32(b+pos+4);
  if(n<8||n>end-pos)return nil;
  if(cmd==0x1d){if(signature||n!=16)return nil;unsigned off=le32(b+pos+8);length=le32(b+pos+12);
   if(off>end&&off<=size&&length<=size-off)signature=b+off;else return nil;}
  pos+=n;
 }
 if(pos!=end||!signature||length<12||be32(signature)!=0xfade0cc0)return nil;
 unsigned total=be32(signature+4),slots=be32(signature+8);
 if(total>length||total<12||slots>(total-12)/8||slots>64)return nil;
 NSDictionary*result=nil;
 for(unsigned i=0;i<slots;i++)if(be32(signature+12+8*i)==5){
  unsigned off=be32(signature+16+8*i);if(result||off<12+8*slots||off>total||total-off<8)return nil;
  unsigned n=be32(signature+off+4);if(be32(signature+off)!=0xfade7171||n<8||n>total-off||n>65536)return nil;
  id object=[NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:signature+off+8 length:n-8] options:NSPropertyListImmutable format:NULL error:NULL];
  if(![object isKindOfClass:NSDictionary.class])return nil;result=object;
 }
 return [result[@"application-identifier"]isEqual:identifier]?result:nil;
}
static BOOL validProxy(Class proxy,NSString *identifier,NSString *path){
 id app=[proxy applicationProxyForIdentifier:identifier];id state=[app respondsToSelector:@selector(appState)]?[app appState]:nil;
 return [state respondsToSelector:@selector(isValid)]&&[state isValid]&&
  [app respondsToSelector:@selector(bundleURL)]&&[[app bundleURL].path.stringByStandardizingPath isEqual:path];
}
static NSURL *containerURL(Class kind,NSString *identifier){
 NSError*error=nil;id container=[kind containerWithIdentifier:identifier createIfNecessary:YES existed:NULL error:&error];
 NSURL*url=[container respondsToSelector:@selector(url)]?[container url]:nil;
 if(!url.isFileURL||!url.path.length){fprintf(stderr,"A5XELTE Apps: container unavailable id=%s error=%ld\n",identifier.UTF8String,(long)error.code);return nil;}
 return url;
}
static NSDictionary *registration(NSString *path,NSDictionary *info,NSDictionary *rights,Class appClass,Class sharedClass,Class systemClass){
 NSString*identifier=info[@"CFBundleIdentifier"],*containerID=identifier;
 id required=rights[@"com.apple.private.security.container-required"];
 BOOL contained=![rights[@"com.apple.private.security.no-container"]boolValue];
 if([required isKindOfClass:NSNumber.class])contained=[required boolValue];
 else if([required isKindOfClass:NSString.class]&&[required length])containerID=required;
 NSURL*data=contained?containerURL(appClass,containerID):nil;if(contained&&!data)return nil;
 NSMutableDictionary*record=[@{@"ApplicationType":@"System",@"CFBundleIdentifier":identifier,
  @"CodeInfoIdentifier":identifier,@"Path":path,@"BundleNameIsLocalized":@YES,
  @"CompatibilityState":@0,@"IsContainerized":@(contained),@"IsDeletable":@NO,
  @"Entitlements":rights,@"LSInstallType":@1}mutableCopy];
 if(data)record[@"Container"]=data.path;
 NSString*home=data?data.path:@"/var/mobile";
 record[@"EnvironmentVariables"]=@{@"CFFIXED_USER_HOME":home,@"HOME":home,
  @"TMPDIR":data?[home stringByAppendingPathComponent:@"tmp"]:@"/var/tmp"};
 NSString*team=rights[@"com.apple.developer.team-identifier"];
 if([team isKindOfClass:NSString.class])record[@"TeamIdentifier"]=team;
 NSMutableDictionary*groups=[NSMutableDictionary new];
 for(NSString*key in @[@"com.apple.security.application-groups",@"com.apple.security.system-groups"]){
  id ids=rights[key];if(!ids)continue;if(![ids isKindOfClass:NSArray.class]||[ids count]>32)return nil;
  for(id group in ids){
   if(![group isKindOfClass:NSString.class]||![group length]||[group length]>255||[group containsString:@"/"])return nil;
   NSURL*url=containerURL([key isEqual:@"com.apple.security.system-groups"]?systemClass:sharedClass,group);if(!url)return nil;
   groups[group]=url.path;
  }
  if([ids count])record[[key isEqual:@"com.apple.security.system-groups"]?@"HasSystemGroupContainers":@"HasAppGroupContainers"]=@YES;
 }
 if(groups.count)record[@"GroupContainers"]=groups;
 return record;
}
int A5RegisterSelectedStockApps(void){@autoreleasepool{
#ifndef A5_STOCK_APPS_HOST_TEST
 if(geteuid()!=0){fprintf(stderr,"A5XELTE Apps: registration requires system helper\n");return 1;}
 dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_NOW);
 dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager",RTLD_NOW);
#endif
 Class workspaceClass=runtimeClass(@"LSApplicationWorkspace"),proxy=runtimeClass(@"LSApplicationProxy");
 Class app=runtimeClass(@"MCMAppDataContainer"),shared=runtimeClass(@"MCMSharedDataContainer"),system=runtimeClass(@"MCMSystemDataContainer");
 id workspace=[workspaceClass respondsToSelector:@selector(defaultWorkspace)]?[workspaceClass defaultWorkspace]:nil;
 if(!workspace||![proxy respondsToSelector:@selector(applicationProxyForIdentifier:)]||
    ![workspace respondsToSelector:@selector(registerApplicationDictionary:)]||
    ![app respondsToSelector:@selector(containerWithIdentifier:createIfNecessary:existed:error:)]||
    ![shared respondsToSelector:@selector(containerWithIdentifier:createIfNecessary:existed:error:)]||
    ![system respondsToSelector:@selector(containerWithIdentifier:createIfNecessary:existed:error:)]){
  fprintf(stderr,"A5XELTE Apps: registration API unavailable\n");return 2;
 }
 BOOL done[3]={0},called[3]={0};
#ifdef A5_STOCK_APPS_HOST_TEST
 const unsigned attempts=2;
#else
 const unsigned attempts=24;
#endif
 for(unsigned attempt=0;attempt<attempts;attempt++){
  unsigned complete=0;
  for(unsigned i=0;i<3;i++){
   if(done[i]){complete++;continue;}
   NSString*path=[@"/Applications" stringByAppendingPathComponent:@(selected[i].bundle)],*identifier=@(selected[i].identifier);
   @try{
    BOOL before=validProxy(proxy,identifier,path);
    if(called[i]&&before){done[i]=YES;complete++;fprintf(stderr,"A5XELTE Apps: VERIFIED id=%s\n",selected[i].identifier);continue;}
    if(!called[i]){
     NSData*plist=regularFile([path stringByAppendingPathComponent:@"Info.plist"],1024*1024);
     id info=originalBytes(plist,selected[i].infoSHA)?[NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:NULL]:nil;
     if(![info isKindOfClass:NSDictionary.class]||![info[@"CFBundleIdentifier"]isEqual:identifier]||
        ![info[@"CFBundleExecutable"]isEqual:@(selected[i].executable)]){
      fprintf(stderr,"A5XELTE Apps: bundle manifest invalid id=%s\n",selected[i].identifier);continue;
     }
     NSData*code=regularFile([path stringByAppendingPathComponent:@(selected[i].executable)],8*1024*1024);
     NSDictionary*rights=originalBytes(code,selected[i].codeSHA)?entitlements(code,identifier):nil;
     if(!rights){fprintf(stderr,"A5XELTE Apps: signed entitlements unavailable id=%s\n",selected[i].identifier);continue;}
     NSDictionary*record=registration(path,info,rights,app,shared,system);if(!record)continue;
     BOOL accepted=[workspace registerApplicationDictionary:record];called[i]=accepted;
     BOOL after=validProxy(proxy,identifier,path);
     fprintf(stderr,"A5XELTE Apps: REGISTER id=%s attempt=%u before=%u accepted=%u after=%u\n",selected[i].identifier,attempt+1,before,accepted,after);
     if(accepted&&after){done[i]=YES;complete++;}
    }
   }@catch(NSException*exception){fprintf(stderr,"A5XELTE Apps: registration exception id=%s name=%s\n",selected[i].identifier,exception.name.UTF8String);}
  }
  if(complete==3){fprintf(stderr,"A5XELTE Apps: VERIFIED selected=3\n");return 0;}
#ifndef A5_STOCK_APPS_HOST_TEST
  if(attempt+1<attempts)sleep(5);
#endif
 }
 fprintf(stderr,"A5XELTE Apps: registration incomplete verified=%u/3\n",done[0]+done[1]+done[2]);return 3;
}}
