import Foundation

/// Read-only view of the session written by `grok login`.
struct GrokCredentials {
    static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    static let trustedIssuer = "https://auth.x.ai"

    var accessToken: String
    var expiresAt: Date?
    var email: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(60)
    }

    static func load(from url: URL = authURL) throws -> GrokCredentials {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = pick(from: root),
              let token = entry["key"] as? String,
              !token.isEmpty
        else { throw KeychainError.notFound }

        return GrokCredentials(
            accessToken: token,
            expiresAt: date(entry["expires_at"]) ?? JWT.expiry(jwt: token),
            email: entry["email"] as? String
        )
    }

    /// Grok may also store customer-IdP entries in this file. Those tokens are
    /// for a private proxy and must never be sent to xAI's public CLI endpoint.
    static func pick(from root: [String: Any], now: Date = Date()) -> [String: Any]? {
        let trusted = root.compactMap { key, raw -> [String: Any]? in
            guard let entry = raw as? [String: Any],
                  key.hasPrefix(trustedIssuer)
                    || (entry["oidc_issuer"] as? String) == trustedIssuer
            else { return nil }
            return entry
        }
        return trusted.first { entry in
            guard let expires = date(entry["expires_at"]) else { return true }
            return expires > now.addingTimeInterval(60)
        } ?? trusted.first
    }

    static func date(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        return parseISO8601(value)
    }
}
