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
            return "Sign in with Claude Code, then grant keychain access when macOS asks."
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
