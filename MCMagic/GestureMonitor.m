#import "GestureMonitor.h"
#import "MultitouchTypes.h"
#import "MissionControlDetector.h"
#import "SwipeGestureClassifier.h"
#import "SwipeGestureRouter.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDDeviceKeys.h>
#import <dlfcn.h>
#import <os/lock.h>

typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch *, size_t, double, size_t, void *);
typedef CFArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterCallbackFunction)(MTDeviceRef, MTFrameCallback, void *);
typedef void (*MTUnregisterCallbackFunction)(MTDeviceRef, MTFrameCallback);
typedef int32_t (*MTDeviceStartFunction)(MTDeviceRef, int32_t);
typedef int32_t (*MTDeviceStopFunction)(MTDeviceRef);
typedef bool (*MTDeviceIsBuiltInFunction)(MTDeviceRef);
typedef int32_t (*MTDeviceDimensionsFunction)(MTDeviceRef, int *, int *);
typedef io_service_t (*MTDeviceGetServiceFunction)(MTDeviceRef);
typedef void (*CoreDockSendNotificationFunction)(CFStringRef);

typedef NS_ENUM(uint8_t, SwipeState) {
    SwipeStateIdle,
    SwipeStateCandidate,
    SwipeStateRejected,
    SwipeStateTriggered,
};

static NSString *const GestureMonitorErrorDomain = @"com.bitbldr.MCMagic.GestureMonitor";

@interface GestureMonitor () {
    void *_multitouchFramework;
    MTUnregisterCallbackFunction _unregisterCallback;
    MTDeviceStopFunction _stopDevice;
    NSMutableArray<NSValue *> *_devices;

    CFMachPortRef _eventTap;
    CFRunLoopSourceRef _eventTapSource;

    os_unfair_lock _stateLock;
    SwipeState _swipeState;
    float _originX;
    float _originY;
    double _gestureStartTime;
    BOOL _suppressScrollSequence;
    BOOL _suppressMomentum;
    BOOL _running;
}

- (BOOL)isMagicMouse:(MTDeviceRef)device
            isBuiltIn:(MTDeviceIsBuiltInFunction)isBuiltIn
         getDimensions:(MTDeviceDimensionsFunction)getDimensions
             getService:(MTDeviceGetServiceFunction)getService;
- (void)handleTouches:(MTTouch *)touches count:(size_t)touchCount timestamp:(double)timestamp;
- (BOOL)shouldSuppressScrollEvent:(CGEventRef)event;
- (void)activateMissionControl;
- (void)dismissMissionControl;
- (void)toggleMissionControl;
- (void)postKey:(CGKeyCode)keyCode flags:(CGEventFlags)flags;
- (void)reenableEventTap;
- (void)releaseDevices;
- (void)closeFramework;
- (void)setError:(NSError **)error code:(NSInteger)code description:(NSString *)description;
@end

static void contactFrameCallback(MTDeviceRef device,
                                 MTTouch *touches,
                                 size_t touchCount,
                                 double timestamp,
                                 size_t frame,
                                 void *context);

static CGEventRef eventTapCallback(CGEventTapProxy proxy,
                                   CGEventType type,
                                   CGEventRef event,
                                   void *context);

@implementation GestureMonitor

+ (GestureMonitor *)sharedMonitor {
    static GestureMonitor *monitor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        monitor = [[GestureMonitor alloc] init];
    });
    return monitor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _devices = [NSMutableArray array];
        _stateLock = OS_UNFAIR_LOCK_INIT;
        _swipeState = SwipeStateIdle;
        _activationDirection = MCMagicDirectionPreferenceUp;
        _dismissalDirection = MCMagicDirectionPreferenceDown;
        _selectHoveredWindowOnDismiss = YES;
    }
    return self;
}

- (BOOL)isRunning {
    os_unfair_lock_lock(&_stateLock);
    BOOL running = _running;
    os_unfair_lock_unlock(&_stateLock);
    return running;
}

- (BOOL)startWithError:(NSError **)error {
    NSAssert([NSThread isMainThread], @"GestureMonitor must be started on the main thread");
    if (self.isRunning) {
        return YES;
    }

    _multitouchFramework = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW | RTLD_LOCAL
    );
    if (_multitouchFramework == NULL) {
        [self setError:error code:1 description:@"The private multitouch framework could not be loaded."];
        return NO;
    }

    MTDeviceCreateListFunction createDeviceList = dlsym(_multitouchFramework, "MTDeviceCreateList");
    MTRegisterCallbackFunction registerCallback = dlsym(
        _multitouchFramework,
        "MTRegisterContactFrameCallbackWithRefcon"
    );
    MTDeviceStartFunction startDevice = dlsym(_multitouchFramework, "MTDeviceStart");
    _stopDevice = dlsym(_multitouchFramework, "MTDeviceStop");
    _unregisterCallback = dlsym(_multitouchFramework, "MTUnregisterContactFrameCallback");
    MTDeviceIsBuiltInFunction isBuiltIn = dlsym(_multitouchFramework, "MTDeviceIsBuiltIn");
    MTDeviceDimensionsFunction getDimensions = dlsym(
        _multitouchFramework,
        "MTDeviceGetSensorSurfaceDimensions"
    );
    MTDeviceGetServiceFunction getService = dlsym(_multitouchFramework, "MTDeviceGetService");

    if (createDeviceList == NULL || registerCallback == NULL || startDevice == NULL || _stopDevice == NULL) {
        [self setError:error code:2 description:@"The multitouch framework is missing required functions."];
        [self closeFramework];
        return NO;
    }

    CFArrayRef allDevices = createDeviceList();
    if (allDevices == NULL) {
        [self setError:error code:3 description:@"No multitouch devices are available."];
        [self closeFramework];
        return NO;
    }

    CFIndex deviceCount = CFArrayGetCount(allDevices);
    for (CFIndex index = 0; index < deviceCount; index++) {
        MTDeviceRef device = CFArrayGetValueAtIndex(allDevices, index);
        if (![self isMagicMouse:device
                    isBuiltIn:isBuiltIn
                 getDimensions:getDimensions
                     getService:getService]) {
            continue;
        }

        CFRetain(device);
        [_devices addObject:[NSValue valueWithPointer:device]];
    }
    CFRelease(allDevices);

    if (_devices.count == 0) {
        [self setError:error code:4 description:@"No connected Magic Mouse was found."];
        [self closeFramework];
        return NO;
    }

    CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel);
    _eventTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        eventTapCallback,
        (__bridge void *)self
    );
    if (_eventTap == NULL) {
        [self releaseDevices];
        [self setError:error
                  code:5
           description:@"Accessibility permission is required to intercept scrolling."];
        [self closeFramework];
        return NO;
    }

    _eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);

    for (NSValue *deviceValue in _devices) {
        MTDeviceRef device = deviceValue.pointerValue;
        registerCallback(device, contactFrameCallback, (__bridge void *)self);
        startDevice(device, 0);
    }

    os_unfair_lock_lock(&_stateLock);
    _swipeState = SwipeStateIdle;
    _suppressScrollSequence = NO;
    _suppressMomentum = NO;
    _running = YES;
    os_unfair_lock_unlock(&_stateLock);
    return YES;
}

- (void)stop {
    NSAssert([NSThread isMainThread], @"GestureMonitor must be stopped on the main thread");

    os_unfair_lock_lock(&_stateLock);
    _running = NO;
    _swipeState = SwipeStateIdle;
    _suppressScrollSequence = NO;
    _suppressMomentum = NO;
    os_unfair_lock_unlock(&_stateLock);

    for (NSValue *deviceValue in _devices) {
        MTDeviceRef device = deviceValue.pointerValue;
        if (_unregisterCallback != NULL) {
            _unregisterCallback(device, contactFrameCallback);
        }
        if (_stopDevice != NULL) {
            _stopDevice(device);
        }
    }

    if (_eventTapSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _eventTapSource, kCFRunLoopCommonModes);
        CFRelease(_eventTapSource);
        _eventTapSource = NULL;
    }
    if (_eventTap != NULL) {
        CFMachPortInvalidate(_eventTap);
        CFRelease(_eventTap);
        _eventTap = NULL;
    }

    [self releaseDevices];
    [self closeFramework];
}

- (BOOL)isMagicMouse:(MTDeviceRef)device
            isBuiltIn:(MTDeviceIsBuiltInFunction)isBuiltIn
         getDimensions:(MTDeviceDimensionsFunction)getDimensions
             getService:(MTDeviceGetServiceFunction)getService {
    if (isBuiltIn != NULL && isBuiltIn(device)) {
        return NO;
    }

    if (getService != NULL) {
        io_service_t service = getService(device);
        if (service != IO_OBJECT_NULL) {
            CFTypeRef productValue = IORegistryEntrySearchCFProperty(
                service,
                kIOServicePlane,
                CFSTR(kIOHIDProductKey),
                kCFAllocatorDefault,
                kIORegistryIterateRecursively | kIORegistryIterateParents
            );
            if (productValue != NULL) {
                NSString *productName = CFGetTypeID(productValue) == CFStringGetTypeID()
                    ? (__bridge NSString *)productValue
                    : nil;
                BOOL isMagicMouse = [productName localizedCaseInsensitiveContainsString:@"Magic Mouse"]
                    || [productName localizedCaseInsensitiveContainsString:@"Multitouch Mouse"];
                BOOL isTrackpad = [productName localizedCaseInsensitiveContainsString:@"Trackpad"];
                CFRelease(productValue);
                if (isMagicMouse) {
                    return YES;
                }
                if (isTrackpad) {
                    return NO;
                }
            }
        }
    }

    // Magic Mouse sensors are portrait-oriented (historically 5152 x 9056),
    // unlike Magic Trackpads. This is a fallback when the I/O Registry has no name.
    if (getDimensions != NULL) {
        int width = 0;
        int height = 0;
        if (getDimensions(device, &width, &height) == 0) {
            return width > 0 && height > width;
        }
    }

    return NO;
}

- (void)handleTouches:(MTTouch *)touches count:(size_t)touchCount timestamp:(double)timestamp {
    float totalX = 0;
    float totalY = 0;
    size_t activeCount = 0;

    for (size_t index = 0; index < touchCount; index++) {
        uint32_t state = touches[index].state;
        if (state >= 3 && state <= 5) {
            totalX += touches[index].normalizedVector.position.x;
            totalY += touches[index].normalizedVector.position.y;
            activeCount++;
        }
    }

    BOOL shouldRouteGesture = NO;
    MCMagicGestureDirection gestureDirection = MCMagicGestureDirectionUndetermined;

    os_unfair_lock_lock(&_stateLock);
    if (!_running) {
        os_unfair_lock_unlock(&_stateLock);
        return;
    }

    if (activeCount == 0) {
        // Native scroll-end and momentum events can arrive after the touch lift.
        // Leave their suppression armed until the event stream ends or restarts.
        _swipeState = SwipeStateIdle;
        os_unfair_lock_unlock(&_stateLock);
        return;
    }

    if (activeCount != 2) {
        // A recognized gesture remains consumed until every finger lifts.
        if (_swipeState == SwipeStateCandidate) {
            _swipeState = SwipeStateRejected;
        }
        os_unfair_lock_unlock(&_stateLock);
        return;
    }

    float currentX = totalX / 2.0f;
    float currentY = totalY / 2.0f;

    if (_swipeState == SwipeStateIdle) {
        _swipeState = SwipeStateCandidate;
        _originX = currentX;
        _originY = currentY;
        _gestureStartTime = timestamp;
        os_unfair_lock_unlock(&_stateLock);
        return;
    }

    if (_swipeState == SwipeStateCandidate) {
        float deltaX = currentX - _originX;
        float deltaY = currentY - _originY;
        double duration = timestamp - _gestureStartTime;

        gestureDirection = MCMagicClassifyGesture(deltaX, deltaY, duration);
        if (gestureDirection == MCMagicGestureDirectionUp
            || gestureDirection == MCMagicGestureDirectionDown) {
            shouldRouteGesture = YES;
        } else if (gestureDirection == MCMagicGestureDirectionRejected) {
            _swipeState = SwipeStateRejected;
        }
    }
    os_unfair_lock_unlock(&_stateLock);

    MCMagicGestureAction action = MCMagicGestureActionIgnore;
    BOOL shouldPerformAction = NO;
    if (shouldRouteGesture) {
        BOOL missionControlIsActive = MCMagicIsMissionControlActive();
        action = MCMagicActionForGesture(
            gestureDirection,
            missionControlIsActive,
            self.activationDirection,
            self.dismissalDirection
        );

        os_unfair_lock_lock(&_stateLock);
        if (_running && _swipeState == SwipeStateCandidate) {
            if (action == MCMagicGestureActionIgnore) {
                _swipeState = SwipeStateRejected;
            } else {
                _swipeState = SwipeStateTriggered;
                _suppressScrollSequence = YES;
                _suppressMomentum = YES;
                shouldPerformAction = action == MCMagicGestureActionActivateMissionControl
                    || action == MCMagicGestureActionDismissMissionControl;
            }
        }
        os_unfair_lock_unlock(&_stateLock);
    }

    if (shouldPerformAction && action == MCMagicGestureActionActivateMissionControl) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activateMissionControl];
        });
    } else if (shouldPerformAction && action == MCMagicGestureActionDismissMissionControl) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissMissionControl];
        });
    }
}

- (BOOL)shouldSuppressScrollEvent:(CGEventRef)event {
    int64_t phase = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
    int64_t momentum = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
    BOOL continuous = CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous) != 0;

    os_unfair_lock_lock(&_stateLock);
    if (!_running) {
        os_unfair_lock_unlock(&_stateLock);
        return NO;
    }

    if (momentum != kCGMomentumScrollPhaseNone) {
        BOOL shouldSuppress = _suppressMomentum;
        // CGMomentumScrollPhase is an enum, not the NSEvent phase bitmask.
        if (momentum == kCGMomentumScrollPhaseEnd) {
            _suppressMomentum = NO;
            _suppressScrollSequence = NO;
        }
        os_unfair_lock_unlock(&_stateLock);
        return shouldSuppress;
    }

    // A discrete wheel on another mouse is independent of the touch gesture.
    if (!continuous && phase == 0) {
        os_unfair_lock_unlock(&_stateLock);
        return NO;
    }

    if ((phase & (kCGScrollPhaseBegan | kCGScrollPhaseMayBegin)) != 0
        && _swipeState != SwipeStateTriggered) {
        // Fresh physical scrolling supersedes old momentum, even if its final
        // event was missing. Touch contact alone must not release queued inertia.
        _suppressScrollSequence = NO;
        _suppressMomentum = NO;
    }
    if (_swipeState == SwipeStateTriggered) {
        _suppressScrollSequence = YES;
        _suppressMomentum = YES;
    }

    BOOL shouldSuppress = _swipeState == SwipeStateCandidate
        || _swipeState == SwipeStateTriggered
        || (_suppressScrollSequence && phase != 0);
    if ((phase & kCGScrollPhaseCancelled) != 0) {
        _suppressScrollSequence = NO;
        _suppressMomentum = NO;
    } else if ((phase & kCGScrollPhaseEnded) != 0) {
        // Finger scrolling ended, but its momentum may not have started yet.
        _suppressScrollSequence = NO;
    }
    os_unfair_lock_unlock(&_stateLock);
    return shouldSuppress;
}

- (void)postKey:(CGKeyCode)keyCode flags:(CGEventFlags)flags {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, keyCode, false);
    if (keyDown != NULL && keyUp != NULL) {
        CGEventSetFlags(keyDown, flags);
        CGEventSetFlags(keyUp, flags);
        CGEventPost(kCGHIDEventTap, keyDown);
        CGEventPost(kCGHIDEventTap, keyUp);
    }
    if (keyDown != NULL) {
        CFRelease(keyDown);
    }
    if (keyUp != NULL) {
        CFRelease(keyUp);
    }
    if (source != NULL) {
        CFRelease(source);
    }
}

- (void)activateMissionControl {
    [self toggleMissionControl];
}

- (void)toggleMissionControl {
    CoreDockSendNotificationFunction sendDockNotification = dlsym(
        RTLD_DEFAULT,
        "CoreDockSendNotification"
    );
    if (sendDockNotification != NULL) {
        sendDockNotification(CFSTR("com.apple.expose.awake"));
        return;
    }

    // Fallback to the default Mission Control shortcut (Control-Up Arrow).
    [self postKey:(CGKeyCode)126 flags:kCGEventFlagMaskControl];
}

- (void)dismissMissionControl {
    // This runs asynchronously after recognition. A click or native gesture
    // may already have closed Mission Control; do not toggle it back open.
    if (!self.isRunning || !MCMagicIsMissionControlActive()) {
        return;
    }

    if (self.selectHoveredWindowOnDismiss) {
        // Let the Dock commit its hovered window selection when leaving Mission
        // Control, just as the native gesture does. Escape cancels that selection.
        [self toggleMissionControl];
    } else {
        [self postKey:(CGKeyCode)53 flags:0];
    }
}

- (void)reenableEventTap {
    if (_eventTap != NULL) {
        CGEventTapEnable(_eventTap, true);
    }
}

- (void)releaseDevices {
    for (NSValue *deviceValue in _devices) {
        CFRelease(deviceValue.pointerValue);
    }
    [_devices removeAllObjects];
}

- (void)closeFramework {
    _stopDevice = NULL;
    _unregisterCallback = NULL;
    if (_multitouchFramework != NULL) {
        dlclose(_multitouchFramework);
        _multitouchFramework = NULL;
    }
}

- (void)setError:(NSError **)error code:(NSInteger)code description:(NSString *)description {
    if (error != NULL) {
        *error = [NSError errorWithDomain:GestureMonitorErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

@end

static void contactFrameCallback(MTDeviceRef device,
                                 MTTouch *touches,
                                 size_t touchCount,
                                 double timestamp,
                                 size_t frame,
                                 void *context) {
    GestureMonitor *monitor = (__bridge GestureMonitor *)context;
    [monitor handleTouches:touches count:touchCount timestamp:timestamp];
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy,
                                   CGEventType type,
                                   CGEventRef event,
                                   void *context) {
    GestureMonitor *monitor = (__bridge GestureMonitor *)context;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [monitor reenableEventTap];
        return event;
    }

    if (type == kCGEventScrollWheel && [monitor shouldSuppressScrollEvent:event]) {
        return NULL;
    }
    return event;
}
