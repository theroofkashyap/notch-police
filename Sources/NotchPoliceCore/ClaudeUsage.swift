import Foundation

public enum ClaudeUsage {
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let legacyTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let keychainService = "Claude Code-credentials"

    public struct Parsed: Equatable {
        public var plan: String?
        public var windows: [LimitWindow]
    }

    public static func parse(object: [String: Any], plan: String? = nil) -> Parsed {
        let scale = PercentScale.detect(utilizations(in: object))
        var windows: [LimitWindow] = []

        if let window = window(id: "session", label: "5-hour session", from: object["five_hour"], scale: scale) {
            windows.append(window)
        }
        if let window = window(id: "weekly", label: "Weekly", from: object["seven_day"], scale: scale) {
            windows.append(window)
        }
        for limit in scopedLimits(in: object) {
            let name = (((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String)
                ?? "Model cap"
            windows.append(
                LimitWindow(
                    id: "scoped-\(name)",
                    label: "\(name) weekly",
                    usedPercent: scale.normalize(number(limit["percent"]) ?? 0),
                    resetsAt: parseISO8601(limit["resets_at"] as? String)
                )
            )
        }
        return Parsed(plan: plan, windows: windows)
    }

    /// Every utilization reading in the payload, so the 0–100 vs 0–1 scale is
    /// decided once for the whole response rather than window by window.
    private static func utilizations(in object: [String: Any]) -> [Double] {
        var values: [Double] = []
        for key in ["five_hour", "seven_day"] {
            if let dict = object[key] as? [String: Any], let value = number(dict["utilization"]) {
                values.append(value)
            }
        }
        for limit in scopedLimits(in: object) {
            if let value = number(limit["percent"]) { values.append(value) }
        }
        return values
    }

    private static func scopedLimits(in object: [String: Any]) -> [[String: Any]] {
        guard let limits = object["limits"] as? [[String: Any]] else { return [] }
        return limits.filter { limit in
            (limit["kind"] as? String) == "weekly_scoped" && (limit["is_active"] as? Bool ?? false)
        }
    }

    private static func window(
        id: String,
        label: String,
        from raw: Any?,
        scale: PercentScale
    ) -> LimitWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        return LimitWindow(
            id: id,
            label: label,
            usedPercent: scale.normalize(number(dict["utilization"]) ?? 0),
            resetsAt: parseISO8601(dict["resets_at"] as? String)
        )
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    public static func prettyPlan(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: "default_", with: "")
            .replacingOccurrences(of: "claude_", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    public static func refreshToken(in root: [String: Any]) -> String? {
        (root["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String
    }

    public static func mergeRefreshedOAuth(
        existing: [String: Any],
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int,
        scope: String?,
        now: Date = Date()
    ) -> [String: Any] {
        var root = existing
        var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        if let refreshToken, !refreshToken.isEmpty {
            oauth["refreshToken"] = refreshToken
        }
        oauth["expiresAt"] = Int(now.timeIntervalSince1970 * 1000) + expiresIn * 1000
        if let scope, !scope.isEmpty {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        root["claudeAiOauth"] = oauth
        return root
    }
}
