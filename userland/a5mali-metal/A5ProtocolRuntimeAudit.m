/* SPDX-License-Identifier: MIT */
/* Compile and run inside the target iOS process/OS after loading the plugin.
 * No protocol conformance is asserted.  This observes selector availability
 * and the actual Objective-C calling shape of the loaded class hierarchy.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *className, *protocolName; } Target;
static const Target targets[] = {
    {"A5MaliMetalDevice", "MTLDeviceSPI"},
    {"A5MaliMetalBuffer", "MTLCommandBuffer"},
    {"A5MaliMetalRenderEncoder", "MTLCommandEncoderSPI"},
    {"A5MaliMetalBlitEncoder", "MTLCommandEncoderSPI"},
    {"A5MaliMetalTexture", "MTLTextureSPI"},
    {"A5MaliPrivateBuffer", "MTLResourceSPI"},
    {"A5MaliSharedReadBuffer", "MTLResourceSPI"},
    {"A5MaliPrivateBuffer", "MTLBuffer"},
    {"A5MaliSharedReadBuffer", "MTLBuffer"},
    {"A5MaliMetalLibrary", "MTLLibrarySPI"},
    {"A5MaliMetalFunction", "MTLFunctionSPI"},
    {"A5MaliCompiledPipeline", "MTLRenderPipelineState"},
    {"A5MaliSamplerState", "MTLSamplerStateSPI"},
    {"A5MaliDepthStencilState", "MTLDepthStencilStateSPI"},
};

static char typeClass(const char *type)
{
    while (*type && strchr("rnNoORV", *type)) ++type; /* ObjC qualifiers */
    if (*type == '@') return 'o';
    if (*type == '^' || *type == '*' || *type == ':' || *type == '#') return 'p';
    if (strchr("cCsSiIlLqQB", *type)) return 'i';
    if (strchr("fdD", *type)) return 'f';
    if (strchr("{([", *type)) return 'a';
    if (*type == 'v') return 'v';
    return '?';
}

static BOOL sameType(const char *want, const char *got)
{
    /* Foundation cannot size every valid ObjC bitfield aggregate encoding.
     * Exact encodings already prove equal calling types without that parser. */
    if (strcmp(want,got)==0) return YES;
    char wc=typeClass(want), gc=typeClass(got);
    if (wc=='?' || gc=='?' || wc!=gc) return NO;
    if (wc=='v') return YES;
    NSUInteger ws=0, wa=0, gs=0, ga=0;
    @try {
        NSGetSizeAndAlignment(want,&ws,&wa);
        NSGetSizeAndAlignment(got,&gs,&ga);
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
    return ws==gs && wa==ga;
}

static unsigned checkProtocol(Class cls, Protocol *proto, unsigned *checked)
{
    unsigned errors=0, count=0;
    struct objc_method_description *methods=protocol_copyMethodDescriptionList(proto,YES,YES,&count);
    for (unsigned i=0; i<count; ++i) {
        const char *name=sel_getName(methods[i].name);
        Method implementation=class_getInstanceMethod(cls,methods[i].name);
        ++*checked;
        if (!implementation) {
            fprintf(stderr,"MISSING %s %s\n",class_getName(cls),name);
            ++errors; continue;
        }
        const char *actual=method_getTypeEncoding(implementation);
        if (!methods[i].types || !actual) {
            fprintf(stderr,"NO_ENCODING %s %s\n",class_getName(cls),name);
            ++errors; continue;
        }
        /* Compare the full encoding before NSMethodSignature. On iOS 16 its
         * parser rejects the inherited IndirectArgumentBufferCapabilities
         * bitfield return even when both encodings are byte-identical. */
        if (strcmp(methods[i].types,actual)==0) continue;
        @try {
            NSMethodSignature *w=[NSMethodSignature signatureWithObjCTypes:methods[i].types];
            NSMethodSignature *g=[NSMethodSignature signatureWithObjCTypes:actual];
            if (!w || !g || w.numberOfArguments!=g.numberOfArguments ||
                !sameType(w.methodReturnType,g.methodReturnType)) {
                fprintf(stderr,"RETURN_ABI %s %s expected=%s actual=%s\n",
                    class_getName(cls),name,methods[i].types,actual);
                ++errors; continue;
            }
            for (NSUInteger arg=0; arg<w.numberOfArguments; ++arg) {
                if (!sameType([w getArgumentTypeAtIndex:arg],[g getArgumentTypeAtIndex:arg])) {
                    fprintf(stderr,"ARG_ABI %s %s arg=%lu expected=%s actual=%s\n",
                        class_getName(cls),name,(unsigned long)arg,methods[i].types,actual);
                    ++errors; break;
                }
            }
        } @catch (NSException *exception) {
            fprintf(stderr,"UNPARSEABLE_ABI %s %s: %s\n",class_getName(cls),name,
                exception.reason.UTF8String);
            ++errors;
        }
    }
    free(methods);
    unsigned parentCount=0;
    Protocol *__unsafe_unretained *parents=protocol_copyProtocolList(proto,&parentCount);
    for (unsigned i=0;i<parentCount;++i)
        if (strcmp(protocol_getName(parents[i]),"NSObject"))
            errors+=checkProtocol(cls,parents[i],checked);
    free(parents);
    return errors;
}

BOOL A5MaliAuditRuntimeMetalSurface(void)
{
    @autoreleasepool {
        unsigned totalErrors=0, totalChecked=0;
        for (size_t i=0;i<sizeof(targets)/sizeof(targets[0]);++i) {
            Class cls=objc_getClass(targets[i].className);
            Protocol *proto=objc_getProtocol(targets[i].protocolName);
            if (!cls || !proto) {
                fprintf(stderr,"UNAVAILABLE %s %s\n",targets[i].className,targets[i].protocolName);
                ++totalErrors; continue;
            }
            unsigned checked=0, errors=checkProtocol(cls,proto,&checked);
            totalChecked+=checked;
            totalErrors+=errors;
        }
        fprintf(stderr,"A5XELTE Metal ABI audit: classes=%zu methods=%u errors=%u\n",
            sizeof(targets)/sizeof(targets[0]),totalChecked,totalErrors);
        return totalErrors==0;
    }
}

#ifndef A5_MALI_RUNTIME_AUDIT_LIBRARY
int main(int argc,const char **argv)
{
    @autoreleasepool {
        if (argc>2) { fprintf(stderr,"usage: %s [plugin-bundle-path]\n",argv[0]); return 2; }
        if (argc==2) {
            NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
            NSError *error=nil;
            if (![bundle loadAndReturnError:&error]) {
                fprintf(stderr,"BUNDLE_LOAD %s\n",error.description.UTF8String); return 2;
            }
        }
        return A5MaliAuditRuntimeMetalSurface()?0:1;
    }
}
#endif
