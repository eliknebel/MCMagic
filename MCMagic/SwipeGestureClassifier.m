#import "SwipeGestureClassifier.h"

static const float SwipeDistanceThreshold = 0.105f;
static const float VerticalDominanceRatio = 1.25f;
static const NSTimeInterval MaximumSwipeDuration = 0.85;

MCMagicGestureDirection MCMagicClassifyGesture(
    float deltaX,
    float deltaY,
    NSTimeInterval duration
) {
    if (duration > MaximumSwipeDuration) {
        return MCMagicGestureDirectionRejected;
    }

    if (deltaY >= SwipeDistanceThreshold && deltaY > fabsf(deltaX) * VerticalDominanceRatio) {
        return MCMagicGestureDirectionUp;
    }

    if (deltaY <= -SwipeDistanceThreshold && -deltaY > fabsf(deltaX) * VerticalDominanceRatio) {
        return MCMagicGestureDirectionDown;
    }

    if (fabsf(deltaX) >= SwipeDistanceThreshold) {
        return MCMagicGestureDirectionRejected;
    }

    return MCMagicGestureDirectionUndetermined;
}
