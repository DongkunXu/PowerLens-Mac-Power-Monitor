// powerlens-snapshot: renders the real panel, fed by live data, into a PNG.
// Usage: powerlens-snapshot --out file.png [--seconds 35] [--dark] [--language en|zh-Hans]
//                           [--expand 2] [--range 5|15] [--top 3|5] [--assertions]
// It never writes preferences: the language given here is used for this run only.
import AppKit
import PowerLensUI
import SwiftUI

struct Options {
    var out = "panel.png"
    var seconds = 35.0
    var dark = false
    var language = Language.english
    var expand = 0
    var rangeMinutes = 15.0
    var top = 5
    var assertions = false

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--out": out = it.next() ?? out
            case "--seconds": seconds = it.next().flatMap(Double.init) ?? seconds
            case "--dark": dark = true
            case "--language":
                guard let value = it.next(), let parsed = Language(rawValue: value) else {
                    FileHandle.standardError.write(Data("--language expects one of: \(Language.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    exit(2)
                }
                language = parsed
            case "--expand": expand = it.next().flatMap(Int.init) ?? expand
            case "--range": rangeMinutes = it.next().flatMap(Double.init) ?? rangeMinutes
            case "--top": top = it.next().flatMap(Int.init) ?? top
            case "--assertions": assertions = true
            default:
                FileHandle.standardError.write(Data("unknown argument \(arg)\n".utf8))
                exit(2)
            }
        }
    }
}

let options = Options(CommandLine.arguments)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let model = AppModel(temporaryLanguage: options.language)
model.chartRange = options.rangeMinutes * 60
model.chartTopN = options.top
model.assertionsExpanded = options.assertions

let size = NSSize(width: 360, height: 760)
let root = PanelView(model: model).background(Color(nsColor: .windowBackgroundColor))
let hosting = NSHostingView(rootView: root)
hosting.frame = NSRect(origin: .zero, size: size)
let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                      styleMask: .borderless, backing: .buffered, defer: false)
window.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)
window.contentView = hosting
window.orderFrontRegardless()

Task { @MainActor in
    try? await Task.sleep(for: .seconds(options.seconds))
    if let rows = model.state?.rows {
        model.expanded = Set(rows.prefix(options.expand).map(\.id))
    }
    try? await Task.sleep(for: .seconds(1.5))
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
        exit(1)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do {
        try png.write(to: URL(fileURLWithPath: options.out))
        print("wrote \(options.out)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}

app.run()
