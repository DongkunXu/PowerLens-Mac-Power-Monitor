#include "CProbes.h"

#include <errno.h>
#include <libproc.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <xpc/xpc.h>
#include <IOKit/IOKitLib.h>

// MARK: - Coalitions (layout from XNU osfmk/mach/coalition.h)

#define PL_COALITION_TYPE_RESOURCE 0
#define PL_COALITION_NUM_TYPES 2
#define PL_COALITION_NUM_THREAD_QOS_TYPES 7
#define PL_PROC_PIDCOALITIONINFO 20

struct pl_xnu_coalition_resource_usage {
    uint64_t tasks_started;
    uint64_t tasks_exited;
    uint64_t time_nonempty;
    uint64_t cpu_time;
    uint64_t interrupt_wakeups;
    uint64_t platform_idle_wakeups;
    uint64_t bytesread;
    uint64_t byteswritten;
    uint64_t gpu_time;
    uint64_t cpu_time_billed_to_me;
    uint64_t cpu_time_billed_to_others;
    uint64_t energy;
    uint64_t logical_immediate_writes;
    uint64_t logical_deferred_writes;
    uint64_t logical_invalidated_writes;
    uint64_t logical_metadata_writes;
    uint64_t logical_immediate_writes_to_external;
    uint64_t logical_deferred_writes_to_external;
    uint64_t logical_invalidated_writes_to_external;
    uint64_t logical_metadata_writes_to_external;
    uint64_t energy_billed_to_me;
    uint64_t energy_billed_to_others;
    uint64_t cpu_ptime;
    uint64_t cpu_time_eqos_len;
    uint64_t cpu_time_eqos[PL_COALITION_NUM_THREAD_QOS_TYPES];
    uint64_t cpu_instructions;
    uint64_t cpu_cycles;
    uint64_t fs_metadata_writes;
    uint64_t pm_writes;
    uint64_t cpu_pinstructions;
    uint64_t cpu_pcycles;
    uint64_t conclave_mem;
    uint64_t ane_mach_time;
    uint64_t ane_energy_nj;
    uint64_t phys_footprint;
    uint64_t gpu_energy_nj;
    uint64_t gpu_energy_nj_billed_to_me;
    uint64_t gpu_energy_nj_billed_to_others;
    uint64_t swapins;
};

struct pl_xnu_proc_pidcoalitioninfo {
    uint64_t coalition_id[PL_COALITION_NUM_TYPES];
    uint64_t reserved1;
    uint64_t reserved2;
    uint64_t reserved3;
};

extern int coalition_info_resource_usage(uint64_t cid, struct pl_xnu_coalition_resource_usage *cru, size_t sz);
extern xpc_object_t xpc_coalition_copy_info(uint64_t cid);

int pl_pid_resource_coalition(pid_t pid, uint64_t *cid_out) {
    struct pl_xnu_proc_pidcoalitioninfo info;
    int n = proc_pidinfo(pid, PL_PROC_PIDCOALITIONINFO, 0, &info, sizeof info);
    if (n != (int)sizeof info) return -1;
    *cid_out = info.coalition_id[PL_COALITION_TYPE_RESOURCE];
    return 0;
}

int pl_coalition_usage_read(uint64_t cid, pl_coalition_usage *out) {
    struct pl_xnu_coalition_resource_usage cru;
    memset(&cru, 0, sizeof cru);
    if (coalition_info_resource_usage(cid, &cru, sizeof cru) != 0) return -1;
    out->cpu_time_mach = cru.cpu_time;
    out->cpu_energy_nj = cru.energy;
    out->gpu_time_ns = cru.gpu_time;
    out->gpu_energy_nj = cru.gpu_energy_nj;
    out->ane_time_mach = cru.ane_mach_time;
    out->ane_energy_nj = cru.ane_energy_nj;
    out->tasks_started = cru.tasks_started;
    out->tasks_exited = cru.tasks_exited;
    return 0;
}

char *pl_coalition_copy_name(uint64_t cid) {
    xpc_object_t info = xpc_coalition_copy_info(cid);
    if (info == NULL) return NULL;
    char *result = NULL;
    if (xpc_get_type(info) == XPC_TYPE_DICTIONARY) {
        const char *name = xpc_dictionary_get_string(info, "name");
        if (name != NULL && name[0] != '\0') result = strdup(name);
    }
    xpc_release(info);
    return result;
}

// MARK: - Processes

int pl_proc_usage_read(pid_t pid, pl_proc_usage *out) {
    struct rusage_info_v6 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&ri) != 0) return -1;
    out->cpu_energy_nj = ri.ri_energy_nj;
    // On Apple Silicon ri_user_time / ri_system_time are in mach_absolute_time units.
    out->cpu_time_mach = ri.ri_user_time + ri.ri_system_time;
    return 0;
}

int pl_proc_bsdinfo_read(pid_t pid, pl_proc_bsdinfo *out) {
    struct proc_bsdinfo bi;
    int n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, PROC_PIDTBSDINFO_SIZE);
    if (n == PROC_PIDTBSDINFO_SIZE) {
        out->pid = (pid_t)bi.pbi_pid;
        out->ppid = (pid_t)bi.pbi_ppid;
        out->uid = bi.pbi_uid;
        out->start_sec = bi.pbi_start_tvsec;
        out->start_usec = bi.pbi_start_tvusec;
        const char *name = bi.pbi_name[0] != '\0' ? bi.pbi_name : bi.pbi_comm;
        strlcpy(out->name, name, sizeof out->name);
        return 0;
    }

    // Processes of other users: the full record is denied, the short one is not.
    // It has no start time, and pbsi_comm is truncated to MAXCOMLEN, so prefer the
    // executable's basename when the path is readable.
    struct proc_bsdshortinfo si;
    n = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &si, PROC_PIDT_SHORTBSDINFO_SIZE);
    if (n != PROC_PIDT_SHORTBSDINFO_SIZE) return -1;
    out->pid = (pid_t)si.pbsi_pid;
    out->ppid = (pid_t)si.pbsi_ppid;
    out->uid = si.pbsi_uid;
    out->start_sec = 0;
    out->start_usec = 0;
    strlcpy(out->name, si.pbsi_comm, sizeof out->name);
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof path) > 0) {
        const char *slash = strrchr(path, '/');
        const char *base = slash != NULL ? slash + 1 : path;
        if (base[0] != '\0' && strncmp(base, si.pbsi_comm, strlen(si.pbsi_comm)) == 0) {
            strlcpy(out->name, base, sizeof out->name);
        }
    }
    return 0;
}

int pl_proc_cwd(pid_t pid, char *buf, size_t buflen) {
    struct proc_vnodepathinfo vpi;
    int n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof vpi);
    if (n != (int)sizeof vpi) return -1;
    strlcpy(buf, vpi.pvi_cdir.vip_path, buflen);
    return 0;
}

int pl_proc_argv(pid_t pid, char *buf, size_t buflen, int *argc_out, size_t *len_out) {
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return -1;
    char *raw = malloc(size);
    if (raw == NULL) return -1;
    if (sysctl(mib, 3, raw, &size, NULL, 0) != 0 || size < sizeof(int)) { free(raw); return -1; }

    // Layout: int argc, exec_path\0, padding \0..., argv[0]\0 ... argv[argc-1]\0, env...
    int argc;
    memcpy(&argc, raw, sizeof argc);
    char *p = raw + sizeof argc;
    char *end = raw + size;
    while (p < end && *p != '\0') p++;       // skip exec path
    while (p < end && *p == '\0') p++;       // skip padding

    size_t written = 0;
    int copied = 0;
    while (copied < argc && p < end) {
        size_t len = strnlen(p, (size_t)(end - p));
        if (written + len + 1 > buflen) break;
        memcpy(buf + written, p, len);
        buf[written + len] = '\0';
        written += len + 1;
        p += len + 1;
        copied++;
    }
    free(raw);
    *argc_out = copied;
    *len_out = written;
    return 0;
}

// MARK: - SMC

typedef struct { char major, minor, build, reserved; uint16_t release; } pl_smc_vers;
typedef struct { uint16_t version, length; uint32_t cpu_plimit, gpu_plimit, mem_plimit; } pl_smc_plimit;
typedef struct { uint32_t data_size, data_type; uint8_t data_attributes; } pl_smc_keyinfo;
typedef struct {
    uint32_t key;
    pl_smc_vers vers;
    pl_smc_plimit plimit;
    pl_smc_keyinfo keyinfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} pl_smc_param;

enum { PL_SMC_KERNEL_INDEX = 2, PL_SMC_CMD_READ_BYTES = 5, PL_SMC_CMD_READ_KEYINFO = 9 };

static io_connect_t smc_conn = 0;

typedef struct { uint32_t key; pl_smc_keyinfo info; } pl_smc_cache_entry;
static pl_smc_cache_entry smc_cache[32];
static int smc_cache_count = 0;

static uint32_t smc_fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static int smc_call(pl_smc_param *in, pl_smc_param *out) {
    size_t out_size = sizeof *out;
    kern_return_t kr = IOConnectCallStructMethod(smc_conn, PL_SMC_KERNEL_INDEX, in, sizeof *in, out, &out_size);
    if (kr != KERN_SUCCESS || out->result != 0) return -1;
    return 0;
}

int pl_smc_open(void) {
    if (smc_conn != 0) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return -1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &smc_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) { smc_conn = 0; return -1; }
    return 0;
}

void pl_smc_close(void) {
    if (smc_conn != 0) {
        IOServiceClose(smc_conn);
        smc_conn = 0;
    }
    smc_cache_count = 0;
}

static int smc_keyinfo(uint32_t key, pl_smc_keyinfo *info) {
    for (int i = 0; i < smc_cache_count; i++) {
        if (smc_cache[i].key == key) { *info = smc_cache[i].info; return 0; }
    }
    pl_smc_param in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = key;
    in.data8 = PL_SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != 0) return -1;
    *info = out.keyinfo;
    if (smc_cache_count < (int)(sizeof smc_cache / sizeof smc_cache[0])) {
        smc_cache[smc_cache_count].key = key;
        smc_cache[smc_cache_count].info = out.keyinfo;
        smc_cache_count++;
    }
    return 0;
}

int pl_smc_read_float(const char *key, float *out_value) {
    if (smc_conn == 0 || key == NULL || strlen(key) != 4) { errno = EINVAL; return -1; }
    uint32_t k = smc_fourcc(key);
    pl_smc_keyinfo info;
    if (smc_keyinfo(k, &info) != 0) return -1;
    if (info.data_type != smc_fourcc("flt ") || info.data_size != 4) { errno = EINVAL; return -1; }

    pl_smc_param in, out;
    memset(&in, 0, sizeof in);
    memset(&out, 0, sizeof out);
    in.key = k;
    in.keyinfo.data_size = info.data_size;
    in.data8 = PL_SMC_CMD_READ_BYTES;
    if (smc_call(&in, &out) != 0) return -1;
    float value;
    memcpy(&value, out.bytes, sizeof value);
    *out_value = value;
    return 0;
}
