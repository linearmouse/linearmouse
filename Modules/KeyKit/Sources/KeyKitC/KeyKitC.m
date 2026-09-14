//
//  CGSKitC.m
//  
//
//  Created by Jiahao Lu on 2022/7/24.
//

#import "include/KeyKitC.h"

kern_return_t KeyKitPostAuxControlButton(io_connect_t handle, const NXEventData *eventData) {
    // Preserve IOHIDSystem's handling of auxiliary keys, including Caps Lock
    // and global event flags. Migrating this path requires validating those
    // behaviors; confine the legacy API's deprecation warning to this call.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return IOHIDPostEvent(handle, NX_SYSDEFINED, (IOGPoint){0, 0}, eventData,
                          kNXEventDataVersion, 0, kIOHIDSetGlobalEventFlags);
#pragma clang diagnostic pop
}
