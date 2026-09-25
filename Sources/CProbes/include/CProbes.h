// CProbes: read-only access to kernel energy accounting and the SMC.
//
// Everything here works without root. Private interfaces used:
//   - coalition_info_resource_usage / PROC_PIDCOALITIONINFO (libsystem_kernel, XNU bsd/sys/coalition.h)
//   - xpc_coalition_copy_info (libxpc)
//   - AppleSMC user client (IOKit)
// All functions return 0 on success and -1 on failure (errno preserved where meaningful).

#ifndef CPROBES_H
#define CPROBES_H

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Cumulative counters for one resource coalition (≈ one app with all its helpers,
/// including tasks that have already exited).
typedef struct {
    uint64_t cpu_time_mach;   // mach_absolute_time units
    uint64_t cpu_energy_nj;   // nanojoules
    uint64_t gpu_time_ns;     // nanoseconds
    uint64_t gpu_energy_nj;   // nanojoules
    uint64_t ane_time_mach;   // mach_absolute_time units
    uint64_t ane_energy_nj;   // nanojoules
    uint64_t tasks_started;
    uint64_t tasks_exited;
} pl_coalition_usage;

/// Resource-coalition id of a process.
int pl_pid_resource_coalition(pid_t pid, uint64_t *cid_out);

int pl_coalition_usage_read(uint64_t cid, pl_coalition_usage *out);

/// launchd label of a coalition (e.g. "application.com.apple.Safari.123.456").
/// Returns a malloc'd string the caller must free(), or NULL.
char *pl_coalition_copy_name(uint64_t cid);

/// Cumulative counters for one process. Requires same uid (or root).
typedef struct {
    uint64_t cpu_energy_nj;   // nanojoules
    uint64_t cpu_time_mach;   // user + system, mach_absolute_time units
} pl_proc_usage;

int pl_proc_usage_read(pid_t pid, pl_proc_usage *out);

typedef struct {
    pid_t pid;
    pid_t ppid;
    uid_t uid;
    uint64_t start_sec;
    uint64_t start_usec;
    char name[64];            // best available short name (pbi_name, else pbi_comm)
} pl_proc_bsdinfo;

int pl_proc_bsdinfo_read(pid_t pid, pl_proc_bsdinfo *out);

/// Current working directory of a process (same uid or root). NUL-terminated.
int pl_proc_cwd(pid_t pid, char *buf, size_t buflen);

/// argv of a process as consecutive NUL-terminated strings (same uid or root).
/// On success *argc_out holds the argument count and *len_out the bytes written.
int pl_proc_argv(pid_t pid, char *buf, size_t buflen, int *argc_out, size_t *len_out);

/// SMC access. pl_smc_open must succeed before pl_smc_read_float.
/// Not thread-safe: call from a single serial queue.
int pl_smc_open(void);
void pl_smc_close(void);
/// Reads a 4-character SMC key of type 'flt '.
int pl_smc_read_float(const char *key, float *out);

#ifdef __cplusplus
}
#endif

#endif
