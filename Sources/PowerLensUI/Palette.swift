import AppKit
import SwiftUI

/// Chart palette: the first five categorical slots of the validated reference palette,
/// each with its own light and dark step. Slot order is the CVD-safety mechanism; do not reorder.
enum Palette {
    private static let slots: [(light: UInt32, dark: UInt32)] = [
        (0x2A78D6, 0x3987E5), // blue
        (0xEB6834, 0xD95926), // orange
        (0x1BAF7A, 0x199E70), // aqua
        (0xEDA100, 0xC98500), // yellow
        (0xE87BA4, 0xD55181), // magenta
    ]

    static let slotCount = slots.count

    static func series(_ slot: Int) -> Color {
        let pair = slots[slot % slots.count]
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: dark ? pair.dark : pair.light)
        })
    }

    /// Hairline grid and axis colors (recessive, one step off the surface).
    static let grid = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x2C2C2A) : NSColor(hex: 0xE1E0D9)
    })
    static let axisLabel = Color(nsColor: NSColor(hex: 0x898781))
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
