#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>

#import "MissionControlDetector.h"

// Replace only the OS boundaries so these cases exercise the real host lookup,
// accessibility parsing, and fallback selection without querying the desktop.
@interface DetectorTestApplication : NSObject
@property(nonatomic) pid_t processIdentifier;
@end
@implementation DetectorTestApplication
@end

static NSDictionary *hostIdentifiers;
static NSArray *fallbackWindows;
static NSUInteger fallbackQueries;

static NSArray *TestRunningApplications(id self, SEL selector, NSString *bundleIdentifier) {
    if (hostIdentifiers[bundleIdentifier] == nil) return @[];
    DetectorTestApplication *app = [DetectorTestApplication new];
    app.processIdentifier = [bundleIdentifier isEqualToString:@"com.apple.dock"] ? 1 : 2;
    return @[app];
}

AXUIElementRef AXUIElementCreateApplication(pid_t pid) {
    return (AXUIElementRef)CFNumberCreate(NULL, kCFNumberIntType, &pid);
}

AXError AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef *value) {
    *value = NULL;
    if (CFEqual(attribute, kAXChildrenAttribute)) {
        int pid = 0;
        CFNumberGetValue((CFNumberRef)element, kCFNumberIntType, &pid);
        id identifiers = hostIdentifiers[pid == 1 ? @"com.apple.dock" : @"com.apple.WindowManager"];
        if (![identifiers isKindOfClass:NSArray.class]) return kAXErrorCannotComplete;
        *value = CFRetain((__bridge CFArrayRef)identifiers);
        return kAXErrorSuccess;
    }
    if (CFEqual(attribute, kAXIdentifierAttribute)) {
        *value = CFRetain(element);
        return kAXErrorSuccess;
    }
    return kAXErrorAttributeUnsupported;
}

CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID window) {
    fallbackQueries++;
    return CFRetain((__bridge CFArrayRef)fallbackWindows);
}

static void AssertHostDetection(NSDictionary *hosts, BOOL expected, BOOL usesFallback, NSString *scenario) {
    hostIdentifiers = hosts;
    fallbackQueries = 0;
    BOOL actual = MCMagicIsMissionControlActive();
    if (actual != expected || (fallbackQueries > 0) != usesFallback) {
        NSLog(@"FAIL: %@ (active=%d, fallback queries=%lu)", scenario, actual, (unsigned long)fallbackQueries);
        exit(EXIT_FAILURE);
    }
}

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

        if (!MCMagicAccessibilityIdentifiersIndicateMissionControl(@[@"mc.display"])) {
            NSLog(@"FAIL: WindowManager Mission Control display should report active");
            return EXIT_FAILURE;
        }

        if (MCMagicAccessibilityIdentifiersIndicateMissionControl(@[@"appexpose.display"])) {
            NSLog(@"FAIL: App Exposé display must not report Mission Control active");
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

        Method lookup = class_getClassMethod(NSRunningApplication.class,
                                             @selector(runningApplicationsWithBundleIdentifier:));
        IMP originalLookup = method_setImplementation(lookup, (IMP)TestRunningApplications);
        fallbackWindows = @[Window(@"Dock", @"", 20), Window(@"Dock", @"", 18)];
        AssertHostDetection(@{@"com.apple.dock": @[], @"com.apple.WindowManager": @[@"mc.display"]},
                            YES, NO, @"readable Dock must not mask active WindowManager Mission Control");
        AssertHostDetection(@{@"com.apple.dock": @[], @"com.apple.WindowManager": @[]},
                            NO, NO, @"closing Mission Control clears the WindowManager identifier");
        AssertHostDetection(@{@"com.apple.dock": @[@"mc"]},
                            YES, NO, @"legacy Dock detection works without WindowManager");
        AssertHostDetection(@{@"com.apple.WindowManager": @[@"mc.display"]},
                            YES, NO, @"WindowManager detection works when Dock is absent");
        AssertHostDetection(@{@"com.apple.dock": NSNull.null, @"com.apple.WindowManager": @[@"mc.display"]},
                            YES, NO, @"Dock accessibility failure does not hide WindowManager");
        AssertHostDetection(@{@"com.apple.dock": @[], @"com.apple.WindowManager": @[@"appexpose.display"]},
                            NO, NO, @"App Exposé is not Mission Control");
        AssertHostDetection(@{@"com.apple.dock": NSNull.null, @"com.apple.WindowManager": NSNull.null},
                            YES, YES, @"window fallback remains available when neither host is readable");
        method_setImplementation(lookup, originalLookup);

        NSLog(@"MissionControlDetectorTests passed");
    }
    return EXIT_SUCCESS;
}
