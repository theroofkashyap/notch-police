import Foundation

public final class AntigravityProvider {
    private let trust = LocalhostTrust()
    private lazy var session = URLSession(
        configuration: .ephemeral,
        delegate: trust,
        delegateQueue: nil
    )
    private var cachedEndpoint: AntigravityBridge.Endpoint?

    public init() {}

    public func fetchSnapshot() async -> ProviderSnapshot {
        do {
            let parsed = try await quota()
            return ProviderSnapshot(
                kind: .antigravity,
                plan: parsed.plan,
                windows: parsed.windows,
                fetchedAt: Date(),
                status: parsed.windows.isEmpty
                    ? .error("Antigravity returned no quota windows")
                    : .ok
            )
        } catch AntigravityBridgeError.notRunning {
            return unsigned()
        } catch AntigravityBridgeError.rateLimited(let retryAfter) {
            return ProviderSnapshot(
                kind: .antigravity,
                fetchedAt: Date(),
                status: .rateLimited(retryAfter: retryAfter)
            )
        } catch AntigravityBridgeError.noQuota {
            return ProviderSnapshot(
                kind: .antigravity,
                status: .error("Antigravity is running, but its local server returned no quota windows.")
            )
        } catch {
            return ProviderSnapshot(
                kind: .antigravity,
                status: .error("Could not reach Antigravity’s local usage server.")
            )
        }
    }

    private func quota() async throws -> AntigravityUsage.Parsed {
        if let cachedEndpoint {
            do {
                return try await AntigravityBridge.fetch(from: cachedEndpoint, session: session)
            } catch AntigravityBridgeError.rateLimited(let retryAfter) {
                // Keep the endpoint cached across a throttle; it is still the
                // right server and rediscovery would only spawn ps/lsof.
                throw AntigravityBridgeError.rateLimited(retryAfter)
            } catch {
                // Its ports change whenever Antigravity restarts.
                self.cachedEndpoint = nil
            }
        }

        guard let endpoint = await Task.detached(priority: .utility, operation: {
            AntigravityBridge.discover()
        }).value else {
            throw AntigravityBridgeError.notRunning
        }
        cachedEndpoint = endpoint
        return try await AntigravityBridge.fetch(from: endpoint, session: session)
    }

    private func unsigned() -> ProviderSnapshot {
        ProviderSnapshot(
            kind: .antigravity,
            status: .needsAuth,
            signInHint: ProviderKind.antigravity.signInHint
        )
    }
}
