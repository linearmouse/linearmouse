//
//  Touch-Bridging-Header.h
//  LinearMouse
//
//  Created by lujjjh on 2021/8/5.
//

#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include "../Touch/TouchSimulate.h"

typedef void (^IOHIDServiceClientBlock)(void *, void *, IOHIDServiceClientRef);

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
void IOHIDEventSystemClientSetMatchingMultiple(IOHIDEventSystemClientRef, CFArrayRef);
void IOHIDEventSystemClientRegisterDeviceMatchingBlock(IOHIDEventSystemClientRef, IOHIDServiceClientBlock, void *, void *);

typedef void (^IOHIDEventSystemClientEventBlock)(void* target, void* refcon, IOHIDServiceClientRef sender, void* event);
void IOHIDEventSystemClientRegisterEventBlock(IOHIDEventSystemClientRef client, IOHIDEventSystemClientEventBlock callback, void* target, void* refcon);

void IOHIDEventSystemClientUnregisterDeviceMatchingBlock(IOHIDEventSystemClientRef);
void IOHIDEventSystemClientScheduleWithDispatchQueue(IOHIDEventSystemClientRef, dispatch_queue_t);

void IOHIDServiceClientRegisterRemovalBlock(IOHIDServiceClientRef, IOHIDServiceClientBlock, void*, void*);

typedef void (*IOHIDEventSystemClientPropertyChangedCallback)(void* target, void* context, CFStringRef property, CFTypeRef value);
void IOHIDEventSystemClientRegisterPropertyChangedCallback(IOHIDEventSystemClientRef client, CFStringRef property, IOHIDEventSystemClientPropertyChangedCallback callback, void* target, void *context);

enum {
    kIOHIDEventTypeNULL,
    kIOHIDEventTypeVendorDefined,
    kIOHIDEventTypeKeyboard = 3,
    kIOHIDEventTypeRotation = 5,
    kIOHIDEventTypeScroll = 6,
    kIOHIDEventTypeZoom = 8,
    kIOHIDEventTypeDigitizer = 11,
    kIOHIDEventTypeNavigationSwipe = 16,
    kIOHIDEventTypeForce = 32,
};
typedef uint32_t IOHIDEventType;
typedef CFTypeRef IOHIDEventRef;
typedef double IOHIDFloat;
typedef uint32_t IOHIDEventField;

#define IOHIDEventFieldBase(type) (type << 16)

#define kIOHIDEventFieldScrollBase IOHIDEventFieldBase(kIOHIDEventTypeScroll)
static const IOHIDEventField kIOHIDEventFieldScrollX = (kIOHIDEventFieldScrollBase | 0);
static const IOHIDEventField kIOHIDEventFieldScrollY = (kIOHIDEventFieldScrollBase | 1);

IOHIDEventRef CGEventCopyIOHIDEvent(CGEventRef);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef, IOHIDEventField);
void IOHIDEventSetFloatValue(IOHIDEventRef, IOHIDEventField, IOHIDFloat);
