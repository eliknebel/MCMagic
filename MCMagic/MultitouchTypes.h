#pragma once

#include <stdint.h>

typedef const void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

// Reverse-engineered layout used by MultitouchSupport.framework on modern macOS.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    uint32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t reserved9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t reserved14;
    int32_t reserved15;
    float zDensity;
} MTTouch;

_Static_assert(sizeof(MTTouch) == 96, "Unexpected MTTouch ABI");

