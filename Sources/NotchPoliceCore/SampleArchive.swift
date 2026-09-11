import Foundation

/// Remaining samples only: provider, window, time, percentage. Never tokens.
public enum SampleArchive {
    public static let defaultsKey = "notchpolice.samples.v1"
    public static let retention: TimeInterval = 6 * 3600

    public static func key(kind: ProviderKind, windowID: String) -> String {
        "\(kind.rawValue)|\(windowID)"
    }

    public static func prune(
        _ samples: [String: [RemainingSample]],
        now: Date = Date(),
        retention: TimeInterval = retention
    ) -> [String: [RemainingSample]] {
        let cutoff = now.addingTimeInterval(-retention)
        var next: [String: [RemainingSample]] = [:]
        for (key, list) in samples {
            let kept = list.filter { $0.at >= cutoff }
            if !kept.isEmpty { next[key] = kept }
        }
        return next
    }

    public static func encode(
        _ samples: [String: [RemainingSample]],
        now: Date = Date()
    ) -> Data? {
        let pruned = prune(samples, now: now)
        let stored = Stored(
            series: pruned.mapValues { list in
                list.map { Point(at: $0.at.timeIntervalSince1970, remaining: $0.remaining) }
            }
        )
        return try? JSONEncoder().encode(stored)
    }

    public static func decode(_ data: Data, now: Date = Date()) -> [String: [RemainingSample]] {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return [:] }
        var samples: [String: [RemainingSample]] = [:]
        for (key, points) in stored.series {
            samples[key] = points.map {
                RemainingSample(at: Date(timeIntervalSince1970: $0.at), remaining: $0.remaining)
            }
        }
        return prune(samples, now: now)
    }

    private struct Stored: Codable {
        var series: [String: [Point]]
    }

    private struct Point: Codable {
        var at: Double
        var remaining: Double
    }
}

public final class SampleStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(now: Date = Date()) -> [String: [RemainingSample]] {
        guard let data = defaults.data(forKey: SampleArchive.defaultsKey) else { return [:] }
        return SampleArchive.decode(data, now: now)
    }

    public func save(_ samples: [String: [RemainingSample]], now: Date = Date()) {
        if let data = SampleArchive.encode(samples, now: now) {
            defaults.set(data, forKey: SampleArchive.defaultsKey)
        }
    }
}
