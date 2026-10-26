#import <Foundation/Foundation.h>
#include <assert.h>
@interface PRSwitcherConfiguration:NSObject
@property id configurations,selectedConfiguration,activeConfiguration,heldAssociatedConfigurations;
@end
@implementation PRSwitcherConfiguration
@end
@interface PBFPosterExtensionDataStore:NSObject {
@public PRSwitcherConfiguration *_stateLock_switcherConfiguration;
BOOL _stateLock_initialExtensionsLoaded;
id _stateLock_selectedConfiguration;
}
@property unsigned calls;
@property BOOL originalSawEmptySlot;
- (void)_stateLock_setupSwitcherConfigurationForFirstTime;
@end
@implementation PBFPosterExtensionDataStore
- (void)_stateLock_setupSwitcherConfigurationForFirstTime {
 self.calls++;self.originalSawEmptySlot=(_stateLock_switcherConfiguration==nil);
 if(self.originalSawEmptySlot){_stateLock_switcherConfiguration=[PRSwitcherConfiguration new];
 _stateLock_switcherConfiguration.configurations=@[@"stock default"];
 _stateLock_switcherConfiguration.activeConfiguration=@"stock default";}
}
@end
#define A5_POSTER_HOST_TEST 1
#include "A5PosterBootstrap.m"
static PBFPosterExtensionDataStore *fixture(void){
 PBFPosterExtensionDataStore*s=[PBFPosterExtensionDataStore new];
 s->_stateLock_switcherConfiguration=[PRSwitcherConfiguration new];
 s->_stateLock_switcherConfiguration.configurations=@[];
 s->_stateLock_switcherConfiguration.heldAssociatedConfigurations=[NSSet set];return s;
}
int main(void){@autoreleasepool{
 assert(!installForIdentity(@"com.apple.SpringBoard",@"/Applications/PosterBoard.app"));
 assert(!installForIdentity(@"com.apple.PosterBoard",@"/tmp/PosterBoard.app"));
 assert(installForIdentity(@"com.apple.PosterBoard",@"/Applications/PosterBoard.app"));
 assert(installForIdentity(@"com.apple.PosterBoard",@"/Applications/PosterBoard.app"));
 PBFPosterExtensionDataStore*s=fixture();id old=s->_stateLock_switcherConfiguration;
 [s _stateLock_setupSwitcherConfigurationForFirstTime];
 assert(s.calls==1&&s.originalSawEmptySlot&&s->_stateLock_switcherConfiguration!=old);
 assert([s->_stateLock_switcherConfiguration.configurations count]==1);
 assert(!s->_stateLock_initialExtensionsLoaded); // only the stock caller sets this
 for(unsigned mode=0;mode<7;mode++){
  s=fixture();old=s->_stateLock_switcherConfiguration;
  if(mode==0)s->_stateLock_initialExtensionsLoaded=YES;
  if(mode==1)s->_stateLock_switcherConfiguration.configurations=@[@"keep"];
  if(mode==2)s->_stateLock_switcherConfiguration.activeConfiguration=@"keep";
  if(mode==3)s->_stateLock_switcherConfiguration.selectedConfiguration=@"keep";
  if(mode==4)s->_stateLock_switcherConfiguration.heldAssociatedConfigurations=@[@"keep"];
  if(mode==5)s->_stateLock_selectedConfiguration=@"keep";
  if(mode==6)s->_stateLock_switcherConfiguration.configurations=@"invalid collection";
  [s _stateLock_setupSwitcherConfigurationForFirstTime];
  assert(s.calls==1&&!s.originalSawEmptySlot&&s->_stateLock_switcherConfiguration==old);
 }
 s=[PBFPosterExtensionDataStore new];[s _stateLock_setupSwitcherConfigurationForFirstTime];
 assert(s.calls==1&&s.originalSawEmptySlot&&s->_stateLock_switcherConfiguration);
 puts("PASS actual Poster bootstrap: empty pre-extension state repaired, stock setup executed once; loaded/nonempty/selected/held/unknown states and identity preserved");
}return 0;}
