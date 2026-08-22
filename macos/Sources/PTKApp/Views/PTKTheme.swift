import AppKit
import SwiftUI

/* Hallmark · genre: modern-minimal · macrostructure: Workbench · tone: utilitarian
 * theme: macOS system · designed-as-app · native status-item panel
 */

enum PTKType {
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum PTKSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

enum PTKMotion {
    static let microDuration: Double = 0.12
    static let reducedDuration: Double = 0.15

    static let micro = Animation.timingCurve(0.16, 1, 0.3, 1, duration: microDuration)

    static func micro(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: reducedDuration) : micro
    }
}

enum PTKTheme {
    static let radiusControl: CGFloat = 6
    static let radiusGroup: CGFloat = 8
    static let radiusPanel: CGFloat = 10

    static let paper = Color(nsColor: .windowBackgroundColor)
    static let lift = adaptive(
        light: NSColor(calibratedWhite: 1, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1, alpha: 0.06)
    )
    static let rule = Color(nsColor: .separatorColor)
    static let ink = Color.primary
    static let muted = Color.secondary
    static let faint = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color.accentColor
    static let danger = Color(nsColor: .systemRed)
    static let caution = Color(nsColor: .systemOrange)
    static let running = Color(nsColor: .systemGreen)
    static let focus = accent

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
