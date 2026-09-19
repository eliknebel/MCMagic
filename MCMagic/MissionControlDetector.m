#import "MissionControlDetector.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>

static const NSInteger MissionControlOverlayLayer = 20;
static const NSInteger DockBarMaximumLayer = 18;

BOOL MCMagicAccessibilityIdentifiersIndicateMissionControl(
    NSArray<NSString *> *identifiers
) {
    return [identifiers containsObject:@"mc"];
}

static BOOL MCMagicTryAccessibilityDetection(BOOL *detectionAvailable) {
    *detectionAvailable = NO;

    NSRunningApplication *dock = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:@"com.apple.dock"].firstObject;
    if (dock == nil) {
        return NO;
    }

    AXUIElementRef dockElement = AXUIElementCreateApplication(dock.processIdentifier);
    if (dockElement == NULL) {
        return NO;
    }

    CFTypeRef childrenValue = NULL;
    AXError childrenError = AXUIElementCopyAttributeValue(
        dockElement,
        kAXChildrenAttribute,
        &childrenValue
    );
    CFRelease(dockElement);

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
    BOOL accessibilityDetection = MCMagicTryAccessibilityDetection(
        &accessibilityDetectionAvailable
    );
    if (accessibilityDetectionAvailable) {
        return accessibilityDetection;
    }

    // Retain the window-list heuristic as a fallback when Accessibility is
    // unavailable or the Dock's accessibility tree cannot be queried.
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
