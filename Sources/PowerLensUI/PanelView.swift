import Charts
import PowerLensCore
import SwiftUI

public struct PanelView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = model.state {
                TotalsHeader(model: model, state: state)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                Divider()
                ChartSection(model: model, state: state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AppListView(model: model, state: state)
                        AssertionsView(model: model, assertions: state.assertions)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity)
                Divider()
                FooterView(state: state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ProgressView(model.language.strings.collecting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 360, height: 760)
        .environment(\.strings, model.language.strings)
        .environment(\.locale, model.language.locale)
        .onAppear { model.setPanelVisible(true) }
        .onDisappear { model.setPanelVisible(false) }
    }
}

struct TotalsHeader: View {
    @Bindable var model: AppModel
    let state: PanelState
    @Environment(\.strings) private var strings

    var body: some View {
        let t = state.totals
        let window = state.time.addingTimeInterval(-state.sparklineWindow)...state.time
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(strings.systemPower)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsMenu(model: model)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.watts(t.system.now))
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                    Text(Format.watts(t.system.smoothed))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    TotalTile(title: "CPU", reading: t.cpu, window: window,
                              series: state.recentTotals.map { ($0.time, $0.cpu) },
                              help: strings.cpuHelp)
                    TotalTile(title: "GPU", reading: t.gpu, window: window,
                              series: state.recentTotals.map { ($0.time, $0.gpu) },
                              help: strings.gpuHelp)
                }
                GridRow {
                    TotalTile(title: "ANE", reading: t.ane, window: window,
                              series: state.recentTotals.map { ($0.time, $0.ane) },
                              help: strings.aneHelp)
                    TotalTile(title: strings.other, reading: t.other, window: window,
                              series: state.recentTotals.compactMap { s in s.other.map { (s.time, $0) } },
                              help: strings.otherHelp)
                }
            }
        }
    }
}

private struct TotalTile: View {
    let title: String
    let reading: PowerReading
    let window: ClosedRange<Date>
    let series: [(Date, Double)]
    let help: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.watts(reading.now))
                    .font(.system(.title3, weight: .medium))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(Format.watts(reading.smoothed))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            // Kept in the lower part of the tile so it sits under the text, not through it.
            Sparkline(points: series, window: window)
                .frame(height: 20)
        }
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(help)
    }
}

/// Unlabelled background curve: shape only, no axes or values.
private struct Sparkline: View {
    struct Point: Identifiable {
        var time: Date
        var value: Double
        var id: Date { time }
    }

    let points: [(Date, Double)]
    let window: ClosedRange<Date>
    @Environment(\.strings) private var strings

    var body: some View {
        let data = points.map { Point(time: $0.0, value: $0.1) }
        let top = ChartSection.niceCeiling(max(0.5, (data.map(\.value).max() ?? 0) * 1.1))
        Chart(data) { p in
            AreaMark(x: .value(strings.time, p.time), y: .value(strings.power, p.value))
                .foregroundStyle(Color.primary.opacity(0.06))
                .interpolationMethod(.monotone)
            LineMark(x: .value(strings.time, p.time), y: .value(strings.power, p.value))
                .foregroundStyle(Color.primary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: window)
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
