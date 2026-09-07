import Foundation

/// Parses the official credits response used by Grok CLI's `/usage` command.
/// `creditUsagePercent` is the weekly Grok Build allowance; the endpoint does
/// not expose consumer Grok Chat's separate free-tier limits.
public enum GrokUsage {
    public static func parse(data: Data) -> [LimitWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = root["config"] as? [String: Any]
        else { return [] }

        let reset = date((config["currentPeriod"] as? [String: Any])?["end"])
            ?? date(config["billingPeriodEnd"])
        let products = config["productUsage"] as? [[String: Any]] ?? []

        if let used = number(config["creditUsagePercent"]) {
            let product = products.first?["product"] as? String
            return [
                LimitWindow(
                    id: "credits",
                    label: product.map(humanize) ?? "Grok Build",
                    usedPercent: clampPercent(used),
                    resetsAt: reset
                ),
            ]
        }

        return products.enumerated().compactMap { index, product in
            guard let used = number(product["usagePercent"]) else { return nil }
            let wireName = product["product"] as? String
            return LimitWindow(
                id: index == 0 ? "credits" : (wireName ?? "product-\(index)"),
                label: wireName.map(humanize) ?? "Grok usage",
                usedPercent: clampPercent(used),
                resetsAt: reset
            )
        }
    }

    static func humanize(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isUppercase, !result.isEmpty,
               result.last?.isWhitespace == false
            {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static func date(_ raw: Any?) -> Date? {
        GrokCredentials.date(raw)
    }
}
