/* SPDX-License-Identifier: MIT
 * Real Metal constant/descriptor snapshots and filesystem forwarding only.
 * No GPU, compiler, device connection or installed system path is used.
 */
#import "A5MaliShaderCompileRequest.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <stdatomic.h>
@interface MTLLinkedFunctions (A5MaliRequestTestLinkedSPI)
- (void)setPrivateFunctions:(NSArray *)functions;
@end

#ifndef A5_SHADER_REQUEST_TEST_ROOT
#error "private test spool path required"
#endif
static NSString *const root=@A5_SHADER_REQUEST_TEST_ROOT;
static NSString *uidPath(void){return [root stringByAppendingPathComponent:[NSString stringWithFormat:@"%u",geteuid()]];}
static void resetSpool(void)
{
    NSFileManager *fm=NSFileManager.defaultManager;
    assert([root hasPrefix:@"/private/tmp/"]);
    [fm removeItemAtPath:root error:NULL];
    assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert(!chmod(root.fileSystemRepresentation,01777));
}
static NSString *digest(NSData *data)
{
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    char raw[65];for(unsigned i=0;i<sizeof(bytes);++i)snprintf(raw+2*i,3,"%02x",bytes[i]);
    return [NSString stringWithUTF8String:raw];
}
static NSString *requestPath(NSString *key)
{return [uidPath() stringByAppendingPathComponent:[key stringByAppendingString:@".request.json"]];}
static NSDictionary *constant(NSDictionary *payload,NSString *name)
{for(NSDictionary *r in payload[@"named_constants"])if([r[@"name"] isEqual:name])return r;return nil;}
static MTLRenderPipelineDescriptor *descriptor(void)
{
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    d.colorAttachments[0].blendingEnabled=YES;
    d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;
    d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    d.colorAttachments[1].pixelFormat=MTLPixelFormatRGBA16Float;
    d.colorAttachments[1].writeMask=MTLColorWriteMaskNone;
    MTLVertexDescriptor *v=[MTLVertexDescriptor vertexDescriptor];
    const MTLVertexFormat f[4]={MTLVertexFormatFloat4,MTLVertexFormatFloat2,MTLVertexFormatFloat2,MTLVertexFormatHalf4};
    const NSUInteger off[4]={0,16,24,32};
    for(unsigned i=0;i<4;++i){v.attributes[i].format=f[i];v.attributes[i].offset=off[i];v.attributes[i].bufferIndex=1;}
    v.layouts[1].stride=48;v.layouts[1].stepFunction=MTLVertexStepFunctionPerVertex;v.layouts[1].stepRate=1;
    d.vertexDescriptor=v;return d;
}
int main(void)
{
    @autoreleasepool {
        resetSpool();NSError *error=nil;
        MTLFunctionConstantValues *values=[MTLFunctionConstantValues new];
        uint8_t byte=54,packed[3]={1,2,255};BOOL yes=YES;uint32_t index=0x12345678;
        float vector[3]={1.0f,-2.0f,0.5f};
        [values setConstantValue:&byte type:MTLDataTypeUChar withName:@"fc_blend_function"];
        [values setConstantValue:packed type:MTLDataTypeUChar3 withName:@"fc_color_opcodes0"];
        [values setConstantValue:&yes type:MTLDataTypeBool withName:@"fc_framebuffer_fetch"];
        [values setConstantValue:vector type:MTLDataTypeFloat3 withName:@"test_float3"];
        [values setConstantValue:&index type:MTLDataTypeUInt atIndex:7];
        NSDictionary *fragment=A5MaliShaderCompileFunctionPayload(@"fixed_frag_lph_cph",MTLFunctionTypeFragment,values,&error);
        assert(fragment&&!error);
        assert([constant(fragment,@"fc_color_opcodes0")[@"raw"] isEqual:@"0102ff"]);
        assert([constant(fragment,@"fc_color_opcodes0")[@"bytes"] isEqual:@3]);
        assert([constant(fragment,@"test_float3")[@"raw"] isEqual:@"0000803f000000c00000003f"]);
        assert([fragment[@"indexed_constants"][0][@"raw"] isEqual:@"78563412"]);
        assert([fragment[@"indexed_constants"][0][@"index"] isEqual:@7]);
        byte=0;[values setConstantValue:&byte type:MTLDataTypeUChar withName:@"fc_blend_function"];
        assert([constant(fragment,@"fc_blend_function")[@"raw"] isEqual:@"36"]);
        assert(!A5MaliShaderCompileFunctionPayload(@"../bad",MTLFunctionTypeFragment,nil,&error)&&error);
        NSString *nul=[[NSString alloc]initWithBytes:"abc\0def" length:7 encoding:NSASCIIStringEncoding];
        assert(!A5MaliShaderCompileFunctionPayload(nul,MTLFunctionTypeFragment,nil,&error));
        assert(!A5MaliShaderCompileFunctionPayload(@"good",MTLFunctionTypeKernel,nil,&error));
        NSDictionary *vertex=A5MaliShaderCompileFunctionPayload(@"fixed_vert_lph_spc",MTLFunctionTypeVertex,nil,&error);
        assert(vertex&&!error&&[vertex[@"named_constants"] count]==0);
        NSDictionary *blend=@{@"format":@80,@"write_mask":@15,@"rgb_operation":@3,@"alpha_operation":@4,
            @"source_rgb":@1,@"destination_rgb":@1,@"source_alpha":@1,@"destination_alpha":@1};
        NSMutableDictionary *variant=[fragment mutableCopy];variant[@"blend_state"]=blend;
        NSString *blendKey=A5MaliShaderCompileRequestID(variant,&error);assert(blendKey&&!error);
        assert(![blendKey isEqual:A5MaliShaderCompileRequestID(fragment,&error)]&&!error);
        for(id badValue in @[@15,@(-1),@1.5,@YES,NSNull.null]){
            NSMutableDictionary *badBlend=[blend mutableCopy];badBlend[@"source_rgb"]=badValue;
            variant[@"blend_state"]=badBlend;assert(!A5MaliShaderCompileRequestID(variant,&error)&&error);
        }
        variant=[vertex mutableCopy];variant[@"blend_state"]=blend;
        assert(!A5MaliShaderCompileRequestID(variant,&error)&&error);
        MTLRenderPipelineDescriptor *d=descriptor();
        NSDictionary *pipeline=A5MaliShaderCompilePipelinePayload(d,vertex,fragment,&error);
        assert(pipeline&&!error);
        NSDictionary *state=pipeline[@"descriptor"];
        assert([state[@"color_attachments"] count]==8&&[state[@"vertex_attributes"] count]==31);
        assert([state[@"color_attachments"][1][@"format"] isEqual:@115]);
        assert([state[@"color_attachments"][1][@"write_mask"] isEqual:@0]);
        assert([state[@"color_attachments"][7][@"write_mask"] isEqual:@15]);
        assert([state[@"vertex_attributes"][1][@"format"] isEqual:@29]);
        assert([state[@"vertex_attributes"][2][@"offset"] isEqual:@24]);
        d.colorAttachments[1].writeMask=MTLColorWriteMaskAll;d.vertexDescriptor.attributes[1].offset=20;
        assert([state[@"color_attachments"][1][@"write_mask"] isEqual:@0]);
        assert([state[@"vertex_attributes"][1][@"offset"] isEqual:@16]);
        assert(!A5MaliShaderCompilePipelinePayload(d,fragment,vertex,&error));
        MTLLinkedFunctions *linked=[MTLLinkedFunctions linkedFunctions];
        assert([linked respondsToSelector:@selector(setPrivateFunctions:)]);
        /* Rejection needs only a nonempty opaque link input, never a compiled
         * function or GPU execution. No message is sent to this test object. */
        [linked setPrivateFunctions:@[(id<MTLFunction>)[NSObject new]]];
        MTLRenderPipelineDescriptor *withPrivate=[d copy];withPrivate.vertexLinkedFunctions=linked;
        assert(!A5MaliShaderCompilePipelinePayload(withPrivate,vertex,fragment,&error)&&error);

        NSString *identity=A5MaliShaderCompileRequestID(pipeline,&error);
        assert(identity.length==64&&!error&&[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL].count==0);
        NSString *key=nil;A5MaliShaderForwardResult result=A5MaliForwardShaderCompileRequest(pipeline,&key,&error);
        assert(result==A5MaliShaderForwardQueued&&[key isEqual:identity]&&!error);
        NSString *path=requestPath(key);struct stat before,after;
        assert(!lstat(path.fileSystemRepresentation,&before)&&(before.st_mode&0777)==0600);
        NSData *stored=[NSData dataWithContentsOfFile:path];
        NSMutableDictionary *read=[[NSJSONSerialization JSONObjectWithData:stored options:0 error:&error] mutableCopy];
        assert(read&&!error&&[read[@"request_id"] isEqual:key]&&[read[@"owner_uid"] unsignedIntValue]==geteuid());
        [read removeObjectForKey:@"request_id"];
        NSData *canonical=[NSJSONSerialization dataWithJSONObject:read options:NSJSONWritingSortedKeys error:&error];
        assert([digest(canonical) isEqual:key]);
        assert(A5MaliForwardShaderCompileRequest(pipeline,NULL,&error)==A5MaliShaderForwardAlreadyQueued&&!error);
        assert(!lstat(path.fileSystemRepresentation,&after)&&before.st_ino==after.st_ino);
        int held=open([[uidPath()stringByAppendingPathComponent:@".lock"]fileSystemRepresentation],O_RDWR);
        assert(held>=0&&!flock(held,LOCK_EX|LOCK_NB));
        NSString *busyID=nil;
        assert(A5MaliForwardShaderCompileRequest(pipeline,&busyID,&error)==A5MaliShaderForwardBusy&&!error&&[busyID isEqual:key]);
        assert([A5MaliShaderCompileRequestID(pipeline,&error)isEqual:key]&&!error);
        close(held);
        NSDictionary *changed=A5MaliShaderCompilePipelinePayload(d,vertex,fragment,&error);NSString *other=nil;
        assert(A5MaliForwardShaderCompileRequest(changed,&other,&error)==A5MaliShaderForwardQueued&&![other isEqual:key]);

        NSMutableDictionary *bad=[fragment mutableCopy];bad[@"command"]=@"must_not_be_serialized";
        assert(A5MaliForwardShaderCompileRequest(bad,NULL,&error)==A5MaliShaderForwardFailed&&error);
        bad=[fragment mutableCopy];bad[@"metallib_sha256"]=@"untrusted";
        assert(A5MaliForwardShaderCompileRequest(bad,NULL,&error)==A5MaliShaderForwardFailed);
        bad=[fragment mutableCopy];bad[@"named_constants"]=@[@{@"name":@"x",@"type":@51,@"bytes":@4,@"raw":@"00000000"}];
        assert(A5MaliForwardShaderCompileRequest(bad,NULL,&error)==A5MaliShaderForwardFailed);
        assert([@"corrupt" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL]);
        assert(!chmod(path.fileSystemRepresentation,0600));
        assert(A5MaliForwardShaderCompileRequest(pipeline,NULL,&error)==A5MaliShaderForwardFailed);
        assert([stored writeToFile:path atomically:NO]);assert(!chmod(path.fileSystemRepresentation,0600));
        NSString *outside=[root stringByAppendingString:@"-outside"];
        assert([@"untouched" writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        assert(!unlink(path.fileSystemRepresentation));assert(!symlink(outside.fileSystemRepresentation,path.fileSystemRepresentation));
        assert(A5MaliForwardShaderCompileRequest(pipeline,NULL,&error)==A5MaliShaderForwardFailed);
        assert([[NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding error:NULL] isEqual:@"untouched"]);
        assert(!unlink(path.fileSystemRepresentation));assert(!unlink(outside.fileSystemRepresentation));
        assert(!chmod(uidPath().fileSystemRepresentation,0755));
        assert(A5MaliForwardShaderCompileRequest(pipeline,NULL,&error)==A5MaliShaderForwardFailed);
        assert(!chmod(uidPath().fileSystemRepresentation,0700));
        assert(!chmod(root.fileSystemRepresentation,0755));
        assert(A5MaliForwardShaderCompileRequest(pipeline,NULL,&error)==A5MaliShaderForwardFailed);

        resetSpool();
        atomic_uint queued=0,already=0,failed=0;
        atomic_uint *queuedPtr=&queued,*alreadyPtr=&already,*failedPtr=&failed;
        dispatch_apply(16,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t i){
            (void)i;@autoreleasepool {
                A5MaliShaderForwardResult r;
                unsigned attempts=0;
                do {r=A5MaliForwardShaderCompileRequest(pipeline,NULL,NULL);
                    if(r==A5MaliShaderForwardBusy)usleep(1000);
                }while(r==A5MaliShaderForwardBusy&&++attempts<10000);
                if(r==A5MaliShaderForwardQueued)atomic_fetch_add(queuedPtr,1);
                else if(r==A5MaliShaderForwardAlreadyQueued)atomic_fetch_add(alreadyPtr,1);
                else atomic_fetch_add(failedPtr,1);
            }
        });
        assert(queued==1&&already==15&&failed==0);
        for(unsigned i=1;i<64;++i){NSString *p=[uidPath() stringByAppendingPathComponent:[NSString stringWithFormat:@"pending-%u",i]];
            assert([NSData.data writeToFile:p atomically:NO]);}
        /* A full receipt lane cannot prevent durable function demand. */
        NSString *functionDir=[uidPath()stringByAppendingPathComponent:@"functions"];
        NSString *functionID=nil;error=nil;
        assert(A5MaliForwardShaderCompileRequest(fragment,&functionID,&error)==A5MaliShaderForwardQueued&&!error);
        NSString *functionPath=[functionDir stringByAppendingPathComponent:[functionID stringByAppendingString:@".request.json"]];
        assert([NSFileManager.defaultManager fileExistsAtPath:functionPath]);
        assert(A5MaliForwardShaderCompileRequest(fragment,NULL,&error)==A5MaliShaderForwardAlreadyQueued&&!error);
        for(unsigned i=1;i<64;i++)assert(([NSData.data writeToFile:
            [functionDir stringByAppendingPathComponent:[NSString stringWithFormat:@"pending-%u",i]]atomically:NO]));
        NSString *waitingID=nil;
        assert(A5MaliForwardShaderCompileRequest(vertex,&waitingID,&error)==A5MaliShaderForwardBusy&&!error);
        assert([waitingID isEqual:A5MaliShaderCompileRequestID(vertex,NULL)]);
        assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:functionDir error:NULL].count==65);
        assert(!unlink([[functionDir stringByAppendingPathComponent:@"pending-1"]fileSystemRepresentation]));
        assert(A5MaliForwardShaderCompileRequest(vertex,NULL,&error)==A5MaliShaderForwardQueued&&!error);
        /* No nested symlink may redirect a function request outside its UID. */
        resetSpool();
        assert([NSFileManager.defaultManager createDirectoryAtPath:uidPath() withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL]);
        assert(!symlink("/private/tmp",[[uidPath()stringByAppendingPathComponent:@"functions"]fileSystemRepresentation]));
        assert(A5MaliForwardShaderCompileRequest(fragment,NULL,&error)==A5MaliShaderForwardFailed&&error);
        puts("shader request snapshots, exact typed bytes, canonical identity, dedup, quota, corrupt/symlink guards and concurrent atomic publication: PASS");
    }
    return 0;
}
