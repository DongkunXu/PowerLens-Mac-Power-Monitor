import Darwin
import Foundation

/// Descriptive details of a process shown when a group is expanded.
public struct ProcessDetails: Sendable, Equatable {
    /// Short command line with argv[0] reduced to its basename; nil when not readable.
    public var commandLine: String?
    /// Working directory, abbreviated with "~"; nil when not readable.
    public var workingDirectory: String?
}

/// Lazily reads and caches argv / cwd for processes. Only processes of the current
/// user (or all, when running as root) can be inspected. Not thread-safe.
final class ProcessCatalog {
    private struct Entry {
        var details: ProcessDetails
        var fetchedAt: Double
    }

    private var entries: [pid_t: Entry] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// The working directory can change; argv cannot. Refresh cwd at most this often.
    private let refreshInterval: Double = 10

    func details(pid: pid_t, now: Double) -> ProcessDetails {
        if let entry = entries[pid], now - entry.fetchedAt < refreshInterval {
            return entry.details
        }
        let commandLine = entries[pid]?.details.commandLine ?? Probes.arguments(pid).flatMap(Self.summarize)
        let cwd = Probes.workingDirectory(pid).map(abbreviate)
        let details = ProcessDetails(commandLine: commandLine, workingDirectory: cwd == "/" ? nil : cwd)
        entries[pid] = Entry(details: details, fetchedAt: now)
        return details
    }

    func forget(pid: pid_t) {
        entries[pid] = nil
    }

    private func abbreviate(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func summarize(_ argv: [String]) -> String? {
        guard let first = argv.first else { return nil }
        let head = (first as NSString).lastPathComponent
        let rest = argv.dropFirst().map { arg -> String in
            // Long absolute paths make the line unreadable; keep their last component.
            if arg.hasPrefix("/") && arg.count > 40 { return "…/" + (arg as NSString).lastPathComponent }
            return arg
        }
        let line = ([head] + rest).joined(separator: " ")
        return line.count > 200 ? String(line.prefix(200)) + "…" : line
    }
}
