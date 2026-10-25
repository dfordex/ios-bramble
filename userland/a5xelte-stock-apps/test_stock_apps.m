/* SPDX-License-Identifier: MIT
 * Actual stock manifests and code-signature parsing; fake SPI only, so no host
 * LaunchServices/container writes are possible in this executable.
 */
#define A5_STOCK_APPS_HOST_TEST 1
#import "A5StockApps.m"
#include <assert.h>
static NSString*mode;
static NSMutableDictionary*records;
static NSMutableDictionary*calls;
static unsigned containerCalls;
@interface TestContainer:NSObject
@property NSURL*url;
@end
@implementation TestContainer
+ (id)containerWithIdentifier:(NSString*)identifier createIfNecessary:(BOOL)create existed:(BOOL*)existed error:(NSError**)error{
 assert(create&&!existed);containerCalls++;
 if([mode isEqual:@"container-failure"]){if(error)*error=[NSError errorWithDomain:@"test" code:13 userInfo:nil];return nil;}
 TestContainer*r=[TestContainer new];r.url=[NSURL fileURLWithPath:[@"/private/var/mobile/Containers/Test" stringByAppendingPathComponent:identifier]];return r;
}
@end
@interface TestState:NSObject
@property BOOL isValid;
@end
@implementation TestState @end
@interface TestProxy:NSObject
@property NSURL*bundleURL;
@property TestState*appState;
@end
@implementation TestProxy
+ (id)applicationProxyForIdentifier:(NSString*)identifier{
 assert(([@[@"com.apple.Preferences",@"com.apple.mobiletimer",@"com.apple.mobilesafari"] containsObject:identifier]));
 NSDictionary*r=records[identifier];TestProxy*p=[TestProxy new];p.appState=[TestState new];
 p.appState.isValid=r&&![mode isEqual:@"invalid-state"];
 p.bundleURL=r?[NSURL fileURLWithPath:[mode isEqual:@"wrong-path"]?@"/Applications/Unrelated.app":r[@"Path"]]:nil;
 return p;
}
@end
@interface TestWorkspace:NSObject @end
@implementation TestWorkspace
+ (id)defaultWorkspace{return [mode isEqual:@"api-unavailable"]?nil:[TestWorkspace new];}
- (BOOL)registerApplicationDictionary:(NSDictionary*)d{
 NSString*identifier=d[@"CFBundleIdentifier"];calls[identifier]=@([calls[identifier]unsignedIntValue]+1);
 assert([d[@"ApplicationType"]isEqual:@"System"]&&[d[@"CodeInfoIdentifier"]isEqual:identifier]);
 assert([d[@"Entitlements"][@"application-identifier"]isEqual:identifier]);
 assert([d[@"IsContainerized"]boolValue]&&[d[@"Container"]length]);
 assert([d[@"EnvironmentVariables"][@"HOME"]isEqual:d[@"Container"]]);
 assert(!d[@"SignerIdentity"]&&!d[@"IsAdHocSigned"]); /* never invent signatures */
 if([identifier isEqual:@"com.apple.Preferences"]){assert([d[@"GroupContainers"]count]==11);assert([d[@"HasSystemGroupContainers"]boolValue]&&[d[@"HasAppGroupContainers"]boolValue]);}
 if([identifier isEqual:@"com.apple.mobiletimer"]){assert(!d[@"GroupContainers"]);}
 if([identifier isEqual:@"com.apple.mobilesafari"]){assert([d[@"GroupContainers"]count]==1&&[d[@"HasSystemGroupContainers"]boolValue]);}
 if([mode isEqual:@"register-failure"])return NO;
 if([mode isEqual:@"retry"]&&[identifier isEqual:@"com.apple.mobilesafari"]&&[calls[identifier]unsignedIntValue]==1)return NO;
 records[identifier]=d;return YES;
}
@end
Class A5StockAppsTestClass(NSString*name){
 if([name isEqual:@"LSApplicationWorkspace"])return TestWorkspace.class;
 if([name isEqual:@"LSApplicationProxy"])return TestProxy.class;
 if([@[@"MCMAppDataContainer",@"MCMSharedDataContainer",@"MCMSystemDataContainer"]containsObject:name])return TestContainer.class;
 abort();
}
static void parserGuards(void){
 NSString*path=@"/Applications/Preferences.app/Preferences";
 NSData*actual=regularFile(path,8*1024*1024);assert(actual&&entitlements(actual,@"com.apple.Preferences"));
 assert(originalBytes(actual,selected[0].codeSHA));
 NSMutableData*tampered=[actual mutableCopy];((uint8_t*)tampered.mutableBytes)[4096]^=1;
 assert(entitlements(tampered,@"com.apple.Preferences")&&!originalBytes(tampered,selected[0].codeSHA));
 assert(!entitlements(actual,@"com.apple.mobilesafari"));
 for(unsigned n=0;n<33;n++)assert(!entitlements([actual subdataWithRange:NSMakeRange(0,n)],@"com.apple.Preferences"));
 for(unsigned off=0;off<24;off+=4){NSMutableData*bad=[actual mutableCopy];memset((uint8_t*)bad.mutableBytes+off,0xff,4);
  if(off==0||off==4||off==16||off==20)assert(!entitlements(bad,@"com.apple.Preferences"));}
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);mode=@(argv[1]);records=[NSMutableDictionary new];calls=[NSMutableDictionary new];parserGuards();
 if([mode isEqual:@"existing"])
  for(unsigned i=0;i<3;i++)records[@(selected[i].identifier)]=@{@"Path":[@"/Applications" stringByAppendingPathComponent:@(selected[i].bundle)]};
 int result=A5RegisterSelectedStockApps();
 if([mode isEqual:@"happy"]||[mode isEqual:@"retry"]){assert(result==0&&records.count==3&&calls.count==3&&containerCalls>=15);for(NSString*k in calls)assert([calls[k]unsignedIntValue]<=2);}
 else if([mode isEqual:@"existing"]){assert(result==0&&records.count==3&&!calls.count&&!containerCalls);}
 else if([mode isEqual:@"api-unavailable"]){assert(result==2&&!calls.count&&!records.count);}
 else{assert(result==3);if([mode isEqual:@"container-failure"])assert(!calls.count);if([mode isEqual:@"register-failure"])assert(!records.count);}
 printf("stock app registration %s PASS (real Apple inputs, fake SPI; no host database writes)\n",argv[1]);
}return 0;}
