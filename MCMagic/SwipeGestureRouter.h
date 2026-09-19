#import <Foundation/Foundation.h>

#import "SwipeGestureClassifier.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MCMagicDirectionPreference) {
    MCMagicDirectionPreferenceUp,
    MCMagicDirectionPreferenceDown,
    MCMagicDirectionPreferenceBoth,
};

typedef NS_ENUM(NSInteger, MCMagicGestureAction) {
    MCMagicGestureActionIgnore,
    MCMagicGestureActionConsume,
    MCMagicGestureActionActivateMissionControl,
    MCMagicGestureActionDismissMissionControl,
};

FOUNDATION_EXPORT MCMagicGestureAction MCMagicActionForGesture(
    MCMagicGestureDirection gestureDirection,
    BOOL missionControlIsActive,
    MCMagicDirectionPreference activationDirection,
    MCMagicDirectionPreference dismissalDirection
);

NS_ASSUME_NONNULL_END
