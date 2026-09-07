import Foundation

public enum ChatGPTUsage {
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public struct Parsed: Equatable {
        public var plan: String?
        public var windows: [LimitWindow]
    }

    public static func parse(object: [String: Any]) -> Parsed {
        let plan = (object["plan_type"] as? String)
            ?? (object["planType"] as? String)
        let rate = (object["rate_limit"] as? [String: Any])
            ?? (object["rateLimits"] as? [String: Any])
            ?? [:]

        let primary = rate["primary_window"] ?? rate["primary"] ?? object["five_hour"] ?? object["five_hour_limit"]
        let secondary = rate["secondary_window"] ?? rate["secondary"] ?? object["weekly"] ?? object["weekly_limit"]
        let scale = PercentScale.detect([primary, secondary].compactMap(usedPercent))

        var windows: [LimitWindow] = []
        if let window = parseWindow(id: "five-hour", defaultLabel: "5-hour", raw: primary, scale: scale) {
            windows.append(window)
        }
        if let window = parseWindow(id: "weekly", defaultLabel: "Weekly", raw: secondary, scale: scale) {
            windows.append(window)
        }
        return Parsed(plan: plan.map(CursorUsage.prettyPlan), windows: windows)
    }

    private static func usedPercent(_ raw: Any?) -> Double? {
        guard let dict = raw as? [String: Any] else { return nil }
        return number(dict["used_percent"])
            ?? number(dict["usedPercent"])
            ?? number(dict["utilization"])
    }

    private static func parseWindow(
        id: String,
        defaultLabel: String,
        raw: Any?,
        scale: PercentScale
    ) -> LimitWindow? {
        guard let dict = raw as? [String: Any] else { return nil }
        let used = usedPercent(dict) ?? 0
        let seconds = number(dict["limit_window_seconds"])
            ?? number(dict["limitWindowSeconds"])
            ?? number(dict["window_seconds"])
        let label = labelForWindow(seconds: seconds, fallback: defaultLabel)
        let resets = parseEpoch(dict["reset_at"] ?? dict["resets_at"] ?? dict["resetAt"])
            ?? relativeReset(dict["reset_after_seconds"])
        return LimitWindow(id: id, label: label, usedPercent: scale.normalize(used), resetsAt: resets)
    }

    private static func relativeReset(_ raw: Any?) -> Date? {
        guard let seconds = number(raw) else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private static func labelForWindow(seconds: Double?, fallback: String) -> String {
        guard let seconds else { return fallback }
        if abs(seconds - 18_000) < 60 { return "5-hour" }
        if abs(seconds - 604_800) < 3600 { return "Weekly" }
        if seconds >= 86_400 {
            return "\(Int((seconds / 86_400).rounded()))-day"
        }
        return fallback
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}
