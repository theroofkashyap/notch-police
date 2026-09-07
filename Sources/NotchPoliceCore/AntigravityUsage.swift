import Foundation

/// Parsers for the local Connect-RPC responses exposed by Antigravity's
/// language server. The server reports remaining fractions directly, so this
/// adapter never has to infer a limit or turn request counts into percentages.
public enum AntigravityUsage {
    public struct Parsed: Equatable {
        public var plan: String?
        public var windows: [LimitWindow]
    }

    public static func parseUserStatus(_ data: Data) -> Parsed? {
        guard let response = try? JSONDecoder().decode(UserStatusResponse.self, from: data),
              response.code?.isOK != false,
              let status = response.userStatus
        else { return nil }

        let plan = status.userTier?.preferredName
            ?? status.planStatus?.planInfo?.preferredName
        return Parsed(
            plan: plan,
            windows: windows(from: status.cascadeModelConfigData?.clientModelConfigs ?? [])
        )
    }

    public static func parseCommandModels(_ data: Data) -> Parsed? {
        guard let response = try? JSONDecoder().decode(CommandModelsResponse.self, from: data),
              response.code?.isOK != false
        else { return nil }
        return Parsed(plan: nil, windows: windows(from: response.clientModelConfigs ?? []))
    }

    public static func parseQuotaSummary(_ data: Data) -> Parsed? {
        guard let response = try? JSONDecoder().decode(QuotaSummaryResponse.self, from: data)
        else { return nil }
        let groups = response.response?.groups ?? response.groups ?? []
        var result: [LimitWindow] = []
        for group in groups {
            for bucket in group.buckets ?? [] {
                guard let remaining = bucket.remainingFraction,
                      remaining.isFinite,
                      (0...1).contains(remaining)
                else { continue }
                let label = nonempty(group.displayName)
                    ?? nonempty(bucket.displayName)
                    ?? "Antigravity"
                result.append(
                    LimitWindow(
                        id: nonempty(bucket.bucketId) ?? slug(label),
                        label: label,
                        usedPercent: (1 - remaining) * 100,
                        resetsAt: parseISO8601(bucket.resetTime)
                    )
                )
            }
        }
        return Parsed(plan: nil, windows: deduplicated(result))
    }

    private static func windows(from configs: [ModelConfig]) -> [LimitWindow] {
        let result = configs.compactMap { config -> LimitWindow? in
            guard let remaining = config.quotaInfo?.remainingFraction,
                  remaining.isFinite,
                  (0...1).contains(remaining)
            else { return nil }
            let label = nonempty(config.label)
                ?? nonempty(config.modelOrAlias?.model)
                ?? "Antigravity model"
            return LimitWindow(
                id: nonempty(config.modelOrAlias?.model) ?? slug(label),
                label: label,
                usedPercent: (1 - remaining) * 100,
                resetsAt: parseISO8601(config.quotaInfo?.resetTime)
            )
        }
        return deduplicated(result)
    }

    /// Some server versions repeat aliases for the same model. Preserve the
    /// first display label but keep the tightest reading and latest reset.
    private static func deduplicated(_ windows: [LimitWindow]) -> [LimitWindow] {
        var order: [String] = []
        var byID: [String: LimitWindow] = [:]
        for window in windows {
            if byID[window.id] == nil { order.append(window.id) }
            if let old = byID[window.id], old.usedPercent >= window.usedPercent {
                continue
            }
            byID[window.id] = window
        }
        return order.compactMap { byID[$0] }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func slug(_ value: String) -> String {
        String(
            value.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        )
    }
}

private struct UserStatusResponse: Decodable {
    var code: AntigravityCode?
    var userStatus: AntigravityUserStatus?
}

private struct CommandModelsResponse: Decodable {
    var code: AntigravityCode?
    var clientModelConfigs: [ModelConfig]?
}

private struct AntigravityUserStatus: Decodable {
    var planStatus: PlanStatus?
    var cascadeModelConfigData: ModelConfigData?
    var userTier: UserTier?
}

private struct ModelConfigData: Decodable {
    var clientModelConfigs: [ModelConfig]?
}

private struct ModelConfig: Decodable {
    var label: String?
    var modelOrAlias: ModelAlias?
    var quotaInfo: QuotaInfo?
}

private struct ModelAlias: Decodable {
    var model: String?
}

private struct QuotaInfo: Decodable {
    var remainingFraction: Double?
    var resetTime: String?
}

private struct PlanStatus: Decodable {
    var planInfo: PlanInfo?
}

private struct PlanInfo: Decodable {
    var planName: String?
    var planDisplayName: String?
    var displayName: String?
    var productName: String?
    var planShortName: String?

    var preferredName: String? {
        [planDisplayName, displayName, productName, planName, planShortName]
            .compactMap { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { return nil }
                return value
            }
            .first
    }
}

private struct UserTier: Decodable {
    var name: String?

    var preferredName: String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }
}

private enum AntigravityCode: Decodable {
    case int(Int)
    case string(String)

    var isOK: Bool {
        switch self {
        case .int(let value): return value == 0
        case .string(let value):
            return value == "0"
                || value.caseInsensitiveCompare("ok") == .orderedSame
                || value.caseInsensitiveCompare("success") == .orderedSame
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let int = try? value.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try value.decode(String.self))
        }
    }
}

private struct QuotaSummaryResponse: Decodable {
    struct Body: Decodable {
        var groups: [Group]?
    }

    struct Group: Decodable {
        var displayName: String?
        var buckets: [Bucket]?
    }

    struct Bucket: Decodable {
        var bucketId: String?
        var displayName: String?
        var remainingFraction: Double?
        var resetTime: String?
    }

    var response: Body?
    var groups: [Group]?
}
