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
void IOHIDEventSystemClientRegisterDeviceMatchingBlock(IOHIDEventSystemClientRef, IOHIDServiceClientBlock, void *, void *);
void IOHIDEventSystemClientUnregisterDeviceMatchingBlock(IOHIDEventSystemClientRef);
void IOHIDEventSystemClientScheduleWithDispatchQueue(IOHIDEventSystemClientRef, dispatch_queue_t);

void IOHIDServiceClientRegisterRemovalBlock(IOHIDServiceClientRef, IOHIDServiceClientBlock, void*, void*);
