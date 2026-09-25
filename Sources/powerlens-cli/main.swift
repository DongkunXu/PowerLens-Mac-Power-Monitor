// powerlens-cli: headless view of the same data the menu-bar app shows.
// Usage: powerlens-cli [seconds] [--range minutes] [--toggle open,closed]
//   (default 10 s, 15 min; prints one table per second)
//   --toggle 5,7 simulates opening the panel for 5 s and closing it for 7 s, repeatedly.
// Each update also reports how many completed chart buckets changed since the previous update
// (must stay 0: finished history is immutable, only the live edge moves).
import Foundation
import PowerLensCore

var arguments = Array(CommandLine.arguments.dropFirst())
var rangeMinutes = 15.0
if let i = arguments.firstIndex(of: "--range"), i + 1 < arguments.count, let m = Double(arguments[i + 1]) {
    rangeMinutes = m
    arguments.removeSubrange(i...(i + 1))
}
var toggle: (open: Double, closed: Double)?
if let i = arguments.firstIndex(of: "--toggle"), i + 1 < arguments.count {
    let parts = arguments[i + 1].split(separator: ",").compactMap { Double($0) }
    if parts.count == 2 { toggle = (parts[0], parts[1]) }
    arguments.removeSubrange(i...(i + 1))
}
let seconds = arguments.first.flatMap(Int.init) ?? 10

func watts(_ value: Double?) -> String {
    guard let value else { return "    —  " }
    return String(format: "%6.2fW", value)
}

let monitor = PowerMonitor()
let lock = NSLock()
nonisolated(unsafe) var updates = 0
nonisolated(unsafe) var previousChart: [GroupKey: [Date: Double]] = [:]

monitor.setOptions(PanelOptions(chartRange: rangeMinutes * 60))
monitor.setVisible(true)
monitor.start { state in
    lock.lock(); defer { lock.unlock() }
    updates += 1
    var out = "\n=== \(ISO8601DateFormatter().string(from: state.time))  (smoothing \(Int(state.smoothingWindow)) s\(state.warmedUp ? "" : ", warming up")) ===\n"
    let t = state.totals
    out += "System \(watts(t.system.now)) now \(watts(t.system.smoothed)) avg | CPU \(watts(t.cpu.smoothed))  GPU \(watts(t.gpu.smoothed))  ANE \(watts(t.ane.smoothed))  Other \(watts(t.other.smoothed))\n"
    for row in state.rows {
        let s = row.smoothed
        out += String(format: "  %@ avg %@ now | cpu %5.2fW gpu %5.2fW ane %5.2fW | cores %4.2f gpu %3.0f%% | %@\n",
                      watts(s.totalPower), watts(row.now.totalPower), s.cpuPower, s.gpuPower, s.anePower,
                      s.cpuCores, s.gpuUtilization * 100, row.info.displayName)
        for child in row.children.prefix(3) {
            out += String(format: "        %@ cores %4.2f  %@  %@\n", watts(child.cpuPower), child.cpuCores,
                          child.details.commandLine ?? child.name, child.details.workingDirectory ?? "")
        }
        if row.remainderPower > 0.02 {
            out += "        \(watts(row.remainderPower)) \(row.remainderKind == .exitedProcesses ? "exited processes" : "unreadable/exited members")\n"
        }
        if let c = row.containers {
            for container in c.containers.prefix(5) {
                out += String(format: "        [container] %@ cores %4.2f  %@\n", watts(container.power), container.cpuCores, container.name)
            }
            out += "        [vm overhead] \(watts(c.overheadPower))\(c.error.map { "  error: \($0)" } ?? "")\n"
        }
    }
    out += "  chart: " + state.chart.series.map { "\(state.chartInfo[$0.key]?.displayName ?? $0.key.rawValue) \(String(format: "%.2f", $0.averagePower))W/\($0.points.count)pts" }.joined(separator: ", ") + "\n"
    var current: [GroupKey: [Date: Double]] = [:]
    var compared = 0, changed = 0, moved = 0
    let visibleFrom = state.chart.start
    for series in state.chart.series {
        let completed = series.points.dropLast()   // the last bucket is still filling up
        current[series.key] = Dictionary(completed.map { ($0.time, $0.power) }, uniquingKeysWith: { a, _ in a })
        guard let before = previousChart[series.key] else { continue }
        for (time, power) in current[series.key]! {
            guard let old = before[time] else { continue }
            compared += 1
            if abs(old - power) > 1e-9 { changed += 1 }
        }
        // Previously completed points still inside the range must reappear at the same time.
        moved += before.keys.filter { $0 > visibleFrom && current[series.key]![$0] == nil }.count
    }
    previousChart = current
    out += "  chart stability: \(changed) of \(compared) completed points changed, \(moved) moved/vanished since last update (bucket \(Int(state.chart.bucketSeconds)) s)\n"
    // Tile sparkline coverage: how much of the window's left edge is empty, and the largest hole.
    let windowStart = state.time.addingTimeInterval(-state.sparklineWindow)
    let times = state.recentTotals.map(\.time)
    let lead = times.first.map { $0.timeIntervalSince(windowStart) } ?? state.sparklineWindow
    let hole = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0
    out += String(format: "  tile sparkline: %d points, left edge empty %.2f s, largest gap %.2f s\n", times.count, lead, hole)
    out += "  self: \(watts(state.selfPower)) | sleep assertions: \(state.assertions.count)\n"
    FileHandle.standardOutput.write(Data(out.utf8))
}

if let toggle {
    nonisolated(unsafe) var open = true
    func flip() {
        let delay = open ? toggle.open : toggle.closed
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            open.toggle()
            monitor.setVisible(open)
            FileHandle.standardOutput.write(Data("\n>>> panel \(open ? "opened" : "closed")\n".utf8))
            flip()
        }
    }
    flip()
}

DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { exit(0) }
dispatchMain()
