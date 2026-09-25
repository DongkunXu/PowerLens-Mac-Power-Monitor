import AppKit
import Observation
import PowerLensCore
import ServiceManagement

@MainActor
@Observable
public final class AppModel {
    public private(set) var state: PanelState?
    public var expanded: Set<GroupKey> = []
    public var assertionsExpanded = false

    public var chartRange: TimeInterval = 15 * 60 {
        didSet { pushOptions() }
    }
    public var chartTopN: Int = 5 {
        didSet { pushOptions() }
    }

    /// Chart color slot per group. A group keeps its color while it stays charted,
    /// so a change in rank never repaints it.
    private(set) var colorSlots: [GroupKey: Int] = [:]

    @ObservationIgnored private let monitor = PowerMonitor()
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    public enum Appearance: String, CaseIterable, Sendable {
        case system, light, dark
    }

    private static let appearanceKey = "appearance"
    private static let languageKey = "language"

    /// False for the snapshot tool, which must leave no preferences behind.
    @ObservationIgnored private let savesPreferences: Bool

    /// Stored in the app's preferences (removed by scripts/uninstall.sh).
    public var appearance: Appearance = Appearance(
        rawValue: UserDefaults.standard.string(forKey: AppModel.appearanceKey) ?? "") ?? .system {
        didSet {
            if savesPreferences { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
            applyAppearance()
        }
    }

    /// Panel language; English unless the user picked another one. Stored in the app's preferences.
    public var language: Language = Language(
        rawValue: UserDefaults.standard.string(forKey: AppModel.languageKey) ?? "") ?? .english {
        didSet {
            if savesPreferences { UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey) }
        }
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// - Parameter temporaryLanguage: when given, this instance uses that language and never writes
    ///   preferences at all (the snapshot tool); otherwise settings are read from and saved to
    ///   the app's preferences.
    public init(temporaryLanguage: Language? = nil) {
        savesPreferences = temporaryLanguage == nil
        if let temporaryLanguage { language = temporaryLanguage }
        applyAppearance()
        monitor.start { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
    }

    public func setPanelVisible(_ visible: Bool) {
        monitor.setVisible(visible)
    }

    private func pushOptions() {
        monitor.setOptions(PanelOptions(chartRange: chartRange, chartTopN: chartTopN))
    }

    private func apply(_ newState: PanelState) {
        assignColors(for: newState.chart.series.map(\.key))
        // Keep icons only for rows currently shown.
        let shown = Set(newState.rows.compactMap(\.info.bundlePath))
        icons = icons.filter { shown.contains($0.key) }
        state = newState
    }

    private func assignColors(for keys: [GroupKey]) {
        let wanted = Set(keys)
        var slots = colorSlots.filter { wanted.contains($0.key) }
        var free = Set(0..<Palette.slotCount).subtracting(slots.values)
        for key in keys where slots[key] == nil {
            guard let slot = free.min() else { break }
            slots[key] = slot
            free.remove(slot)
        }
        if slots != colorSlots { colorSlots = slots }
    }

    func icon(for info: GroupInfo) -> NSImage? {
        guard let path = info.bundlePath else { return nil }
        if let cached = icons[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        icons[path] = image
        return image
    }

    func toggleExpanded(_ key: GroupKey) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    // MARK: - Launch at login

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}
