#include "Process.h"

ProcessInfo getProcessInfo(pid_t pid) {
    ProcessInfo pi = { 0 };

    struct kinfo_proc info;
    size_t length = sizeof(struct kinfo_proc);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &info, &length, NULL, 0) < 0 || !length)
        return pi;

    pi.ppid = info.kp_eproc.e_ppid;
    pi.pgid = info.kp_eproc.e_pgid;

    return pi;
}
