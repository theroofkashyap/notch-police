import Foundation

public final class GrokProvider {
    public static let creditsURL = URL(
        string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
    )!

    public init() {}

    public func fetchSnapshot() async -> ProviderSnapshot {
        let credentials: GrokCredentials
        do {
            credentials = try GrokCredentials.load()
        } catch {
            return unsigned()
        }
        guard !credentials.isExpired else {
            return ProviderSnapshot(
                kind: .grok,
                status: .needsAuth,
                signInHint: "Your Grok CLI session expired. Run `grok login` again."
            )
        }

        do {
            let response = try await PoliceHTTP.get(
                Self.creditsURL,
                headers: [
                    "Authorization": "Bearer \(credentials.accessToken)",
                    "X-XAI-Token-Auth": "xai-grok-cli",
                    "Accept": "application/json",
                    "User-Agent": "NotchPolice/0.1",
                ]
            )
            if response.isRateLimited {
                return ProviderSnapshot(
                    kind: .grok,
                    fetchedAt: Date(),
                    status: .rateLimited(retryAfter: response.retryAfter())
                )
            }
            guard (200..<300).contains(response.status) else {
                if response.status == 401 || response.status == 403 {
                    return unsigned()
                }
                return ProviderSnapshot(
                    kind: .grok,
                    status: .error("Grok usage HTTP \(response.status)")
                )
            }

            let windows = GrokUsage.parse(data: response.data)
            return ProviderSnapshot(
                kind: .grok,
                windows: windows,
                fetchedAt: Date(),
                status: windows.isEmpty
                    ? .error("Grok returned no metered credits for this account")
                    : .ok
            )
        } catch {
            return ProviderSnapshot(kind: .grok, status: .error(error.localizedDescription))
        }
    }

    private func unsigned() -> ProviderSnapshot {
        ProviderSnapshot(
            kind: .grok,
            status: .needsAuth,
            signInHint: ProviderKind.grok.signInHint
        )
    }
}
