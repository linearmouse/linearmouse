#ifndef LINEARMOUSE_PROCESS_H
#define LINEARMOUSE_PROCESS_H

#include <sys/sysctl.h>

typedef struct ProcessInfo {
    pid_t ppid;
    pid_t pgid;
} ProcessInfo;

ProcessInfo getProcessInfo(pid_t pid);

#endif /* LINEARMOUSE_PROCESS_H */
