// Validation 2: per-app (coalition) GPU / ANE energy vs the chip-level IOReport counters.
//
// Sums GPU and ANE energy over all resource coalitions during an interval and prints it next to
// IOReport's "Energy Model" channels for the same interval. Run it while synthetic_load drives
// the GPU or the ANE. Note: on macOS 27 the IOReport CPU and ANE channels are stalled (read 0);
// GPU still works, so GPU is the cross-check and ANE is judged from the coalition side alone.
//
// Usage: coalition_vs_chip [seconds]
#include "CProbes.h"

#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef CFDictionaryRef IOReportSample;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
extern void *IOReportCreateSubscription(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamples(void *, CFMutableDictionaryRef, CFTypeRef);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
extern void IOReportIterate(CFDictionaryRef, int (^)(IOReportSample));
extern CFStringRef IOReportChannelGetChannelName(IOReportSample);
extern CFStringRef IOReportChannelGetUnitLabel(IOReportSample);
extern int64_t IOReportSimpleGetIntegerValue(IOReportSample, int32_t);

#define MAX_COALITIONS 4096

static int list_coalitions(uint64_t *out, int max) {
    static pid_t pids[16384];
    int n = proc_listallpids(pids, sizeof pids);
    int count = 0;
    for (int i = 0; i < n; i++) {
        uint64_t cid;
        if (pl_pid_resource_coalition(pids[i], &cid) != 0) continue;
        int seen = 0;
        for (int j = 0; j < count; j++) if (out[j] == cid) { seen = 1; break; }
        if (!seen && count < max) out[count++] = cid;
    }
    return count;
}

int main(int argc, char **argv) {
    double seconds = argc > 1 ? atof(argv[1]) : 5;
    static uint64_t cids[MAX_COALITIONS];
    static pl_coalition_usage before[MAX_COALITIONS], after[MAX_COALITIONS];
    int n = list_coalitions(cids, MAX_COALITIONS);

    CFDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    CFMutableDictionaryRef wanted = CFDictionaryCreateMutableCopy(NULL, 0, channels), subscribed = NULL;
    void *sub = IOReportCreateSubscription(NULL, wanted, &subscribed, 0, NULL);

    CFDictionaryRef s0 = IOReportCreateSamples(sub, subscribed, NULL);
    for (int i = 0; i < n; i++) pl_coalition_usage_read(cids[i], &before[i]);
    usleep((useconds_t)(seconds * 1e6));
    CFDictionaryRef s1 = IOReportCreateSamples(sub, subscribed, NULL);
    for (int i = 0; i < n; i++) pl_coalition_usage_read(cids[i], &after[i]);

    __block double chip_gpu = 0, chip_ane = 0;
    IOReportIterate(IOReportCreateSamplesDelta(s0, s1, NULL), ^int(IOReportSample ch) {
        char name[96] = "", unit[16] = "";
        CFStringGetCString(IOReportChannelGetChannelName(ch), name, sizeof name, kCFStringEncodingUTF8);
        CFStringRef u = IOReportChannelGetUnitLabel(ch);
        if (u) CFStringGetCString(u, unit, sizeof unit, kCFStringEncodingUTF8);
        double scale = !strcmp(unit, "mJ") ? 1e-3 : !strcmp(unit, "uJ") ? 1e-6 : !strcmp(unit, "nJ") ? 1e-9 : 0;
        double joules = IOReportSimpleGetIntegerValue(ch, 0) * scale;
        if (!strcmp(name, "GPU Energy")) chip_gpu = joules;
        else if (!strcmp(name, "ANE") || !strcmp(name, "ANE0") || !strcmp(name, "ANE1")) chip_ane += joules;
        return 0;
    });

    double cpu = 0, gpu = 0, ane = 0;
    for (int i = 0; i < n; i++) {
        if (after[i].cpu_energy_nj < before[i].cpu_energy_nj) continue;
        cpu += (after[i].cpu_energy_nj - before[i].cpu_energy_nj) / 1e9;
        gpu += (after[i].gpu_energy_nj - before[i].gpu_energy_nj) / 1e9;
        ane += (after[i].ane_energy_nj - before[i].ane_energy_nj) / 1e9;
    }
    printf("chip (IOReport): GPU %.3f W  ANE %.3f W | coalitions (%d): CPU %.3f W  GPU %.3f W  ANE %.3f W\n",
           chip_gpu / seconds, chip_ane / seconds, n, cpu / seconds, gpu / seconds, ane / seconds);
    return 0;
}
