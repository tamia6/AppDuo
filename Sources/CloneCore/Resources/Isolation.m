#import <Foundation/Foundation.h>
#include <pwd.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

static NSString *my_NSHomeDirectory(void) {
    const char *custom = getenv("HOME");
    if (custom && custom[0]) {
        return [NSString stringWithUTF8String:custom];
    }
    return NSHomeDirectory();
}

static NSString *my_NSHomeDirectoryForUser(NSString *userName) {
    const char *custom = getenv("HOME");
    if (custom && custom[0]) {
        return [NSString stringWithUTF8String:custom];
    }
    return NSHomeDirectoryForUser(userName);
}

static NSString *my_NSTemporaryDirectory(void) {
    const char *custom = getenv("TMPDIR");
    if (custom && custom[0]) {
        NSString *t = [NSString stringWithUTF8String:custom];
        if (![t hasSuffix:@"/"]) {
            t = [t stringByAppendingString:@"/"];
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:t withIntermediateDirectories:YES attributes:nil error:nil];
        return t;
    }
    return NSTemporaryDirectory();
}

static NSArray<NSString *> *my_NSSearchPathForDirectoriesInDomains(
    NSSearchPathDirectory directory,
    NSSearchPathDomainMask domainMask,
    BOOL expandTilde) {
    const char *custom_home = getenv("HOME");
    if (custom_home && custom_home[0] && (domainMask & NSUserDomainMask)) {
        NSString *homeStr = [NSString stringWithUTF8String:custom_home];
        NSString *sub = nil;
        switch (directory) {
            case NSApplicationSupportDirectory:
                sub = @"Library/Application Support";
                break;
            case NSCachesDirectory:
                sub = @"Library/Caches";
                break;
            case NSLibraryDirectory:
                sub = @"Library";
                break;
            case NSDocumentDirectory:
                sub = @"Documents";
                break;
            default:
                break;
        }
        if (sub) {
            NSString *full = [homeStr stringByAppendingPathComponent:sub];
            [[NSFileManager defaultManager] createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:nil];
            return @[full];
        }
    }
    return NSSearchPathForDirectoriesInDomains(directory, domainMask, expandTilde);
}

static struct passwd *my_getpwuid(uid_t uid) {
    struct passwd *pw = getpwuid(uid);
    if (pw) {
        const char *custom_home = getenv("HOME");
        if (custom_home && custom_home[0]) {
            __thread static struct passwd fake_pw;
            fake_pw = *pw;
            fake_pw.pw_dir = (char *)custom_home;
            return &fake_pw;
        }
    }
    return pw;
}

static int my_getpwuid_r(uid_t uid, struct passwd *pwd, char *buffer, size_t bufsize, struct passwd **result) {
    int ret = getpwuid_r(uid, pwd, buffer, bufsize, result);
    if (ret == 0 && result && *result) {
        const char *custom_home = getenv("HOME");
        if (custom_home && custom_home[0]) {
            pwd->pw_dir = (char *)custom_home;
        }
    }
    return ret;
}

static size_t my_confstr(int name, char *buf, size_t len) {
    if (name == _CS_DARWIN_USER_TEMP_DIR || name == _CS_DARWIN_USER_CACHE_DIR) {
        const char *custom_tmp = getenv("TMPDIR");
        if (custom_tmp && custom_tmp[0]) {
            size_t n = strlen(custom_tmp) + 1;
            if (buf && len > 0) {
                strncpy(buf, custom_tmp, len);
                buf[len - 1] = 0;
            }
            return n;
        }
    }
    return confstr(name, buf, len);
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
            __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

DYLD_INTERPOSE(my_NSHomeDirectory, NSHomeDirectory)
DYLD_INTERPOSE(my_NSHomeDirectoryForUser, NSHomeDirectoryForUser)
DYLD_INTERPOSE(my_NSTemporaryDirectory, NSTemporaryDirectory)
DYLD_INTERPOSE(my_NSSearchPathForDirectoriesInDomains, NSSearchPathForDirectoriesInDomains)
DYLD_INTERPOSE(my_getpwuid, getpwuid)
DYLD_INTERPOSE(my_getpwuid_r, getpwuid_r)
DYLD_INTERPOSE(my_confstr, confstr)