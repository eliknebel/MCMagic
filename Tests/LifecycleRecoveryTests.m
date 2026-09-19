#import <Foundation/Foundation.h>

#import "LifecycleRecovery.h"

static void AssertAction(MCMagicLifecycleEvent event,
                         BOOL enabled,
                         BOOL sleeping,
                         MCMagicLifecycleAction expected,
                         NSString *scenario) {
    MCMagicLifecycleAction actual = MCMagicLifecycleActionForEvent(event, enabled, sleeping);
    if (actual != expected) {
        NSLog(@"FAIL: %@ (expected %ld, got %ld)", scenario, (long)expected, (long)actual);
        exit(EXIT_FAILURE);
    }
}

static void AssertProduct(NSString *productName, BOOL expected, NSString *scenario) {
    BOOL actual = MCMagicProductNameIsMagicMouse(productName);
    if (actual != expected) {
        NSLog(@"FAIL: %@ (expected %@, got %@)",
              scenario,
              expected ? @"Magic Mouse" : @"other device",
              actual ? @"Magic Mouse" : @"other device");
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        AssertAction(
            MCMagicLifecycleEventWillSleep,
            YES,
            NO,
            MCMagicLifecycleActionStopMonitor,
            @"sleep stops active monitoring"
        );
        AssertAction(
            MCMagicLifecycleEventDidWake,
            YES,
            NO,
            MCMagicLifecycleActionRestartMonitor,
            @"wake rebuilds active monitoring"
        );
        AssertAction(
            MCMagicLifecycleEventScreenDidWake,
            YES,
            NO,
            MCMagicLifecycleActionRestartMonitor,
            @"display wake rebuilds active monitoring"
        );
        AssertAction(
            MCMagicLifecycleEventSessionDidBecomeActive,
            YES,
            NO,
            MCMagicLifecycleActionRestartMonitor,
            @"session reactivation rebuilds active monitoring"
        );
        AssertAction(
            MCMagicLifecycleEventMagicMouseChanged,
            YES,
            NO,
            MCMagicLifecycleActionRestartMonitor,
            @"mouse connection change rebuilds active monitoring"
        );
        AssertAction(
            MCMagicLifecycleEventMagicMouseChanged,
            YES,
            YES,
            MCMagicLifecycleActionNone,
            @"mouse changes do not restart while the system sleeps"
        );
        AssertAction(
            MCMagicLifecycleEventDidWake,
            NO,
            NO,
            MCMagicLifecycleActionNone,
            @"disabled utility remains stopped after wake"
        );

        AssertProduct(@"Magic Mouse", YES, @"Apple Magic Mouse product name");
        AssertProduct(@"Magic Mouse 2", YES, @"versioned Magic Mouse product name");
        AssertProduct(@"Multitouch Mouse", YES, @"private multitouch product name");
        AssertProduct(@"Magic Trackpad", NO, @"Magic Trackpad exclusion");
        AssertProduct(@"USB Optical Mouse", NO, @"ordinary mouse exclusion");

        if (!MCMagicHIDPropertiesIndicateMagicMouse(@"", @"Bluetooth", 76)) {
            NSLog(@"FAIL: unnamed Apple Bluetooth mouse should match live Magic Mouse HID data");
            return EXIT_FAILURE;
        }
        if (MCMagicHIDPropertiesIndicateMagicMouse(@"Magic Trackpad", @"Bluetooth", 76)) {
            NSLog(@"FAIL: named Magic Trackpad should remain excluded");
            return EXIT_FAILURE;
        }
        if (MCMagicHIDPropertiesIndicateMagicMouse(@"", @"Bluetooth", 1234)) {
            NSLog(@"FAIL: unnamed non-Apple Bluetooth mouse should remain excluded");
            return EXIT_FAILURE;
        }

        NSLog(@"LifecycleRecoveryTests passed");
    }
    return EXIT_SUCCESS;
}
