/* SPDX-License-Identifier: MIT
 * A real stock plain function must consume its actual worker publication.
 * This is provider/cache coverage, not physical GPU execution. */
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliShaderCompileRequest.h"
#include <assert.h>
#include <unistd.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
static kern_return_t wire(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;assert(!"function creation must not submit GPU work");return kIOReturnError;}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3);NSError*error=nil;
 NSMutableDictionary*p=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:NSJSONReadingMutableContainers error:&error];assert(p&&!error);
 NSString*key=p[@"request_id"],*name=p[@"function"];[p removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 assert(![p[@"named_constants"] count]&&![p[@"indexed_constants"] count]);
 assert([A5MaliShaderCompileRequestID(p,&error)isEqual:key]&&!error);
 unsigned context=0;A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&context commandCapabilities:63 operationCapabilities:0x7ffff];
 A5MaliMetalLibrary*l=[d newLibraryWithURL:[NSURL fileURLWithPath:@(argv[2])] error:&error];assert(l&&!error);
 assert(l.functionNames.count==141&&[l.functionNames containsObject:name]&&[l.functionNames containsObject:@"p3_clamp_lph"]);
 /* This entry must not come from the precompiled native registry. */
 size_t n=0;const A5MaliCompiledProfile*profiles=A5MaliCompiledProfiles(&n);
 for(size_t i=0;i<n;i++)assert(![name isEqual:@(profiles[i].fragmentName)]&&![name isEqual:@(profiles[i].vertexName)]);
 A5MaliMetalFunction*f=[l newFunctionWithName:name];
 assert(f&&f.functionType==MTLFunctionTypeFragment&&f.dynamicShader&&[f.dynamicShader.requestID isEqual:key]);
 assert(f.dynamicShader.shader->byteCount>0);
 MTLFunctionDescriptor*desc=[MTLFunctionDescriptor new];desc.name=name;
 A5MaliMetalFunction*g=[l newFunctionWithDescriptor:desc error:&error];
 assert(g&&!error&&[g.dynamicShader.requestID isEqual:key]);
 /* Empty explicit values and a nil constants object identify the same stage. */
 A5MaliMetalFunction*h=[l newFunctionWithName:name constantValues:[MTLFunctionConstantValues new] error:&error];
 assert(h&&!error&&[h.dynamicShader.requestID isEqual:key]);
 assert(![l newFunctionWithName:@"not_an_entry"]);
 assert(![l newFunctionWithName:@"fixed_frag_lph_cph"]); /* required constants retained */
 puts("PASS141 authenticated directory entries; genuine unregistered plain fragment via name/descriptor/empty constants, invalid names and missing required constants reject (host only)");
}return 0;}
