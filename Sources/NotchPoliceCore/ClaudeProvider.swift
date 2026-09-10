import Foundation

/// A stored Claude session the server no longer honours. Distinct from a
/// transport or HTTP error so the UI can route it to "sign in again".
public enum ClaudeAuthError: Error, Equatable {
    case sessionRevoked

    /// Statuses from the OAuth token endpoint that mean the refresh token is no
    /// good: 400 carries `invalid_grant`, and 401/403 are the unauthorized
    /// family. A 5xx or 429 is *not* here — those are transient and keep the
    /// last reading instead of prompting a needless re-login.
    public static func isSessionRevoked(_ status: Int) -> Bool {
        status == 400 || status == 401 || status == 403
    }
}

public final class ClaudeProvider {
    private var memoryToken: String?
    private var memoryExpiry: Date?

    public init() {}

    public func fetchSnapshot() async -> ProviderSnapshot {
        do {
            let creds = try loadCredentials()
            let token = try await validAccessToken(creds)
            var response = try await PoliceHTTP.get(ClaudeUsage.usageURL, headers: claudeHeaders(token: token))
            if response.status == 401 {
                let refreshed = try await refresh(using: creds)
                response = try await PoliceHTTP.get(ClaudeUsage.usageURL, headers: claudeHeaders(token: refreshed))
            }
            if response.isRateLimited {
                return ProviderSnapshot(
                    kind: .claude,
                    plan: creds.plan,
                    fetchedAt: Date(),
                    status: .rateLimited(retryAfter: response.retryAfter())
                )
            }
            return snapshot(response, plan: creds.plan)
        } catch KeychainError.accessDenied {
            return ProviderSnapshot(
                kind: .claude,
                status: .accessDenied,
                signInHint: "macOS blocked the Claude login in Keychain. Unlock your login keychain, or right-click the notch → Ask Keychain again."
            )
        } catch KeychainError.notFound {
            return unsigned()
        } catch ClaudeAuthError.sessionRevoked {
            return expired()
        } catch {
            return ProviderSnapshot(kind: .claude, status: .error(error.localizedDescription))
        }
    }

    private func unsigned() -> ProviderSnapshot {
        ProviderSnapshot(
            kind: .claude,
            status: .needsAuth,
            signInHint: ProviderKind.claude.signInHint
        )
    }

    /// A stored session that the server has revoked reads the same to the user
    /// as never having signed in — the ring is `needsAuth`, not an error — but
    /// the hint tells them the login they *did* have has lapsed so they know to
    /// sign in again rather than assume the app is broken.
    private func expired() -> ProviderSnapshot {
        ProviderSnapshot(
            kind: .claude,
            status: .needsAuth,
            signInHint: "Your Claude session has expired or been signed out. Run `claude` to sign in again."
        )
    }

    private func snapshot(_ response: PoliceResponse, plan: String?) -> ProviderSnapshot {
        guard response.status == 200, let object = try? JSONValue.object(from: response.data) else {
            return ProviderSnapshot(
                kind: .claude,
                plan: plan,
                status: response.status == 401 ? .needsAuth : .error("Claude usage HTTP \(response.status)")
            )
        }
        let parsed = ClaudeUsage.parse(object: object, plan: plan)
        return ProviderSnapshot(
            kind: .claude,
            plan: parsed.plan,
            windows: parsed.windows,
            fetchedAt: Date(),
            status: parsed.windows.isEmpty ? .error("Claude returned no quota windows") : .ok
        )
    }

    private enum Source {
        case file(URL)
        case keychain(account: String?)
    }

    private struct Creds {
        var root: [String: Any]
        var access: String
        var refresh: String
        var expiresAt: Date?
        var plan: String?
        var source: Source
    }

    private func loadCredentials() throws -> Creds {
        if let file = credentialsFile(),
           let data = try? Data(contentsOf: file),
           let root = ClaudeUsage.credentialsObject(from: data),
           let creds = creds(from: root, source: .file(file))
        {
            return creds
        }
        let record = try Keychain.readGenericPassword(service: ClaudeUsage.keychainService)
        guard let root = ClaudeUsage.credentialsObject(from: record.data),
              let creds = creds(from: root, source: .keychain(account: record.account))
        else {
            throw KeychainError.notFound
        }
        return creds
    }

    private func creds(from root: [String: Any], source: Source) -> Creds? {
        guard let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String, !access.isEmpty,
              let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty
        else { return nil }
        let expiresMs = (oauth["expiresAt"] as? Int) ?? (oauth["expiresAt"] as? Double).map(Int.init)
        let expires = expiresMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        let plan = ClaudeUsage.prettyPlan(
            (oauth["rateLimitTier"] as? String) ?? (oauth["subscriptionType"] as? String)
        )
        return Creds(
            root: root,
            access: access,
            refresh: refresh,
            expiresAt: expires,
            plan: plan,
            source: source
        )
    }

    private func validAccessToken(_ creds: Creds) async throws -> String {
        if let memoryToken, let memoryExpiry, memoryExpiry > Date().addingTimeInterval(60) {
            return memoryToken
        }
        if let expiresAt = creds.expiresAt, expiresAt > Date().addingTimeInterval(60) {
            return creds.access
        }
        return try await refresh(using: creds)
    }

    private func refresh(using creds: Creds) async throws -> String {
        var payload: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refresh,
            "client_id": ClaudeUsage.clientID,
        ]
        if let oauth = creds.root["claudeAiOauth"] as? [String: Any],
           let list = oauth["scopes"] as? [String], !list.isEmpty
        {
            payload["scope"] = list.joined(separator: " ")
        }
        let body = try JSONValue.encode(payload)
        let headers = [
            "Content-Type": "application/json",
            "User-Agent": "claude-cli/2.1.201 (external, cli)",
        ]
        var response = try await PoliceHTTP.post(ClaudeUsage.tokenURL, headers: headers, body: body)
        if response.status == 404 || response.status == 405 {
            response = try await PoliceHTTP.post(ClaudeUsage.legacyTokenURL, headers: headers, body: body)
        }
        // A refresh token the server rejects (revoked, rotated away, or a fresh
        // login elsewhere) is a re-auth signal, not a transient failure. The
        // token endpoint answers `invalid_grant` with 400; treat the whole
        // unauthorized family that way so the ring says "sign in" not "!".
        if ClaudeAuthError.isSessionRevoked(response.status) {
            throw ClaudeAuthError.sessionRevoked
        }
        guard response.status == 200 else {
            throw PoliceHTTPError.status(response.status, response.data)
        }
        let object = try JSONValue.object(from: response.data)
        guard let access = object["access_token"] as? String, !access.isEmpty else {
            throw PoliceHTTPError.status(response.status, response.data)
        }
        let expiresIn = (object["expires_in"] as? Int) ?? 28_800
        persist(
            accessToken: access,
            refreshToken: object["refresh_token"] as? String,
            expiresIn: expiresIn,
            scope: object["scope"] as? String,
            startedFrom: creds
        )
        memoryToken = access
        memoryExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        return access
    }

    /// Claude Code may refresh these same credentials while we are mid-flight,
    /// and a refresh rotates the refresh token. The token we started from is
    /// the guard: if what is stored no longer matches it, another client has
    /// already rotated and writing our merge would replace a newer token with
    /// an older one, locking both apps out. In that case the write is dropped —
    /// the access token we just received is still good for this session, and
    /// the next poll picks up whatever the other client wrote.
    private func persist(
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int,
        scope: String?,
        startedFrom creds: Creds
    ) {
        func merged(onto current: [String: Any]) -> Data? {
            guard ClaudeUsage.refreshToken(in: current) == creds.refresh else { return nil }
            let root = ClaudeUsage.mergeRefreshedOAuth(
                existing: current,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: expiresIn,
                scope: scope
            )
            return try? JSONSerialization.data(withJSONObject: root, options: [])
        }

        // Whole-document merge when the blob is valid JSON. If `mcpOAuth` was
        // truncated, splice only the OAuth object so the leftover tail stays.
        func persistData(from raw: Data) -> Data? {
            if let current = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
                return merged(onto: current)
            }
            guard let current = ClaudeUsage.credentialsObject(from: raw),
                  ClaudeUsage.refreshToken(in: current) == creds.refresh
            else { return nil }
            let root = ClaudeUsage.mergeRefreshedOAuth(
                existing: current,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: expiresIn,
                scope: scope
            )
            guard let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
            return ClaudeUsage.replacingOAuthObject(in: raw, with: oauth)
        }

        switch creds.source {
        case .file(let url):
            guard let data = try? Data(contentsOf: url),
                  let out = persistData(from: data)
            else { return }
            try? out.write(to: url, options: [.atomic])
        case .keychain(let account):
            guard let record = try? Keychain.readGenericPassword(service: ClaudeUsage.keychainService),
                  let out = persistData(from: record.data)
            else { return }
            try? Keychain.updateGenericPassword(
                service: ClaudeUsage.keychainService,
                account: account ?? record.account,
                data: out
            )
        }
    }

    private func credentialsFile() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".claude/.credentials.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func claudeHeaders(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "User-Agent": "claude-cli/2.1.201 (external, cli)",
            "x-app": "cli",
            "Accept": "application/json",
        ]
    }
}
