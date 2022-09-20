#include "unix.h"

// Returns the parent process id for the given process id (pid).
int OPParentIDForProcessID(int pid) {
    struct kinfo_proc info;
    size_t length = sizeof(struct kinfo_proc);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
        return -1;
    if (length == 0)
        return -1;
    return info.kp_eproc.e_ppid;
}
