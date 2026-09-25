import PowerLensCore
import SwiftUI

struct AssertionsView: View {
    @Bindable var model: AppModel
    let assertions: [SleepAssertionState]
    @Environment(\.strings) private var strings

    var body: some View {
        DisclosureGroup(isExpanded: $model.assertionsExpanded) {
            if assertions.isEmpty {
                Text(strings.noSleepAssertions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(assertions) { a in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(a.processName)
                                Spacer()
                                Text(a.effect == .preventsSystemSleep ? strings.preventsSystemSleep : strings.preventsDisplaySleep)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            Text(a.reason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            Text(strings.sleepAssertions(assertions.count))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 6)
    }
}

struct FooterView: View {
    let state: PanelState
    @Environment(\.strings) private var strings

    var body: some View {
        HStack(spacing: 12) {
            Text(strings.legend(Int(state.smoothingWindow)))
            Spacer()
            Text(strings.selfPower(Format.watts(state.selfPower)))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Top-right "⋯" menu: launch at login, appearance, language, quit.
struct SettingsMenu: View {
    @Bindable var model: AppModel
    @Environment(\.strings) private var strings

    var body: some View {
        Menu {
            Toggle(strings.launchAtLogin, isOn: Binding(get: { model.launchesAtLogin },
                                                       set: { model.setLaunchesAtLogin($0) }))
            if let error = model.loginItemError {
                Text(error)
            }
            Picker(strings.appearance, selection: $model.appearance) {
                ForEach(AppModel.Appearance.allCases, id: \.self) { Text(title(of: $0)).tag($0) }
            }
            Picker(strings.language, selection: $model.language) {
                ForEach(Language.allCases, id: \.self) { Text($0.nativeName).tag($0) }
            }
            Divider()
            Button(strings.quit) { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(strings.settings)
    }

    private func title(of appearance: AppModel.Appearance) -> String {
        switch appearance {
        case .system: return strings.appearanceSystem
        case .light: return strings.appearanceLight
        case .dark: return strings.appearanceDark
        }
    }
}
