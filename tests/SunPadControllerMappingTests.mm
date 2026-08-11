#import <Foundation/Foundation.h>

#include <cassert>
#include <iostream>

#import "SunPadControllerMapping.h"

int main(void) {
    @autoreleasepool {
        SunPadControllerButtonMapping mapping = SunPadDefaultControllerButtonMapping();
        assert(SunPadControllerButtonMappingIsValid(mapping));
        assert(SunPadApplyControllerButtonMapping(mapping,
            SunPadPhysicalControllerButtonA | SunPadPhysicalControllerButtonRightShoulder) ==
            (SunPadButtonA | SunPadButtonZ));

        mapping = SunPadControllerButtonMappingByAssigning(
            mapping, SunPadPhysicalControllerButtonB, SunPadButtonA);
        assert(mapping.gameA == SunPadPhysicalControllerButtonB);
        assert(mapping.gameB == SunPadPhysicalControllerButtonA);
        assert(SunPadApplyControllerButtonMapping(mapping,
            SunPadPhysicalControllerButtonA | SunPadPhysicalControllerButtonB) ==
            (SunPadButtonA | SunPadButtonB));

        SunPadControllerButtonMapping corrupt = mapping;
        corrupt.gameZ = SunPadPhysicalControllerButtonB;
        assert(!SunPadControllerButtonMappingIsValid(corrupt));
        assert(SunPadApplyControllerButtonMapping(corrupt,
            SunPadPhysicalControllerButtonRightShoulder) == SunPadButtonZ);

        std::cout << "SunPad controller mapping regression test passed\n";
    }
    return 0;
}
