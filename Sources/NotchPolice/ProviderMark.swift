import AppKit
import SwiftUI
import NotchPoliceCore

enum ProviderIcon {
    /// Decoded once per provider. SwiftUI re-evaluates these bodies on every
    /// hover and on every frame of the low-credit pulse, and the source files
    /// are a few hundred kilobytes each.
    private static var cache: [ProviderKind: NSImage] = [:]

    static func nsImage(for kind: ProviderKind) -> NSImage? {
        if let cached = cache[kind] { return cached }
        guard let image = load(kind) else { return nil }
        cache[kind] = image
        return image
    }

    private static func load(_ kind: ProviderKind) -> NSImage? {
        let name: String
        switch kind {
        case .claude: name = "claude"
        case .cursor: name = "cursor"
        case .chatgpt: name = "chatgpt"
        case .antigravity: name = "antigravity"
        case .grok: name = "grok"
        }
        let candidates: [URL] = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Providers"),
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/Providers/\(name).png"),
        ].compactMap { $0 }
        for url in candidates {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}

struct ProviderMark: View {
    var kind: ProviderKind
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let image = ProviderIcon.nsImage(for: kind) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Palette.accent(kind))
                    Text(kind.fallbackMark)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(kind.fallbackMarkColor)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .clipShape(Circle())
        .opacity(dimmed ? 0.35 : 1)
        .overlay(
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .accessibilityLabel(kind.displayName)
    }
}

private extension ProviderKind {
    var fallbackMark: String {
        switch self {
        case .claude: return "C"
        case .cursor: return "C"
        case .chatgpt: return "GPT"
        case .antigravity: return "A"
        case .grok: return "G"
        }
    }

    var fallbackMarkColor: Color {
        switch self {
        case .cursor, .grok: return .black.opacity(0.86)
        default: return .white
        }
    }
}

struct RemainingRing: View {
    var remaining: Double?
    var band: UsageBand
    var kind: ProviderKind
    var pulse: Bool = false

    var body: some View {
        let shown = remaining ?? 0
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(shown / 100))
                .stroke(
                    Palette.band(band),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            ProviderMark(kind: kind, dimmed: remaining == nil)
                .frame(width: 24, height: 24)
        }
        .scaleEffect(pulse ? 1.06 : 1)
        .animation(pulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
    }
}
