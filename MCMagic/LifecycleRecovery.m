#import "LifecycleRecovery.h"

MCMagicLifecycleAction MCMagicLifecycleActionForEvent(
    MCMagicLifecycleEvent event,
    BOOL utilityEnabled,
    BOOL systemSleeping
) {
    if (!utilityEnabled) {
        return MCMagicLifecycleActionNone;
    }

    if (event == MCMagicLifecycleEventWillSleep) {
        return MCMagicLifecycleActionStopMonitor;
    }

    if (systemSleeping) {
        return MCMagicLifecycleActionNone;
    }

    switch (event) {
        case MCMagicLifecycleEventDidWake:
        case MCMagicLifecycleEventScreenDidWake:
        case MCMagicLifecycleEventSessionDidBecomeActive:
        case MCMagicLifecycleEventMagicMouseChanged:
            return MCMagicLifecycleActionRestartMonitor;
        case MCMagicLifecycleEventWillSleep:
            return MCMagicLifecycleActionStopMonitor;
    }

    return MCMagicLifecycleActionNone;
}

BOOL MCMagicProductNameIsMagicMouse(NSString *productName) {
    return [productName localizedCaseInsensitiveContainsString:@"Magic Mouse"]
        || [productName localizedCaseInsensitiveContainsString:@"Multitouch Mouse"];
}

BOOL MCMagicHIDPropertiesIndicateMagicMouse(
    NSString *productName,
    NSString *transport,
    NSInteger vendorID
) {
    if (productName.length > 0) {
        return MCMagicProductNameIsMagicMouse(productName);
    }

    static const NSInteger AppleVendorID = 76;
    return vendorID == AppleVendorID
        && [transport caseInsensitiveCompare:@"Bluetooth"] == NSOrderedSame;
}
