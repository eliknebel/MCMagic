#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Evaluates a Core Graphics window list for the Dock window combination that
/// identifies Mission Control while excluding Launchpad and Finder Dock stacks.
FOUNDATION_EXPORT BOOL MCMagicWindowListIndicatesMissionControl(
    NSArray<NSDictionary<NSString *, id> *> *windows
);

/// Evaluates the accessibility identifiers exposed by the Dock. Mission
/// Control contributes a child whose identifier is "mc" while it is visible.
FOUNDATION_EXPORT BOOL MCMagicAccessibilityIdentifiersIndicateMissionControl(
    NSArray<NSString *> *identifiers
);

/// Returns whether Mission Control is currently visible.
FOUNDATION_EXPORT BOOL MCMagicIsMissionControlActive(void);

NS_ASSUME_NONNULL_END
