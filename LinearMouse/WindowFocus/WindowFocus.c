// MIT License
// Copyright (c) 2026 LinearMouse

#include "WindowFocus.h"
#include <Carbon/Carbon.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <string.h>
#include <unistd.h>

// SkyLight's process/key-window event protocol is undocumented. Resolve all
// entry points at runtime and fail closed; never fall back to activation/raise.
// Protocol references:
// https://github.com/asmvik/yabai/blob/master/src/window_manager.c
// https://github.com/sbmpost/AutoRaise/blob/master/AutoRaise.mm
static CGError (*setFrontProcess)(ProcessSerialNumber *, uint32_t, uint32_t);
static CGError (*postRecord)(ProcessSerialNumber *, uint8_t *);
static AXError (*getWindowID)(AXUIElementRef, CGWindowID *);

bool LMWindowFocusAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (skyLight) {
            setFrontProcess = dlsym(skyLight, "_SLPSSetFrontProcessWithOptions");
            postRecord = dlsym(skyLight, "SLPSPostEventRecordTo");
        }
        getWindowID = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    });
    return setFrontProcess && postRecord && getWindowID;
}

bool LMGetWindowID(AXUIElementRef window, CGWindowID *windowID) {
    return LMWindowFocusAvailable() && getWindowID(window, windowID) == kAXErrorSuccess;
}

static CGError sendWindowState(ProcessSerialNumber *process, CGWindowID windowID, uint8_t state) {
    uint8_t record[0xf8] = {0};
    record[4] = sizeof(record);
    record[8] = 0x0d;
    record[0x8a] = state;
    memcpy(record + 0x3c, &windowID, sizeof(windowID));
    return postRecord(process, record);
}

bool LMFocusWindowWithoutRaising(pid_t pid, CGWindowID windowID,
                                pid_t previousPID, CGWindowID previousWindowID) {
    if (!LMWindowFocusAvailable() || !windowID) return false;
    ProcessSerialNumber process;
    if (GetProcessForPID(pid, &process) != noErr) return false;

    if (pid == previousPID && previousWindowID && previousWindowID != windowID) {
        if (sendWindowState(&process, previousWindowID, 2) != kCGErrorSuccess) return false;
        // Some applications need separation between losing and gaining key
        // status. This executes exclusively on the focus worker, never a tap.
        usleep(40000);
        if (sendWindowState(&process, windowID, 1) != kCGErrorSuccess) return false;
    }

    if (setFrontProcess(&process, windowID, 0x200) != kCGErrorSuccess) return false;
    uint8_t record[0xf8] = {0};
    record[4] = sizeof(record);
    record[0x3a] = 0x10;
    memcpy(record + 0x3c, &windowID, sizeof(windowID));
    memset(record + 0x20, 0xff, 0x10);
    record[8] = 1;
    if (postRecord(&process, record) != kCGErrorSuccess) return false;
    record[8] = 2;
    return postRecord(&process, record) == kCGErrorSuccess;
}
