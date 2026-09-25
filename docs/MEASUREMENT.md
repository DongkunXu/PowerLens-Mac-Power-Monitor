# How PowerLens measures power

Validated on a MacBook Pro with an Apple M5 Pro (one 6-core S cluster and two 6-core P clusters), macOS 27.0 (26A428), in September 2026.

## Data sources

| Number in the panel | Source | Access |
|---|---|---|
| System power | SMC sensor `PSTR` (measured whole-system power, updated about every 0.9 s) | Normal user |
| Per-app CPU / GPU / ANE energy | Kernel resource-coalition counters: `energy`, `gpu_energy_nj` and `ane_energy_nj` in `coalition_info_resource_usage` (nanojoules, cumulative, including members that have exited) | Normal user |
| Per-app CPU and GPU usage | `cpu_time` and `gpu_time` in the same structure | Normal user |
| Grouping and names | Each process's coalition (`PROC_PIDCOALITIONINFO`) and the coalition's launchd label (`xpc_coalition_copy_info`). Labels of the form `application.<bundle id>.…` are shown as apps; everything else as services or processes | Normal user |
| CPU energy of child processes | `ri_energy_nj` from `proc_pid_rusage` | Own processes only |
| Containers | Measured CPU energy of the virtual machine host process (`OrbStack Helper` for OrbStack), split by each container's share of CPU time as reported by the Docker API | Normal user |
| CPU / GPU / ANE tiles | Sum of the corresponding energy over all apps | Derived |
| Other | System minus (CPU + GPU + ANE): display backlight, memory, storage, wireless, shared chip logic, idle cores | Derived |

A resource coalition is the grouping Activity Monitor uses when it combines processes by app: Electron helpers, XPC services and command-line child processes started by an app all belong to it.

## Sources that were tried and dropped

- **IOReport "Energy Model" CPU channels.** On macOS 27 they stopped updating and read 0 even as root (the same is reported in macmon issue #76). The ANE channel also reads 0, while the coalition ANE counters work. The GPU channel works and is used as a cross-check.
- **`powermetrics`.** It needs root, and at a 1-second interval it uses 36–47 ms of CPU per second itself, which made it the largest energy consumer on an idle machine. Too expensive for a live source.
- **SMC CPU power rails.** Key meanings differ between chip generations and would have to be verified per chip, while the kernel already provides per-app figures.

## Validation (`scripts/validate.sh`)

**CPU: N cores at full load; energy billed to those processes versus the rise in system power**

| Busy cores | Rise in system power | Energy billed to the workers | Share |
|---|---|---|---|
| 1 | 5.2–6.5 W | 3.5 W | 53–68% |
| 3 | 8.7–15.5 W | 8.5 W | 55–98% |
| 6 | 19.6–23.0 W | 16.6–17.2 W | 72–88% |

The ranges cover two runs on a machine in normal use, where the idle baseline moved by ±1–2 W. The kernel bills the energy of the cores themselves. Waking a cluster, the on-chip fabric, the memory controller and heat are shared costs that belong to no single process, and they land in Other. App figures show what each app consumes directly: the right order of magnitude, and comparable between apps.

**GPU: Metal compute load**

Chip counter 18.13–18.55 W; sum over all coalitions 17.26–17.42 W, i.e. 94–95% of the chip counter.

**ANE: Vision text recognition**

The chip counter reads 0 (broken, see above); the coalition counters record 0.50–1.44 W, all under the app running the load. The first time a program uses the Neural Engine, the system compiles the model, on the CPU, inside the `aned` service; only then does the work run on the ANE. The validation script therefore warms up once before measuring.

**Per-process counter resolution.** Read every 0.2 s, the values rise smoothly without batching, which supports a 1-second refresh.

**PowerLens's own cost.** With the panel closed (a sample every 3 s), about 0.001 W of CPU power, 0.5–0.7% of one core. One full sample takes about 2.6 ms. With the panel open, about 0.02 W.

## What the numbers mean

- Every value is an **average over an interval**. The counters are cumulative: the difference between two readings divided by the elapsed time gives the exact average for that interval, short peaks included.
- Large numbers are the latest sample (the last second while the panel is open, the last 3 seconds while it is closed). Small grey numbers are 30-second averages. The list is sorted by the 30-second average, which keeps its order steady from one second to the next.
- The tile curves cover the last 60 seconds, one point per sample. A point at the left edge is interpolated from the sample just before the window, which lets the curve fill the whole tile. The big chart does the same. Right after launch there is nothing older to interpolate from, and the left part stays empty until real data arrives.
- **Chart.** Each point is the average power in a time bucket: 2 s for the 5-minute range, 5 s for the 15-minute range. Bucket boundaries are aligned to absolute time (multiples of the bucket width). Completed buckets stay identical on every refresh, and only the rightmost, still-filling bucket changes. Anchoring buckets to the start of the sliding window would re-partition the data with a different phase on every refresh, and the whole curve would visibly jump. A sample that spans several buckets is split in proportion to time. The line breaks wherever data is missing or the Mac was asleep. The y-axis maximum is rounded up to 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8 or 10 times a power of ten, which keeps the axis still when the peak moves a little. The chart shows the N apps with the highest average over the selected range; an app keeps its color regardless of rank.
- **Exited processes**: the app's total energy minus the sum of its running child processes. If the app has member processes owned by another user (such as root), the row reads **Unreadable or exited processes**, because the two cannot be told apart.

## Known limitations

- The kernel's own coalition (`kernel_task`) is visible, but it cannot be broken down further without root.
- Container figures are estimates: the virtual machine host's energy is measured, but its split between containers is derived from CPU-time shares. **VM overhead** is the part that cannot be attributed to any container.
- The container split has been verified with OrbStack only. The Docker Desktop path (host process `com.apple.Virtualization.VirtualMachine`, socket `~/.docker/run/docker.sock`) is implemented but not yet verified.
- PowerLens connects to a container runtime only when its virtual machine is already running. A stopped runtime stays stopped.
- Validated on one machine (M5 Pro, macOS 27). Other chips may differ in counter coverage and in what the SMC `PSTR` key measures; `scripts/validate.sh` is the way to check.
