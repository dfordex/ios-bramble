/* SPDX-License-Identifier: MIT */
#define A5_MALI_RUNTIME_AUDIT_LIBRARY 1
#include "A5ProtocolRuntimeAudit.m"
#include <assert.h>

static void unusedImplementation(id object, SEL selector)
{ (void)object; (void)selector; }

static unsigned runCase(const char *name, const char *expected,
                        const char *actual, BOOL addMethod)
{
    Protocol *protocol=objc_allocateProtocol(name);
    assert(protocol);
    SEL selector=sel_registerName("capabilities");
    protocol_addMethodDescription(protocol,selector,expected,YES,YES);
    objc_registerProtocol(protocol);
    Class cls=objc_allocateClassPair([NSObject class],name,0);
    assert(cls);
    if (addMethod)
        assert(class_addMethod(cls,selector,(IMP)unusedImplementation,actual));
    objc_registerClassPair(cls);
    unsigned checked=0;
    unsigned errors=checkProtocol(cls,protocol,&checked);
    assert(checked==1);
    return errors;
}

int main(void)
{
    @autoreleasepool {
        const char *bits="{IndirectArgumentBufferCapabilities=b1b1b1b29}16@0:8";
        assert(runCase("A5AuditIdenticalBitfield",bits,bits,YES)==0);
        assert(runCase("A5AuditDifferentReturn","Q16@0:8","I16@0:8",YES)==1);
        assert(runCase("A5AuditDifferentArgs","v24@0:8Q16","v24@0:8I16",YES)==1);
        assert(runCase("A5AuditMissing","v16@0:8",NULL,NO)==1);
        assert(sameType("{IndirectArgumentBufferCapabilities=b1b1b1b29}",
                        "{IndirectArgumentBufferCapabilities=b1b1b1b29}"));
        assert(!sameType("Q","I"));
        assert(!sameType("@","Q"));
        puts("runtime audit: identical bitfield accepted; width/argument/missing-method regressions rejected PASS");
    }
    return 0;
}
