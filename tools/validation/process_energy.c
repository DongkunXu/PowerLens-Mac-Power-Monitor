// Average CPU power and CPU usage of one process over an interval (kernel per-process energy).
// Used to measure PowerLens's own overhead.
//
// Usage: process_energy <pid> [seconds]
#include "CProbes.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_time.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <pid> [seconds]\n", argv[0]); return 2; }
    pid_t pid = (pid_t)atoi(argv[1]);
    int seconds = argc > 2 ? atoi(argv[2]) : 30;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);

    pl_proc_usage a, b;
    if (pl_proc_usage_read(pid, &a) != 0) { perror("proc_pid_rusage"); return 1; }
    uint64_t t0 = mach_absolute_time();
    sleep((unsigned)seconds);
    if (pl_proc_usage_read(pid, &b) != 0) { perror("proc_pid_rusage"); return 1; }
    double elapsed = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e9;
    double cpu = (double)(b.cpu_time_mach - a.cpu_time_mach) * tb.numer / tb.denom / 1e9;

    printf("pid %d over %.1f s: CPU power %.4f W, CPU %.2f%% of one core\n",
           pid, elapsed, (b.cpu_energy_nj - a.cpu_energy_nj) / 1e9 / elapsed, cpu / elapsed * 100);
    return 0;
}
