#import <Foundation/Foundation.h>

#import "SwipeGestureRouter.h"

NS_ASSUME_NONNULL_BEGIN

/// Recognizes two-finger Mission Control gestures on a Magic Mouse and consumes
/// the corresponding scroll events before they reach the application under the cursor.
@interface GestureMonitor : NSObject

@property (class, nonatomic, readonly) GestureMonitor *sharedMonitor;
@property (atomic, readonly, getter=isRunning) BOOL running;
@property (atomic) MCMagicDirectionPreference activationDirection;
@property (atomic) MCMagicDirectionPreference dismissalDirection;

- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
