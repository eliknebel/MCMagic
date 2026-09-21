#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "GestureMonitor.h"
#import "MultitouchTypes.h"
#import "MissionControlDetector.h"

// Exercise the real touch classifier, router, and scroll filter without opening
// devices, requesting permissions, querying the Dock, or posting keyboard input.
@interface GestureMonitor (ScrollTests)
- (void)handleTouches:(MTTouch *)touches count:(size_t)count timestamp:(double)timestamp;
- (BOOL)shouldSuppressScrollEvent:(CGEventRef)event;
- (void)activateMissionControl;
- (void)dismissMissionControl;
- (void)toggleMissionControl;
- (void)postKey:(CGKeyCode)keyCode flags:(CGEventFlags)flags;
@end

@interface TestGestureMonitor : GestureMonitor
@end

@implementation TestGestureMonitor
- (void)activateMissionControl {}
- (void)dismissMissionControl {}
@end

// Run the real activation/dismissal methods, recording their external effects.
// In particular, the old Escape path must never send input to the test desktop.
@interface TestMissionControlActions : GestureMonitor
@property(nonatomic) NSUInteger toggleCount;
@property(nonatomic) NSUInteger keyCount;
@property(nonatomic) CGKeyCode lastKeyCode;
@property(nonatomic) CGEventFlags lastKeyFlags;
@end

@implementation TestMissionControlActions
- (void)toggleMissionControl { self.toggleCount++; }
- (void)postKey:(CGKeyCode)keyCode flags:(CGEventFlags)flags {
    self.keyCount++;
    self.lastKeyCode = keyCode;
    self.lastKeyFlags = flags;
}
@end

static BOOL missionControlActive = YES;
static NSUInteger failures = 0;

BOOL MCMagicIsMissionControlActive(void) {
    return missionControlActive;
}

static GestureMonitor *NewMonitor(void) {
    GestureMonitor *monitor = [[TestGestureMonitor alloc] init];
    // Bypass startWithError:, which opens physical devices and an event tap.
    [monitor setValue:@YES forKey:@"running"];
    return monitor;
}

static void Touches(GestureMonitor *monitor, size_t count, float x, float y, double time) {
    MTTouch touches[2] = {0};
    for (size_t index = 0; index < count; index++) {
        touches[index].state = 4;
        touches[index].normalizedVector.position.x = x;
        touches[index].normalizedVector.position.y = y;
    }
    [monitor handleTouches:touches count:count timestamp:time];
}

static void AssertScroll(GestureMonitor *monitor,
                         CGScrollPhase phase,
                         CGMomentumScrollPhase momentum,
                         BOOL continuous,
                         BOOL expectedSuppression,
                         NSString *scenario) {
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, 10);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, continuous);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, phase);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventMomentumPhase, momentum);
    BOOL actual = [monitor shouldSuppressScrollEvent:event];
    CFRelease(event);
    if (actual != expectedSuppression) {
        NSLog(@"FAIL: %@ (expected %@, got %@)", scenario,
              expectedSuppression ? @"suppressed" : @"allowed",
              actual ? @"suppressed" : @"allowed");
        failures++;
    }
}

static void BeginDismissal(GestureMonitor *monitor) {
    missionControlActive = YES;
    Touches(monitor, 2, 0.5, 0.5, 1.0);
    AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, YES,
                 @"candidate scroll is suppressed before recognition");
    Touches(monitor, 2, 0.5, 0.35, 1.1);
    AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, YES,
                 @"recognized dismissal consumes direct scrolling");
}

static void AssertDismissal(BOOL active, BOOL running, BOOL selectHoveredWindow,
                            NSUInteger expectedToggles, NSUInteger expectedKeys,
                            NSString *scenario) {
    TestMissionControlActions *monitor = [[TestMissionControlActions alloc] init];
    [monitor setValue:@(running) forKey:@"running"];
    monitor.selectHoveredWindowOnDismiss = selectHoveredWindow;
    missionControlActive = active;
    [monitor dismissMissionControl];
    if (monitor.toggleCount != expectedToggles || monitor.keyCount != expectedKeys
        || (expectedKeys > 0 && (monitor.lastKeyCode != 53 || monitor.lastKeyFlags != 0))) {
        NSLog(@"FAIL: %@ (toggles: %lu, direct key events: %lu)", scenario,
              (unsigned long)monitor.toggleCount, (unsigned long)monitor.keyCount);
        failures++;
    }
    [monitor stop];
}

int main(void) {
    @autoreleasepool {
        AssertDismissal(YES, YES, YES, 1, 0,
                        @"dismissal uses native selection-preserving toggle instead of Escape");
        AssertDismissal(NO, YES, YES, 0, 0,
                        @"Mission Control closed before queued dismissal must not reopen");
        AssertDismissal(YES, NO, YES, 0, 0,
                        @"stopped monitoring must discard queued dismissal");
        AssertDismissal(YES, YES, NO, 0, 1,
                        @"unchecked preference dismisses with Escape and preserves the previous window");
        AssertDismissal(NO, YES, NO, 0, 0,
                        @"unchecked preference must not send Escape to an ordinary app");
        AssertDismissal(YES, NO, NO, 0, 0,
                        @"stopped monitoring must not send Escape");

        GestureMonitor *monitor = NewMonitor();
        BeginDismissal(monitor);
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, kCGScrollPhaseEnded, kCGMomentumScrollPhaseNone, YES, YES,
                     @"scroll end arriving after finger lift belongs to dismissal");
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, YES,
                     @"dismissal momentum begins suppressed");
        // Specifically exceeds the former 700 ms blanket suppression interval.
        [NSThread sleepForTimeInterval:0.80];
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseContinue, YES, YES,
                     @"momentum remains suppressed after the old timeout");
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseEnd, YES, YES,
                     @"terminal momentum event is consumed too");
        AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, NO,
                     @"normal scrolling resumes after momentum finishes");
        [monitor stop];

        monitor = NewMonitor();
        BeginDismissal(monitor);
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, kCGScrollPhaseEnded, kCGMomentumScrollPhaseNone, YES, YES,
                     @"physical end does not release pending momentum");
        Touches(monitor, 1, 0.5, 0.5, 1.21);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseContinue, YES, YES,
                     @"new contact alone does not leak an old queued momentum event");
        AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, NO,
                     @"fresh scroll begins immediately even without old momentum end");
        AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, NO,
                     @"fresh scroll continues without a cooldown");
        AssertScroll(monitor, kCGScrollPhaseEnded, kCGMomentumScrollPhaseNone, YES, NO,
                     @"fresh scroll ends normally");
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, NO,
                     @"fresh scroll keeps its own momentum");
        [monitor stop];

        monitor = NewMonitor();
        BeginDismissal(monitor);
        Touches(monitor, 1, 0.5, 0.3, 1.2);
        [NSThread sleepForTimeInterval:0.80];
        AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, YES,
                     @"lifting one finger does not release a consumed gesture");
        Touches(monitor, 2, 0.5, 0.25, 1.3);
        AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, YES,
                     @"putting a finger back does not restart the consumed gesture");
        Touches(monitor, 0, 0, 0, 1.4);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, YES,
                     @"staggered lifts still consume following momentum");
        [monitor stop];

        monitor = NewMonitor();
        BeginDismissal(monitor);
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseNone, NO, NO,
                     @"unrelated discrete wheel events are not held behind a cooldown");
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseContinue, YES, YES,
                     @"a discrete wheel event does not release old gesture momentum");
        AssertScroll(monitor, kCGScrollPhaseCancelled, kCGMomentumScrollPhaseNone, YES, YES,
                     @"cancellation event closes the consumed scroll");
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, NO,
                     @"cancelled sequence does not leave momentum suppression armed");
        [monitor stop];

        monitor = NewMonitor();
        missionControlActive = NO;
        Touches(monitor, 2, 0.5, 0.5, 1.0);
        Touches(monitor, 2, 0.7, 0.5, 1.1);
        AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, NO,
                     @"rejected horizontal gesture remains ordinary scrolling");
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, NO,
                     @"rejected gesture retains normal momentum");
        [monitor stop];

        monitor = NewMonitor();
        BeginDismissal(monitor);
        AssertScroll(monitor, kCGScrollPhaseEnded, kCGMomentumScrollPhaseNone, YES, YES,
                     @"native scroll end can precede the final touch callback");
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, YES,
                     @"touch lift after native end still preserves momentum suppression");
        Touches(monitor, 2, 0.5, 0.5, 1.3);
        AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, YES,
                     @"a fresh two-finger candidate is classified independently");
        Touches(monitor, 2, 0.7, 0.5, 1.4);
        AssertScroll(monitor, kCGScrollPhaseChanged, kCGMomentumScrollPhaseNone, YES, NO,
                     @"rejecting the fresh candidate allows scrolling immediately");
        Touches(monitor, 0, 0, 0, 1.5);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, NO,
                     @"fresh rejected gesture does not inherit dismissal suppression");
        [monitor stop];

        monitor = NewMonitor();
        missionControlActive = NO;
        Touches(monitor, 2, 0.5, 0.5, 1.0);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseContinue, YES, NO,
                     @"a candidate does not swallow previous ordinary scroll momentum");
        AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, YES,
                     @"activation candidate consumes its own scroll begin");
        Touches(monitor, 2, 0.5, 0.65, 1.1);
        Touches(monitor, 0, 0, 0, 1.2);
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, YES,
                     @"activation gestures also consume their momentum");
        AssertScroll(monitor, kCGScrollPhaseBegan, kCGMomentumScrollPhaseNone, YES, NO,
                     @"activation does not delay fresh scrolling either");
        [monitor stop];

        monitor = NewMonitor();
        BeginDismissal(monitor);
        [monitor stop];
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseContinue, YES, NO,
                     @"stopped monitoring never suppresses scrolling");
        [monitor setValue:@YES forKey:@"running"];
        AssertScroll(monitor, 0, kCGMomentumScrollPhaseBegin, YES, NO,
                     @"stop clears suppression before monitoring resumes");
        [monitor stop];

        if (failures > 0) {
            NSLog(@"GestureMonitorScrollTests: %lu failures", (unsigned long)failures);
            return EXIT_FAILURE;
        }
        NSLog(@"GestureMonitorScrollTests passed");
    }
    return EXIT_SUCCESS;
}
