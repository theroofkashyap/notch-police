import Foundation

public struct RemainingSample: Equatable, Sendable {
    public var at: Date
    public var remaining: Double

    public init(at: Date, remaining: Double) {
        self.at = at
        self.remaining = remaining
    }
}

public struct Pace: Equatable, Sendable {
    public var minutesToEmpty: Int
    public var copy: String

    public init(minutesToEmpty: Int, copy: String) {
        self.minutesToEmpty = minutesToEmpty
        self.copy = copy
    }
}

public enum Forecast {
    /// Linear remaining-drop over the sample window. Needs a real decline
    /// spanning at least two minutes so a single poll blip is not a prophecy.
    public static func pace(
        samples: [RemainingSample],
        now: Date = Date(),
        minimumSpan: TimeInterval = 120
    ) -> Pace? {
        let usable = sinceLastReset(samples.sorted { $0.at < $1.at })
        guard usable.count >= 2 else { return nil }
        guard let first = usable.first, let last = usable.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return nil }

        let dropped = first.remaining - last.remaining
        guard dropped >= 1 else { return nil }

        guard let perSecond = declinePerSecond(usable), perSecond > 0 else { return nil }

        let remaining = last.remaining
        guard remaining > 0.5 else {
            return Pace(minutesToEmpty: 0, copy: "Empty now")
        }

        let secondsLeft = remaining / perSecond
        let minutes = max(1, Int((secondsLeft / 60).rounded()))
        let copy: String
        if minutes < 60 {
            copy = "Empty in \(minutes) min"
        } else if minutes < 48 * 60 {
            let hours = max(1, Int((Double(minutes) / 60).rounded()))
            copy = "Empty in \(hours) hr"
        } else {
            copy = "Slow burn"
        }
        return Pace(minutesToEmpty: minutes, copy: copy)
    }

    /// A quota reset sends remaining back up. Samples from before the jump
    /// describe a window that no longer exists, so the fit starts after it.
    static func sinceLastReset(_ samples: [RemainingSample]) -> [RemainingSample] {
        var start = samples.startIndex
        for index in samples.indices.dropFirst() where samples[index].remaining > samples[index - 1].remaining + 1 {
            start = index
        }
        return Array(samples[start...])
    }

    /// Least squares across every retained sample, so one noisy poll cannot
    /// set the pace on its own. Positive means remaining is falling.
    static func declinePerSecond(_ samples: [RemainingSample]) -> Double? {
        guard let base = samples.first?.at.timeIntervalSince1970 else { return nil }
        let xs = samples.map { $0.at.timeIntervalSince1970 - base }
        let ys = samples.map(\.remaining)
        let count = Double(samples.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            variance += (x - meanX) * (x - meanX)
        }
        guard variance > 0 else { return nil }
        return -(covariance / variance)
    }
}
