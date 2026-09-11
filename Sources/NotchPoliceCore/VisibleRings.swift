import Foundation

/// Which rings belong on the notch, and which local sessions we are
/// allowed to read. Off in Settings means that provider is not polled —
/// not even to keep a stale percentage around.
public enum VisibleRings {
    /// Enabled providers, in display order.
    public static func kindsToPoll(enabled: [ProviderKind: Bool]) -> [ProviderKind] {
        ProviderKind.allCases.filter { enabled[$0] ?? true }
    }

    /// Enabled providers, minus unsigned ones when that setting is on.
    /// If every enabled agent still needs a session, the unsigned rings stay
    /// so the notch is never an empty pill.
    public static func snapshots(
        from snapshots: [ProviderSnapshot],
        enabled: [ProviderKind: Bool],
        hideUnsigned: Bool,
        ringWindowID: (ProviderKind) -> String?,
        demo: Bool
    ) -> [ProviderSnapshot] {
        let enabledSnaps: [ProviderSnapshot] = ProviderKind.allCases.compactMap { kind in
            guard enabled[kind] ?? true else { return nil }
            let snap = snapshots.first(where: { $0.kind == kind })
                ?? ProviderSnapshot(kind: kind, status: .needsAuth, signInHint: kind.signInHint)
            return snap.pinning(ringWindowID(kind))
        }
        if demo || !hideUnsigned { return enabledSnaps }
        let signedIn = enabledSnaps.filter { !$0.needsSession }
        return signedIn.isEmpty ? enabledSnaps : signedIn
    }
}

public extension ProviderSnapshot {
    /// No local session (or Antigravity is not running). Distinct from a
    /// Keychain denial or a transport error, which still belong on the notch.
    var needsSession: Bool {
        if case .needsAuth = status { return true }
        return false
    }
}
