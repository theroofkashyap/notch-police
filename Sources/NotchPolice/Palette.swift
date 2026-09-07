import SwiftUI
import NotchPoliceCore

enum Palette {
    static let bezel = Color.black
    static let brass = Color(red: 0.83, green: 0.68, blue: 0.36)
    static let track = Color.white.opacity(0.12)
    static let glyph = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.45)
    static let card = Color(red: 0.05, green: 0.05, blue: 0.055)

    static func band(_ band: UsageBand) -> Color {
        switch band {
        case .clear: return Color(red: 0.22, green: 0.86, blue: 0.52)
        case .warning: return Color(red: 0.96, green: 0.78, blue: 0.18)
        case .critical, .empty: return Color(red: 1.0, green: 0.32, blue: 0.22)
        case .unknown: return Color.white.opacity(0.28)
        }
    }

    static func accent(_ kind: ProviderKind) -> Color {
        switch kind {
        case .claude: return Color(red: 0.84, green: 0.44, blue: 0.32)
        case .cursor: return Color(red: 0.92, green: 0.92, blue: 0.94)
        case .chatgpt: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .antigravity: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .grok: return Color(red: 0.90, green: 0.91, blue: 0.94)
        }
    }
}

enum NotchMetrics {
    static let depth: CGFloat = 56
    static let cell: CGFloat = 64
    static let ring: CGFloat = 36
    static let curl: CGFloat = 12
    static let corner: CGFloat = 18
    static let tooltipWidth: CGFloat = 276
    static let tooltipGap: CGFloat = 8
    static let handle: CGFloat = 22
    /// Horizontal edges lay ring and label side by side, so a cell is wider
    /// than it is tall there; the pill is only `depth` tall.
    static let wideCell: CGFloat = 80
    /// Room reserved for the tooltip card along the axis it grows on.
    static let tooltipHeightAllowance: CGFloat = 380
}
