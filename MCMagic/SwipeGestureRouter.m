#import "SwipeGestureRouter.h"

static BOOL MCMagicPreferenceIncludesDirection(
    MCMagicDirectionPreference preference,
    MCMagicGestureDirection direction
) {
    if (preference == MCMagicDirectionPreferenceBoth) {
        return direction == MCMagicGestureDirectionUp
            || direction == MCMagicGestureDirectionDown;
    }

    return (preference == MCMagicDirectionPreferenceUp
            && direction == MCMagicGestureDirectionUp)
        || (preference == MCMagicDirectionPreferenceDown
            && direction == MCMagicGestureDirectionDown);
}

MCMagicGestureAction MCMagicActionForGesture(
    MCMagicGestureDirection gestureDirection,
    BOOL missionControlIsActive,
    MCMagicDirectionPreference activationDirection,
    MCMagicDirectionPreference dismissalDirection
) {
    if (!missionControlIsActive) {
        return MCMagicPreferenceIncludesDirection(activationDirection, gestureDirection)
            ? MCMagicGestureActionActivateMissionControl
            : MCMagicGestureActionIgnore;
    }

    if (gestureDirection == MCMagicGestureDirectionUp
        || gestureDirection == MCMagicGestureDirectionDown) {
        return MCMagicPreferenceIncludesDirection(dismissalDirection, gestureDirection)
            ? MCMagicGestureActionDismissMissionControl
            : MCMagicGestureActionConsume;
    }

    return MCMagicGestureActionIgnore;
}
