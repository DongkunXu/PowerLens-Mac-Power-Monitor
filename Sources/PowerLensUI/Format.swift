import Foundation

enum Format {
    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value < 0.005 { return "<0.01 W" }
        if value >= 10 { return String(format: "%.1f W", value) }
        return String(format: "%.2f W", value)
    }

    /// CPU time per second as a percentage of one core (Activity Monitor convention).
    static func cpuPercent(_ cores: Double) -> String {
        let percent = cores * 100
        if percent < 0.05 { return "0%" }
        if percent < 10 { return String(format: "%.1f%%", percent) }
        return String(format: "%.0f%%", percent)
    }

    static func percent(_ fraction: Double) -> String {
        let percent = fraction * 100
        if percent < 0.5 { return "0%" }
        return String(format: "%.0f%%", percent)
    }
}
