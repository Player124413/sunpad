#import <Foundation/Foundation.h>

#include <cassert>
#include <iostream>

#import "SunPadDiagnostics.h"

int main(void) {
    @autoreleasepool {
        SunPadDiagnosticsStart();
        SunPadLog(@"diagnostic snapshot test sentinel");
        NSString *homePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/SunPad"];
        NSString *temporaryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"import.iso"];
        SunPadLog(@"private paths home=%@ temporary=%@", homePath, temporaryPath);

        NSError *error = nil;
        NSURL *snapshotURL = SunPadDiagnosticsSnapshotURL(&error);
        assert(snapshotURL != nil);
        assert(error == nil);
        assert([snapshotURL.pathExtension isEqualToString:@"log"]);

        NSString *contents = [NSString stringWithContentsOfURL:snapshotURL
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        assert(contents != nil);
        assert(error == nil);
        assert([contents containsString:@"diagnostic snapshot test sentinel"]);
        assert([contents containsString:@"session start version="]);
        assert(![contents containsString:NSHomeDirectory()]);
        assert(![contents containsString:NSTemporaryDirectory()]);
        // The test home itself lives below the temporary directory, so the
        // more specific temporary-directory redaction legitimately wins.
        assert([contents containsString:@"home/Library/SunPad"]);
        assert([contents containsString:@"<temporary>/import.iso"]);

        std::cout << "SunPad diagnostic log snapshot test passed\n";
    }
    return 0;
}
