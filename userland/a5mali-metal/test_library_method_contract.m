/* SPDX-License-Identifier: MIT */
#import "A5MaliRestrictedDevice.h"
#import <objc/runtime.h>
#include <assert.h>
#include <stdlib.h>
@interface A5MaliMetalLibrary (MethodContractTest)
@property (nonatomic,readonly) NSUUID *libraryIdentifier;
@property (nonatomic,readonly) NSArray *externFunctionNames;
@property (nonatomic,readonly) NSData *bitcodeData;
@property (nonatomic,copy) NSString *overrideTriple;
@property (nonatomic) BOOL shaderValidationEnabled;
- (BOOL)serializeToURL:(NSURL *)url error:(NSError **)error;
- (id)newFunctionWithDescriptor:(MTLFunctionDescriptor *)d destinationArchive:(id)a error:(NSError **)e;
- (id)newFunctionWithName:(NSString *)n constantValues:(MTLFunctionConstantValues *)v pipelineLibrary:(id)p error:(NSError **)e;
- (void)newFunctionWithName:(NSString *)n constantValues:(MTLFunctionConstantValues *)v pipelineLibrary:(id)p completionHandler:(void (^)(id,NSError *))h;
- (id)newIntersectionFunctionWithDescriptor:(MTLIntersectionFunctionDescriptor *)d error:(NSError **)e;
- (void)newIntersectionFunctionWithDescriptor:(MTLIntersectionFunctionDescriptor *)d completionHandler:(void (^)(id,NSError *))h;
@end
@interface A5MaliMetalFunction (MethodContractTest)
- (void)reflectionWithOptions:(NSUInteger)options completionHandler:(void (^)(id))handler;
- (NSArray *)relocations;
- (void)setRelocations:(NSArray *)array;
@end
static kern_return_t noTransport(void*c,uint32_t s,const void*i,size_t n,void*o,size_t*z)
{(void)c;(void)s;(void)i;(void)n;(void)o;(void)z;assert(0);return KERN_FAILURE;}
static void waitFor(dispatch_semaphore_t semaphore)
{assert(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
static void expectUnsupported(void(^action)(void))
{
 BOOL raised=NO;@try{action();}@catch(NSException *exception){
 assert([exception.name isEqualToString:NSInvalidArgumentException]);
 assert([exception.reason containsString:@"unsupported"]);raised=YES;}assert(raised);
}
int main(void)
{
 @autoreleasepool {
 const char *path=getenv("A5_MALI_STOCK_QUARTZCORE_METALLIB");assert(path);
 int context=0;
 A5MaliRestrictedDevice *device=[[A5MaliRestrictedDevice alloc]initWithTransport:noTransport context:&context commandCapabilities:31];
 NSError *error=(id)[NSObject new];
 A5MaliMetalLibrary *library=[device newLibraryWithURL:[NSURL fileURLWithPath:@(path)] error:&error];
 assert(library && !error);assert(library.type==MTLLibraryTypeExecutable && !library.installName);
 assert([library.libraryIdentifier isEqual:library.libraryIdentifier]);
 assert(!library.externFunctionNames.count && !library.bitcodeData && !library.overrideTriple && !library.shaderValidationEnabled);
 library.overrideTriple=nil;library.shaderValidationEnabled=NO;
 expectUnsupported(^{library.overrideTriple=@"wrong-target";});
 expectUnsupported(^{library.shaderValidationEnabled=YES;});
 A5MaliMetalFunction *function=[library newFunctionWithName:@"read_surf_frag"];
 assert(function && function.device==device && function.options==0 && function.patchType==MTLPatchTypeNone && function.patchControlPointCount==-1);
 assert(!function.vertexAttributes && !function.stageInputAttributes && !function.functionConstantsDictionary.count);
 id reflection=[NSObject new];assert(![function newArgumentEncoderWithBufferIndex:0 reflection:&reflection] && !reflection);
 assert(![function newArgumentEncoderWithBufferIndex:NSUIntegerMax]);
 [function setRelocations:@[]];assert(!function.relocations.count);
 expectUnsupported(^{[function setRelocations:@[[NSObject new]]];});
 NSURL *destination=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 error=nil;assert(![library serializeToURL:destination error:&error] && error.code==kIOReturnUnsupported);
 assert(![NSFileManager.defaultManager fileExistsAtPath:destination.path]);
 MTLFunctionDescriptor *descriptor=[MTLFunctionDescriptor functionDescriptor];descriptor.name=@"read_surf_frag";
 error=nil;assert([library newFunctionWithDescriptor:descriptor destinationArchive:nil error:&error] && !error);
 error=nil;assert(![library newFunctionWithDescriptor:descriptor destinationArchive:@[] error:&error] && error.code==kIOReturnUnsupported);
 dispatch_semaphore_t done=dispatch_semaphore_create(0);__block unsigned callbacks=0;
 [library newFunctionWithDescriptor:descriptor completionHandler:^(id<MTLFunction> f,NSError *e){assert(f && !e);++callbacks;dispatch_semaphore_signal(done);}];
 descriptor.name=@"mutated_after_call";waitFor(done);assert(callbacks==1);
 [library newFunctionWithName:@"read_surf_frag" constantValues:nil completionHandler:^(id<MTLFunction> f,NSError *e){assert(f && !e);++callbacks;dispatch_semaphore_signal(done);}];
 waitFor(done);assert(callbacks==2);
 [library newFunctionWithName:@"not_supported" constantValues:nil completionHandler:^(id<MTLFunction> f,NSError *e){assert(!f && e.code==kIOReturnUnsupported);++callbacks;dispatch_semaphore_signal(done);}];
 waitFor(done);assert(callbacks==3);
 [library newIntersectionFunctionWithDescriptor:nil completionHandler:^(id f,NSError *e){assert(!f && e.code==kIOReturnUnsupported);++callbacks;dispatch_semaphore_signal(done);}];
 waitFor(done);assert(callbacks==4);
 [library newFunctionWithName:@"read_surf_frag" constantValues:nil pipelineLibrary:@[] completionHandler:^(id f,NSError *e){assert(!f && e.code==kIOReturnUnsupported);++callbacks;dispatch_semaphore_signal(done);}];
 waitFor(done);assert(callbacks==5);
 [function reflectionWithOptions:0 completionHandler:^(id result){assert(!result);++callbacks;dispatch_semaphore_signal(done);}];
 waitFor(done);assert(callbacks==6);
 [library newFunctionWithDescriptor:nil completionHandler:nil];
 [library newFunctionWithName:@"read_surf_frag" constantValues:nil completionHandler:nil];
 puts("library/function: asynchronous snapshot, callback-once, metadata and explicit unsupported contracts PASS");
 }
 return 0;
}
