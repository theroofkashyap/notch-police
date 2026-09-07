import Foundation

public final class ChatGPTProvider {
    public init() {}

    public func fetchSnapshot() async -> ProviderSnapshot {
        do {
            let auth = try loadAuth()
            var headers = [
                "Authorization": "Bearer \(auth.token)",
                "Accept": "application/json",
                "Origin": "https://chatgpt.com",
                "Referer": "https://chatgpt.com/",
                "User-Agent": "NotchPolice/0.1",
            ]
            if let account = auth.accountID, !account.isEmpty {
                headers["ChatGPT-Account-Id"] = account
            }
            let response = try await PoliceHTTP.get(ChatGPTUsage.usageURL, headers: headers)
            if response.isRateLimited {
                return ProviderSnapshot(
                    kind: .chatgpt,
                    plan: auth.plan,
                    fetchedAt: Date(),
                    status: .rateLimited(retryAfter: response.retryAfter())
                )
            }
            guard response.status == 200, let object = try? JSONValue.object(from: response.data) else {
                return ProviderSnapshot(
                    kind: .chatgpt,
                    status: response.status == 401 ? .needsAuth : .error("ChatGPT usage HTTP \(response.status)"),
                    signInHint: ProviderKind.chatgpt.signInHint
                )
            }
            let parsed = ChatGPTUsage.parse(object: object)
            return ProviderSnapshot(
                kind: .chatgpt,
                plan: parsed.plan ?? auth.plan,
                windows: parsed.windows,
                fetchedAt: Date(),
                status: parsed.windows.isEmpty ? .error("ChatGPT returned no quota windows") : .ok
            )
        } catch {
            return ProviderSnapshot(
                kind: .chatgpt,
                status: .needsAuth,
                signInHint: ProviderKind.chatgpt.signInHint
            )
        }
    }

    private struct Auth {
        var token: String
        var accountID: String?
        var plan: String?
    }

    private func loadAuth() throws -> Auth {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KeychainError.notFound
        }
        let data = try Data(contentsOf: url)
        let object = try JSONValue.object(from: data)
        let tokens = object["tokens"] as? [String: Any]
        let token = (tokens?["access_token"] as? String)
            ?? (object["access_token"] as? String)
            ?? (object["accessToken"] as? String)
        guard let token, !token.isEmpty else { throw KeychainError.notFound }
        let account = (tokens?["account_id"] as? String)
            ?? (object["account_id"] as? String)
            ?? (object["accountId"] as? String)
        let plan = (object["plan_type"] as? String) ?? (object["planType"] as? String)
        return Auth(token: token, accountID: account, plan: plan)
    }
}
