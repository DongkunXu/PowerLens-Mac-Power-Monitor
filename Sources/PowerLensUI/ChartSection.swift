import Charts
import PowerLensCore
import SwiftUI

struct ChartSection: View {
    @Bindable var model: AppModel
    let state: PanelState
    @State private var hoverTime: Date?
    @Environment(\.strings) private var strings

    private static let ranges: [TimeInterval] = [5 * 60, 15 * 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(strings.timeRange, selection: $model.chartRange) {
                    ForEach(Self.ranges, id: \.self) { Text(strings.minutes(Int($0 / 60))).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Picker(strings.seriesCount, selection: $model.chartTopN) {
                    Text(strings.top(3)).tag(3)
                    Text(strings.top(5)).tag(5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
                Spacer()
            }

            if state.chart.series.isEmpty {
                Text(strings.noData)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                chart
                    .frame(height: 150)
                legend
            }
        }
    }

    /// Whole-minute ticks (every 1 min for 5 min, every 5 min for 15 min), kept away from the
    /// edges so the first and last labels are never clipped.
    private var xTicks: [Date] {
        let range = state.chart.end.timeIntervalSince(state.chart.start)
        let step: TimeInterval = range <= 5 * 60 ? 60 : 5 * 60
        let lower = state.chart.start.timeIntervalSinceReferenceDate + step * 0.3
        let upper = state.chart.end.timeIntervalSinceReferenceDate - step * 0.35
        var t = (lower / step).rounded(.up) * step
        var ticks: [Date] = []
        while t <= upper {
            ticks.append(Date(timeIntervalSinceReferenceDate: t))
            t += step
        }
        return ticks
    }

    /// Upper bound of the y axis, rounded up to a "nice" value so small changes in the peak
    /// do not rescale the axis on every refresh.
    private var yMax: Double {
        let peak = state.chart.series.flatMap(\.points).map(\.power).max() ?? 0
        return Self.niceCeiling(max(0.5, peak * 1.1))
    }

    static func niceCeiling(_ value: Double) -> Double {
        let magnitude = pow(10, (log10(value)).rounded(.down))
        let steps: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        let normalized = value / magnitude
        let step = steps.first { normalized <= $0 + 1e-9 } ?? 10
        return step * magnitude
    }

    private func color(_ key: GroupKey) -> Color {
        Palette.series(model.colorSlots[key] ?? 0)
    }

    private func name(_ key: GroupKey) -> String {
        state.chartInfo[key]?.displayName ?? key.rawValue
    }

    private var chart: some View {
        Chart {
            ForEach(state.chart.series) { series in
                ForEach(series.points) { point in
                    LineMark(
                        x: .value(strings.time, point.time),
                        y: .value(strings.power, point.power),
                        series: .value(strings.series, "\(series.key.rawValue)#\(point.segment)")
                    )
                    .foregroundStyle(color(series.key))
                    // Monotone keeps the curve smooth without overshooting below zero.
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let hover = hoverReadout {
                RuleMark(x: .value(strings.time, hover.time))
                    .foregroundStyle(Palette.axisLabel.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverTooltip(readout: hover, color: color, name: name)
                    }
            }
        }
        .chartXScale(domain: state.chart.start...state.chart.end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: xTicks) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.grid)
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .foregroundStyle(Palette.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.grid)
                AxisValueLabel {
                    if let w = value.as(Double.self) {
                        Text(w < 10 ? String(format: "%.1f W", w) : String(format: "%.0f W", w))
                    }
                }
                .foregroundStyle(Palette.axisLabel)
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $hoverTime)
    }

    /// Values of every series at the bucket nearest the pointer.
    private var hoverReadout: HoverReadout? {
        guard let hoverTime else { return nil }
        let half = state.chart.bucketSeconds / 2 + 0.001
        var time: Date?
        var values: [(GroupKey, Double)] = []
        for series in state.chart.series {
            guard let nearest = series.points.min(by: {
                abs($0.time.timeIntervalSince(hoverTime)) < abs($1.time.timeIntervalSince(hoverTime))
            }), abs(nearest.time.timeIntervalSince(hoverTime)) <= half else { continue }
            time = time ?? nearest.time
            values.append((series.key, nearest.power))
        }
        guard let time, !values.isEmpty else { return nil }
        return HoverReadout(time: time, values: values.sorted { $0.1 > $1.1 })
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            ForEach(state.chart.series) { series in
                HStack(spacing: 6) {
                    LineKey(color: color(series.key))
                    Text(name(series.key))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .help(strings.legendHelp(name(series.key), Format.watts(series.averagePower)))
            }
        }
    }
}

struct HoverReadout {
    var time: Date
    var values: [(GroupKey, Double)]
}

private struct HoverTooltip: View {
    let readout: HoverReadout
    let color: (GroupKey) -> Color
    let name: (GroupKey) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(readout.time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(readout.values, id: \.0) { key, value in
                HStack(spacing: 6) {
                    LineKey(color: color(key))
                    Text(Format.watts(value))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(name(key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1)))
    }
}

/// Short stroke of the series color (legends and tooltips key lines with lines, not boxes).
struct LineKey: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 12, height: 2.5)
    }
}
