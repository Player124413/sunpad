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
