#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import "MissionControlDetector.h"

static NSDictionary<NSString *, id> *Window(NSString *owner, NSString *name, NSInteger layer) {
    return @{
        (__bridge NSString *)kCGWindowOwnerName: owner,
        (__bridge NSString *)kCGWindowName: name,
        (__bridge NSString *)kCGWindowLayer: @(layer),
    };
}

static void AssertDetection(NSArray<NSDictionary<NSString *, id> *> *windows,
                            BOOL expected,
                            NSString *scenario) {
    BOOL actual = MCMagicWindowListIndicatesMissionControl(windows);
    if (actual != expected) {
        NSLog(@"FAIL: %@ (expected %@, got %@)",
              scenario,
              expected ? @"active" : @"inactive",
              actual ? @"active" : @"inactive");
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        if (!MCMagicAccessibilityIdentifiersIndicateMissionControl(@[@"mc"])) {
            NSLog(@"FAIL: Dock accessibility identifier should report Mission Control active");
            return EXIT_FAILURE;
        }

        if (MCMagicAccessibilityIdentifiersIndicateMissionControl(@[@"appexpose", @"desktop"])) {
            NSLog(@"FAIL: unrelated Dock accessibility identifiers should report Mission Control inactive");
            return EXIT_FAILURE;
        }

        AssertDetection(@[
            Window(@"Dock", @"", 20),
            Window(@"Dock", @"", 18),
        ], YES, @"Mission Control overlay and Dock bar");

        AssertDetection(@[
            Window(@"Dock", @"", 20),
        ], NO, @"Finder stack-like overlay without Dock bar");

        AssertDetection(@[
            Window(@"Dock", @"", 28),
            Window(@"Dock", @"", 18),
        ], NO, @"Launchpad layers");

        AssertDetection(@[
            Window(@"Dock", @"Mission Control", 20),
            Window(@"Dock", @"", 18),
        ], NO, @"Named Dock overlay");

        AssertDetection(@[
            Window(@"Other App", @"", 20),
            Window(@"Dock", @"", 18),
        ], NO, @"Non-Dock overlay");

        NSLog(@"MissionControlDetectorTests passed");
    }
    return EXIT_SUCCESS;
}
