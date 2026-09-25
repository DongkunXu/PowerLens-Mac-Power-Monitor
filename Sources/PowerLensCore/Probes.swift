import CProbes
import Darwin
import Foundation

/// Conversion between mach_absolute_time ticks and seconds.
enum MachTime {
    static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func seconds(fromTicks ticks: UInt64) -> Double { Double(ticks) * secondsPerTick }

    /// Seconds since boot, excluding time asleep.
    static func awakeNow() -> Double { seconds(fromTicks: mach_absolute_time()) }

    /// Seconds since boot, including time asleep.
    static func continuousNow() -> Double { seconds(fromTicks: mach_continuous_time()) }
}

/// Cumulative counters of one resource coalition.
struct CoalitionCounters: Equatable {
    var cpuTime: Double      // seconds
    var cpuEnergy: Double    // joules
    var gpuTime: Double      // seconds
    var gpuEnergy: Double    // joules
    var aneEnergy: Double    // joules
}

/// Cumulative counters of one process.
struct ProcessCounters: Equatable {
    var cpuTime: Double      // seconds
    var cpuEnergy: Double    // joules
}

struct ProcessBasicInfo: Equatable {
    var pid: pid_t
    var ppid: pid_t
    var uid: uid_t
    var startSec: UInt64
    var startUsec: UInt64
    var name: String
}

/// Thin Swift wrappers over CProbes. All functions are safe to call from any thread
/// except the SMC reader, which is owned by a single sampler.
enum Probes {
    static func allPIDs() -> [pid_t] {
        var capacity = 4096
        while true {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = buffer.withUnsafeMutableBytes { raw in
                proc_listallpids(raw.baseAddress, Int32(raw.count))
            }
            if bytes <= 0 { return [] }
            let count = Int(bytes)
            // proc_listallpids returns a count of pids; if the buffer was full, grow and retry.
            // pid 0 is kernel_task; it belongs to the kernel coalition and is kept.
            if count < capacity { return Array(buffer.prefix(count)) }
            capacity *= 2
        }
    }

    static func coalitionID(of pid: pid_t) -> UInt64? {
        var cid: UInt64 = 0
        return pl_pid_resource_coalition(pid, &cid) == 0 ? cid : nil
    }

    static func coalitionCounters(_ cid: UInt64) -> CoalitionCounters? {
        var usage = pl_coalition_usage()
        guard pl_coalition_usage_read(cid, &usage) == 0 else { return nil }
        return CoalitionCounters(
            cpuTime: MachTime.seconds(fromTicks: usage.cpu_time_mach),
            cpuEnergy: Double(usage.cpu_energy_nj) / 1e9,
            gpuTime: Double(usage.gpu_time_ns) / 1e9,
            gpuEnergy: Double(usage.gpu_energy_nj) / 1e9,
            aneEnergy: Double(usage.ane_energy_nj) / 1e9
        )
    }

    static func coalitionName(_ cid: UInt64) -> String? {
        guard let cString = pl_coalition_copy_name(cid) else { return nil }
        defer { free(cString) }
        return String(cString: cString)
    }

    static func processCounters(_ pid: pid_t) -> ProcessCounters? {
        var usage = pl_proc_usage()
        guard pl_proc_usage_read(pid, &usage) == 0 else { return nil }
        return ProcessCounters(
            cpuTime: MachTime.seconds(fromTicks: usage.cpu_time_mach),
            cpuEnergy: Double(usage.cpu_energy_nj) / 1e9
        )
    }

    static func basicInfo(_ pid: pid_t) -> ProcessBasicInfo? {
        var info = pl_proc_bsdinfo()
        guard pl_proc_bsdinfo_read(pid, &info) == 0 else { return nil }
        let name = withUnsafeBytes(of: info.name) { raw -> String in
            let bytes = raw.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
        return ProcessBasicInfo(pid: info.pid, ppid: info.ppid, uid: info.uid,
                                startSec: info.start_sec, startUsec: info.start_usec, name: name)
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return string(fromNulTerminated: buffer)
    }

    static func workingDirectory(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) + 1)
        guard pl_proc_cwd(pid, &buffer, buffer.count) == 0 else { return nil }
        let path = string(fromNulTerminated: buffer)
        return path.isEmpty ? nil : path
    }

    private static func string(fromNulTerminated buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func arguments(_ pid: pid_t) -> [String]? {
        var buffer = [CChar](repeating: 0, count: 16 * 1024)
        var argc: Int32 = 0
        var length = 0
        guard pl_proc_argv(pid, &buffer, buffer.count, &argc, &length) == 0 else { return nil }
        var result: [String] = []
        var start = 0
        for i in 0..<length where buffer[i] == 0 {
            let bytes = buffer[start..<i].map { UInt8(bitPattern: $0) }
            result.append(String(decoding: bytes, as: UTF8.self))
            start = i + 1
        }
        return result
    }
}

/// Owns the SMC connection. Not thread-safe; use from the sampler queue only.
final class SMCReader {
    private var isOpen = false

    init() {
        isOpen = pl_smc_open() == 0
    }

    deinit {
        if isOpen { pl_smc_close() }
    }

    /// Whole-system power in watts (SMC key PSTR), or nil when unavailable.
    func systemPower() -> Double? {
        guard isOpen else { return nil }
        var value: Float = 0
        guard pl_smc_read_float("PSTR", &value) == 0, value.isFinite, value >= 0 else { return nil }
        return Double(value)
    }
}
