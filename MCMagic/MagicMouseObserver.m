#import "MagicMouseObserver.h"

#import "LifecycleRecovery.h"

#import <IOKit/hid/IOHIDDevice.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDUsageTables.h>
#import <IOKit/hid/IOHIDDeviceKeys.h>
#import <IOKit/IOKitLib.h>

static void magicMouseMatched(void *context,
                              IOReturn result,
                              void *sender,
                              IOHIDDeviceRef device);
static void magicMouseRemoved(void *context,
                              IOReturn result,
                              void *sender,
                              IOHIDDeviceRef device);

@interface MagicMouseObserver () {
    IOHIDManagerRef _manager;
    NSMutableSet<NSNumber *> *_knownMagicMouseIDs;
    MCMagicMagicMouseChangeHandler _changeHandler;
}

- (void)handleMatchedDevice:(IOHIDDeviceRef)device notify:(BOOL)notify;
- (void)handleRemovedDevice:(IOHIDDeviceRef)device;
- (BOOL)isMagicMouseDevice:(IOHIDDeviceRef)device;
- (NSNumber *)identifierForDevice:(IOHIDDeviceRef)device;

@end


@implementation MagicMouseObserver

- (instancetype)initWithChangeHandler:(MCMagicMagicMouseChangeHandler)changeHandler {
    self = [super init];
    if (self) {
        _changeHandler = [changeHandler copy];
        _knownMagicMouseIDs = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    NSAssert([NSThread isMainThread], @"MagicMouseObserver must start on the main thread");
    if (_manager != NULL) {
        return;
    }

    _manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (_manager == NULL) {
        return;
    }

    NSDictionary *matching = @{
        @kIOHIDDeviceUsagePageKey: @(kHIDPage_GenericDesktop),
        @kIOHIDDeviceUsageKey: @(kHIDUsage_GD_Mouse),
    };
    IOHIDManagerSetDeviceMatching(_manager, (__bridge CFDictionaryRef)matching);

    // Device enumeration and connection callbacks do not require opening devices
    // for input access. Keep this observer independent of Input Monitoring.
    CFSetRef currentDevices = IOHIDManagerCopyDevices(_manager);
    if (currentDevices != NULL) {
        for (id deviceValue in (__bridge NSSet *)currentDevices) {
            [self handleMatchedDevice:(__bridge IOHIDDeviceRef)deviceValue notify:NO];
        }
        CFRelease(currentDevices);
    }

    IOHIDManagerRegisterDeviceMatchingCallback(
        _manager,
        magicMouseMatched,
        (__bridge void *)self
    );
    IOHIDManagerRegisterDeviceRemovalCallback(
        _manager,
        magicMouseRemoved,
        (__bridge void *)self
    );
    IOHIDManagerScheduleWithRunLoop(_manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

- (void)stop {
    NSAssert([NSThread isMainThread], @"MagicMouseObserver must stop on the main thread");
    if (_manager == NULL) {
        return;
    }

    IOHIDManagerUnscheduleFromRunLoop(_manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    IOHIDManagerRegisterDeviceMatchingCallback(_manager, NULL, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(_manager, NULL, NULL);
    CFRelease(_manager);
    _manager = NULL;
    [_knownMagicMouseIDs removeAllObjects];
}

- (void)handleMatchedDevice:(IOHIDDeviceRef)device notify:(BOOL)notify {
    if (![self isMagicMouseDevice:device]) {
        return;
    }

    NSNumber *identifier = [self identifierForDevice:device];
    if ([_knownMagicMouseIDs containsObject:identifier]) {
        return;
    }

    [_knownMagicMouseIDs addObject:identifier];
    if (notify) {
        _changeHandler();
    }
}

- (void)handleRemovedDevice:(IOHIDDeviceRef)device {
    NSNumber *identifier = [self identifierForDevice:device];
    if (![_knownMagicMouseIDs containsObject:identifier]) {
        return;
    }

    [_knownMagicMouseIDs removeObject:identifier];
    _changeHandler();
}

- (BOOL)isMagicMouseDevice:(IOHIDDeviceRef)device {
    CFTypeRef productValue = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    NSString *productName = productValue != NULL
        && CFGetTypeID(productValue) == CFStringGetTypeID()
        ? (__bridge NSString *)productValue
        : nil;

    CFTypeRef transportValue = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDTransportKey));
    NSString *transport = transportValue != NULL
        && CFGetTypeID(transportValue) == CFStringGetTypeID()
        ? (__bridge NSString *)transportValue
        : nil;

    CFTypeRef vendorIDValue = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey));
    NSInteger vendorID = vendorIDValue != NULL
        && CFGetTypeID(vendorIDValue) == CFNumberGetTypeID()
        ? [(__bridge NSNumber *)vendorIDValue integerValue]
        : 0;

    return MCMagicHIDPropertiesIndicateMagicMouse(productName, transport, vendorID);
}

- (NSNumber *)identifierForDevice:(IOHIDDeviceRef)device {
    io_service_t service = IOHIDDeviceGetService(device);
    uint64_t registryEntryID = 0;
    if (service != IO_OBJECT_NULL
        && IORegistryEntryGetRegistryEntryID(service, &registryEntryID) == kIOReturnSuccess) {
        return @(registryEntryID);
    }

    return @((uintptr_t)device);
}

@end

static void magicMouseMatched(void *context,
                              IOReturn result,
                              void *sender,
                              IOHIDDeviceRef device) {
    MagicMouseObserver *observer = (__bridge MagicMouseObserver *)context;
    [observer handleMatchedDevice:device notify:YES];
}

static void magicMouseRemoved(void *context,
                              IOReturn result,
                              void *sender,
                              IOHIDDeviceRef device) {
    MagicMouseObserver *observer = (__bridge MagicMouseObserver *)context;
    [observer handleRemovedDevice:device];
}
