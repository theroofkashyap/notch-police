import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case notFound
    case accessDenied
    case unexpectedStatus(OSStatus)
}

public struct KeychainRecord: Equatable {
    public var service: String
    public var account: String?
    public var data: Data
}

public enum Keychain {
    public static func readGenericPassword(service: String, account: String? = nil) throws -> KeychainRecord {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account, !account.isEmpty {
            query[kSecAttrAccount as String] = account
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeychainError.accessDenied
        default:
            throw KeychainError.unexpectedStatus(status)
        }

        guard let dict = item as? [String: Any],
              let data = dict[kSecValueData as String] as? Data
        else {
            throw KeychainError.notFound
        }
        let foundAccount = dict[kSecAttrAccount as String] as? String
        return KeychainRecord(service: service, account: foundAccount, data: data)
    }

    /// Overwrite an existing item in place. Claude OAuth refresh *rotates*
    /// the refresh token, so failing to persist bricks the owning app's login.
    public static func updateGenericPassword(service: String, account: String?, data: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account, !account.isEmpty {
            query[kSecAttrAccount as String] = account
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccount as String] = account ?? NSUserName()
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw KeychainError.accessDenied
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
