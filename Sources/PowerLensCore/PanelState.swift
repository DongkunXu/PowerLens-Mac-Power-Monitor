import Foundation

/// User-adjustable view options that affect aggregation.
public struct PanelOptions: Sendable, Equatable {
    public var chartRange: TimeInterval
    public var chartTopN: Int

    public init(chartRange: TimeInterval = 15 * 60, chartTopN: Int = 5) {
        self.chartRange = chartRange
        self.chartTopN = chartTopN
    }
}

/// A pair of readings: the latest sampling interval (1 s while the panel is open), and the smoothed window.
public struct PowerReading: Sendable, Equatable {
    public var now: Double?
    public var smoothed: Double?

    public init(now: Double?, smoothed: Double?) {
        self.now = now
        self.smoothed = smoothed
    }
}

public struct TotalsState: Sendable, Equatable {
    /// SMC whole-system power (nil when the SMC is unreadable).
    public var system: PowerReading
    /// Sums over all groups, from kernel per-app counters.
    public var cpu: PowerReading
    public var gpu: PowerReading
    public var ane: PowerReading
    /// system − (cpu + gpu + ane): display, memory, storage, radios, SoC fabric, idle cores.
    public var other: PowerReading
}

/// Category totals of one sampling interval (watts).
public struct TotalsSample: Sendable, Equatable, Identifiable {
    public var time: Date
    public var system: Double?
    public var cpu: Double
    public var gpu: Double
    public var ane: Double
    public var other: Double?
    public var id: Date { time }
}

public struct ChildState: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var details: ProcessDetails
    /// Averages over the smoothing window.
    public var cpuPower: Double
    public var cpuCores: Double
    /// Latest sampling interval (0 when the process was idle in it).
    public var nowCpuPower: Double
    public var nowCpuCores: Double
    public var id: Int32 { pid }
}

public enum RemainderKind: Sendable, Equatable {
    /// Energy of member processes that exited during the window.
    case exitedProcesses
    /// Members exist whose per-process counters this user cannot read; the remainder
    /// includes them (and possibly exited processes).
    case unreadableOrExited
}

public struct RowState: Sendable, Equatable, Identifiable {
    public var info: GroupInfo
    public var smoothed: GroupAverage
    public var now: GroupAverage
    /// Live member processes, highest power first (capped).
    public var children: [ChildState]
    /// Number of live members not listed in `children`.
    public var hiddenChildren: Int
    /// CPU power of the group not explained by the listed + hidden live members.
    public var remainderPower: Double
    public var remainderKind: RemainderKind
    public var containers: ContainerBreakdown?
    public var id: GroupKey { info.key }
}

public struct PanelState: Sendable, Equatable {
    public var time: Date
    public var sampleInterval: TimeInterval
    public var smoothingWindow: TimeInterval
    public var totals: TotalsState
    /// Per-sample category totals over the last `sparklineWindow` seconds.
    public var recentTotals: [TotalsSample]
    public var sparklineWindow: TimeInterval
    public var rows: [RowState]
    public var chart: ChartData
    /// Names for every series in the chart (they may fall outside the top-10 rows).
    public var chartInfo: [GroupKey: GroupInfo]
    public var assertions: [SleepAssertionState]
    /// PowerLens's own CPU power over the smoothed window.
    public var selfPower: Double?
    /// False until enough samples exist for the smoothed window.
    public var warmedUp: Bool
}
