import Foundation

public enum ProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case cursor
    case chatgpt
    case antigravity
    case grok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .chatgpt: return "ChatGPT"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        }
    }

    public var shortName: String {
        switch self {
        case .claude: return "CL"
        case .cursor: return "CU"
        case .chatgpt: return "GPT"
        case .antigravity: return "AG"
        case .grok: return "GR"
        }
    }

    public var dashboardURL: URL {
        switch self {
        case .claude:
            return URL(string: "https://claude.ai/settings/usage")!
        case .cursor:
            return URL(string: "https://cursor.com/dashboard?tab=usage")!
        case .chatgpt:
            return URL(string: "https://chatgpt.com/#settings")!
        case .antigravity:
            return URL(string: "https://antigravity.google")!
        case .grok:
            return URL(string: "https://grok.com/?_s=usage")!
        }
    }

    public var signInHint: String {
        switch self {
        case .claude:
            return "Sign in with Claude Code. Notch Police reads the login it keeps in Keychain."
        case .cursor:
            return "Open Cursor and sign in. Notch Police reads the editor’s local session."
        case .chatgpt:
            return "Run `codex login` (ChatGPT / Codex CLI). The desktop ChatGPT app does not expose a readable session."
        case .antigravity:
            return "Open Antigravity or run `agy`. Notch Police reads quota from its local language server while it is running."
        case .grok:
            return "Run `grok login`. Notch Police reads the Grok CLI session in ~/.grok/auth.json."
        }
    }

    public var signInCommand: String? {
        switch self {
        case .claude: return "claude auth login"
        case .cursor: return nil
        case .chatgpt: return "codex login"
        case .antigravity: return "open -a Antigravity"
        case .grok: return "grok login"
        }
    }

    /// Windows that exist on typical plans, so Settings can offer a pin
    /// before the first poll (and while a scoped cap is temporarily absent).
    public var stableRingWindows: [RingWindowOption] {
        switch self {
        case .claude:
            return [
                RingWindowOption(id: "session", label: "5-hour session"),
                RingWindowOption(id: "weekly", label: "Weekly"),
            ]
        case .cursor:
            return [
                RingWindowOption(id: "included", label: "Included usage"),
                RingWindowOption(id: "api", label: "API / named models"),
            ]
        case .chatgpt:
            return [
                RingWindowOption(id: "five-hour", label: "5-hour"),
                RingWindowOption(id: "weekly", label: "Weekly"),
            ]
        case .antigravity:
            return []
        case .grok:
            return [RingWindowOption(id: "credits", label: "Grok Build")]
        }
    }
}

public struct RingWindowOption: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// The ring pin stored in preferences. `tightest` is the default and is
/// never persisted, so old installs keep today's behaviour.
public enum RingWindowPin {
    public static let tightest = "tightest"

    public static func options(
        kind: ProviderKind,
        windows: [LimitWindow],
        pinned: String? = nil
    ) -> [RingWindowOption] {
        var seen = Set<String>()
        var result: [RingWindowOption] = []
        func add(_ id: String, _ label: String) {
            guard id != tightest, seen.insert(id).inserted else { return }
            result.append(RingWindowOption(id: id, label: label))
        }
        for window in kind.stableRingWindows {
            add(window.id, window.label)
        }
        for window in windows {
            add(window.id, window.label)
        }
        if let pinned, !pinned.isEmpty, pinned != tightest {
            add(pinned, label(for: pinned, kind: kind, windows: windows))
        }
        return result
    }

    public static func label(
        for id: String,
        kind: ProviderKind,
        windows: [LimitWindow]
    ) -> String {
        if let window = windows.first(where: { $0.id == id }) { return window.label }
        if let known = kind.stableRingWindows.first(where: { $0.id == id }) { return known.label }
        if id.hasPrefix("scoped-") {
            return "\(id.dropFirst("scoped-".count)) weekly"
        }
        return id
    }
}

public enum DisplayMode: String, Codable, Sendable {
    case remaining
    case used
}

public enum ScreenEdge: String, CaseIterable, Identifiable, Codable, Sendable {
    case right, left, top, bottom
    public var id: String { rawValue }
    public var isVertical: Bool { self == .left || self == .right }
}
