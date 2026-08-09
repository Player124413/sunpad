#import <Foundation/Foundation.h>

#include <cassert>
#include <iostream>

#import "SunPadDiagnostics.h"

int main(void) {
    @autoreleasepool {
        SunPadDiagnosticsStart();
        SunPadLog(@"diagnostic snapshot test sentinel");

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

        std::cout << "SunPad diagnostic log snapshot test passed\n";
    }
    return 0;
}
