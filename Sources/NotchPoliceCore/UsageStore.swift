import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshots: [ProviderSnapshot] = []
    @Published public var preferences: Preferences {
        didSet { preferenceStore.save(preferences) }
    }
    @Published public var hiddenUntil: Date?
    @Published public var hovered: ProviderKind?
    @Published public var expanded: Bool = false
    /// Which project each provider's handover would draw from, published so the
    /// copy button can name it before the user commits to copying.
    @Published public private(set) var contextProjects: [ProviderKind: String] = [:]

    public var paces: [ProviderKind: Pace] = [:]

    private let preferenceStore: PreferenceStore
    private let claude = ClaudeProvider()
    private let cursor = CursorProvider()
    private let chatgpt = ChatGPTProvider()
    private let antigravity = AntigravityProvider()
    private let grok = GrokProvider()
    private var samples: [ProviderKind: [RemainingSample]] = [:]
    private var timer: Timer?
    private var backoff: [ProviderKind: Backoff] = [:]
    private var notified: Set<ProviderKind> = []
    private var excerpts: [ProviderKind: Cached] = [:]

    private struct Cached {
        var excerpt: SessionExcerpt?
        var at: Date
    }
    public var onLowRemaining: ((ProviderSnapshot, Double) -> Void)?

    public init(preferenceStore: PreferenceStore = PreferenceStore()) {
        self.preferenceStore = preferenceStore
        self.preferences = preferenceStore.load()
    }

    public var visibleSnapshots: [ProviderSnapshot] {
        ProviderKind.allCases.compactMap { kind in
            guard preferences.isEnabled(kind) else { return nil }
            return snapshots.first(where: { $0.kind == kind })
                ?? ProviderSnapshot(kind: kind, status: .needsAuth, signInHint: kind.signInHint)
        }
    }

    public var isHidden: Bool {
        if let hiddenUntil { return hiddenUntil > Date() }
        return false
    }

    public func start() {
        Task { await refresh() }
        reschedule()
    }

    public func reschedule() {
        timer?.invalidate()
        let interval = TimeInterval(max(30, preferences.pollSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        if preferences.demo {
            snapshots = Fixtures.demoSnapshots()
            return
        }

        let previous = snapshots
        let now = Date()
        async let claudeSnap = poll(.claude, now: now)
        async let cursorSnap = poll(.cursor, now: now)
        async let chatgptSnap = poll(.chatgpt, now: now)
        async let antigravitySnap = poll(.antigravity, now: now)
        async let grokSnap = poll(.grok, now: now)

        let next = await [
            claudeSnap,
            cursorSnap,
            chatgptSnap,
            antigravitySnap,
            grokSnap,
        ].map { snap in
            record(snap, previous: previous.first { $0.kind == snap.kind })
        }
        snapshots = next
        recordSamples(next)
        notifyIfNeeded(next)
    }

    /// Skips the request entirely while a provider's backoff is in force. The
    /// empty `.stale` result is filled in from the previous reading below.
    private func poll(_ kind: ProviderKind, now: Date) async -> ProviderSnapshot {
        if backoff[kind]?.isBlocked(now: now) == true {
            return ProviderSnapshot(kind: kind, status: .stale)
        }
        switch kind {
        case .claude: return await claude.fetchSnapshot()
        case .cursor: return await cursor.fetchSnapshot()
        case .chatgpt: return await chatgpt.fetchSnapshot()
        case .antigravity: return await antigravity.fetchSnapshot()
        case .grok: return await grok.fetchSnapshot()
        }
    }

    private func record(_ snap: ProviderSnapshot, previous: ProviderSnapshot?) -> ProviderSnapshot {
        switch snap.status {
        case .rateLimited(let retryAfter):
            var current = backoff[snap.kind] ?? Backoff()
            current.record(retryAfter: retryAfter, now: Date())
            backoff[snap.kind] = current
        case .ok:
            backoff[snap.kind]?.reset()
        default:
            break
        }
        return snap.fallingBack(to: previous)
    }

    public func retryAfter(for kind: ProviderKind) -> Date? {
        backoff[kind]?.until
    }

    public func hide(for interval: TimeInterval) {
        hiddenUntil = Date().addingTimeInterval(interval)
    }

    public func reveal() {
        hiddenUntil = nil
    }

    public func pace(for kind: ProviderKind) -> Pace? {
        Forecast.pace(samples: samples[kind] ?? [])
    }

    /// Async because building this reads session transcripts off disk, and the
    /// only caller is a button press that has to stay responsive.
    public func handover(for kind: ProviderKind) async -> String {
        let snap = visibleSnapshots.first(where: { $0.kind == kind })
            ?? ProviderSnapshot(kind: kind, status: .needsAuth, signInHint: kind.signInHint)
        return Handover.make(
            snapshot: snap,
            pace: pace(for: kind),
            excerpt: await excerpt(for: kind)
        )
    }

    /// The prompt-only handover. No transcript text goes into it; the local
    /// session is consulted only for the project name, from the same cache
    /// the hover warms, so this is as instant as the context copy.
    public func summaryPrompt(for kind: ProviderKind) async -> String {
        let snap = visibleSnapshots.first(where: { $0.kind == kind })
            ?? ProviderSnapshot(kind: kind, status: .needsAuth, signInHint: kind.signInHint)
        return Handover.summaryPrompt(
            snapshot: snap,
            pace: pace(for: kind),
            project: await excerpt(for: kind)?.project
        )
    }

    /// Warms the excerpt while the user is still hovering, so the project name
    /// is on the button before it is clicked and the copy itself is instant.
    public func prepareContext(for kind: ProviderKind) {
        guard !isExcerptFresh(kind) else { return }
        Task { _ = await excerpt(for: kind) }
    }

    private func excerpt(for kind: ProviderKind) async -> SessionExcerpt? {
        if isExcerptFresh(kind) { return excerpts[kind]?.excerpt }
        let demo = preferences.demo || snapshots.first { $0.kind == kind }?.status == .demo
        let found = await SessionContext.latest(for: kind, demo: demo)
        excerpts[kind] = Cached(excerpt: found, at: Date())
        contextProjects[kind] = found?.project
        return found
    }

    private func isExcerptFresh(_ kind: ProviderKind) -> Bool {
        guard let cached = excerpts[kind] else { return false }
        return Date().timeIntervalSince(cached.at) < 30
    }

    public var dyingKind: ProviderKind? {
        visibleSnapshots.first(where: { $0.isDying(below: preferences.dyingBelow) })?.kind
    }

    private func recordSamples(_ snaps: [ProviderSnapshot]) {
        let now = Date()
        for snap in snaps {
            guard snap.status == .ok, let remaining = snap.primaryRemaining else { continue }
            var list = samples[snap.kind] ?? []
            list.append(RemainingSample(at: now, remaining: remaining))
            let cutoff = now.addingTimeInterval(-6 * 3600)
            samples[snap.kind] = list.filter { $0.at >= cutoff }
        }
    }

    private func notifyIfNeeded(_ snaps: [ProviderSnapshot]) {
        let threshold = Double(preferences.notifyBelow)
        guard threshold > 0 else { return }
        for snap in snaps {
            guard snap.status == .ok, let remaining = snap.primaryRemaining else { continue }
            if remaining <= threshold {
                if !notified.contains(snap.kind) {
                    notified.insert(snap.kind)
                    onLowRemaining?(snap, remaining)
                }
            } else if remaining > threshold + 5 {
                notified.remove(snap.kind)
            }
        }
    }
}
