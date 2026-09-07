import Foundation

public final class CursorProvider {
    private var memoryAccess: String?

    public init() {}

    public func fetchSnapshot() async -> ProviderSnapshot {
        do {
            var response = try await usage(token: try await accessToken())
            if response.status == 401 {
                memoryAccess = nil
                response = try await usage(token: try await accessToken(forceRefresh: true))
            }
            if response.isRateLimited {
                return ProviderSnapshot(
                    kind: .cursor,
                    fetchedAt: Date(),
                    status: .rateLimited(retryAfter: response.retryAfter())
                )
            }
            return decode(response)
        } catch {
            return ProviderSnapshot(
                kind: .cursor,
                status: .needsAuth,
                signInHint: ProviderKind.cursor.signInHint
            )
        }
    }

    private func usage(token: String) async throws -> PoliceResponse {
        try await PoliceHTTP.post(
            CursorUsage.periodURL,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
                "User-Agent": "NotchPolice/0.1",
            ],
            body: Data("{}".utf8)
        )
    }

    private func decode(_ response: PoliceResponse) -> ProviderSnapshot {
        guard response.status == 200, let object = try? JSONValue.object(from: response.data) else {
            return ProviderSnapshot(
                kind: .cursor,
                status: response.status == 401 ? .needsAuth : .error("Cursor usage HTTP \(response.status)")
            )
        }
        let membership = try? readState("cursorAuth/stripeMembershipType")
        let parsed = CursorUsage.parse(object: object, membership: membership)
        return ProviderSnapshot(
            kind: .cursor,
            plan: parsed.plan,
            windows: parsed.windows,
            fetchedAt: Date(),
            status: parsed.windows.isEmpty ? .error("Cursor returned no quota windows") : .ok
        )
    }

    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let memoryAccess, !JWT.isExpired(memoryAccess) {
            return memoryAccess
        }
        let access = try readState("cursorAuth/accessToken")
        if !forceRefresh, !JWT.isExpired(access) {
            memoryAccess = access
            return access
        }
        if let refreshed = try? await refresh(using: readState("cursorAuth/refreshToken")) {
            memoryAccess = refreshed
            return refreshed
        }
        memoryAccess = access
        return access
    }

    private func refresh(using refreshToken: String) async throws -> String {
        let body = try JSONValue.encode([
            "grant_type": "refresh_token",
            "client_id": CursorUsage.clientID,
            "refresh_token": refreshToken,
        ])
        let response = try await PoliceHTTP.post(
            CursorUsage.tokenURL,
            headers: ["Content-Type": "application/json"],
            body: body
        )
        guard response.status == 200 else {
            throw PoliceHTTPError.status(response.status, response.data)
        }
        let object = try JSONValue.object(from: response.data)
        if object["shouldLogout"] as? Bool == true {
            throw KeychainError.notFound
        }
        guard let access = object["access_token"] as? String, !access.isEmpty else {
            throw PoliceHTTPError.status(response.status, response.data)
        }
        return access
    }

    private func readState(_ key: String) throws -> String {
        let path = Self.stateDBPath()
        guard FileManager.default.fileExists(atPath: path) else {
            throw KeychainError.notFound
        }
        guard let value = try SQLiteRead.string(
            path: path,
            sql: "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;",
            parameters: [key]
        ), !value.isEmpty else {
            throw KeychainError.notFound
        }
        return value
    }

    public static func stateDBPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }
}
