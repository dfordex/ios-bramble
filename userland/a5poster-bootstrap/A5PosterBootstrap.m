/* SPDX-License-Identifier: MIT
 * Repair the empty lazy configuration created before initial extension load.
 * Runs only in this lab port's PosterBoard; stock first-time setup still runs.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#include <string.h>

static Ivar configIvar, loadedIvar, selectedIvar;
static void (*stockSetup)(id,SEL);
static BOOL installing;
static BOOL objectGetter(id object,const char *name,id *value)
{
    SEL selector=sel_registerName(name);
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    if(!signature || signature.numberOfArguments!=2 || signature.methodReturnType[0]!='@')return NO;
    *value=((id(*)(id,SEL))objc_msgSend)(object,selector);return YES;
}
static BOOL emptyCollection(id value)
{
    if(!value)return YES;
    if(![value isKindOfClass:NSArray.class] && ![value isKindOfClass:NSDictionary.class] && ![value isKindOfClass:NSSet.class] &&
       ![value isKindOfClass:NSOrderedSet.class])return NO;
    return [value count]==0;
}
static BOOL resetEmptyBootstrap(id store)
{
    const unsigned char *bytes=(const unsigned char *)(__bridge const void *)store;
    if(bytes[ivar_getOffset(loadedIvar)])return NO;
    id old=object_getIvar(store,configIvar);
    if(!old || object_getIvar(store,selectedIvar))return NO;
    Class configuration=objc_getClass("PRSwitcherConfiguration");
    if(!configuration || object_getClass(old)!=configuration)return NO;
    id configurations=nil,selected=nil,active=nil,held=nil;
    if(!objectGetter(old,"configurations",&configurations) ||
       !objectGetter(old,"selectedConfiguration",&selected) ||
       !objectGetter(old,"activeConfiguration",&active) ||
       !objectGetter(old,"heldAssociatedConfigurations",&held) ||
       selected || active || !emptyCollection(configurations) || !emptyCollection(held))return NO;
    /* The original getter builds this empty object before extensions arrive.
     * Do not mark initialExtensionsLoaded or skip default/legacy setup.
     * Caller already holds the stock state lock. This is a strong ARC slot. */
    object_setIvarWithStrongDefault(store,configIvar,nil);
    fprintf(stderr,"A5XELTE Poster bootstrap: reset empty pre-extension configuration; stock setup follows\n");
    return YES;
}
static void setup(id store,SEL command)
{
    const unsigned char *bytes=(const unsigned char *)(__bridge const void *)store;
    fprintf(stderr,"A5XELTE Poster bootstrap: setup initial_loaded=%u configuration=%u store_selected=%u\n",
        bytes[ivar_getOffset(loadedIvar)]!=0,object_getIvar(store,configIvar)!=nil,object_getIvar(store,selectedIvar)!=nil);
    BOOL repaired=resetEmptyBootstrap(store);
    stockSetup(store,command);
    if(repaired)fprintf(stderr,"A5XELTE Poster bootstrap: stock setup returned configuration=%u\n",
                       object_getIvar(store,configIvar)!=nil);
}
static BOOL installForIdentity(NSString *identifier,NSString *path)
{
    if(![identifier isEqualToString:@"com.apple.PosterBoard"] ||
       ![path isEqualToString:@"/Applications/PosterBoard.app"])return NO;
    if(installing)return YES;
    Class c=objc_getClass("PBFPosterExtensionDataStore");
    Method method=class_getInstanceMethod(c,sel_registerName("_stateLock_setupSwitcherConfigurationForFirstTime"));
    Ivar config=class_getInstanceVariable(c,"_stateLock_switcherConfiguration");
    Ivar loaded=class_getInstanceVariable(c,"_stateLock_initialExtensionsLoaded");
    Ivar selected=class_getInstanceVariable(c,"_stateLock_selectedConfiguration");
    if(!c || !method || !config || !loaded || !selected || method_getNumberOfArguments(method)!=2 ||
       strcmp(ivar_getTypeEncoding(config),"@\"PRSwitcherConfiguration\"") ||
       strcmp(ivar_getTypeEncoding(loaded),"B") || ivar_getTypeEncoding(selected)[0]!='@')return NO;
    char *ret=method_copyReturnType(method);BOOL valid=ret && !strcmp(ret,"v");free(ret);
    if(!valid)return NO;
#ifndef A5_POSTER_HOST_TEST
    if(ivar_getOffset(config)!=0x98 || ivar_getOffset(loaded)!=0xe9 ||
       ivar_getOffset(selected)!=0x90 || class_getInstanceSize(c)<0xea)return NO;
    const uint32_t *code=(const uint32_t *)method_getImplementation(method);
    /* Exact observed iOS16 getter/check ABI; reject another implementation. */
    if(code[16]!=0xf9404c08 || code[18]!=0x3943a668)return NO;
#endif
    configIvar=config;loadedIvar=loaded;selectedIvar=selected;
    stockSetup=(void(*)(id,SEL))method_setImplementation(method,(IMP)setup);
    installing=YES;
    fprintf(stderr,"A5XELTE Poster bootstrap: installed guarded empty-state repair\n");
    return YES;
}
#ifndef A5_POSTER_HOST_TEST
__attribute__((constructor)) static void initialize(void)
{
    @autoreleasepool {
        NSBundle *bundle=NSBundle.mainBundle;
        if(!installForIdentity(bundle.bundleIdentifier,bundle.bundlePath))
            fprintf(stderr,"A5XELTE Poster bootstrap: inactive (identity or stock ABI mismatch)\n");
    }
}
#endif
