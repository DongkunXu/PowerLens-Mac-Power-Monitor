import Darwin
import Foundation

/// Owns sampling, history and aggregation. All mutable state lives on `queue`;
/// container polling runs on its own queue because Docker requests can block.
public final class PowerMonitor: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Sampling interval while the panel is open.
        public var visibleInterval: TimeInterval = 1
        /// Sampling interval while the panel is closed (history keeps accumulating).
        public var hiddenInterval: TimeInterval = 3
        /// Window for the smoothed values and the list ranking.
        public var smoothingWindow: TimeInterval = 30
        /// History kept for the chart: the longest chart range (15 min) plus one minute of slack.
        public var retention: TimeInterval = 16 * 60
        /// Window of the sparklines behind the category tiles.
        public var sparklineWindow: TimeInterval = 60
        public var maxRows = 10
        public var maxChildren = 8
        public var chartPoints = 180
        public var containerInterval: TimeInterval = 3
        public var assertionRefresh: TimeInterval = 5

        public init() {}
    }

    private let config: Configuration
    private let queue = DispatchQueue(label: "PowerLens.monitor", qos: .utility)
    private let containerQueue = DispatchQueue(label: "PowerLens.containers", qos: .utility)

    // State confined to `queue`.
    private let sampler = Sampler()
    private let history: UsageHistory
    private let processHistory: ProcessHistory
    private var timer: DispatchSourceTimer?
    private var visible = false
    private var options = PanelOptions()
    private var lastSample: RawSample?
    private var containerResults: [ContainerBreakdown] = []
    private var assertions: [SleepAssertionState] = []
    private var assertionsReadAt: Double = -.infinity
    private var onUpdate: (@Sendable (PanelState) -> Void)?
    private var ticksSincePrune = 0

    // State confined to `containerQueue`.
    private let containerMonitor = ContainerMonitor()
    private var containerTimer: DispatchSourceTimer?

    private let ownPID = getpid()

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        self.history = UsageHistory(retention: configuration.retention)
        self.processHistory = ProcessHistory(retention: configuration.smoothingWindow + 5)
    }

    /// Starts sampling. `onUpdate` is called on a background queue after every sample while visible.
    public func start(onUpdate: @escaping @Sendable (PanelState) -> Void) {
        queue.async {
            self.onUpdate = onUpdate
            _ = self.sampler.sample()   // establish baselines
            self.schedule(interval: self.visible ? self.config.visibleInterval : self.config.hiddenInterval)
        }
    }

    public func setVisible(_ newValue: Bool) {
        queue.async {
            guard self.visible != newValue else { return }
            self.visible = newValue
            self.schedule(interval: newValue ? self.config.visibleInterval : self.config.hiddenInterval)
            if newValue {
                self.assertionsReadAt = -.infinity
                self.publish()
            } else {
                self.containerResults = []
            }
        }
        containerQueue.async {
            if newValue { self.startContainerPolling() } else { self.stopContainerPolling() }
        }
    }

    public func setOptions(_ newValue: PanelOptions) {
        queue.async {
            guard self.options != newValue else { return }
            self.options = newValue
            if self.visible { self.publish() }
        }
    }

    // MARK: - Sampling loop (queue)

    private func schedule(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Leeway lets the OS coalesce wakeups with other timers.
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        if let sample = sampler.sample() {
            history.append(sample)
            processHistory.append(sample)
            lastSample = sample
        }
        ticksSincePrune += 1
        if ticksSincePrune >= 60 {
            ticksSincePrune = 0
            sampler.prune(keeping: history.liveKeys)
        }
        if visible { publish() }
    }

    private func publish() {
        guard let onUpdate else { return }
        onUpdate(buildState())
    }

    private func buildState() -> PanelState {
        let now = lastSample?.wallTime ?? Date()
        let smoothed = history.summary(lastSeconds: config.smoothingWindow, now: now)
        let recent = history.latestSummary()   // "now" = the latest sampling interval only
        let processes = processHistory.averages(lastSeconds: config.smoothingWindow, now: now)
        let latestProcesses = processHistory.latest()
        let awakeNow = MachTime.awakeNow()

        func reading(_ value: (WindowSummary) -> Double) -> PowerReading {
            PowerReading(now: recent.coveredSeconds > 0 ? value(recent) : nil,
                         smoothed: smoothed.coveredSeconds > 0 ? value(smoothed) : nil)
        }
        func other(_ s: WindowSummary) -> Double? {
            guard s.coveredSeconds > 0, let system = s.systemPower else { return nil }
            return max(0, system - (s.cpuPower + s.gpuPower + s.anePower))
        }
        let totals = TotalsState(
            system: PowerReading(now: recent.systemPower, smoothed: smoothed.systemPower),
            cpu: reading(\.cpuPower),
            gpu: reading(\.gpuPower),
            ane: reading(\.anePower),
            other: PowerReading(now: other(recent), smoothed: other(smoothed))
        )

        let ranked = smoothed.groups.sorted {
            $0.value.totalPower > $1.value.totalPower || ($0.value.totalPower == $1.value.totalPower && $0.key < $1.key)
        }.prefix(config.maxRows)

        let unreadable = lastSample?.groupsWithUnreadableMembers ?? []
        var rows: [RowState] = []
        for (key, average) in ranked {
            let members = (processes[key] ?? []).sorted { $0.cpuPower > $1.cpuPower || ($0.cpuPower == $1.cpuPower && $0.pid < $1.pid) }
            let visibleMembers = members.filter { $0.cpuPower >= 0.005 || $0.cpuCores >= 0.005 }.prefix(config.maxChildren)
            let children = visibleMembers.map { p in
                ChildState(pid: p.pid,
                           name: sampler.processInfo(p.pid)?.name ?? "pid \(p.pid)",
                           details: sampler.catalog.details(pid: p.pid, now: awakeNow),
                           cpuPower: p.cpuPower, cpuCores: p.cpuCores,
                           nowCpuPower: latestProcesses[p.pid]?.cpuPower ?? 0,
                           nowCpuCores: latestProcesses[p.pid]?.cpuCores ?? 0)
            }
            let attributed = members.reduce(0) { $0 + $1.cpuPower }
            rows.append(RowState(
                info: info(for: key),
                smoothed: average,
                now: recent.groups[key] ?? GroupAverage(),
                children: Array(children),
                hiddenChildren: max(0, members.count - children.count),
                remainderPower: max(0, average.cpuPower - attributed),
                remainderKind: unreadable.contains(key) ? .unreadableOrExited : .exitedProcesses,
                containers: containerResults.first { $0.groupKey == key }
            ))
        }

        let chart = history.chart(range: options.chartRange, now: now,
                                  maxPoints: config.chartPoints, topN: options.chartTopN)
        var chartInfo: [GroupKey: GroupInfo] = [:]
        for series in chart.series { chartInfo[series.key] = info(for: series.key) }

        if awakeNow - assertionsReadAt >= config.assertionRefresh {
            assertions = SleepAssertions.read()
            assertionsReadAt = awakeNow
        }

        let selfPower = processes.values.lazy.flatMap { $0 }.first { $0.pid == self.ownPID }?.cpuPower

        return PanelState(
            time: now,
            sampleInterval: visible ? config.visibleInterval : config.hiddenInterval,
            smoothingWindow: config.smoothingWindow,
            totals: totals,
            recentTotals: history.totalsSeries(lastSeconds: config.sparklineWindow, now: now),
            sparklineWindow: config.sparklineWindow,
            rows: rows,
            chart: chart,
            chartInfo: chartInfo,
            assertions: assertions,
            selfPower: selfPower,
            warmedUp: smoothed.coveredSeconds >= config.smoothingWindow * 0.9
        )
    }

    private func info(for key: GroupKey) -> GroupInfo {
        sampler.groupInfo[key] ?? GroupInfo(key: key, kind: .process, displayName: key.rawValue, subtitle: nil, bundlePath: nil)
    }

    // MARK: - Containers (containerQueue)

    private func startContainerPolling() {
        containerTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: containerQueue)
        t.schedule(deadline: .now(), repeating: config.containerInterval, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.pollContainers() }
        t.resume()
        containerTimer = t
    }

    private func stopContainerPolling() {
        containerTimer?.cancel()
        containerTimer = nil
        containerMonitor.reset()
    }

    private func pollContainers() {
        let results = containerMonitor.poll(vmProcess: Self.findProcess)
        queue.async {
            if self.visible { self.containerResults = results }
        }
    }

    /// Finds a live process by name, optionally requiring its coalition's group key.
    static func findProcess(named name: String, in key: GroupKey?) -> pid_t? {
        for pid in Probes.allPIDs() {
            guard let info = Probes.basicInfo(pid), info.name == name else { continue }
            guard let key else { return pid }
            guard let cid = Probes.coalitionID(of: pid) else { continue }
            let kind = CoalitionNaming.kind(label: Probes.coalitionName(cid))
            if CoalitionNaming.key(kind: kind, leaderName: info.name) == key { return pid }
        }
        return nil
    }
}
