//
//  TouchSimulate.m
//  LinearMouse
//
//  Created by lujjjh on 2021/8/5.
//

#import <Foundation/Foundation.h>
#import "TouchEvents.h"

void simulateSwipe(TLInfoSwipeDirection dir) {
    @autoreleasepool {
        NSDictionary* swipeInfo1 = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @(kTLInfoSubtypeSwipe), kTLInfoKeyGestureSubtype,
                                    @(1), kTLInfoKeyGesturePhase,
                                    nil];

        NSDictionary* swipeInfo2 = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @(kTLInfoSubtypeSwipe), kTLInfoKeyGestureSubtype,
                                    @(dir), kTLInfoKeySwipeDirection,
                                    @(4), kTLInfoKeyGesturePhase,
                                    nil];

        CGEventRef event1 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)(swipeInfo1), (__bridge CFArrayRef)@[]);
        CGEventRef event2 = tl_CGEventCreateFromGesture((__bridge CFDictionaryRef)(swipeInfo2), (__bridge CFArrayRef)@[]);

        CFRetain(event1);
        CFRetain(event2);

        CGEventPost(kCGHIDEventTap, event1);
        CGEventPost(kCGHIDEventTap, event2);

        CFRelease(event1);
        CFRelease(event2);
    }
}

void simulateSwipeLeft(void) {
    simulateSwipe(kTLInfoSwipeLeft);
}

void simulateSwipeRight(void) {
    simulateSwipe(kTLInfoSwipeRight);
}
