/*
 * Copyright (C) 2020 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef IOKITSPIMAC_H
#define IOKITSPIMAC_H

#import <IOKit/hid/IOHIDDevice.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDUsageTables.h>

#define kIOHIDVendorIDKey "VendorID"
#define kIOHIDProductIDKey "ProductID"

CF_IMPLICIT_BRIDGING_ENABLED

typedef CFTypeRef IOHIDEventRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient * IOHIDServiceClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient * IOHIDEventSystemClientRef;
typedef void (^IOHIDServiceClientBlock)(void *, void *, IOHIDServiceClientRef);

typedef CF_ENUM(int, IOHIDEventSystemClientType)
{
    kIOHIDEventSystemClientTypeAdmin,
    kIOHIDEventSystemClientTypeMonitor,
    kIOHIDEventSystemClientTypePassive,
    kIOHIDEventSystemClientTypeRateControlled,
    kIOHIDEventSystemClientTypeSimple
};

IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef, IOHIDEventSystemClientType, CFDictionaryRef);
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
void IOHIDEventSystemClientSetMatchingMultiple(IOHIDEventSystemClientRef, CFArrayRef);
IOHIDServiceClientRef IOHIDEventSystemClientCopyServiceForRegistryID(IOHIDEventSystemClientRef, uint64_t registryID);
void IOHIDEventSystemClientRegisterDeviceMatchingBlock(IOHIDEventSystemClientRef, IOHIDServiceClientBlock, void *, void *);
void IOHIDEventSystemClientUnregisterDeviceMatchingBlock(IOHIDEventSystemClientRef);
void IOHIDEventSystemClientScheduleWithDispatchQueue(IOHIDEventSystemClientRef, dispatch_queue_t);
void IOHIDEventSystemClientUnscheduleFromDispatchQueue(IOHIDEventSystemClientRef, dispatch_queue_t);
void IOHIDEventSystemClientSetDispatchQueue(IOHIDEventSystemClientRef, dispatch_queue_t);
void IOHIDEventSystemClientActivate(IOHIDEventSystemClientRef);

void IOHIDServiceClientRegisterRemovalBlock(IOHIDServiceClientRef, IOHIDServiceClientBlock, void*, void*);

typedef void (*IOHIDEventSystemClientPropertyChangedCallback)(void* target, void* context, CFStringRef property, CFTypeRef value);
void IOHIDEventSystemClientRegisterPropertyChangedCallback(IOHIDEventSystemClientRef client, CFStringRef property, IOHIDEventSystemClientPropertyChangedCallback callback, void* target, void *context);

CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);

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

typedef uint32_t IOHIDEventField;
typedef uint64_t IOHIDEventSenderID;


enum {
    kIOHIDEventScrollMomentumInterrupted = (1 << 4),
};
typedef uint8_t IOHIDEventScrollMomentumBits;

#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

#define IOHIDEventFieldBase(type) (type << 16)

#define kIOHIDEventFieldScrollBase IOHIDEventFieldBase(kIOHIDEventTypeScroll)
//static const IOHIDEventField kIOHIDEventFieldScrollX = (kIOHIDEventFieldScrollBase | 0);
//static const IOHIDEventField kIOHIDEventFieldScrollY = (kIOHIDEventFieldScrollBase | 1);

uint64_t IOHIDEventGetTimeStamp(IOHIDEventRef);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef, IOHIDEventField);
IOHIDEventSenderID IOHIDEventGetSenderID(IOHIDEventRef);
IOHIDEventScrollMomentumBits IOHIDEventGetScrollMomentum(IOHIDEventRef);

typedef void (^IOHIDEventSystemClientEventBlock)(void* target, void* refcon, IOHIDServiceClientRef sender, IOHIDEventRef event);
void IOHIDEventSystemClientRegisterEventBlock(IOHIDEventSystemClientRef client, IOHIDEventSystemClientEventBlock callback, void* target, void* refcon);

CF_IMPLICIT_BRIDGING_DISABLED

#endif // IOKITSPIMAC_H
