import SwiftUI

enum MotionDockTheme {
    static let background = Color(hex: 0x101113)
    static let surface = Color(hex: 0x15161A)
    static let secondarySurface = surface
    static let card = Color(hex: 0x1C1D21)
    static let border = Color.white.opacity(0.08)
    static let accent = Color(hex: 0x0A84FF)
    static let cyan = Color(hex: 0x30D5FF)
    static let cyanHighlight = cyan
    static let success = Color(hex: 0x30D158)
    static let secondaryText = Color.white.opacity(0.56)
    static let mutedText = Color.white.opacity(0.36)
    static let cornerRadius: CGFloat = 18
    static let radius = cornerRadius
    static let animation = Animation.easeInOut(duration: 0.18)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
