/* SPDX-License-Identifier: MIT
 * Genuine private stage publication through synchronous Metal specialization.
 * Saturation must wait, retry the same request and consume actual compiled code.
 * No worker, GPU execution or persistent system path is involved. */
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliMetalDeviceResources.h"
#import "A5MaliShaderCompileRequest.h"
#include <assert.h>
#include <stdatomic.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef A5_SHADER_REQUEST_TEST_ROOT
#error private test root required
#endif
#ifndef A5_DYNAMIC_SHADER_CACHE_TEST_ROOT
#error private publication root required
#endif
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
static kern_return_t wire(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*b)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)b;assert(!"factory must not submit GPU work");return kIOReturnError;}
static MTLFunctionConstantValues *values(NSDictionary*p){
 MTLFunctionConstantValues*v=[MTLFunctionConstantValues new];
 for(NSDictionary*r in p[@"named_constants"]){
  NSString*hex=r[@"raw"];NSMutableData*bytes=[NSMutableData dataWithLength:[r[@"bytes"] unsignedIntegerValue]];
  assert(hex.length==bytes.length*2);
  for(NSUInteger j=0;j<bytes.length;j++){unsigned value=0;assert(sscanf([hex substringWithRange:NSMakeRange(j*2,2)].UTF8String,"%02x",&value)==1);((uint8_t*)bytes.mutableBytes)[j]=(uint8_t)value;}
  [v setConstantValue:bytes.bytes type:[r[@"type"] unsignedIntegerValue] withName:r[@"name"]];
 }
 assert(![p[@"indexed_constants"] count]);return v;
}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==4);NSFileManager*fm=NSFileManager.defaultManager;NSError*error=nil;
 NSMutableDictionary*p=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:NSJSONReadingMutableContainers error:&error];assert(p&&!error);
 NSString*key=p[@"request_id"];[p removeObjectsForKeys:@[@"owner_uid",@"request_id"]];
 assert([A5MaliShaderCompileRequestID(p,&error)isEqual:key]&&!error);
 NSString*root=@A5_SHADER_REQUEST_TEST_ROOT,*cache=@A5_DYNAMIC_SHADER_CACHE_TEST_ROOT;
 assert([root hasPrefix:@"/private/tmp/"]&&[cache hasPrefix:@"/private/tmp/"]);
 assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]&&!error);
 assert(!chmod(root.fileSystemRepresentation,01777));
 NSString*owner=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",geteuid()]];
 assert([fm createDirectoryAtPath:owner withIntermediateDirectories:YES attributes:nil error:&error]&&!error);assert(!chmod(owner.fileSystemRepresentation,0700));
 assert([fm createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:&error]&&!error);
 for(unsigned i=0;i<64;i++)assert(([NSData.data writeToFile:[owner stringByAppendingPathComponent:[NSString stringWithFormat:@"old-%u.request.json",i]] atomically:NO]));
 unsigned context=0;A5MaliRestrictedDevice*d=[[A5MaliRestrictedDevice alloc]initWithTransport:wire context:&context commandCapabilities:63 operationCapabilities:0x7ffff];
 A5MaliMetalLibrary*l=[d newLibraryWithURL:[NSURL fileURLWithPath:@(argv[3])] error:&error];assert(l&&!error);
 dispatch_semaphore_t done=dispatch_semaphore_create(0);atomic_bool returned=false;atomic_bool*returnedPtr=&returned;
 MTLFunctionConstantValues*c=values(p);__block A5MaliMetalFunction*f=nil;__block NSError*failure=nil;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  f=[l newFunctionWithName:p[@"function"] constantValues:c error:&failure];
  atomic_store(returnedPtr,true);dispatch_semaphore_signal(done);
 }});
 usleep(300000);assert(!atomic_load(&returned)); /* quota cannot become nil specialization */
 assert([fm contentsOfDirectoryAtPath:owner error:NULL].count==65); /* lock +64 */
 assert([fm removeItemAtPath:[owner stringByAppendingPathComponent:@"old-0.request.json"] error:&error]&&!error);
 NSString*request=[owner stringByAppendingPathComponent:[key stringByAppendingString:@".request.json"]];
 unsigned poll=0;while(![fm fileExistsAtPath:request]&&poll++<500)usleep(10000);
 assert([fm fileExistsAtPath:request]&&!atomic_load(&returned));
 /* Publish unchanged, authenticated native program; this cannot be replaced
  * by a success placeholder while the actual stage is unavailable. */
 assert([fm copyItemAtPath:@(argv[2]) toPath:[cache stringByAppendingPathComponent:key] error:&error]&&!error);
 assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)));
 assert(f&&!failure&&f.dynamicShader&&[f.dynamicShader.requestID isEqual:key]);
 /* An executable pipeline has a pure identity, but no compile-spool side effect. */
 for(NSString*n in [fm contentsOfDirectoryAtPath:owner error:NULL])if(![n hasPrefix:@"."])assert([fm removeItemAtPath:[owner stringByAppendingPathComponent:n] error:&error]&&!error);
 const A5MaliCompiledProfile*profile=A5MaliCompiledProfileForID(603);assert(profile);
 size_t count=0;const A5MaliCompiledFunctionConstant*vc=A5MaliCompiledVertexConstantsForProfile(603,&count);
 MTLFunctionConstantValues*v=[MTLFunctionConstantValues new];for(size_t i=0;i<count;i++)[v setConstantValue:vc[i].raw type:vc[i].dataType withName:@(vc[i].name)];
 MTLRenderPipelineDescriptor*desc=[MTLRenderPipelineDescriptor new];
 desc.vertexFunction=(id)[l newFunctionWithName:@(profile->vertexName) constantValues:v error:&error];desc.fragmentFunction=(id)f;
 desc.colorAttachments[0].pixelFormat=80;desc.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<profile->attributeCount;i++){const A5MaliCompiledVertexAttribute*a=profile->attributes+i;desc.vertexDescriptor.attributes[a->index].format=a->format;desc.vertexDescriptor.attributes[a->index].offset=a->offset;desc.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 desc.vertexDescriptor.layouts[1].stride=48;desc.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;desc.vertexDescriptor.layouts[1].stepRate=1;
 assert([d newRenderPipelineStateWithDescriptor:desc error:&error]&&!error);
 assert([fm contentsOfDirectoryAtPath:owner error:NULL].count==1); /* only lock */
 puts("PASS real Metal function: saturated64 waits, exact retry publishes, genuine stage consumed; executable pipeline adds no request (host only)");
}return 0;}
