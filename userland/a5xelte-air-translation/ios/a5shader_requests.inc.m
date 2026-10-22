/* SPDX-License-Identifier: MIT
 * Bounded root worker for exact, typed Metal requests forwarded by the
 * provider. Included by a5shader_compile.m after its process-limit helpers.
 * No provider-supplied path, command, shader bytes or GPU address is executed.
 */
#include <dirent.h>

#ifndef A5_SHADER_HOST_TEST
static NSString *const requestRoot = @"/private/var/tmp/a5mali-shader-requests";
static NSString *const publishedRoot = @"/private/var/tmp/a5mali-shader-compiled";
#else
#ifndef A5_TEST_REQUESTS
#define A5_TEST_REQUESTS "/private/tmp/a5shader-host-unused-requests"
#endif
#ifndef A5_TEST_PUBLISHED
#define A5_TEST_PUBLISHED "/private/tmp/a5shader-host-unused-published"
#endif
static NSString *const requestRoot = @A5_TEST_REQUESTS;
static NSString *const publishedRoot = @A5_TEST_PUBLISHED;
#endif

static void a5PrepareRequestRoots(void)
{
    for (NSString *path in @[requestRoot,publishedRoot]) {
        mode_t mode = [path isEqual:requestRoot] ? 01777 : 0755;
        struct stat st;
        if (lstat(path.fileSystemRepresentation,&st)) {
            if (errno != ENOENT ||
                ![NSFileManager.defaultManager createDirectoryAtPath:path
                    withIntermediateDirectories:NO
                    attributes:@{NSFilePosixPermissions:@(mode)} error:NULL] ||
                chmod(path.fileSystemRepresentation,mode))
                fail(@"cannot create shader request/publication root");
        }
        if (lstat(path.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) ||
            st.st_uid != geteuid() || (st.st_mode & 07777) != mode)
            fail(@"untrusted shader request/publication root");
    }
}

static BOOL a5HexDigest(NSString *s)
{
    if (![s isKindOfClass:NSString.class] || s.length != 64) return NO;
    for (NSUInteger i = 0; i < 64; ++i) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

static NSData *a5Canonical(id value)
{
    return [NSJSONSerialization dataWithJSONObject:value
        options:NSJSONWritingSortedKeys error:NULL];
}

static BOOL a5ExactKeys(NSDictionary *d, NSArray<NSString *> *keys)
{
    return [d isKindOfClass:NSDictionary.class] &&
        [[NSSet setWithArray:d.allKeys] isEqual:[NSSet setWithArray:keys]];
}

static BOOL a5RequestFunction(NSDictionary *f, NSString *stage,
                              NSString *name, NSArray *constants,
                              NSString *sourceSHA)
{
    if (!a5ExactKeys(f,@[@"schema",@"kind",@"source_library",@"metallib_sha256",
                         @"gpu_id",@"compiler_abi",@"stage",@"function",
                         @"named_constants",@"indexed_constants"])) return NO;
    return [f[@"schema"] isEqual:@1] && [f[@"kind"] isEqual:@"function"] &&
        [f[@"source_library"] isEqual:@"quartzcore"] &&
        [f[@"metallib_sha256"] isEqual:sourceSHA] &&
        [f[@"gpu_id"] isEqual:@"07201000"] &&
        [f[@"compiler_abi"] isEqual:@1] && [f[@"stage"] isEqual:stage] &&
        [f[@"function"] isEqual:name] &&
        [f[@"named_constants"] isEqual:constants] &&
        [f[@"indexed_constants"] isEqual:@[]];
}

static BOOL a5KnownProfile(NSDictionary *request, NSDictionary *known)
{
    if (![request[@"kind"] isEqual:@"pipeline"] ||
        !a5ExactKeys(request,@[@"schema",@"kind",@"source_library",
            @"metallib_sha256",@"gpu_id",@"compiler_abi",@"vertex",
            @"fragment",@"descriptor",@"owner_uid",@"request_id"])) return NO;
    return [request[@"schema"] isEqual:@1] &&
        [request[@"source_library"] isEqual:@"quartzcore"] &&
        [request[@"metallib_sha256"] isEqual:known[@"metallib_sha256"]] &&
        [request[@"gpu_id"] isEqual:@"07201000"] &&
        [request[@"compiler_abi"] isEqual:@1] &&
        [request[@"descriptor"] isKindOfClass:NSDictionary.class] &&
        a5RequestFunction(request[@"vertex"],@"vertex",known[@"vertex_function"],
                          known[@"vertex_constants"],known[@"metallib_sha256"]) &&
        a5RequestFunction(request[@"fragment"],@"fragment",known[@"fragment_function"],
                          known[@"fragment_constants"],known[@"metallib_sha256"]);
}

static NSData *a5ReadRequest(int directory, const char *name, uid_t uid)
{
    int fd = openat(directory,name,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
    if (fd < 0) return nil;
    struct stat st;
    BOOL ok = !fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_uid == uid &&
        st.st_nlink == 1 && (st.st_mode & 0777) == 0600 &&
        st.st_size > 0 && st.st_size <= 128*1024;
    NSMutableData *data = ok ? [NSMutableData dataWithLength:(NSUInteger)st.st_size] : nil;
    uint8_t *p = data.mutableBytes;
    NSUInteger left = data.length;
    while (ok && left) {
        ssize_t n = read(fd,p,left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = NO; break; }
        p += n; left -= (NSUInteger)n;
    }
    uint8_t extra;
    if (ok && read(fd,&extra,1) != 0) ok = NO;
    close(fd);
    return ok ? data : nil;
}

static void a5WriteStatus(NSString *key, NSString *status, NSString *reason)
{
    NSString *folder = [cacheRoot stringByAppendingPathComponent:@"request-status"];
    /* mkdir is idempotent here. Foundation's createDirectoryAtPath returns NO
     * for an existing directory on the device, which used to terminate the
     * worker after its first unsupported request. A pre-existing object must
     * still be checked, including owner, type and exact private mode. */
    if (mkdir(folder.fileSystemRepresentation,0700) && errno != EEXIST) {
        fprintf(stderr,"A5XELTE shader compiler: cannot create status directory errno=%d\n",errno);
        _exit(1); /* fail() itself attempts to record a request status */
    }
    int directory = open(folder.fileSystemRepresentation,
                         O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    struct stat st;
    if (directory < 0 || fstat(directory,&st) || !S_ISDIR(st.st_mode) ||
        st.st_uid != geteuid() || (st.st_mode & 07777) != 0700) {
        fprintf(stderr,"A5XELTE shader compiler: untrusted request status directory\n");
        if (directory >= 0) close(directory);
        _exit(1);
    }
    NSData *data = a5Canonical(@{@"schema":@1,@"request_id":key,
        @"status":status,@"reason":reason});
    if (!data || !a5HexDigest(key)) {
        fprintf(stderr,"A5XELTE shader compiler: invalid request status\n");
        close(directory); _exit(1);
    }
    NSString *name = [key stringByAppendingString:@".json"];
    int fd = openat(directory,name.fileSystemRepresentation,
                    O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (fd < 0 && errno == EEXIST) {
        fd = openat(directory,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);
        BOOL trusted = fd >= 0 && !fstat(fd,&st) && S_ISREG(st.st_mode) &&
            st.st_uid == geteuid() && st.st_nlink == 1 &&
            (st.st_mode & 07777) == 0600;
        if (fd >= 0) close(fd);
        close(directory);
        if (trusted) return;
        fprintf(stderr,"A5XELTE shader compiler: untrusted existing request status\n");
        _exit(1);
    }
    if (fd < 0) {
        fprintf(stderr,"A5XELTE shader compiler: cannot create request status errno=%d\n",errno);
        close(directory); _exit(1);
    }
    const uint8_t *p = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t n = write(fd,p,left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            fprintf(stderr,"A5XELTE shader compiler: short request status write\n");
            close(fd); close(directory); _exit(1);
        }
        p += n; left -= (NSUInteger)n;
    }
    if (fsync(fd) || close(fd) || fsync(directory) || close(directory)) {
        fprintf(stderr,"A5XELTE shader compiler: request status sync failed\n");
        _exit(1);
    }
}

static NSArray<NSString *> *a5ConstantArguments(NSArray<NSDictionary *> *constants)
{
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    for (NSDictionary *item in constants) {
        NSNumber *type = item[@"type"];
        NSString *kind = [type isEqual:@49] ? @"uchar" :
                         [type isEqual:@51] ? @"uchar3" :
                         [type isEqual:@53] ? @"bool" : nil;
        NSString *raw = item[@"raw"];
        NSUInteger width = [type isEqual:@51] ? 3 : 1;
        if (!kind || ![raw isKindOfClass:NSString.class] || raw.length != 2*width ||
            ![item[@"bytes"] isEqual:@(width)]) fail(@"generic constant width/type differs");
        NSMutableArray *values = [NSMutableArray array];
        for (NSUInteger i=0; i<width; ++i) {
            unsigned n=0;
            if (![[NSScanner scannerWithString:[raw substringWithRange:NSMakeRange(2*i,2)]] scanHexInt:&n])
                fail(@"invalid generic constant hex");
            [values addObject:[type isEqual:@53] ? (n ? @"true" : @"false") :
                [NSString stringWithFormat:@"%u",n]];
        }
        [args addObjectsFromArray:@[@"--constant",[NSString stringWithFormat:@"%@:%@:%@",
            item[@"name"],kind,[values componentsJoinedByString:@","]]]];
    }
    return args;
}

static void a5PinnedFile(NSString *path, NSDictionary *pin)
{
    NSData *data = regularData(path,1024*1024);
    if (![@(data.length) isEqual:pin[@"bytes"]] ||
        ![digest(data) isEqual:pin[@"sha256"]])
        fail([@"exact generic compiler output differs: " stringByAppendingString:path]);
}

static NSDictionary *a5NativeRecord(NSString *filename, NSDictionary *pin,
                                    NSUInteger registers)
{
    return @{@"file":filename,@"bytes":pin[@"bytes"],@"sha256":pin[@"sha256"],
             @"first_tag":@5,@"work_registers":@(registers),
             @"tls_bytes":@0,@"wls_bytes":@0};
}

static void a5CompileKnown(NSString *self, NSDictionary *request, NSDictionary *known)
{
    NSString *key = request[@"request_id"];
    NSString *final = [publishedRoot stringByAppendingPathComponent:key];
    if ([NSFileManager.defaultManager fileExistsAtPath:final]) {
        fprintf(stderr,"A5XELTE shader compiler: compiled request already published %s\n",key.UTF8String);
        return;
    }
    activeRequestKey = key;
    NSString *work = [cacheRoot stringByAppendingPathComponent:
        [@".request-work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![NSFileManager.defaultManager createDirectoryAtPath:work
        withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL])
        fail(@"cannot create generic compiler workspace");
    activeWork = work;
    NSString *prefix = [work stringByAppendingPathComponent:@"shader"];
    NSString *meta = [work stringByAppendingPathComponent:@"reflection.json"];
    NSString *packing = [work stringByAppendingPathComponent:@"packing0.json"];
    NSData *packingData = a5Canonical(known[@"configured_vertex_packing0"]);
    if (!packingData) fail(@"cannot serialize known vertex packing");
    writeData(packingData,packing);
    NSMutableArray *air = [NSMutableArray arrayWithArray:@[
        [installed stringByAppendingPathComponent:@"metal2vulkan"],sourceLibrary,
        [prefix stringByAppendingString:@".spv"],@"--profile",
        [installed stringByAppendingPathComponent:@"profile.json"],
        @"--function",known[@"vertex_function"],@"--fragment",known[@"fragment_function"],
        @"--color-format",@"0:BGRA8Unorm",@"--vertex-descriptor",packing,
        @"--emit-meta",meta,@"--no-timeout"]];
    [air addObjectsFromArray:a5ConstantArguments(known[@"fragment_constants"])];
    setenv("METAL2VULKAN_SPIRV_VAL",
        [installed stringByAppendingPathComponent:@"spirv-val"].fileSystemRepresentation,1);
    run(self,air,[work stringByAppendingPathComponent:@"air.log"]);
    NSString *airText = [[NSString alloc] initWithData:regularData(
        [work stringByAppendingPathComponent:@"air.log"],8*1024*1024)
        encoding:NSUTF8StringEncoding];
    if (![airText containsString:@"spirv-val vulkan1.2: PASS"])
        fail(@"generic SPIR-V validation did not run");
    NSDictionary *reflection = readJSON(meta);
    if (![reflection[@"vertex_input"] isEqual:known[@"reflected_vertex_input"]] ||
        ![reflection[@"layout"] isEqual:known[@"reflected_layout"]] ||
        ![reflection[@"graphics"][@"color_write_rules"] isEqual:
            known[@"reflected_color_write_rules"]])
        fail(@"generic translated metadata differs");
    for (NSString *stage in @[@"vert",@"frag"]) {
        NSString *spv = [prefix stringByAppendingFormat:@".%@.spv",stage];
        a5PinnedFile(spv,known[@"spirv"][stage]);
    }
    run(self,@[[installed stringByAppendingPathComponent:@"midgard-generic602"],
        [prefix stringByAppendingString:@".vert.spv"],
        [prefix stringByAppendingString:@".frag.spv"],
        [prefix stringByAppendingString:@".vert.midgard"],
        [prefix stringByAppendingString:@".frag.midgard"]],
        [work stringByAppendingPathComponent:@"midgard.log"]);
    for (NSString *stage in @[@"vert",@"frag"])
        a5PinnedFile([prefix stringByAppendingFormat:@".%@.midgard",stage],
                     known[@"midgard"][stage]);
    NSString *pubWork = [publishedRoot stringByAppendingPathComponent:
        [@".work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![NSFileManager.defaultManager createDirectoryAtPath:pubWork
        withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL])
        fail(@"cannot create publication workspace");
    for (NSString *stage in @[@"vert",@"frag"]) {
        NSString *name = [stage isEqual:@"vert"] ? @"vertex.midgard" : @"fragment.midgard";
        NSString *src = [prefix stringByAppendingFormat:@".%@.midgard",stage];
        NSString *dst = [pubWork stringByAppendingPathComponent:name];
        writeData(regularData(src,1024*1024),dst);
        if (chmod(dst.fileSystemRepresentation,0444)) fail(@"cannot mark compiled shader readonly");
    }
    NSData *descriptorData = a5Canonical(request[@"descriptor"]);
    NSData *vertexData = a5Canonical(request[@"vertex"][@"named_constants"]);
    NSData *fragmentData = a5Canonical(request[@"fragment"][@"named_constants"]);
    if (!descriptorData || !vertexData || !fragmentData) fail(@"invalid request contract serialization");
    NSNumber *profile = known[@"profile_id"];
    NSString *recipeName = [NSString stringWithFormat:@"quartzcore-generic-%@",profile];
    NSDictionary *receipt = @{@"schema":@1,@"request_id":key,@"profile_id":profile,
        @"source_library":@"quartzcore",@"metallib_sha256":known[@"metallib_sha256"],
        @"gpu_id":@"07201000",@"compiler_abi":@1,
        @"recipe":recipeName,@"stage_compiled":@YES,
        @"pipeline_compatible":@NO,
        @"descriptor_sha256":digest(descriptorData),
        @"vertex_constants_sha256":digest(vertexData),
        @"fragment_constants_sha256":digest(fragmentData),
        @"vertex":a5NativeRecord(@"vertex.midgard",known[@"midgard"][@"vert"],
            [known[@"midgard"][@"vert"][@"native_info"][@"work_regs"] unsignedIntegerValue]),
        @"fragment":a5NativeRecord(@"fragment.midgard",known[@"midgard"][@"frag"],
            [known[@"midgard"][@"frag"][@"native_info"][@"work_regs"] unsignedIntegerValue])};
    NSString *receiptPath = [pubWork stringByAppendingPathComponent:@"receipt.json"];
    writeData(a5Canonical(receipt),receiptPath);
    if (chmod(receiptPath.fileSystemRepresentation,0444) ||
        chmod(pubWork.fileSystemRepresentation,0755))
        fail(@"cannot mark compiled receipt readonly");
    for (NSString *name in @[@"receipt.json",@"vertex.midgard",@"fragment.midgard"]) {
        int fd = open([pubWork stringByAppendingPathComponent:name].fileSystemRepresentation,
                      O_RDONLY|O_NOFOLLOW);
        if (fd<0 || fsync(fd) || close(fd)) fail(@"compiled publication sync failed");
    }
    int directory = open(pubWork.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (directory<0 || fsync(directory) || close(directory) ||
        rename(pubWork.fileSystemRepresentation,final.fileSystemRepresentation))
        fail(@"compiled publication rename failed");
    directory = open(publishedRoot.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (directory<0 || fsync(directory) || close(directory)) fail(@"compiled publication sync failed");
    [NSFileManager.defaultManager removeItemAtPath:work error:NULL];
    activeWork = nil;
    activeRequestKey = nil;
    fprintf(stderr,"A5XELTE shader compiler: PUBLISHED profile=%u request=%s\n",
        profile.unsignedIntValue,key.UTF8String);
}

static void a5HandleRequest(NSString *self, NSDictionary *request,
                            NSArray<NSDictionary *> *knownProfiles, NSString *key)
{
    NSString *status = [[cacheRoot stringByAppendingPathComponent:@"request-status"]
        stringByAppendingPathComponent:[key stringByAppendingString:@".json"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:status] ||
        [NSFileManager.defaultManager fileExistsAtPath:
            [publishedRoot stringByAppendingPathComponent:key]]) return;
    NSDictionary *known = nil;
    for (NSDictionary *candidate in knownProfiles) {
        if (a5KnownProfile(request,candidate)) { known = candidate; break; }
    }
    if (!known) {
        a5WriteStatus(key,@"unsupported",
            @"Only exact captured 602 or candidate 603 fixed_vert_lph_spc/fixed_frag_lph_cph typed pairs compile; other requests remain unsupported.");
        fprintf(stderr,"A5XELTE shader compiler: UNSUPPORTED request=%s\n",key.UTF8String);
        return;
    }
    a5CompileKnown(self,request,known);
}

static void a5ScanRequests(NSString *self, NSArray<NSDictionary *> *knownProfiles)
{
    int rootfd = open(requestRoot.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (rootfd < 0) return; /* provider has not forwarded a request yet */
    struct stat rootstat;
    if (fstat(rootfd,&rootstat) || !S_ISDIR(rootstat.st_mode) ||
        rootstat.st_uid != geteuid() || (rootstat.st_mode & 07777) != 01777)
        fail(@"untrusted shader request spool root");
    DIR *users = fdopendir(dup(rootfd));
    if (!users) fail(@"cannot enumerate request spool");
    struct dirent *user;
    while ((user=readdir(users))) {
        NSString *component = [NSString stringWithUTF8String:user->d_name];
        if (!component.length ||
            [component rangeOfCharacterFromSet:
                [NSCharacterSet.decimalDigitCharacterSet invertedSet]].location != NSNotFound)
            continue;
        unsigned long long number = strtoull(user->d_name,NULL,10);
        if (number > UINT32_MAX) continue;
        uid_t uid = (uid_t)number;
        int uidfd = openat(rootfd,user->d_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        struct stat st;
        if (uidfd<0 || fstat(uidfd,&st) || !S_ISDIR(st.st_mode) ||
            st.st_uid!=uid || (st.st_mode & 0777)!=0700) {
            if (uidfd>=0) close(uidfd);
            continue;
        }
        DIR *files = fdopendir(dup(uidfd));
        if (!files) { close(uidfd); continue; }
        unsigned count=0;
        struct dirent *entry;
        while ((entry=readdir(files)) && count<64) {
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if (![name hasSuffix:@".request.json"] || name.length != 77) continue;
            NSString *key = [name substringToIndex:64];
            if (!a5HexDigest(key)) continue;
            count++;
            NSData *bytes = a5ReadRequest(uidfd,entry->d_name,uid);
            if (!bytes) continue;
            id parsed = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL];
            if (![parsed isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *request = parsed;
            if (![request[@"request_id"] isEqual:key] ||
                ![request[@"owner_uid"] isEqual:@(uid)]) continue;
            NSMutableDictionary *body = [request mutableCopy];
            [body removeObjectForKey:@"request_id"];
            NSData *canonical = a5Canonical(body);
            if (!canonical || ![digest(canonical) isEqual:key]) continue;
            a5HandleRequest(self,request,knownProfiles,key);
        }
        closedir(files); close(uidfd);
    }
    closedir(users); close(rootfd);
}

static void a5Serve(NSString *self)
{
    a5PrepareRequestRoots();
    NSMutableArray<NSDictionary *> *knownProfiles = [NSMutableArray array];
    NSString *sourceSHA = digest(regularData(sourceLibrary,64*1024*1024));
    for (NSNumber *profile in @[@602,@603]) {
        NSString *name = [NSString stringWithFormat:@"generic%@.json",profile];
        NSDictionary *known = readJSON([installed stringByAppendingPathComponent:name]);
        if (![known[@"profile_id"] isEqual:profile] ||
            ![sourceSHA isEqual:known[@"metallib_sha256"]])
            fail(@"installed generic recipe or stock library differs");
        [knownProfiles addObject:known];
    }
    for (;;) {
        @autoreleasepool { a5ScanRequests(self,knownProfiles); }
        sleep(5);
    }
}
