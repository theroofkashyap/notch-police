import Foundation

/// Doubles the wait each time a provider throttles us and forgets the
/// escalation once a request succeeds. The previous deadline cannot be used to
/// derive the next wait, because by the time we retry it is already in the
/// past — the interval is tracked separately for that reason.
public struct Backoff: Equatable, Sendable {
    public let minimum: TimeInterval
    public let maximum: TimeInterval
    private var interval: TimeInterval?
    public private(set) var until: Date?

    public init(minimum: TimeInterval = 60, maximum: TimeInterval = 15 * 60) {
        self.minimum = minimum
        self.maximum = max(minimum, maximum)
    }

    public func isBlocked(now: Date = Date()) -> Bool {
        guard let until else { return false }
        return until > now
    }

    /// Records a throttle and returns the deadline. A server hint is honoured
    /// when it asks for more time than we chose; never for less.
    @discardableResult
    public mutating func record(retryAfter: Date? = nil, now: Date = Date()) -> Date {
        let next = min(maximum, interval.map { $0 * 2 } ?? minimum)
        interval = next
        var deadline = now.addingTimeInterval(next)
        if let retryAfter, retryAfter > deadline {
            deadline = retryAfter
        }
        until = deadline
        return deadline
    }

    public mutating func reset() {
        interval = nil
        until = nil
    }
}
