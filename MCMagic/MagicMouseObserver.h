#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MCMagicMagicMouseChangeHandler)(void);

/// Observes matching HID devices so the gesture monitor can rebuild stale
/// MultitouchSupport registrations after a mouse disconnects or reconnects.
@interface MagicMouseObserver : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithChangeHandler:(MCMagicMagicMouseChangeHandler)changeHandler
    NS_DESIGNATED_INITIALIZER;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
