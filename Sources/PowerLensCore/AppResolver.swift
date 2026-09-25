import AppKit
import Foundation

/// Resolves bundle ids and executable paths to user-facing app names. Results are cached;
/// a miss is cached too so unknown ids are not looked up every sample.
final class AppResolver {
    struct AppBundle: Equatable {
        var name: String
        var path: String
    }

    private var byBundleID: [String: AppBundle?] = [:]
    private var byBundlePath: [String: AppBundle?] = [:]

    /// Forgets all cached lookups (they are only needed when a new group first appears).
    func reset() {
        byBundleID = [:]
        byBundlePath = [:]
    }

    func app(bundleID: String) -> AppBundle? {
        if let cached = byBundleID[bundleID] { return cached }
        var result: AppBundle?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            result = bundle(atPath: url.path)
        }
        byBundleID[bundleID] = result
        return result
    }

    /// The outermost `.app` bundle containing an executable, if any
    /// (e.g. ".../Docker.app/Contents/MacOS/com.docker.backend" -> Docker).
    func enclosingApp(executablePath: String) -> AppBundle? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        let bundlePath = String(executablePath[..<range.lowerBound]) + ".app"
        if let cached = byBundlePath[bundlePath] { return cached }
        let result = bundle(atPath: bundlePath)
        byBundlePath[bundlePath] = result
        return result
    }

    private func bundle(atPath path: String) -> AppBundle? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let info = Bundle(path: path)?.localizedInfoDictionary ?? [:]
        let plain = Bundle(path: path)?.infoDictionary ?? [:]
        let candidates = [info["CFBundleDisplayName"], plain["CFBundleDisplayName"], info["CFBundleName"], plain["CFBundleName"]]
        var name = candidates.compactMap { $0 as? String }.first { !$0.isEmpty }
        if name == nil {
            name = (FileManager.default.displayName(atPath: path) as NSString).deletingPathExtension
        }
        return AppBundle(name: name ?? (path as NSString).lastPathComponent, path: path)
    }
}
