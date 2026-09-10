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

    /// Claude Code stores `{ claudeAiOauth, mcpOAuth }` in one Keychain item.
    /// `mcpOAuth` can grow until `/usr/bin/security -i` (4 KB line) silently
    /// truncates the write, so the blob is no longer valid JSON. The OAuth
    /// object we need sits first and is still complete — take every top-level
    /// value that closed, and ignore a trailing fragment.
    public static func credentialsObject(from data: Data) -> [String: Any]? {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        return CredentialsJSON.partialObject(from: data)
    }

    /// Swap the `claudeAiOauth` object in a (possibly truncated) blob so a
    /// refresh can persist without rewriting `mcpOAuth` from a partial parse,
    /// which would wipe the tail Claude Code still holds.
    public static func replacingOAuthObject(in data: Data, with oauth: [String: Any]) -> Data? {
        CredentialsJSON.replacingTopLevelObject(key: "claudeAiOauth", in: data, with: oauth)
    }
}

/// Byte-level JSON object walk. Structural characters are ASCII; string
/// bodies are skipped, not interpreted, so truncation in a later key cannot
/// poison an earlier complete value.
private enum CredentialsJSON {
    static func partialObject(from data: Data) -> [String: Any]? {
        var root: [String: Any] = [:]
        var i = 0
        skipSpace(data, &i)
        guard i < data.count, data[i] == 0x7B else { return nil }
        i += 1
        while true {
            skipSpace(data, &i)
            guard i < data.count else { break }
            if data[i] == 0x7D { break }
            if data[i] == 0x2C { i += 1; continue }
            guard data[i] == 0x22 else { break }
            let keyStart = i
            guard skipString(data, &i) else { break }
            guard let key = fragment(data[keyStart..<i]) as? String else { break }
            skipSpace(data, &i)
            guard i < data.count, data[i] == 0x3A else { break }
            i += 1
            skipSpace(data, &i)
            let valueStart = i
            guard skipValue(data, &i) else { break }
            root[key] = fragment(data[valueStart..<i])
        }
        return root.isEmpty ? nil : root
    }

    static func replacingTopLevelObject(key: String, in data: Data, with value: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(value),
              let encoded = try? JSONSerialization.data(withJSONObject: value, options: []),
              let range = topLevelValueRange(key: key, in: data)
        else { return nil }
        var out = Data()
        out.append(data[0..<range.lowerBound])
        out.append(encoded)
        out.append(data[range.upperBound...])
        return out
    }

    private static func topLevelValueRange(key: String, in data: Data) -> Range<Int>? {
        var i = 0
        skipSpace(data, &i)
        guard i < data.count, data[i] == 0x7B else { return nil }
        i += 1
        while true {
            skipSpace(data, &i)
            guard i < data.count else { return nil }
            if data[i] == 0x7D { return nil }
            if data[i] == 0x2C { i += 1; continue }
            guard data[i] == 0x22 else { return nil }
            let keyStart = i
            guard skipString(data, &i) else { return nil }
            let found = fragment(data[keyStart..<i]) as? String
            skipSpace(data, &i)
            guard i < data.count, data[i] == 0x3A else { return nil }
            i += 1
            skipSpace(data, &i)
            let valueStart = i
            guard skipValue(data, &i) else { return nil }
            if found == key { return valueStart..<i }
        }
    }

    private static func fragment(_ slice: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: slice, options: [.fragmentsAllowed])
    }

    private static func skipSpace(_ data: Data, _ i: inout Int) {
        while i < data.count {
            switch data[i] {
            case 0x20, 0x09, 0x0A, 0x0D: i += 1
            default: return
            }
        }
    }

    private static func skipString(_ data: Data, _ i: inout Int) -> Bool {
        guard i < data.count, data[i] == 0x22 else { return false }
        i += 1
        while i < data.count {
            let byte = data[i]
            if byte == 0x5C {
                i += 2
                continue
            }
            i += 1
            if byte == 0x22 { return true }
        }
        return false
    }

    private static func skipValue(_ data: Data, _ i: inout Int) -> Bool {
        guard i < data.count else { return false }
        switch data[i] {
        case 0x7B: return skipContainer(data, &i, open: 0x7B, close: 0x7D)
        case 0x5B: return skipContainer(data, &i, open: 0x5B, close: 0x5D)
        case 0x22: return skipString(data, &i)
        case 0x74: return skipLiteral(data, &i, [0x74, 0x72, 0x75, 0x65])
        case 0x66: return skipLiteral(data, &i, [0x66, 0x61, 0x6C, 0x73, 0x65])
        case 0x6E: return skipLiteral(data, &i, [0x6E, 0x75, 0x6C, 0x6C])
        case 0x2D, 0x30...0x39: return skipNumber(data, &i)
        default: return false
        }
    }

    private static func skipContainer(_ data: Data, _ i: inout Int, open: UInt8, close: UInt8) -> Bool {
        guard i < data.count, data[i] == open else { return false }
        var depth = 0
        var inString = false
        var escape = false
        while i < data.count {
            let byte = data[i]
            i += 1
            if inString {
                if escape {
                    escape = false
                } else if byte == 0x5C {
                    escape = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case open: depth += 1
            case close:
                depth -= 1
                if depth == 0 { return true }
            default: break
            }
        }
        return false
    }

    private static func skipLiteral(_ data: Data, _ i: inout Int, _ bytes: [UInt8]) -> Bool {
        guard i + bytes.count <= data.count else { return false }
        for offset in 0..<bytes.count {
            if data[i + offset] != bytes[offset] { return false }
        }
        i += bytes.count
        return true
    }

    private static func skipNumber(_ data: Data, _ i: inout Int) -> Bool {
        let start = i
        if i < data.count, data[i] == 0x2D { i += 1 }
        var seenDigit = false
        while i < data.count, data[i] >= 0x30, data[i] <= 0x39 {
            seenDigit = true
            i += 1
        }
        if i < data.count, data[i] == 0x2E {
            i += 1
            while i < data.count, data[i] >= 0x30, data[i] <= 0x39 {
                seenDigit = true
                i += 1
            }
        }
        if i < data.count, data[i] == 0x65 || data[i] == 0x45 {
            i += 1
            if i < data.count, data[i] == 0x2B || data[i] == 0x2D { i += 1 }
            while i < data.count, data[i] >= 0x30, data[i] <= 0x39 {
                i += 1
            }
        }
        return seenDigit && i > start
    }
}
