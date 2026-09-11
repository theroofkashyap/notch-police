import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshots: [ProviderSnapshot] = []
    @Published public var preferences: Preferences {
        didSet {
            preferenceStore.save(preferences)
            if oldValue.ringWindows != preferences.ringWindows {
                for kind in ProviderKind.allCases
                where oldValue.ringWindows[kind] != preferences.ringWindows[kind] {
                    notified.remove(kind)
                }
            }
            if oldValue.enabled != preferences.enabled {
                Task { await refresh() }
            }
        }
    }
    @Published public var hiddenUntil: Date?
    @Published public var hovered: ProviderKind?
    @Published public var expanded: Bool = false
    /// Which project each provider's handover would draw from, published so the
    /// copy button can name it before the user commits to copying.
    @Published public private(set) var contextProjects: [ProviderKind: String] = [:]

    public var paces: [ProviderKind: Pace] = [:]

    private let preferenceStore: PreferenceStore
    private let sampleStore: SampleStore
    private let claude = ClaudeProvider()
    private let cursor = CursorProvider()
    private let chatgpt = ChatGPTProvider()
    private let antigravity = AntigravityProvider()
    private let grok = GrokProvider()
    /// Remaining history keyed by `provider|window`, so pinning weekly vs
    /// 5-hour cannot mix slopes, and a relaunch still has a pace.
    private var samples: [String: [RemainingSample]] = [:]
    private var timer: Timer?
    private var backoff: [ProviderKind: Backoff] = [:]
    private var notified: Set<ProviderKind> = []
    private var excerpts: [ProviderKind: Cached] = [:]

    private struct Cached {
        var excerpt: SessionExcerpt?
        var at: Date
    }
    public var onLowRemaining: ((ProviderSnapshot, Double) -> Void)?

    public init(
        preferenceStore: PreferenceStore = PreferenceStore(),
        sampleStore: SampleStore = SampleStore()
    ) {
        self.preferenceStore = preferenceStore
        self.sampleStore = sampleStore
        self.preferences = preferenceStore.load()
        self.samples = sampleStore.load()
    }

    public var visibleSnapshots: [ProviderSnapshot] {
        VisibleRings.snapshots(
            from: snapshots,
            enabled: preferences.enabled,
            hideUnsigned: preferences.hideUnsigned,
            ringWindowID: { preferences.ringWindowID(for: $0) },
            demo: preferences.demo
        )
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
        async let claudeSnap = pollIfEnabled(.claude, now: now)
        async let cursorSnap = pollIfEnabled(.cursor, now: now)
        async let chatgptSnap = pollIfEnabled(.chatgpt, now: now)
        async let antigravitySnap = pollIfEnabled(.antigravity, now: now)
        async let grokSnap = pollIfEnabled(.grok, now: now)

        let next = await [
            claudeSnap,
            cursorSnap,
            chatgptSnap,
            antigravitySnap,
            grokSnap,
        ].compactMap { $0 }.map { snap in
            record(snap, previous: previous.first { $0.kind == snap.kind })
        }
        snapshots = next
        if let hovered, !visibleSnapshots.contains(where: { $0.kind == hovered }) {
            self.hovered = nil
            expanded = false
        }
        recordSamples(next)
        notifyIfNeeded(next)
    }

    /// Off in Settings means that local session is not read — not even to
    /// refresh a Claude OAuth token we are not going to display.
    private func pollIfEnabled(_ kind: ProviderKind, now: Date) async -> ProviderSnapshot? {
        guard preferences.isEnabled(kind) else { return nil }
        return await poll(kind, now: now)
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
        Forecast.pace(samples: samples[sampleKey(for: kind)] ?? [])
    }

    public func handoverDestination(leaving kind: ProviderKind) -> ProviderSnapshot? {
        Handover.destination(among: visibleSnapshots, leaving: kind)
    }

    /// Async because building this reads session transcripts off disk, and the
    /// only caller is a button press that has to stay responsive.
    public func handover(for kind: ProviderKind) async -> String {
        let snap = visibleSnapshots.first(where: { $0.kind == kind })
            ?? ProviderSnapshot(kind: kind, status: .needsAuth, signInHint: kind.signInHint)
        return Handover.make(
            snapshot: snap,
            pace: pace(for: kind),
            excerpt: await excerpt(for: kind),
            destination: handoverDestination(leaving: kind)
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
            project: await excerpt(for: kind)?.project,
            destination: handoverDestination(leaving: kind)
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
            let pinned = snap.pinning(preferences.ringWindowID(for: snap.kind))
            guard snap.status == .ok, let remaining = pinned.primaryRemaining,
                  let windowID = pinned.displayed?.id
            else { continue }
            let key = SampleArchive.key(kind: snap.kind, windowID: windowID)
            var list = samples[key] ?? []
            list.append(RemainingSample(at: now, remaining: remaining))
            samples[key] = list
        }
        samples = SampleArchive.prune(samples, now: now)
        sampleStore.save(samples, now: now)
    }

    private func sampleKey(for kind: ProviderKind) -> String {
        let snap = visibleSnapshots.first(where: { $0.kind == kind })
        let windowID = snap?.displayed?.id ?? RingWindowPin.tightest
        return SampleArchive.key(kind: kind, windowID: windowID)
    }

    private func notifyIfNeeded(_ snaps: [ProviderSnapshot]) {
        let threshold = Double(preferences.notifyBelow)
        guard threshold > 0 else { return }
        for snap in snaps {
            let pinned = snap.pinning(preferences.ringWindowID(for: snap.kind))
            guard snap.status == .ok, let remaining = pinned.primaryRemaining else { continue }
            if remaining <= threshold {
                if !notified.contains(snap.kind) {
                    notified.insert(snap.kind)
                    onLowRemaining?(pinned, remaining)
                }
            } else if remaining > threshold + 5 {
                notified.remove(snap.kind)
            }
        }
    }
}
