#import "MissionControlDetector.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

static const NSInteger MissionControlOverlayLayer = 20;
static const NSInteger DockBarMaximumLayer = 18;

BOOL MCMagicAccessibilityIdentifiersIndicateMissionControl(
    NSArray<NSString *> *identifiers
) {
    return [identifiers containsObject:@"mc"]
        || [identifiers containsObject:@"mc.display"];
}

static BOOL MCMagicTryAccessibilityDetection(NSString *bundleIdentifier, BOOL *detectionAvailable) {
    *detectionAvailable = NO;

    NSRunningApplication *application = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:bundleIdentifier].firstObject;
    if (application == nil) {
        return NO;
    }

    AXUIElementRef applicationElement = AXUIElementCreateApplication(application.processIdentifier);
    if (applicationElement == NULL) {
        return NO;
    }

    CFTypeRef childrenValue = NULL;
    AXError childrenError = AXUIElementCopyAttributeValue(
        applicationElement,
        kAXChildrenAttribute,
        &childrenValue
    );
    CFRelease(applicationElement);

    if (childrenError != kAXErrorSuccess
        || childrenValue == NULL
        || CFGetTypeID(childrenValue) != CFArrayGetTypeID()) {
        if (childrenValue != NULL) {
            CFRelease(childrenValue);
        }
        return NO;
    }

    *detectionAvailable = YES;
    NSArray *children = CFBridgingRelease(childrenValue);
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

    for (id child in children) {
        AXUIElementRef childElement = (__bridge AXUIElementRef)child;
        CFTypeRef identifierValue = NULL;
        AXError identifierError = AXUIElementCopyAttributeValue(
            childElement,
            kAXIdentifierAttribute,
            &identifierValue
        );
        if (identifierError == kAXErrorSuccess && identifierValue != NULL) {
            if (CFGetTypeID(identifierValue) == CFStringGetTypeID()) {
                [identifiers addObject:(__bridge NSString *)identifierValue];
            }
            CFRelease(identifierValue);
        }
    }

    return MCMagicAccessibilityIdentifiersIndicateMissionControl(identifiers);
}

BOOL MCMagicWindowListIndicatesMissionControl(
    NSArray<NSDictionary<NSString *, id> *> *windows
) {
    BOOL hasMissionControlOverlay = NO;
    BOOL hasDockBar = NO;

    for (NSDictionary<NSString *, id> *window in windows) {
        NSString *ownerName = window[(__bridge NSString *)kCGWindowOwnerName];
        if (![ownerName isEqualToString:@"Dock"]) {
            continue;
        }

        NSString *windowName = window[(__bridge NSString *)kCGWindowName];
        if (windowName.length > 0) {
            continue;
        }

        NSInteger layer = [window[(__bridge NSString *)kCGWindowLayer] integerValue];
        hasMissionControlOverlay |= layer == MissionControlOverlayLayer;
        hasDockBar |= layer <= DockBarMaximumLayer;

        if (hasMissionControlOverlay && hasDockBar) {
            return YES;
        }
    }

    return NO;
}

BOOL MCMagicIsMissionControlActive(void) {
    BOOL accessibilityDetectionAvailable = NO;
    // Newer macOS versions expose Mission Control through WindowManager rather
    // than the Dock. A readable Dock without "mc" must not hide that result.
    for (NSString *bundleIdentifier in @[@"com.apple.dock", @"com.apple.WindowManager"]) {
        BOOL available = NO;
        if (MCMagicTryAccessibilityDetection(bundleIdentifier, &available)) {
            return YES;
        }
        accessibilityDetectionAvailable |= available;
    }
    if (accessibilityDetectionAvailable) {
        return NO;
    }

    // Retain the window-list heuristic as a fallback when Accessibility is
    // unavailable or neither host's accessibility tree can be queried.
    CFArrayRef windowInfo = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowInfo == NULL) {
        return NO;
    }

    NSArray<NSDictionary<NSString *, id> *> *windows = CFBridgingRelease(windowInfo);
    return MCMagicWindowListIndicatesMissionControl(windows);
}
