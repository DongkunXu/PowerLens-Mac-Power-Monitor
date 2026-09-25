import Darwin
import Foundation

/// Energy and time used by one group during one sampling interval.
public struct GroupUsage: Sendable, Equatable {
    public var cpuEnergy: Double = 0   // J
    public var gpuEnergy: Double = 0   // J
    public var aneEnergy: Double = 0   // J
    public var cpuTime: Double = 0     // s
    public var gpuTime: Double = 0     // s

    public var totalEnergy: Double { cpuEnergy + gpuEnergy + aneEnergy }

    static func += (a: inout GroupUsage, b: GroupUsage) {
        a.cpuEnergy += b.cpuEnergy
        a.gpuEnergy += b.gpuEnergy
        a.aneEnergy += b.aneEnergy
        a.cpuTime += b.cpuTime
        a.gpuTime += b.gpuTime
    }
}

/// CPU energy and time used by one live process during one sampling interval.
public struct ProcessUsage: Sendable, Equatable {
    public var pid: pid_t
    public var key: GroupKey
    public var cpuEnergy: Double       // J
    public var cpuTime: Double         // s
}

/// Result of one sampling pass.
public struct RawSample: Sendable {
    /// Wall-clock time at the end of the interval.
    public var wallTime: Date
    /// Awake seconds covered by this interval (time asleep is excluded; counters stop while asleep).
    public var awakeDuration: Double
    /// True when the machine slept during the interval, i.e. the chart must break here.
    public var sleptDuring: Bool
    /// SMC whole-system power at the end of the interval, if readable.
    public var systemPower: Double?
    public var groups: [GroupKey: GroupUsage]
    public var processes: [ProcessUsage]
    /// Groups that have live members whose per-process counters are not readable (other uid).
    public var groupsWithUnreadableMembers: Set<GroupKey>
}

/// Reads kernel counters and turns consecutive readings into per-interval usage.
/// Not thread-safe: drive it from one serial queue.
final class Sampler {
    private struct ProcessState {
        var basic: ProcessBasicInfo
        var coalition: UInt64
        var counters: ProcessCounters?
        var readable: Bool
    }

    private struct CoalitionState {
        var key: GroupKey
        var counters: CoalitionCounters
    }

    private let smc = SMCReader()
    private let resolver = AppResolver()
    let catalog = ProcessCatalog()

    private var processes: [pid_t: ProcessState] = [:]
    private var coalitions: [UInt64: CoalitionState] = [:]
    private var coalitionLabels: [UInt64: String?] = [:]
    private(set) var groupInfo: [GroupKey: GroupInfo] = [:]

    private var lastAwake: Double?
    private var lastContinuous: Double?

    /// Takes a reading. Returns nil on the first call (it only establishes baselines).
    func sample() -> RawSample? {
        let awake = MachTime.awakeNow()
        let continuous = MachTime.continuousNow()
        let wall = Date()
        let systemPower = smc.systemPower()

        // 1. Processes: membership, identity and per-process counters.
        let pids = Probes.allPIDs()
        var liveProcesses: [pid_t: ProcessState] = [:]
        liveProcesses.reserveCapacity(pids.count)
        var members: [UInt64: [pid_t]] = [:]
        var processUsages: [(pid: pid_t, cid: UInt64, usage: ProcessCounters, previous: ProcessCounters?)] = []
        var unreadableCoalitions: Set<UInt64> = []

        for pid in pids {
            guard let cid = Probes.coalitionID(of: pid) else { continue }
            var state: ProcessState
            if let previous = processes[pid], previous.coalition == cid {
                state = previous
            } else {
                guard let basic = Probes.basicInfo(pid) else { continue }
                state = ProcessState(basic: basic, coalition: cid, counters: nil, readable: true)
            }
            let previousCounters = state.counters
            if state.readable, let counters = Probes.processCounters(pid) {
                // A counter going backwards means the pid was reused by a new process.
                if let prev = previousCounters, counters.cpuEnergy < prev.cpuEnergy || counters.cpuTime < prev.cpuTime {
                    if let basic = Probes.basicInfo(pid) { state.basic = basic }
                    state.counters = counters
                    processUsages.append((pid, cid, counters, nil))
                } else {
                    state.counters = counters
                    processUsages.append((pid, cid, counters, previousCounters))
                }
            } else {
                state.readable = false
                unreadableCoalitions.insert(cid)
            }
            liveProcesses[pid] = state
            members[cid, default: []].append(pid)
        }
        for (pid, state) in processes where liveProcesses[pid] == nil || liveProcesses[pid]!.basic.startSec != state.basic.startSec {
            catalog.forget(pid: pid)
        }
        processes = liveProcesses

        // 2. Coalitions: cumulative energy per app, including exited members.
        var liveCoalitions: [UInt64: CoalitionState] = [:]
        var groupUsage: [GroupKey: GroupUsage] = [:]
        var cidKeys: [UInt64: GroupKey] = [:]
        for (cid, pidsInCoalition) in members {
            guard let counters = Probes.coalitionCounters(cid) else { continue }
            let key = coalitions[cid]?.key ?? identify(cid: cid, members: pidsInCoalition)
            cidKeys[cid] = key
            if let previous = coalitions[cid]?.counters {
                let usage = GroupUsage(
                    cpuEnergy: max(0, counters.cpuEnergy - previous.cpuEnergy),
                    gpuEnergy: max(0, counters.gpuEnergy - previous.gpuEnergy),
                    aneEnergy: max(0, counters.aneEnergy - previous.aneEnergy),
                    cpuTime: max(0, counters.cpuTime - previous.cpuTime),
                    gpuTime: max(0, counters.gpuTime - previous.gpuTime)
                )
                if usage.totalEnergy > 0 || usage.cpuTime > 0 {
                    groupUsage[key, default: GroupUsage()] += usage
                }
            }
            liveCoalitions[cid] = CoalitionState(key: key, counters: counters)
        }
        coalitions = liveCoalitions
        coalitionLabels = coalitionLabels.filter { liveCoalitions[$0.key] != nil }

        defer {
            lastAwake = awake
            lastContinuous = continuous
        }
        guard let lastAwake, let lastContinuous else { return nil }

        let awakeDuration = awake - lastAwake
        let sleptDuring = (continuous - lastContinuous) - awakeDuration > 0.5
        guard awakeDuration > 0 else { return nil }

        var processResults: [ProcessUsage] = []
        processResults.reserveCapacity(processUsages.count)
        for entry in processUsages {
            guard let previous = entry.previous, let key = cidKeys[entry.cid] else { continue }
            let energy = max(0, entry.usage.cpuEnergy - previous.cpuEnergy)
            let time = max(0, entry.usage.cpuTime - previous.cpuTime)
            if energy > 0 || time > 0 {
                processResults.append(ProcessUsage(pid: entry.pid, key: key, cpuEnergy: energy, cpuTime: time))
            }
        }

        return RawSample(
            wallTime: wall,
            awakeDuration: awakeDuration,
            sleptDuring: sleptDuring,
            systemPower: systemPower,
            groups: groupUsage,
            processes: processResults,
            groupsWithUnreadableMembers: Set(unreadableCoalitions.compactMap { cidKeys[$0] })
        )
    }

    func processInfo(_ pid: pid_t) -> ProcessBasicInfo? { processes[pid]?.basic }

    /// Drops naming data for groups that are neither running nor referenced by `referenced`
    /// (the retained history), so long runtimes do not accumulate entries for every app ever seen.
    func prune(keeping referenced: Set<GroupKey>) {
        let live = Set(coalitions.values.map(\.key))
        groupInfo = groupInfo.filter { live.contains($0.key) || referenced.contains($0.key) }
        resolver.reset()
    }

    // MARK: - Naming

    private func identify(cid: UInt64, members: [pid_t]) -> GroupKey {
        let label: String?
        if let cached = coalitionLabels[cid] {
            label = cached
        } else {
            label = Probes.coalitionName(cid)
            coalitionLabels[cid] = label
        }
        let leader = leaderPID(members)
        let leaderName = leader.flatMap { processes[$0]?.basic.name } ?? "cid \(cid)"
        let kind = CoalitionNaming.kind(label: label)
        let key = CoalitionNaming.key(kind: kind, leaderName: leaderName)

        if groupInfo[key] == nil {
            groupInfo[key] = makeInfo(key: key, kind: kind, leader: leader, leaderName: leaderName)
        }
        return key
    }

    /// The process launchd started for the coalition (parent 1), else the oldest member.
    private func leaderPID(_ members: [pid_t]) -> pid_t? {
        let states = members.compactMap { processes[$0] }
        let launchedByLaunchd = states.filter { $0.basic.ppid == 1 }
        let pool = launchedByLaunchd.isEmpty ? states : launchedByLaunchd
        return pool.min { ($0.basic.startSec, $0.basic.startUsec, $0.basic.pid) < ($1.basic.startSec, $1.basic.startUsec, $1.basic.pid) }?.basic.pid
    }

    private func makeInfo(key: GroupKey, kind: GroupKind, leader: pid_t?, leaderName: String) -> GroupInfo {
        let leaderPath = leader.flatMap(Probes.executablePath)
        switch kind {
        case .app(let bundleID):
            if let app = resolver.app(bundleID: bundleID) {
                return GroupInfo(key: key, kind: kind, displayName: app.name, subtitle: bundleID, bundlePath: app.path)
            }
            if let path = leaderPath, let app = resolver.enclosingApp(executablePath: path) {
                return GroupInfo(key: key, kind: kind, displayName: app.name, subtitle: bundleID, bundlePath: app.path)
            }
            return GroupInfo(key: key, kind: kind, displayName: leaderName, subtitle: bundleID, bundlePath: nil)
        case .service(let label):
            if let path = leaderPath, let app = resolver.enclosingApp(executablePath: path) {
                return GroupInfo(key: key, kind: kind, displayName: app.name, subtitle: "\(leaderName) · \(label)", bundlePath: app.path)
            }
            return GroupInfo(key: key, kind: kind, displayName: leaderName, subtitle: label, bundlePath: nil)
        case .process:
            if let path = leaderPath, let app = resolver.enclosingApp(executablePath: path) {
                return GroupInfo(key: key, kind: kind, displayName: app.name, subtitle: leaderName, bundlePath: app.path)
            }
            return GroupInfo(key: key, kind: kind, displayName: leaderName, subtitle: leaderPath, bundlePath: nil)
        }
    }
}
