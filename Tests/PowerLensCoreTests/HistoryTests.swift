import Foundation
import Testing
@testable import PowerLensCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let a = GroupKey("app:a")
private let b = GroupKey("app:b")
private let c = GroupKey("app:c")

private func sample(at seconds: Double, duration: Double, slept: Bool = false, system: Double? = nil,
                    _ groups: [GroupKey: GroupUsage]) -> RawSample {
    RawSample(wallTime: t0.addingTimeInterval(seconds), awakeDuration: duration, sleptDuring: slept,
              systemPower: system, groups: groups, processes: [], groupsWithUnreadableMembers: [])
}

private func cpu(_ joules: Double, time: Double = 0) -> GroupUsage {
    GroupUsage(cpuEnergy: joules, cpuTime: time)
}

@Suite struct UsageHistorySummaryTests {
    @Test func averagesEnergyOverCoveredTime() {
        let h = UsageHistory(retention: 3600)
        h.append(sample(at: 1, duration: 1, system: 10, [a: cpu(2, time: 0.5)]))
        h.append(sample(at: 2, duration: 1, system: 14, [a: cpu(4, time: 1.5), b: GroupUsage(gpuEnergy: 1)]))
        let s = h.summary(lastSeconds: 30, now: t0.addingTimeInterval(2))
        #expect(s.coveredSeconds == 2)
        #expect(abs(s.groups[a]!.cpuPower - 3) < 1e-6)       // 6 J / 2 s
        #expect(abs(s.groups[a]!.cpuCores - 1) < 1e-6)       // 2 s CPU / 2 s
        #expect(abs(s.groups[b]!.gpuPower - 0.5) < 1e-6)     // absent in first sample counts as zero
        #expect(abs(s.systemPower! - 12) < 1e-6)
    }

    @Test func windowExcludesOlderSamples() {
        let h = UsageHistory(retention: 3600)
        h.append(sample(at: 1, duration: 1, [a: cpu(100)]))
        h.append(sample(at: 10, duration: 1, [a: cpu(1)]))
        let s = h.summary(lastSeconds: 2, now: t0.addingTimeInterval(10))
        #expect(s.coveredSeconds == 1)
        #expect(abs(s.groups[a]!.cpuPower - 1) < 1e-6)
    }

    @Test func latestSummaryUsesOnlyTheLastSample() {
        let h = UsageHistory(retention: 3600)
        #expect(h.latestSummary().coveredSeconds == 0)
        h.append(sample(at: 1, duration: 1, system: 20, [a: cpu(10)]))
        h.append(sample(at: 2, duration: 1, system: 8, [a: cpu(2), b: cpu(1)]))
        let s = h.latestSummary()
        #expect(s.coveredSeconds == 1)
        #expect(s.systemPower == 8)
        #expect(s.groups[a]?.cpuPower == 2)
        #expect(s.groups[b]?.cpuPower == 1)
    }

    @Test func systemPowerIsNilWhenNeverReadable() {
        let h = UsageHistory(retention: 3600)
        h.append(sample(at: 1, duration: 1, [a: cpu(1)]))
        #expect(h.summary(lastSeconds: 30, now: t0.addingTimeInterval(1)).systemPower == nil)
    }

    @Test func sparklineReachesTheLeftEdge() {
        let h = UsageHistory(retention: 3600)
        for i in stride(from: 3, through: 120, by: 3) { h.append(sample(at: Double(i), duration: 3, system: 10, [a: cpu(6)])) }
        let now = t0.addingTimeInterval(120)
        let series = h.totalsSeries(lastSeconds: 60, now: now)
        #expect(series.first?.time == now.addingTimeInterval(-60))
        #expect(series.first?.cpu == 2)
        #expect(series.first?.other == 8)
    }

    @Test func expiredGroupsAreForgotten() {
        let h = UsageHistory(retention: 10)
        for i in 1...100 { h.append(sample(at: Double(i), duration: 1, [GroupKey("app:\(i)"): cpu(1)])) }
        // Only groups inside the 10 s window plus at most one compaction batch may remain.
        #expect(h.keyCount <= 10 + 64)
        #expect(h.liveKeys.contains(GroupKey("app:100")))
        #expect(!h.liveKeys.contains(GroupKey("app:1")))
        // Indices must still resolve to the right keys after pruning.
        let s = h.summary(lastSeconds: 1, now: t0.addingTimeInterval(100))
        #expect(s.groups.keys.sorted() == [GroupKey("app:100")])
    }

    @Test func expiresEntriesBeyondRetention() {
        let h = UsageHistory(retention: 10)
        for i in 1...1000 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        #expect(h.count <= 11)
        let s = h.summary(lastSeconds: 3600, now: t0.addingTimeInterval(1000))
        #expect(s.coveredSeconds <= 11)
    }
}

@Suite struct UsageHistoryChartTests {
    @Test func samplingSlowerThanBucketsLeavesNoGaps() {
        // 3 s samples, 60 s range over 30 points => 2 s buckets.
        let h = UsageHistory(retention: 3600)
        for i in 1...20 { h.append(sample(at: Double(i * 3), duration: 3, [a: cpu(6)])) }   // 2 W
        let chart = h.chart(range: 60, now: t0.addingTimeInterval(60), maxPoints: 30, topN: 5)
        #expect(chart.bucketSeconds == 2)
        let series = chart.series.first { $0.key == a }!
        #expect(Set(series.points.map(\.segment)) == [0])
        #expect(series.points.count == 30)
        for p in series.points { #expect(abs(p.power - 2) < 1e-6) }
        #expect(abs(series.averagePower - 2) < 1e-6)
    }

    @Test func missingDataBreaksTheLine() {
        let h = UsageHistory(retention: 3600)
        for i in 1...10 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        for i in 31...40 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        let chart = h.chart(range: 40, now: t0.addingTimeInterval(40), maxPoints: 40, topN: 5)
        let segments = Set(chart.series[0].points.map(\.segment))
        #expect(segments == [0, 1])
    }

    @Test func sleepBreaksTheLine() {
        let h = UsageHistory(retention: 3600)
        for i in 1...10 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        // Machine slept between t=10 and t=19; this sample covers 1 awake second.
        h.append(sample(at: 20, duration: 1, slept: true, [a: cpu(1)]))
        for i in 21...25 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        let chart = h.chart(range: 25, now: t0.addingTimeInterval(25), maxPoints: 25, topN: 5)
        #expect(Set(chart.series[0].points.map(\.segment)).count == 2)
    }

    @Test func picksTopNByAverageOverRange() {
        let h = UsageHistory(retention: 3600)
        // b is highest overall, a second, c spikes once but is lowest on average.
        for i in 1...60 {
            var groups: [GroupKey: GroupUsage] = [a: cpu(2), b: cpu(3)]
            if i == 60 { groups[c] = cpu(50) }
            h.append(sample(at: Double(i), duration: 1, groups))
        }
        let chart = h.chart(range: 60, now: t0.addingTimeInterval(60), maxPoints: 60, topN: 2)
        #expect(chart.series.map(\.key) == [b, a])
    }

    /// Regression: buckets used to be anchored to `now - range`, so every refresh re-partitioned
    /// the same data with a shifted phase and the whole curve alternated between two shapes.
    @Test func completedBucketsDoNotChangeAsTheWindowSlides() {
        let h = UsageHistory(retention: 3600)
        for i in 1...400 {
            let watts = Double((i * 7) % 11)           // irregular load
            h.append(sample(at: Double(i), duration: 1, [a: cpu(watts)]))
        }
        func points(now: Double) -> [Date: Double] {
            let chart = h.chart(range: 300, now: t0.addingTimeInterval(now), maxPoints: 180, topN: 1)
            return Dictionary(uniqueKeysWithValues: chart.series[0].points.map { ($0.time, $0.power) })
        }
        let first = points(now: 390)
        let second = points(now: 391)
        let third = points(now: 392)
        // Buckets that were complete at t=390 must be identical (same time, same value) later on.
        let complete = first.keys.filter { $0 < t0.addingTimeInterval(385) && $0 > t0.addingTimeInterval(100) }
        #expect(complete.count > 100)
        for time in complete {
            #expect(second[time] == first[time])
            #expect(third[time] == first[time])
        }
    }

    @Test func bucketsAreAlignedToAbsoluteTime() {
        let h = UsageHistory(retention: 3600)
        for i in 1...100 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        let chart = h.chart(range: 60, now: t0.addingTimeInterval(100.5), maxPoints: 12, topN: 1)
        #expect(chart.bucketSeconds == 5)
        // Skip the point interpolated on the left edge and the bucket still filling up.
        for p in chart.series[0].points.dropLast() where p.time > chart.start {
            let center = p.time.timeIntervalSinceReferenceDate
            #expect((center - 2.5).truncatingRemainder(dividingBy: 5) == 0)
        }
    }

    @Test func lineReachesTheLeftEdgeWhenOlderDataExists() {
        let h = UsageHistory(retention: 3600)
        for i in 1...200 { h.append(sample(at: Double(i), duration: 1, [a: cpu(Double(i % 5))])) }
        for now in [150.0, 150.4, 151.7] {
            let chart = h.chart(range: 60, now: t0.addingTimeInterval(now), maxPoints: 30, topN: 1)
            #expect(chart.series[0].points.first?.time == chart.start)
        }
    }

    @Test func noLeftEdgePointWithoutOlderData() {
        let h = UsageHistory(retention: 3600)
        for i in 30...60 { h.append(sample(at: Double(i), duration: 1, [a: cpu(1)])) }
        let chart = h.chart(range: 60, now: t0.addingTimeInterval(60), maxPoints: 30, topN: 1)
        #expect(chart.series[0].points.first!.time > chart.start.addingTimeInterval(28))
    }

    @Test func clipLeadingNeverInterpolatesAcrossAGap() {
        let s = t0.addingTimeInterval(10)
        let points = [ChartPoint(time: t0.addingTimeInterval(5), power: 1, segment: 0),
                      ChartPoint(time: t0.addingTimeInterval(15), power: 3, segment: 1)]
        let clipped = UsageHistory.clipLeading(points, at: s)
        #expect(clipped.count == 1)
        #expect(clipped[0].time == t0.addingTimeInterval(15))
        let joined = UsageHistory.clipLeading([points[0], ChartPoint(time: points[1].time, power: 3, segment: 0)], at: s)
        #expect(joined.first == ChartPoint(time: s, power: 2, segment: 0))
    }

    @Test func zeroEnergyGroupsAreNotCharted() {
        let h = UsageHistory(retention: 3600)
        h.append(sample(at: 1, duration: 1, [a: cpu(0, time: 0.1)]))
        let chart = h.chart(range: 60, now: t0.addingTimeInterval(1), maxPoints: 60, topN: 5)
        #expect(chart.series.isEmpty)
    }
}

@Suite struct ProcessHistoryTests {
    @Test func averagesPerGroup() {
        let h = ProcessHistory(retention: 35)
        var s1 = sample(at: 1, duration: 1, [:])
        s1.processes = [ProcessUsage(pid: 10, key: a, cpuEnergy: 1, cpuTime: 0.5)]
        var s2 = sample(at: 2, duration: 1, [:])
        s2.processes = [ProcessUsage(pid: 10, key: a, cpuEnergy: 3, cpuTime: 0.5),
                        ProcessUsage(pid: 11, key: b, cpuEnergy: 2, cpuTime: 1)]
        h.append(s1)
        h.append(s2)
        let result = h.averages(lastSeconds: 30, now: t0.addingTimeInterval(2))
        #expect(abs(result[a]![0].cpuPower - 2) < 1e-6)
        #expect(abs(result[a]![0].cpuCores - 0.5) < 1e-6)
        #expect(abs(result[b]![0].cpuPower - 1) < 1e-6)
    }
}
