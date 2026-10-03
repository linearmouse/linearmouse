#ifndef LINEARMOUSE_WINDOW_FOCUS_H
#define LINEARMOUSE_WINDOW_FOCUS_H

#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

bool LMWindowFocusAvailable(void);
bool LMGetWindowID(AXUIElementRef window, CGWindowID *windowID);
bool LMFocusWindowWithoutRaising(pid_t pid, CGWindowID windowID,
                                pid_t previousPID, CGWindowID previousWindowID);

#endif
