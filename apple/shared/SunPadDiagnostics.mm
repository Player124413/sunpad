#import "SunPadDiagnostics.h"

static NSObject *SunPadDiagnosticsLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSString *SunPadDiagnosticsDirectory(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *root = [paths.firstObject stringByAppendingPathComponent:@"SunPad"];
    return [root stringByAppendingPathComponent:@"Logs"];
}

NSString *SunPadDiagnosticsLogPath(void) {
    return [SunPadDiagnosticsDirectory() stringByAppendingPathComponent:@"runtime.log"];
}

static NSString *SunPadLogTimestamp(void) {
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
        NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:NSDate.date];
}

static NSString *SunPadSnapshotTimestamp(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [formatter stringFromDate:NSDate.date];
}

void SunPadDiagnosticsStart(void) {
    @synchronized (SunPadDiagnosticsLock()) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSString *directory = SunPadDiagnosticsDirectory();
        [fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];

        NSString *currentPath = SunPadDiagnosticsLogPath();
        NSNumber *size = [[fileManager attributesOfItemAtPath:currentPath error:nil]
            objectForKey:NSFileSize];
        if (size.unsignedLongLongValue > 1024 * 1024) {
            NSString *previousPath = [directory stringByAppendingPathComponent:@"runtime.previous.log"];
            [fileManager removeItemAtPath:previousPath error:nil];
            [fileManager moveItemAtPath:currentPath toPath:previousPath error:nil];
        }
    }

    NSBundle *bundle = NSBundle.mainBundle;
    SunPadLog(@"session start version=%@ build=%@ os=%@",
              [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
              [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
              NSProcessInfo.processInfo.operatingSystemVersionString);
}

void SunPadLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSString *temporary = NSTemporaryDirectory();
    if (temporary.length > 1)
        message = [message stringByReplacingOccurrencesOfString:temporary
                                                     withString:@"<temporary>/"];
    NSString *home = NSHomeDirectory();
    if (home.length > 0)
        message = [message stringByReplacingOccurrencesOfString:home
                                                     withString:@"<app-container>"];

    NSLog(@"[SunPad] %@", message);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", SunPadLogTimestamp(), message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil)
        return;

    @synchronized (SunPadDiagnosticsLock()) {
        NSString *path = SunPadDiagnosticsLogPath();
        NSFileManager *fileManager = NSFileManager.defaultManager;
        if (![fileManager fileExistsAtPath:path])
            [fileManager createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

NSURL *SunPadDiagnosticsSnapshotURL(NSError **error) {
    @synchronized (SunPadDiagnosticsLock()) {
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSString *sourcePath = SunPadDiagnosticsLogPath();
        if (![fileManager fileExistsAtPath:sourcePath]) {
            if (error != nil) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileNoSuchFileError
                                         userInfo:@{NSFilePathErrorKey: sourcePath}];
            }
            return nil;
        }

        NSString *fileName = [NSString stringWithFormat:@"SunPad-Diagnostic-%@.log",
                              SunPadSnapshotTimestamp()];
        NSString *snapshotPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
        [fileManager removeItemAtPath:snapshotPath error:nil];
        if (![fileManager copyItemAtPath:sourcePath toPath:snapshotPath error:error])
            return nil;
        return [NSURL fileURLWithPath:snapshotPath];
    }
}
