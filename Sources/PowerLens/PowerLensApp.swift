import PowerLensUI
import ServiceManagement
import SwiftUI

@main
enum Entry {
    static func main() {
        // Used by scripts/uninstall.sh: remove the login item registered by this bundle, then exit.
        if CommandLine.arguments.contains("--unregister-login-item") {
            do {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("unregister failed: \(error)\n".utf8))
                exit(1)
            }
        }
        PowerLensApp.main()
    }
}

struct PowerLensApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            // Static icon only: no live numbers in the menu bar.
            Image(systemName: "bolt.horizontal.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
