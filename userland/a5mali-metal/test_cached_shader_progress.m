/* SPDX-License-Identifier: MIT
 * Actual authenticated publication/library/factory path while the independent
 * request queue lock is held. Run with a bounded host process timeout. */
#import "A5MaliRestrictedDevice.h"
#import "A5MaliDynamicShaderCache.h"
#import "A5MaliShaderCompileRequest.h"
#include <assert.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>
uid_t A5MaliDynamicShaderCacheTestUID(void){return geteuid();}
static kern_return_t transport(void *c,uint32_t s,const void *i,size_t n,void *o,size_t *z)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)z;return kIOReturnUnsupported;}
static NSDictionary *readJSON(NSString *p){return [NSJSONSerialization JSONObjectWithData:
 [NSData dataWithContentsOfFile:p] options:0 error:NULL];}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==4);NSString *request=@(argv[1]),*stock=@(argv[2]),*spool=@(argv[3]);
 assert([spool hasPrefix:@"/private/tmp/"]);NSFileManager *fm=NSFileManager.defaultManager;
 assert([fm createDirectoryAtPath:spool withIntermediateDirectories:YES attributes:nil error:NULL]);chmod(spool.fileSystemRepresentation,01777);
 NSString *uid=[spool stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",geteuid()]];
 assert([fm createDirectoryAtPath:uid withIntermediateDirectories:YES attributes:nil error:NULL]);chmod(uid.fileSystemRepresentation,0700);
 int lock=open([[uid stringByAppendingPathComponent:@".lock"]fileSystemRepresentation],O_RDWR|O_CREAT,0600);
 assert(lock>=0&&!flock(lock,LOCK_EX|LOCK_NB));
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:transport context:&argc commandCapabilities:63 operationCapabilities:0x7ffff];
 NSError *error=nil;A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:stock] error:&error];assert(library&&!error);
 NSDictionary *r=readJSON(request);MTLFunctionConstantValues *constants=[MTLFunctionConstantValues new];
 for(NSDictionary *c in r[@"named_constants"]){NSString *raw=c[@"raw"];uint8_t data[64];assert(raw.length<=128);
  for(NSUInteger i=0;i<raw.length/2;i++){unsigned value=0;assert(sscanf([raw substringWithRange:NSMakeRange(2*i,2)].UTF8String,"%2x",&value)==1);data[i]=value;}
  [constants setConstantValue:data type:[c[@"type"]unsignedIntegerValue] withName:c[@"name"]];}
 assert([r[@"indexed_constants"]count]==0);
 id<MTLFunction> fragment=(id)[library newFunctionWithName:r[@"function"] constantValues:constants error:&error];assert(fragment&&!error);
 assert([fragment isKindOfClass:A5MaliMetalFunction.class]);
 A5MaliDynamicShaderCacheEntry *stage=[(A5MaliMetalFunction*)fragment dynamicShader];assert(stage&&[stage.requestID isEqual:r[@"request_id"]]);
 size_t count=0;const A5MaliCompiledFunctionConstant *v=A5MaliCompiledVertexConstantsForProfile(603,&count);assert(v&&count);
 MTLFunctionConstantValues *vc=[MTLFunctionConstantValues new];for(size_t i=0;i<count;i++)[vc setConstantValue:v[i].raw type:v[i].dataType withName:@(v[i].name)];
 id<MTLFunction> vertex=(id)[library newFunctionWithName:@"fixed_vert_lph_spc" constantValues:vc error:&error];assert(vertex&&!error);
 MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=vertex;d.fragmentFunction=fragment;d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 const A5MaliCompiledProfile *p=A5MaliCompiledProfileForID(603);d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(unsigned i=0;i<p->attributeCount;i++){const A5MaliCompiledVertexAttribute *a=p->attributes+i;d.vertexDescriptor.attributes[a->index].format=a->format;d.vertexDescriptor.attributes[a->index].offset=a->offset;d.vertexDescriptor.attributes[a->index].bufferIndex=a->bufferIndex;}
 d.vertexDescriptor.layouts[1].stride=48;d.vertexDescriptor.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;d.vertexDescriptor.layouts[1].stepRate=1;
 id pipeline=[device newRenderPipelineStateWithDescriptor:d error:&error];assert(pipeline&&!error);
 assert([fm contentsOfDirectoryAtPath:uid error:NULL].count==1);close(lock);
 puts("PASS genuine cached specialization and factory progress with producer lock held; no queue mutation or GPU claim");
}return 0;}
