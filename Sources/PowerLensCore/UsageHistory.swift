import Darwin
import Foundation

/// Compact per-group record inside one history entry (Float keeps an hour of 1 s samples small).
struct CompactUsage: Equatable {
    var cpuEnergy: Float
    var gpuEnergy: Float
    var aneEnergy: Float
    var cpuTime: Float
    var gpuTime: Float

    init(_ u: GroupUsage) {
        cpuEnergy = Float(u.cpuEnergy)
        gpuEnergy = Float(u.gpuEnergy)
        aneEnergy = Float(u.aneEnergy)
        cpuTime = Float(u.cpuTime)
        gpuTime = Float(u.gpuTime)
    }

    var expanded: GroupUsage {
        GroupUsage(cpuEnergy: Double(cpuEnergy), gpuEnergy: Double(gpuEnergy), aneEnergy: Double(aneEnergy),
                   cpuTime: Double(cpuTime), gpuTime: Double(gpuTime))
    }
}

struct HistoryEntry {
    var wallTime: Date
    var awakeDuration: Double
    var sleptDuring: Bool
    /// SMC power × awake duration, when SMC was readable.
    var systemEnergy: Double?
    var groups: [(index: Int32, usage: CompactUsage)]
}

/// Average power of one group over a window.
public struct GroupAverage: Sendable, Equatable {
    public var cpuPower: Double = 0     // W
    public var gpuPower: Double = 0     // W
    public var anePower: Double = 0     // W
    /// CPU time per second of awake time; 1.0 == one fully busy core.
    public var cpuCores: Double = 0
    /// GPU busy fraction (0...1+).
    public var gpuUtilization: Double = 0

    public var totalPower: Double { cpuPower + gpuPower + anePower }
}

public struct WindowSummary: Sendable, Equatable {
    /// Awake seconds actually covered by samples in the window.
    public var coveredSeconds: Double = 0
    /// SMC whole-system average power, nil when never readable in the window.
    public var systemPower: Double?
    public var groups: [GroupKey: GroupAverage] = [:]

    public var cpuPower: Double { groups.values.reduce(0) { $0 + $1.cpuPower } }
    public var gpuPower: Double { groups.values.reduce(0) { $0 + $1.gpuPower } }
    public var anePower: Double { groups.values.reduce(0) { $0 + $1.anePower } }
}

public struct ChartPoint: Sendable, Equatable, Identifiable {
    public var time: Date
    public var power: Double
    /// Increments across gaps (no data / machine asleep) so lines are not drawn through them.
    public var segment: Int
    public var id: Date { time }
}

public struct ChartSeries: Sendable, Equatable, Identifiable {
    public var key: GroupKey
    public var points: [ChartPoint]
    /// Average power of this group across the whole range (used for ranking).
    public var averagePower: Double
    public var id: GroupKey { key }
}

public struct ChartData: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var bucketSeconds: Double
    public var series: [ChartSeries]
}

/// Rolling store of per-interval group usage. Not thread-safe.
final class UsageHistory {
    let retention: TimeInterval
    private var keys: [GroupKey] = []
    private var keyIndex: [GroupKey: Int32] = [:]
    private var entries: [HistoryEntry] = []
    private var head = 0   // entries[..<head] are expired and awaiting compaction

    init(retention: TimeInterval) {
        self.retention = retention
    }

    var count: Int { entries.count - head }

    func append(_ sample: RawSample) {
        var groups: [(Int32, CompactUsage)] = []
        groups.reserveCapacity(sample.groups.count)
        for (key, usage) in sample.groups {
            groups.append((index(for: key), CompactUsage(usage)))
        }
        entries.append(HistoryEntry(
            wallTime: sample.wallTime,
            awakeDuration: sample.awakeDuration,
            sleptDuring: sample.sleptDuring,
            systemEnergy: sample.systemPower.map { $0 * sample.awakeDuration },
            groups: groups
        ))
        expire(now: sample.wallTime)
    }

    private func index(for key: GroupKey) -> Int32 {
        if let i = keyIndex[key] { return i }
        let i = Int32(keys.count)
        keys.append(key)
        keyIndex[key] = i
        return i
    }

    private func expire(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        while head < entries.count, entries[head].wallTime < cutoff { head += 1 }
        // Drop expired entries in small batches, and with them every group key that no longer
        // appears in the retained window, so nothing accumulates over long runtimes.
        if head >= 64 {
            entries.removeFirst(head)
            head = 0
            pruneKeys()
        }
    }

    private func pruneKeys() {
        var used = Set<Int32>()
        for entry in entries { for (index, _) in entry.groups { used.insert(index) } }
        guard used.count < keys.count else { return }
        var remap: [Int32: Int32] = [:]
        var newKeys: [GroupKey] = []
        for old in used.sorted() {
            remap[old] = Int32(newKeys.count)
            newKeys.append(keys[Int(old)])
        }
        for i in entries.indices {
            entries[i].groups = entries[i].groups.map { (remap[$0.index]!, $0.usage) }
        }
        keys = newKeys
        keyIndex = Dictionary(uniqueKeysWithValues: newKeys.enumerated().map { ($1, Int32($0)) })
    }

    /// Group keys referenced by the retained history.
    var liveKeys: Set<GroupKey> { Set(keys) }
    var keyCount: Int { keys.count }

    /// Entries whose end time lies in (start, end].
    private func entries(from start: Date, to end: Date) -> ArraySlice<HistoryEntry> {
        let live = entries[head...]
        // Binary search for the first entry after `start`.
        var lo = live.startIndex, hi = live.endIndex
        while lo < hi {
            let mid = (lo + hi) / 2
            if live[mid].wallTime <= start { lo = mid + 1 } else { hi = mid }
        }
        var upper = lo
        while upper < live.endIndex, live[upper].wallTime <= end { upper += 1 }
        return live[lo..<upper]
    }

    /// Averages over the trailing `seconds` ending at `now`.
    func summary(lastSeconds seconds: TimeInterval, now: Date) -> WindowSummary {
        summarize(entries(from: now.addingTimeInterval(-seconds), to: now))
    }

    /// The most recent sampling interval on its own (the real-time reading, no averaging
    /// with earlier samples).
    func latestSummary() -> WindowSummary {
        summarize(entries[head...].suffix(1))
    }

    private func summarize(_ slice: ArraySlice<HistoryEntry>) -> WindowSummary {
        var covered = 0.0
        var systemEnergy = 0.0, systemCovered = 0.0
        var totals: [Int32: GroupUsage] = [:]
        for entry in slice {
            covered += entry.awakeDuration
            if let e = entry.systemEnergy {
                systemEnergy += e
                systemCovered += entry.awakeDuration
            }
            for (index, usage) in entry.groups {
                totals[index, default: GroupUsage()] += usage.expanded
            }
        }
        var result = WindowSummary(coveredSeconds: covered)
        guard covered > 0 else { return result }
        result.systemPower = systemCovered > 0 ? systemEnergy / systemCovered : nil
        for (index, usage) in totals {
            result.groups[keys[Int(index)]] = GroupAverage(
                cpuPower: usage.cpuEnergy / covered,
                gpuPower: usage.gpuEnergy / covered,
                anePower: usage.aneEnergy / covered,
                cpuCores: usage.cpuTime / covered,
                gpuUtilization: usage.gpuTime / covered
            )
        }
        return result
    }

    /// Per-sample category totals over the trailing window (one point per sampling interval),
    /// for the sparklines behind the CPU / GPU / ANE / other tiles.
    func totalsSeries(lastSeconds seconds: TimeInterval, now: Date) -> [TotalsSample] {
        let start = now.addingTimeInterval(-seconds)
        let slice = entries(from: start, to: now)
        var samples = slice.compactMap(Self.totals)
        // Include the sample just before the window and interpolate a point exactly on the left
        // edge, so the curve always reaches the edge instead of starting a few seconds in.
        if let first = slice.first, !first.sleptDuring, slice.startIndex > head,
           let before = Self.totals(entries[slice.startIndex - 1]), let after = samples.first, after.time > start {
            let f = start.timeIntervalSince(before.time) / after.time.timeIntervalSince(before.time)
            func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
            func lerp(_ a: Double?, _ b: Double?) -> Double? { a.flatMap { a in b.map { lerp(a, $0) } } }
            samples.insert(TotalsSample(time: start, system: lerp(before.system, after.system),
                                        cpu: lerp(before.cpu, after.cpu), gpu: lerp(before.gpu, after.gpu),
                                        ane: lerp(before.ane, after.ane), other: lerp(before.other, after.other)), at: 0)
        }
        return samples
    }

    private static func totals(_ entry: HistoryEntry) -> TotalsSample? {
        guard entry.awakeDuration > 0 else { return nil }
        var cpu = 0.0, gpu = 0.0, ane = 0.0
        for (_, usage) in entry.groups {
            cpu += Double(usage.cpuEnergy)
            gpu += Double(usage.gpuEnergy)
            ane += Double(usage.aneEnergy)
        }
        let d = entry.awakeDuration
        let other = entry.systemEnergy.map { max(0, ($0 - cpu - gpu - ane) / d) }
        return TotalsSample(time: entry.wallTime, system: entry.systemEnergy.map { $0 / d },
                            cpu: cpu / d, gpu: gpu / d, ane: ane / d, other: other)
    }

    /// Bucketed power series for the `topN` groups with the highest average over the range.
    func chart(range seconds: TimeInterval, now: Date, maxPoints: Int, topN: Int) -> ChartData {
        let start = now.addingTimeInterval(-seconds)
        let bucketSeconds = max(1, (seconds / Double(maxPoints)).rounded(.up))
        // Bucket boundaries are fixed in absolute time (multiples of the bucket width). If they
        // were anchored to the sliding window start, every refresh would re-partition the same
        // samples with a different phase and the whole curve would change shape each second.
        // One extra bucket before the range, so the line can be cut exactly at the left edge.
        let origin = Date(timeIntervalSinceReferenceDate:
            ((start.timeIntervalSinceReferenceDate / bucketSeconds).rounded(.down) - 1) * bucketSeconds)
        let totalSpan = now.timeIntervalSince(origin)
        let bucketCount = max(1, Int((totalSpan / bucketSeconds).rounded(.up)))
        let rangeStart = start.timeIntervalSince(origin)   // ranking only counts the selected range
        let slice = entries(from: origin, to: now)

        struct Bucket {
            var covered = 0.0
            var sleptInside = false
            var energy: [Int32: Double] = [:]
        }
        var buckets = [Bucket](repeating: Bucket(), count: bucketCount)
        var rangeEnergy: [Int32: Double] = [:]
        var rangeCovered = 0.0

        for entry in slice {
            // An entry covers the awake interval ending at its wall time. Spread it over every
            // bucket it overlaps, in proportion to the overlap, so a sampling interval longer
            // than a bucket does not leave empty (gap) buckets behind it.
            let entryEnd = entry.wallTime.timeIntervalSince(origin)
            let entryStart = max(0, entryEnd - entry.awakeDuration)
            let span = entryEnd - entryStart
            guard span > 0, entry.awakeDuration > 0 else { continue }
            let perSecond = 1 / entry.awakeDuration   // share of the entry's energy per covered second
            let first = min(bucketCount - 1, max(0, Int(entryStart / bucketSeconds)))
            let last = min(bucketCount - 1, max(0, Int((entryEnd - 1e-9) / bucketSeconds)))
            if entry.sleptDuring { buckets[first].sleptInside = true }
            for b in first...last {
                let overlap = min(entryEnd, Double(b + 1) * bucketSeconds) - max(entryStart, Double(b) * bucketSeconds)
                guard overlap > 0 else { continue }
                buckets[b].covered += overlap
                for (index, usage) in entry.groups {
                    let e = (Double(usage.cpuEnergy) + Double(usage.gpuEnergy) + Double(usage.aneEnergy)) * perSecond * overlap
                    buckets[b].energy[index, default: 0] += e
                }
            }
            let inRange = entryEnd - max(entryStart, rangeStart)
            if inRange > 0 {
                rangeCovered += inRange
                for (index, usage) in entry.groups {
                    rangeEnergy[index, default: 0] += (Double(usage.cpuEnergy) + Double(usage.gpuEnergy) + Double(usage.aneEnergy)) * perSecond * inRange
                }
            }
        }

        let top = rangeEnergy.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(topN)
        var series: [ChartSeries] = []
        for (index, energy) in top where energy > 0 {
            var points: [ChartPoint] = []
            var segment = 0
            var previousHadData = false
            for (b, bucket) in buckets.enumerated() {
                guard bucket.covered > 0 else {
                    if previousHadData { segment += 1 }
                    previousHadData = false
                    continue
                }
                if bucket.sleptInside && previousHadData { segment += 1 }
                // Completed buckets sit at their centre; the bucket still filling up sits at the
                // middle of the part covered so far, so the live edge never runs past `now`.
                let bucketStart = Double(b) * bucketSeconds
                let bucketEnd = min(Double(b + 1) * bucketSeconds, totalSpan)
                let time = origin.addingTimeInterval((bucketStart + bucketEnd) / 2)
                let power = (bucket.energy[index] ?? 0) / bucket.covered
                points.append(ChartPoint(time: time, power: power, segment: segment))
                previousHadData = true
            }
            series.append(ChartSeries(key: keys[Int(index)], points: Self.clipLeading(points, at: start),
                                      averagePower: rangeCovered > 0 ? energy / rangeCovered : 0))
        }
        return ChartData(start: start, end: now, bucketSeconds: bucketSeconds, series: series)
    }
}

extension UsageHistory {
    /// Removes points before `start`; if the line crosses `start`, replaces the part before it
    /// with a point interpolated exactly at `start` (only within one segment, never across a gap).
    static func clipLeading(_ points: [ChartPoint], at start: Date) -> [ChartPoint] {
        guard let i = points.firstIndex(where: { $0.time >= start }) else { return [] }
        guard i > 0 else { return points }
        let before = points[i - 1], after = points[i]
        var result = Array(points[i...])
        if before.segment == after.segment, after.time > start {
            let f = start.timeIntervalSince(before.time) / after.time.timeIntervalSince(before.time)
            result.insert(ChartPoint(time: start, power: before.power + (after.power - before.power) * f,
                                     segment: after.segment), at: 0)
        }
        return result
    }
}

/// Short rolling window of per-process usage, for the expanded rows.
final class ProcessHistory {
    private struct Entry {
        var wallTime: Date
        var awakeDuration: Double
        var processes: [ProcessUsage]
    }

    private let retention: TimeInterval
    private var entries: [Entry] = []

    init(retention: TimeInterval) {
        self.retention = retention
    }

    func append(_ sample: RawSample) {
        entries.append(Entry(wallTime: sample.wallTime, awakeDuration: sample.awakeDuration, processes: sample.processes))
        let cutoff = sample.wallTime.addingTimeInterval(-retention)
        entries.removeAll { $0.wallTime < cutoff }
    }

    struct ProcessAverage {
        var pid: pid_t
        var cpuPower: Double
        var cpuCores: Double
    }

    /// Per-process values of the most recent sampling interval only.
    func latest() -> [pid_t: ProcessAverage] {
        guard let entry = entries.last, entry.awakeDuration > 0 else { return [:] }
        var result: [pid_t: ProcessAverage] = [:]
        for p in entry.processes {
            result[p.pid] = ProcessAverage(pid: p.pid, cpuPower: p.cpuEnergy / entry.awakeDuration,
                                           cpuCores: p.cpuTime / entry.awakeDuration)
        }
        return result
    }

    /// Per-group process averages over the trailing window (same denominator as `UsageHistory.summary`).
    func averages(lastSeconds seconds: TimeInterval, now: Date) -> [GroupKey: [ProcessAverage]] {
        let cutoff = now.addingTimeInterval(-seconds)
        var covered = 0.0
        var totals: [pid_t: (key: GroupKey, energy: Double, time: Double)] = [:]
        for entry in entries where entry.wallTime > cutoff && entry.wallTime <= now {
            covered += entry.awakeDuration
            for p in entry.processes {
                var t = totals[p.pid] ?? (p.key, 0, 0)
                t.energy += p.cpuEnergy
                t.time += p.cpuTime
                totals[p.pid] = t
            }
        }
        guard covered > 0 else { return [:] }
        var result: [GroupKey: [ProcessAverage]] = [:]
        for (pid, t) in totals {
            result[t.key, default: []].append(ProcessAverage(pid: pid, cpuPower: t.energy / covered, cpuCores: t.time / covered))
        }
        return result
    }
}
