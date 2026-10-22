/* SPDX-License-Identifier: MIT
 * Native iOS orchestration of the real AIR -> SPIR-V -> T720 compiler.
 * No GPU submission or fallback shader is performed here.
 */
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <IOKit/IOKitLib.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
extern char **environ;
/* libproc exports are in libSystem on iOS; the public iPhone SDK omits its
 * header. These prototypes match XNU/libproc, with sys/resource.h types. */
extern int proc_listpgrppids(pid_t, void *, int);
extern int proc_pid_rusage(int, int, rusage_info_t *);

#ifndef A5_SHADER_HOST_TEST
static NSString *const installed = @"/usr/libexec/a5shader";
static NSString *const cacheRoot = @"/private/var/db/a5shader-cache";
static NSString *const sourceLibrary = @"/System/Library/Frameworks/QuartzCore.framework/default.metallib";
#else
/* Compiled only by the host regression; no runtime path overrides on iOS. */
static NSString *const installed = @A5_TEST_TOOLS;
static NSString *const cacheRoot = @A5_TEST_CACHE;
static NSString *const sourceLibrary = @A5_TEST_LIBRARY;
#endif
static NSString *activeWork;
static NSString *activeRequestKey;
static void a5WriteStatus(NSString *key, NSString *status, NSString *reason);
static void fail(NSString *reason);

static void showSuccess(void)
{
#ifndef A5_SHADER_HOST_TEST
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("A5XELTEGPU"));
    if (!service) fail(@"compiler completion service unavailable");
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceOpen(service,mach_task_self(),1,&connection);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) fail(@"compiler completion client denied");
    const uint32_t report[6] = {1,24,0,0,3,0};
    size_t outputSize = 0;
    kr = IOConnectCallStructMethod(connection,16,report,sizeof(report),NULL,&outputSize);
    IOServiceClose(connection);
    if (kr != KERN_SUCCESS || outputSize) fail(@"compiler green completion line failed");
    fprintf(stderr,"A5XELTE shader compiler: GREEN LINE verified_pairs=3\n");
#else
    fprintf(stderr,"A5XELTE shader compiler: host test skips device completion line\n");
#endif
}

static void fail(NSString *reason)
{
    fprintf(stderr, "A5XELTE shader compiler: FAILED %s\n", reason.UTF8String);
    if (activeWork) {
        for (NSString *name in @[@"air.log",@"midgard.log"]) {
            NSData *log = [NSData dataWithContentsOfFile:[activeWork stringByAppendingPathComponent:name]];
            if (log.length) {
                NSUInteger length = MIN(log.length,2048);
                fwrite((const uint8_t *)log.bytes+log.length-length,1,length,stderr);
            }
        }
        [NSFileManager.defaultManager removeItemAtPath:activeWork error:NULL];
    }
    if (activeRequestKey) {
        NSString *key = activeRequestKey;
        activeRequestKey = nil;
        a5WriteStatus(key,@"failed",reason);
    }
    exit(1);
}

static NSData *regularData(NSString *path, NSUInteger maximum)
{
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) || !S_ISREG(st.st_mode) ||
        st.st_size <= 0 || (uint64_t)st.st_size > maximum)
        fail([@"invalid regular file: " stringByAppendingString:path]);
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length != (NSUInteger)st.st_size)
        fail([@"cannot read: " stringByAppendingString:path]);
    return data;
}

static NSString *digest(NSData *data)
{
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result = [NSMutableString string];
    for (unsigned i = 0; i < sizeof(bytes); ++i)
        [result appendFormat:@"%02x", bytes[i]];
    return result;
}

static void writeData(NSData *data, NSString *path)
{
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) fail([@"create: " stringByAppendingString:path]);
    const uint8_t *p = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) fail(@"short output write");
        p += n; left -= (NSUInteger)n;
    }
    if (fsync(fd) || close(fd)) fail(@"output sync failed");
}

static double seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) fail(@"monotonic clock unavailable");
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* Separate exec worker inherits finite limits without changing a compositor's
 * process limits. Every child, including spirv-val, stays in its process group. */
static int worker(int argc, char **argv)
{
    if (argc < 4) return 2;
    NSString *path = [NSString stringWithUTF8String:argv[3]];
    if (![path hasPrefix:[installed stringByAppendingString:@"/"]]) return 2;
    struct rlimit file = {8ULL * 1024 * 1024, 8ULL * 1024 * 1024};
    /* Darwin's RLIMIT_DATA includes mapped shared-cache data and can already
     * exceed500MiB before main. Enforce actual group RSS/footprint in parent. */
    if (setrlimit(RLIMIT_FSIZE, &file))
        return 125;
    execv(argv[3], &argv[3]);
    return 126;
}

static void run(NSString *self, NSArray<NSString *> *command, NSString *log)
{
    double start = seconds(), lastProgress = start;
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObjects:self, @"--worker", @"--", nil];
    [all addObjectsFromArray:command];
    char **args = calloc(all.count + 1, sizeof(char *));
    if (!args) fail(@"argument allocation failed");
    for (NSUInteger i = 0; i < all.count; ++i) args[i] = (char *)all[i].UTF8String;
    int fd = open(log.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0600);
    if (fd < 0) fail(@"cannot create compiler log");
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attr;
    int error = posix_spawn_file_actions_init(&actions);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, fd, STDERR_FILENO);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, fd);
    if (!error) error = posix_spawnattr_init(&attr);
    if (error) fail(@"spawn actions initialization failed");
    error = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    if (!error) error = posix_spawnattr_setpgroup(&attr, 0);
    pid_t pid = 0;
    if (!error) error = posix_spawn(&pid, self.fileSystemRepresentation, &actions, &attr, args, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    close(fd); free(args);
    if (error) fail([NSString stringWithFormat:@"spawn error=%d", error]);
    int status = 0;
    struct rusage usage = {};
    for (;;) {
        pid_t done = wait4(pid, &status, WNOHANG, &usage);
        if (done == pid) {
            pid_t remaining[32] = {};
            int count = proc_listpgrppids(pid,remaining,sizeof(remaining));
            if (count != 0) {
                kill(-pid,SIGKILL);
                fail(@"compiler left live descendants or accounting failed");
            }
            break;
        }
        if (done < 0 && errno != EINTR) {
            kill(-pid,SIGKILL);
            fail(@"wait4 failed");
        }
        pid_t members[32] = {};
        int memberCount = proc_listpgrppids(pid,members,sizeof(members));
        bool invalid = memberCount < 0 || memberCount >= 32;
        uint64_t resident = 0;
        for (int i = 0; !invalid && i < memberCount; ++i) {
            if (members[i] <= 0) continue;
            struct rusage_info_v0 info = {};
            if (proc_pid_rusage(members[i],RUSAGE_INFO_V0,(rusage_info_t *)&info)) {
                if (errno != ESRCH) invalid = true;
            } else resident += MAX(info.ri_resident_size,info.ri_phys_footprint);
        }
        if (invalid || resident > 500ULL*1024*1024) {
            kill(-pid,SIGKILL);
            while (waitpid(pid,&status,0)<0 && errno==EINTR) {}
            fail(invalid ? @"cannot account compiler process group" : @"compiler group exceeded500MiB");
        }
        if (seconds() - lastProgress >= 10) {
            fprintf(stderr,"A5XELTE shader compiler: RUNNING stage=%s wall=%.1f resident_bytes=%llu\n",
                command[0].lastPathComponent.UTF8String,seconds()-start,(unsigned long long)resident);
            lastProgress = seconds();
        }
        usleep(20000);
    }
    fprintf(stderr, "A5XELTE shader compiler: stage=%s status=%d wall=%.3f cpu=%.3f peak_bytes=%ld\n",
        command[0].lastPathComponent.UTF8String, status,seconds()-start,
        usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+
        usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6,usage.ru_maxrss);
    if (!WIFEXITED(status) || WEXITSTATUS(status))
        fail([@"compiler/validator failed; see " stringByAppendingString:log]);
    if (usage.ru_maxrss > 500L * 1024 * 1024)
        fail(@"compiler exceeded 500 MiB; no cache published");
}

static void validateMetadata(NSDictionary *meta, NSDictionary *spec)
{
    if (![meta[@"kind"] isEqual:@"render"]) fail(@"not a render pipeline");
    NSArray *stages = meta[@"stages"];
    if (stages.count != 2 || ![stages[0][@"stage"] isEqual:@"vert"] ||
        ![stages[1][@"stage"] isEqual:@"frag"] ||
        ![stages[0][@"entry_point"] isEqual:@"main"] ||
        ![stages[1][@"entry_point"] isEqual:@"main"]) fail(@"changed shader stages");
    NSMutableArray *slots = [NSMutableArray array], *windows = [NSMutableArray array];
    for (NSArray *entry in meta[@"interface"][@"slots"]) {
        if (entry.count != 2) fail(@"invalid resource interface");
        NSDictionary *slot = entry[0], *interface = entry[1];
        [slots addObject:@[slot[@"stage"], slot[@"class"], slot[@"index"]]];
        if ([slot[@"class"] isEqual:@"Sampler"]) {
            if (![spec[@"sampled_texture"] boolValue] ||
                ![interface isEqual:@{@"Sampler":@{@"compare":@NO,@"coordinate_sensitive":@YES}}])
                fail(@"unsupported sampler interface");
        } else if ([slot[@"class"] isEqual:@"Texture"] && [spec[@"sampled_texture"] boolValue]) {
            if (![interface isEqual:@{@"Texture":@{@"texture_type":@"Type2D",@"sampled_type":@"Float",
                @"depth_compare":@NO,@"access":@{@"sample":@YES,@"read":@NO,@"write":@NO}}}])
                fail(@"unsupported sampled texture");
        } else {
            NSDictionary *resource = interface[@"Buffer"] ?: interface[@"Texture"];
            NSDictionary *access = resource[@"access"];
            if (![access[@"read"] boolValue] || [access[@"write"] boolValue] ||
                [access[@"sample"] boolValue]) fail(@"unsupported resource access");
            if (interface[@"Buffer"]) {
                id window = resource[@"window"];
                id length = [window isEqual:@"Whole"] ? @"Whole" : window[@"Bounded"][@"len"];
                [windows addObject:@[resource[@"form"][@"Descriptor"], length]];
            }
        }
    }
    if (![slots isEqual:spec[@"slots"]] || ![windows isEqual:spec[@"buffer_windows"]])
        fail(@"changed resource ABI");
    NSMutableArray *pushes = [NSMutableArray array];
    for (NSDictionary *p in meta[@"layout"][@"push_constants"])
        [pushes addObject:@[[p[@"stages"] intValue] == 1 ? @"Vertex" : @"Fragment", p[@"offset"],p[@"size"]]];
    NSDictionary *graphics = meta[@"graphics"];
    NSArray *colors = graphics[@"color_attachments"];
    if (![pushes isEqual:spec[@"push"]] || colors.count != 1 ||
        ![colors[0][@"format"] isEqual:@44] || ![colors[0][@"write_mask"] isEqual:spec[@"write_mask"]] ||
        ![graphics[@"rasterization_samples"] isEqual:@1] ||
        ![graphics[@"color_write_rules"] isEqual:@[@[@0,@0x2222]]]) fail(@"changed render/push ABI");
    if (spec[@"specialization"] &&
        ![@[stages[0][@"specialization"][@"constants"], stages[1][@"specialization"][@"constants"]]
            isEqual:spec[@"specialization"]]) fail(@"changed specialization ABI");
}

static NSDictionary *readJSON(NSString *path)
{
    id value = [NSJSONSerialization JSONObjectWithData:regularData(path, 2 * 1024 * 1024) options:0 error:NULL];
    if (![value isKindOfClass:[NSDictionary class]]) fail(@"invalid JSON dictionary");
    return value;
}

static void compilePair(NSString *self, NSString *pair)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *spec = readJSON([installed stringByAppendingPathComponent:@"pairs.json"])[pair];
    if (!spec || ![@[@"read_surf",@"downsample_4"] containsObject:pair]) fail(@"unsupported lowering profile");
    NSMutableData *keyData = [NSMutableData data];
    NSArray *inputs = @[self, sourceLibrary, [installed stringByAppendingPathComponent:@"metal2vulkan"],
        [installed stringByAppendingPathComponent:@"spirv-val"], [installed stringByAppendingPathComponent:@"midgard-compile"],
        [installed stringByAppendingPathComponent:@"profile.json"], [installed stringByAppendingPathComponent:@"pairs.json"]];
    for (NSString *path in inputs)
        [keyData appendData:[digest(regularData(path, 64 * 1024 * 1024)) dataUsingEncoding:NSUTF8StringEncoding]];
    [keyData appendData:[pair dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *key = digest(keyData);
    NSString *final = [cacheRoot stringByAppendingPathComponent:key];
    NSString *reportPath = [final stringByAppendingPathComponent:@"report.json"];
    if ([fm fileExistsAtPath:reportPath]) {
        NSDictionary *report = readJSON(reportPath);
        for (NSString *stage in @[@"vert",@"frag"]) {
            NSString *name = [@"shader." stringByAppendingFormat:@"%@.midgard",stage];
            NSData *output = regularData([final stringByAppendingPathComponent:name], 1024 * 1024);
            if (![digest(output) isEqual:report[stage][@"sha256"]])
                fail(@"cache output digest mismatch");
            NSDictionary *expected = spec[@"expected_output"][stage];
            if (expected && (![digest(output) isEqual:expected[@"sha256"]] ||
                ![@(output.length) isEqual:expected[@"bytes"]])) fail(@"cache differs from validated shader reference");
        }
        if (![report[@"key"] isEqual:key]) fail(@"cache key mismatch");
        fprintf(stderr,"A5XELTE shader compiler: CACHE HIT pair=%s key=%s\n",pair.UTF8String,key.UTF8String);
        return;
    }
    /* Bound retained versions and failed/interrupted workspaces. An operator
     * can remove old entries; never grow a cache without a finite limit. */
    NSArray *entries = [fm contentsOfDirectoryAtPath:cacheRoot error:NULL];
    if (!entries || entries.count > 64) fail(@"cache entry limit reached");
    unsigned long long total = 0;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:cacheRoot];
    for (NSString *entry in enumerator) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:[cacheRoot stringByAppendingPathComponent:entry] error:NULL];
        total += [attributes[NSFileSize] unsignedLongLongValue];
        if (total > 256ULL*1024*1024) fail(@"cache size limit reached");
    }
    NSString *work = [cacheRoot stringByAppendingPathComponent:[@".work-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![fm createDirectoryAtPath:work withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL])
        fail(@"cannot create private compiler workspace");
    activeWork = work;
    NSString *prefix = [work stringByAppendingPathComponent:@"shader"];
    NSString *meta = [prefix stringByAppendingString:@"-meta.json"];
    NSMutableArray *air = [NSMutableArray arrayWithArray:@[[installed stringByAppendingPathComponent:@"metal2vulkan"],
        sourceLibrary,[prefix stringByAppendingString:@".spv"],@"--function",spec[@"vertex"],@"--fragment",spec[@"fragment"],
        @"--profile",[installed stringByAppendingPathComponent:@"profile.json"],@"--color-format",@"0:BGRA8Unorm",@"--emit-meta",meta,@"--no-timeout"]];
    if (spec[@"vertex_descriptor"]) {
        NSString *descriptor = [work stringByAppendingPathComponent:@"vertex.json"];
        writeData([NSJSONSerialization dataWithJSONObject:spec[@"vertex_descriptor"] options:0 error:NULL],descriptor);
        [air addObjectsFromArray:@[@"--vertex-descriptor",descriptor]];
    }
    double start = seconds();
    setenv("METAL2VULKAN_SPIRV_VAL",[installed stringByAppendingPathComponent:@"spirv-val"].fileSystemRepresentation,1);
    run(self,air,[work stringByAppendingPathComponent:@"air.log"]);
    NSString *validationLog = [[NSString alloc] initWithData:regularData(
        [work stringByAppendingPathComponent:@"air.log"],8*1024*1024) encoding:NSUTF8StringEncoding];
    if (![validationLog containsString:@"spirv-val vulkan1.2: PASS"] ||
        [validationLog containsString:@"spirv-val: not found"]) fail(@"mandatory SPIR-V validation did not run");
    validateMetadata(readJSON(meta),spec);
    NSMutableArray *midgard = [NSMutableArray arrayWithObject:[installed stringByAppendingPathComponent:@"midgard-compile"]];
    for (NSString *suffix in @[@".vert.spv",@".frag.spv",@".vert.midgard",@".frag.midgard"])
        [midgard addObject:[prefix stringByAppendingString:suffix]];
    if ([pair isEqual:@"downsample_4"]) [midgard addObject:pair];
    run(self,midgard,[work stringByAppendingPathComponent:@"midgard.log"]);
    NSMutableDictionary *report = [@{@"key":key,@"pair":pair,@"seconds":@(seconds()-start),@"gpu_id":@"07201000"} mutableCopy];
    for (NSString *stage in @[@"vert",@"frag"]) {
        NSData *bytes = regularData([prefix stringByAppendingFormat:@".%@.midgard",stage],1024*1024);
        if (bytes.length % 16) fail(@"unaligned Midgard binary");
        NSDictionary *expected = spec[@"expected_output"][stage];
        if (expected && (![digest(bytes) isEqual:expected[@"sha256"]] ||
            ![@(bytes.length) isEqual:expected[@"bytes"]])) fail(@"compiled output differs from validated shader reference");
        report[stage] = @{@"bytes":@(bytes.length),@"sha256":digest(bytes)};
        fprintf(stderr,"A5XELTE shader compiler: pair=%s stage=%s bytes=%lu sha256=%s\n",
            pair.UTF8String,stage.UTF8String,(unsigned long)bytes.length,digest(bytes).UTF8String);
    }
    writeData([NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL],
        [work stringByAppendingPathComponent:@"report.json"]);
    /* Tool-written files need durable data too, not just report.json. */
    for (NSString *name in [fm contentsOfDirectoryAtPath:work error:NULL]) {
        NSString *path = [work stringByAppendingPathComponent:name];
        int fd = open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
        struct stat st;
        if (fd < 0 || fstat(fd,&st) || !S_ISREG(st.st_mode) || fsync(fd) || close(fd))
            fail(@"compiler output sync failed");
    }
    int workfd = open(work.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    if (workfd < 0 || fsync(workfd) || close(workfd)) fail(@"workspace sync failed");
    if (rename(work.fileSystemRepresentation,final.fileSystemRepresentation)) fail(@"cache publication failed");
    activeWork = nil;
    int dir = open(cacheRoot.fileSystemRepresentation,O_RDONLY);
    if (dir < 0 || fsync(dir) || close(dir)) fail(@"cache directory sync failed");
    fprintf(stderr,"A5XELTE shader compiler: COMPILED pair=%s seconds=%.3f vert=%lu frag=%lu key=%s\n",
        pair.UTF8String,[report[@"seconds"] doubleValue],(unsigned long)[report[@"vert"][@"bytes"] unsignedLongValue],
        (unsigned long)[report[@"frag"][@"bytes"] unsignedLongValue],key.UTF8String);
}

#include "a5shader_requests.inc.m"

int main(int argc, char **argv)
{
    @autoreleasepool {
      @try {
        if (argc > 1 && !strcmp(argv[1],"--worker")) return worker(argc,argv);
        if (argc != 2 && argc != 3) { fprintf(stderr,"usage: %s --serve | --selftest | --pair read_surf|downsample_4\n",argv[0]); return 2; }
        NSString *self = NSBundle.mainBundle.executablePath;
        if (!NSFileManager.defaultManager) fail(@"file manager unavailable");
#ifndef A5_SHADER_HOST_TEST
        if (geteuid()) fail(@"compiler service requires root");
#endif
        if (![NSFileManager.defaultManager createDirectoryAtPath:cacheRoot withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:NULL]) fail(@"cannot create cache root");
        struct stat st;
        if (lstat(cacheRoot.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) || st.st_uid != geteuid() || (st.st_mode & 0077))
            fail(@"cache root is not a private root-owned directory");
        NSString *lock = [cacheRoot stringByAppendingPathComponent:@".lock"];
        int lockfd = open(lock.fileSystemRepresentation,O_RDWR|O_CREAT|O_NOFOLLOW,0600);
        if (lockfd < 0 || flock(lockfd,LOCK_EX|LOCK_NB)) fail(@"compiler cache is busy");
        fprintf(stderr,"A5XELTE shader compiler: native iOS ARM64 service start no_time_limit=1\n");
        if (argc == 2 && !strcmp(argv[1],"--serve")) {
            a5PrepareRequestRoots();
            if (setpriority(PRIO_PROCESS,0,10))
                fprintf(stderr,"A5XELTE shader compiler: priority adjustment unavailable errno=%d\n",errno);
        }
        if (argc == 2 && (!strcmp(argv[1],"--selftest") || !strcmp(argv[1],"--serve"))) {
#ifdef A5_SHADER_HOST_TEST
            if (strcmp(argv[1],"--serve")) {
#endif
            for (NSString *pair in @[@"read_surf",@"downsample_4"]) {
                compilePair(self,pair);
                compilePair(self,pair);
            }
            showSuccess();
#ifdef A5_SHADER_HOST_TEST
            }
#endif
            if (!strcmp(argv[1],"--serve")) a5Serve(self);
        } else if (argc == 3 && !strcmp(argv[1],"--pair")) {
            compilePair(self,[NSString stringWithUTF8String:argv[2]]);
        } else return 2;
        close(lockfd);
        fprintf(stderr,"A5XELTE shader compiler: DONE\n");
      } @catch (NSException *exception) {
        fail([@"invalid compiler metadata: " stringByAppendingString:exception.reason ?: exception.name]);
      }
    }
    return 0;
}
