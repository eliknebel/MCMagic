#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MCMagicGestureDirection) {
    MCMagicGestureDirectionUndetermined,
    MCMagicGestureDirectionUp,
    MCMagicGestureDirectionDown,
    MCMagicGestureDirectionRejected,
};

/// Classifies the displacement and duration of an exact two-finger gesture.
FOUNDATION_EXPORT MCMagicGestureDirection MCMagicClassifyGesture(
    float deltaX,
    float deltaY,
    NSTimeInterval duration
);
