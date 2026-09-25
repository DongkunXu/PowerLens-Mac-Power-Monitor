import Foundation

/// Stable identity of an "app" row. Coalition ids change whenever an app relaunches,
/// so history and chart series are keyed by this instead.
public struct GroupKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    public static func < (a: GroupKey, b: GroupKey) -> Bool { a.rawValue < b.rawValue }
}

public enum GroupKind: Sendable, Equatable {
    /// A GUI application, identified by bundle id.
    case app(bundleID: String)
    /// A launchd job (daemon, agent, XPC service) without an app bundle.
    case service(label: String)
    /// A coalition without a launchd label; named after its leading process.
    case process
}

/// Rules for turning a coalition's launchd label into a stable group key.
public enum CoalitionNaming {
    private static let appPrefix = "application."

    /// Bundle id for labels of the form "application.<bundle id>.<n>.<n>".
    public static func bundleID(fromLabel label: String) -> String? {
        guard label.hasPrefix(appPrefix) else { return nil }
        var parts = label.dropFirst(appPrefix.count).split(separator: ".", omittingEmptySubsequences: false)
        while let last = parts.last, !last.isEmpty, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        let bundle = parts.joined(separator: ".")
        return bundle.isEmpty ? nil : bundle
    }

    public static func kind(label: String?) -> GroupKind {
        guard let label, !label.isEmpty else { return .process }
        if let bundle = bundleID(fromLabel: label) { return .app(bundleID: bundle) }
        return .service(label: label)
    }

    /// `leaderName` is only used when the coalition has no label.
    public static func key(kind: GroupKind, leaderName: String) -> GroupKey {
        switch kind {
        case .app(let bundle): return GroupKey("app:" + bundle)
        case .service(let label): return GroupKey("svc:" + label)
        case .process: return GroupKey("proc:" + leaderName)
        }
    }
}

/// Everything the UI needs to present a group.
public struct GroupInfo: Sendable, Equatable {
    public var key: GroupKey
    public var kind: GroupKind
    public var displayName: String
    /// Secondary text: launchd label for services, bundle id for apps.
    public var subtitle: String?
    /// Path of the app bundle (for its icon), when known.
    public var bundlePath: String?
}
