import Foundation

public enum CursorUsage {
    public static let periodURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let tokenURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    public static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    public struct Parsed: Equatable {
        public var plan: String?
        public var windows: [LimitWindow]
    }

    /// `includedSpend` reaching `limit` does not mean the account is cut off:
    /// Cursor keeps serving requests out of `bonusSpend`, and its own UI quotes
    /// `totalPercentUsed` and `apiPercentUsed` as the real ceilings. Those two
    /// percentages drive the rings; the dollar figures are context only, or an
    /// exhausted included allowance would show as an empty quota on an account
    /// that still works. Cursor reports these on a 0–100 scale.
    public static func parse(object: [String: Any], membership: String? = nil) -> Parsed {
        let planUsage = object["planUsage"] as? [String: Any] ?? [:]
        let resets = parseEpoch(object["billingCycleEnd"])
        var windows: [LimitWindow] = []

        if let total = number(planUsage["totalPercentUsed"]) ?? number(planUsage["autoPercentUsed"]) {
            windows.append(
                LimitWindow(
                    id: "included",
                    label: "Included usage",
                    usedPercent: PercentScale.percent.normalize(total),
                    resetsAt: resets,
                    detail: spendDetail(planUsage)
                )
            )
        }
        if let api = number(planUsage["apiPercentUsed"]) {
            windows.append(
                LimitWindow(
                    id: "api",
                    label: "API / named models",
                    usedPercent: PercentScale.percent.normalize(api),
                    resetsAt: resets
                )
            )
        }

        return Parsed(plan: membership.map(prettyPlan), windows: windows)
    }

    /// Reads as "$20 of $20 included · $29 bonus". Cursor reports cents.
    static func spendDetail(_ planUsage: [String: Any]) -> String? {
        guard let limit = number(planUsage["limit"]), limit > 0 else { return nil }
        let included = min(number(planUsage["includedSpend"]) ?? 0, limit)
        var parts = [String(format: "$%.0f of $%.0f included", included / 100, limit / 100)]
        if let bonus = number(planUsage["bonusSpend"]), bonus > 0 {
            parts.append(String(format: "$%.0f bonus", bonus / 100))
        }
        return parts.joined(separator: " · ")
    }

    public static func prettyPlan(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}
