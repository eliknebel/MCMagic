#import <Foundation/Foundation.h>

#import "SwipeGestureRouter.h"

static void AssertAction(MCMagicGestureDirection gestureDirection,
                         BOOL missionControlIsActive,
                         MCMagicDirectionPreference activationDirection,
                         MCMagicDirectionPreference dismissalDirection,
                         MCMagicGestureAction expected,
                         NSString *scenario) {
    MCMagicGestureAction actual = MCMagicActionForGesture(
        gestureDirection,
        missionControlIsActive,
        activationDirection,
        dismissalDirection
    );
    if (actual != expected) {
        NSLog(@"FAIL: %@ (expected %ld, got %ld)", scenario, (long)expected, (long)actual);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        AssertAction(
            MCMagicGestureDirectionUp,
            NO,
            MCMagicDirectionPreferenceUp,
            MCMagicDirectionPreferenceDown,
            MCMagicGestureActionActivateMissionControl,
            @"up activates for the Up preference"
        );
        AssertAction(
            MCMagicGestureDirectionDown,
            NO,
            MCMagicDirectionPreferenceUp,
            MCMagicDirectionPreferenceBoth,
            MCMagicGestureActionIgnore,
            @"down is ignored for the Up activation preference"
        );
        AssertAction(
            MCMagicGestureDirectionDown,
            NO,
            MCMagicDirectionPreferenceDown,
            MCMagicDirectionPreferenceUp,
            MCMagicGestureActionActivateMissionControl,
            @"down activates for the Down preference"
        );
        AssertAction(
            MCMagicGestureDirectionUp,
            NO,
            MCMagicDirectionPreferenceDown,
            MCMagicDirectionPreferenceBoth,
            MCMagicGestureActionIgnore,
            @"up is ignored for the Down activation preference"
        );
        AssertAction(
            MCMagicGestureDirectionUp,
            NO,
            MCMagicDirectionPreferenceBoth,
            MCMagicDirectionPreferenceDown,
            MCMagicGestureActionActivateMissionControl,
            @"up activates for the Both preference"
        );
        AssertAction(
            MCMagicGestureDirectionDown,
            NO,
            MCMagicDirectionPreferenceBoth,
            MCMagicDirectionPreferenceUp,
            MCMagicGestureActionActivateMissionControl,
            @"down activates for the Both preference"
        );

        AssertAction(
            MCMagicGestureDirectionUp,
            YES,
            MCMagicDirectionPreferenceDown,
            MCMagicDirectionPreferenceUp,
            MCMagicGestureActionDismissMissionControl,
            @"up dismisses for the Up preference"
        );
        AssertAction(
            MCMagicGestureDirectionDown,
            YES,
            MCMagicDirectionPreferenceBoth,
            MCMagicDirectionPreferenceUp,
            MCMagicGestureActionConsume,
            @"down is consumed for the Up preference"
        );

        AssertAction(
            MCMagicGestureDirectionDown,
            YES,
            MCMagicDirectionPreferenceUp,
            MCMagicDirectionPreferenceDown,
            MCMagicGestureActionDismissMissionControl,
            @"down dismisses for the Down preference"
        );
        AssertAction(
            MCMagicGestureDirectionUp,
            YES,
            MCMagicDirectionPreferenceBoth,
            MCMagicDirectionPreferenceDown,
            MCMagicGestureActionConsume,
            @"up is consumed for the Down preference"
        );

        AssertAction(
            MCMagicGestureDirectionUp,
            YES,
            MCMagicDirectionPreferenceDown,
            MCMagicDirectionPreferenceBoth,
            MCMagicGestureActionDismissMissionControl,
            @"up dismisses for the Both preference"
        );
        AssertAction(
            MCMagicGestureDirectionDown,
            YES,
            MCMagicDirectionPreferenceUp,
            MCMagicDirectionPreferenceBoth,
            MCMagicGestureActionDismissMissionControl,
            @"down dismisses for the Both preference"
        );

        NSLog(@"SwipeGestureRouterTests passed");
    }
    return EXIT_SUCCESS;
}
