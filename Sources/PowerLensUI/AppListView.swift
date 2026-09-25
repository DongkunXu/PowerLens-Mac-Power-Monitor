import PowerLensCore
import SwiftUI

struct AppListView: View {
    @Bindable var model: AppModel
    let state: PanelState
    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(strings.topApps)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            ForEach(state.rows) { row in
                AppRowView(model: model, row: row, sampleInterval: state.sampleInterval)
            }
        }
    }
}

private struct AppRowView: View {
    @Bindable var model: AppModel
    let row: RowState
    let sampleInterval: TimeInterval
    @Environment(\.strings) private var strings

    private var isExpanded: Bool { model.expanded.contains(row.id) }
    private var canExpand: Bool {
        !row.children.isEmpty || row.remainderPower > 0.01 || row.containers != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if canExpand { model.toggleExpanded(row.id) }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                details
                    .padding(.leading, 44)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
            }
        }
        .background(isExpanded ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(.tertiary)
                .opacity(canExpand ? 1 : 0)
                .frame(width: 8)

            icon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.info.displayName)
                        .font(.callout)
                        .lineLimit(1)
                    if let slot = model.colorSlots[row.id] {
                        LineKey(color: Palette.series(slot))
                            .help(strings.chartLineHelp)
                    }
                }
                Text(breakdown)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.watts(row.now.totalPower))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(Format.watts(row.smoothed.totalPower))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(row.info.subtitle ?? row.info.displayName)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = model.icon(for: row.info) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var symbol: String {
        switch row.info.kind {
        case .app: return "app"
        case .service: return "gearshape"
        case .process: return "cpu"
        }
    }

    /// Real-time split of the row's power (same interval as the big number).
    private var breakdown: String {
        let s = row.now
        var parts = ["CPU \(Format.watts(s.cpuPower)) · \(Format.cpuPercent(s.cpuCores))"]
        if s.gpuPower >= 0.005 || s.gpuUtilization >= 0.005 {
            parts.append("GPU \(Format.watts(s.gpuPower)) · \(Format.percent(s.gpuUtilization))")
        }
        if s.anePower >= 0.005 {
            parts.append("ANE \(Format.watts(s.anePower))")
        }
        return parts.joined(separator: "   ")
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let subtitle = row.info.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if let containers = row.containers {
                ContainersView(breakdown: containers)
            }

            if !row.children.isEmpty {
                Text(strings.processes)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(row.children) { child in
                    ChildRowView(child: child)
                }
            }
            if row.hiddenChildren > 0 {
                Text(strings.moreProcesses(row.hiddenChildren))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if row.remainderPower > 0.01 {
                HStack {
                    Text(row.remainderKind == .exitedProcesses ? strings.exitedProcesses : strings.unreadableProcesses)
                        .help(row.remainderKind == .exitedProcesses
                              ? strings.exitedProcessesHelp
                              : strings.unreadableProcessesHelp)
                    Spacer()
                    Text(Format.watts(row.remainderPower))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChildRowView: View {
    let child: ChildState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(child.details.commandLine ?? child.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(child.details.commandLine ?? child.name)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(verbatim: "pid \(child.pid)")
                    if let cwd = child.details.workingDirectory {
                        Text(cwd)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Format.watts(child.nowCpuPower)) · \(Format.cpuPercent(child.nowCpuCores))")
                    .font(.caption.weight(.medium))
                Text(Format.watts(child.cpuPower))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 1)
    }
}

private struct ContainersView: View {
    let breakdown: ContainerBreakdown
    @Environment(\.strings) private var strings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(strings.containers(breakdown.runtimeName))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .help(strings.containersHelp)
            if let error = breakdown.error {
                Text(strings.readFailed(error))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if breakdown.containers.isEmpty {
                Text(strings.reading)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(breakdown.containers.filter { $0.power >= 0.005 || $0.cpuCores >= 0.005 || $0.nowPower >= 0.005 }) { c in
                    HStack {
                        Text(c.name)
                            .lineLimit(1)
                            .help(c.image ?? c.name)
                        Spacer()
                        Text(Format.cpuPercent(c.nowCpuCores))
                            .foregroundStyle(.secondary)
                        Text(Format.watts(c.nowPower))
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .help(strings.averageHelp(Format.watts(c.power), Format.cpuPercent(c.cpuCores)))
                }
                let idle = breakdown.containers.filter { $0.power < 0.005 && $0.cpuCores < 0.005 && $0.nowPower < 0.005 }.count
                if idle > 0 {
                    Text(strings.idleContainers(idle))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack {
                    Text(strings.vmOverhead)
                        .help(strings.vmOverheadHelp)
                    Spacer()
                    Text(Format.watts(breakdown.nowOverheadPower))
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(.bottom, 2)
    }
}
