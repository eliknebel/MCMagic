#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MCMagicLifecycleEvent) {
    MCMagicLifecycleEventWillSleep,
    MCMagicLifecycleEventDidWake,
    MCMagicLifecycleEventScreenDidWake,
    MCMagicLifecycleEventSessionDidBecomeActive,
    MCMagicLifecycleEventMagicMouseChanged,
};

typedef NS_ENUM(NSInteger, MCMagicLifecycleAction) {
    MCMagicLifecycleActionNone,
    MCMagicLifecycleActionStopMonitor,
    MCMagicLifecycleActionRestartMonitor,
};

FOUNDATION_EXPORT MCMagicLifecycleAction MCMagicLifecycleActionForEvent(
    MCMagicLifecycleEvent event,
    BOOL utilityEnabled,
    BOOL systemSleeping
);

FOUNDATION_EXPORT BOOL MCMagicProductNameIsMagicMouse(NSString * _Nullable productName);

FOUNDATION_EXPORT BOOL MCMagicHIDPropertiesIndicateMagicMouse(
    NSString * _Nullable productName,
    NSString * _Nullable transport,
    NSInteger vendorID
);

NS_ASSUME_NONNULL_END
