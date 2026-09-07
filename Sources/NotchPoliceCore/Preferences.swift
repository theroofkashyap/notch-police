import Foundation

public struct Preferences: Equatable, Sendable {
    public var edge: ScreenEdge
    public var displayMode: DisplayMode
    public var enabled: [ProviderKind: Bool]
    public var pollSeconds: Int
    public var notifyBelow: Int
    public var showDockIcon: Bool
    public var demo: Bool

    public static let `default` = Preferences(
        edge: .right,
        displayMode: .remaining,
        enabled: [
            .claude: true,
            .cursor: true,
            .chatgpt: true,
            .antigravity: true,
            .grok: true,
        ],
        pollSeconds: 90,
        notifyBelow: 15,
        showDockIcon: true,
        demo: false
    )

    public func isEnabled(_ kind: ProviderKind) -> Bool {
        enabled[kind] ?? true
    }

    /// The low-credit alert and the copy-context button read the same number so
    /// they can never disagree about what "about to run out" means. Zero means
    /// the user switched notifications off, not that nothing is ever urgent, so
    /// the button keeps a sensible default.
    public var dyingBelow: Double {
        notifyBelow > 0 ? Double(notifyBelow) : 20
    }
}

public final class PreferenceStore {
    private let defaults: UserDefaults
    private let key = "notchpolice.preferences.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        var prefs = Preferences.default
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            prefs = stored.make()
        }
        // The demo flag is a launch override for screenshots and bug reports.
        // It must not quietly rewrite a saved Dock preference, so it only
        // turns the Dock icon on when nothing has been saved yet.
        if ProcessInfo.processInfo.environment["NOTCH_POLICE_DEMO"] == "1" {
            prefs.demo = true
            if defaults.data(forKey: key) == nil {
                prefs.showDockIcon = true
            }
        }
        return prefs
    }

    public func save(_ prefs: Preferences) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Stored(prefs)) {
            defaults.set(data, forKey: key)
        }
    }

    private struct Stored: Codable {
        var edge: String
        var displayMode: String
        var enabled: [String: Bool]
        var pollSeconds: Int
        var notifyBelow: Int
        var showDockIcon: Bool
        var demo: Bool

        init(_ prefs: Preferences) {
            edge = prefs.edge.rawValue
            displayMode = prefs.displayMode.rawValue
            enabled = Dictionary(uniqueKeysWithValues: prefs.enabled.map { ($0.key.rawValue, $0.value) })
            pollSeconds = prefs.pollSeconds
            notifyBelow = prefs.notifyBelow
            showDockIcon = prefs.showDockIcon
            demo = prefs.demo
        }

        func make() -> Preferences {
            var enabledMap: [ProviderKind: Bool] = Preferences.default.enabled
            for (key, value) in enabled {
                if let kind = ProviderKind(rawValue: key) {
                    enabledMap[kind] = value
                }
            }
            return Preferences(
                edge: ScreenEdge(rawValue: edge) ?? .right,
                displayMode: DisplayMode(rawValue: displayMode) ?? .remaining,
                enabled: enabledMap,
                pollSeconds: max(30, pollSeconds),
                notifyBelow: min(50, max(0, notifyBelow)),
                showDockIcon: showDockIcon,
                demo: demo
            )
        }
    }
}
