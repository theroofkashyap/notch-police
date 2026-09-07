import Foundation

public enum SnapshotStatus: Equatable, Sendable {
    case ok
    case stale
    case needsAuth
    case accessDenied
    case error(String)
    case demo
    /// The provider asked us to back off. Carries the server's own retry hint
    /// when it sent one, so callers never have to parse an error message.
    case rateLimited(retryAfter: Date?)
}

public struct LimitWindow: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var detail: String?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = clampPercent(usedPercent)
        self.resetsAt = resetsAt
        self.detail = detail
    }

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public func displayPercent(mode: DisplayMode) -> Double {
        mode == .remaining ? remainingPercent : usedPercent
    }
}

public struct ProviderSnapshot: Equatable, Sendable, Identifiable {
    public var kind: ProviderKind
    public var plan: String?
    public var windows: [LimitWindow]
    public var fetchedAt: Date
    public var status: SnapshotStatus
    public var signInHint: String?

    public init(
        kind: ProviderKind,
        plan: String? = nil,
        windows: [LimitWindow] = [],
        fetchedAt: Date = Date(),
        status: SnapshotStatus,
        signInHint: String? = nil
    ) {
        self.kind = kind
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.status = status
        self.signInHint = signInHint
    }

    public var id: String { kind.rawValue }

    public var displayName: String { kind.displayName }

    /// The window most likely to cut you off next — highest usage.
    public var tightest: LimitWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    public var primaryRemaining: Double? {
        tightest.map(\.remainingPercent)
    }

    public var isLive: Bool {
        switch status {
        case .ok, .stale, .demo, .rateLimited: return tightest != nil
        default: return false
        }
    }

    /// Replaces a data-less result with the readings we already had, so a
    /// throttled or failed poll dims the ring instead of blanking it.
    public func fallingBack(to previous: ProviderSnapshot?) -> ProviderSnapshot {
        guard windows.isEmpty, let previous, !previous.windows.isEmpty else { return self }
        var merged = self
        merged.windows = previous.windows
        merged.plan = plan ?? previous.plan
        merged.fetchedAt = previous.fetchedAt
        return merged
    }
}

public enum UsageBand: Equatable, Sendable {
    case clear
    case warning
    case critical
    case empty
    case unknown

    /// Remaining-first bands. Plenty left is clear; running out is critical.
    public static func fromRemaining(_ remaining: Double?) -> UsageBand {
        guard let remaining else { return .unknown }
        switch remaining {
        case 50...: return .clear
        case 20..<50: return .warning
        case 0.5..<20: return .critical
        default: return .empty
        }
    }
}

public func clampPercent(_ value: Double) -> Double {
    if value.isNaN || value.isInfinite { return 0 }
    return min(100, max(0, value))
}

/// Providers report utilization on either a 0–100 or a 0–1 scale, and a lone
/// value below 1 is genuinely ambiguous between the two. The scale is decided
/// per payload rather than per value: a payload only counts as fractional when
/// every reading in it is under 1, so a single window sitting at 1% can never
/// be mistaken for an exhausted quota.
public enum PercentScale: Sendable {
    case percent
    case fraction

    public static func detect(_ values: [Double]) -> PercentScale {
        let usable = values.filter { $0.isFinite && $0 > 0 }
        guard !usable.isEmpty, usable.allSatisfy({ $0 < 1 }) else { return .percent }
        return .fraction
    }

    public func normalize(_ raw: Double) -> Double {
        guard raw.isFinite else { return 0 }
        return self == .fraction ? clampPercent(raw * 100) : clampPercent(raw)
    }
}

public func parseISO8601(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let withFrac = ISO8601DateFormatter()
    withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFrac.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
}

public func parseEpoch(_ raw: Any?) -> Date? {
    if let number = raw as? Double {
        return dateFromEpoch(number)
    }
    if let number = raw as? Int {
        return dateFromEpoch(Double(number))
    }
    if let string = raw as? String {
        if let number = Double(string) {
            return dateFromEpoch(number)
        }
        return parseISO8601(string)
    }
    return nil
}

private func dateFromEpoch(_ value: Double) -> Date {
    if value > 1_000_000_000_000 {
        return Date(timeIntervalSince1970: value / 1000)
    }
    return Date(timeIntervalSince1970: value)
}
