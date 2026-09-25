// Validation 1: per-process CPU energy (kernel) vs whole-system power (SMC PSTR).
//
// Measures SMC power while idle, then starts N busy-loop workers and compares the energy the
// kernel attributes to those workers with the rise in SMC system power. The workers' energy
// should account for most of the rise; the rest is shared cost (cluster wake-up, fabric,
// memory controller) that no process is billed for.
//
// Usage: cpu_energy_vs_system <workers> [seconds]
#include "CProbes.h"

#include <signal.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static double average_system_power(int seconds) {
    double sum = 0;
    int n = 0;
    for (int i = 0; i < seconds; i++) {
        sleep(1);
        float w;
        if (pl_smc_read_float("PSTR", &w) == 0) { sum += w; n++; }
    }
    return n ? sum / n : -1;
}

static double workers_energy(const pid_t *pids, int n) {
    double joules = 0;
    for (int i = 0; i < n; i++) {
        pl_proc_usage u;
        if (pl_proc_usage_read(pids[i], &u) == 0) joules += u.cpu_energy_nj / 1e9;
    }
    return joules;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <workers> [seconds]\n", argv[0]); return 2; }
    int workers = atoi(argv[1]);
    int seconds = argc > 2 ? atoi(argv[2]) : 8;
    if (workers < 1 || workers > 64 || seconds < 2) { fprintf(stderr, "bad arguments\n"); return 2; }
    if (pl_smc_open() != 0) { fprintf(stderr, "cannot open SMC\n"); return 1; }

    double idle = average_system_power(seconds);

    pid_t pids[64];
    for (int i = 0; i < workers; i++) {
        pid_t p = fork();
        if (p == 0) { volatile unsigned long x = 0; for (;;) x++; }
        if (p < 0) { perror("fork"); for (int j = 0; j < i; j++) kill(pids[j], SIGKILL); return 1; }
        pids[i] = p;
    }
    sleep(2);  // let frequencies settle
    double e0 = workers_energy(pids, workers);
    double loaded = average_system_power(seconds);
    double e1 = workers_energy(pids, workers);
    for (int i = 0; i < workers; i++) kill(pids[i], SIGKILL);
    for (int i = 0; i < workers; i++) waitpid(pids[i], NULL, 0);
    pl_smc_close();

    double attributed = (e1 - e0) / seconds;
    double rise = loaded - idle;
    printf("workers=%d  system idle %.2f W  loaded %.2f W  rise %.2f W | kernel energy of workers %.2f W (%.0f%% of rise)\n",
           workers, idle, loaded, rise, attributed, rise > 0 ? attributed / rise * 100 : 0);
    return 0;
}
