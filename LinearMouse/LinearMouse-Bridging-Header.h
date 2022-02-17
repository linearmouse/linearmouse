//
//  Touch-Bridging-Header.h
//  LinearMouse
//
//  Created by lujjjh on 2021/8/5.
//

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

int _CGSDefaultConnection(void);
void CGSSetSwipeScrollDirection(int cid, BOOL dir);
