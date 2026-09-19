#import <Foundation/Foundation.h>

#import "SwipeGestureClassifier.h"

static void AssertDirection(float deltaX,
                            float deltaY,
                            NSTimeInterval duration,
                            MCMagicGestureDirection expected,
                            NSString *scenario) {
    MCMagicGestureDirection actual = MCMagicClassifyGesture(deltaX, deltaY, duration);
    if (actual != expected) {
        NSLog(@"FAIL: %@ (expected %ld, got %ld)", scenario, (long)expected, (long)actual);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        AssertDirection(0.01f, 0.11f, 0.2, MCMagicGestureDirectionUp, @"vertical swipe up");
        AssertDirection(0.01f, -0.11f, 0.2, MCMagicGestureDirectionDown, @"vertical swipe down");
        AssertDirection(0.11f, 0.01f, 0.2, MCMagicGestureDirectionRejected, @"horizontal swipe");
        AssertDirection(0.11f, 0.11f, 0.2, MCMagicGestureDirectionRejected, @"diagonal swipe");
        AssertDirection(0.01f, 0.11f, 0.9, MCMagicGestureDirectionRejected, @"slow swipe");
        AssertDirection(0.01f, 0.05f, 0.2, MCMagicGestureDirectionUndetermined, @"small movement");

        NSLog(@"SwipeGestureClassifierTests passed");
    }
    return EXIT_SUCCESS;
}
