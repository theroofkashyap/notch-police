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

/// Generic-password access through `/usr/bin/security` instead of the
/// Security framework.
///
/// The item this exists for, Claude Code's `Claude Code-credentials`, was
/// created by that tool, so its access list and partition list name
/// `/usr/bin/security` and nothing else. Calling `SecItemCopyMatching` from
/// this app makes securityd judge *our* signature instead. An ad-hoc build
/// has no team ID, so the partition is keyed on the build's cdhash and the
/// two-step "Always Allow" plus keychain-password dialog comes back after
/// every rebuild. Going through the tool the item already trusts asks
/// nothing, for any build. It is also how Claude Code reads the item.
///
/// This widens nothing: any process running as the same user can run the
/// same command, so the secret's real boundary is the unlocked login
/// session, not which app is asking.
public enum Keychain {
    private static let tool = URL(fileURLWithPath: "/usr/bin/security")

    /// `keychain` is a path so tests can use a scratch keychain. `nil` means
    /// the default search list, where Claude Code's item lives.
    public static func readGenericPassword(
        service: String,
        account: String? = nil,
        keychain: String? = nil
    ) throws -> KeychainRecord {
        var lookup = ["find-generic-password", "-s", service]
        if let account, !account.isEmpty {
            lookup += ["-a", account]
        }
        if let keychain {
            lookup.append(keychain)
        }

        // Attributes first: that output carries no secret and gives the
        // account the write-back needs. Then the data alone with `-w`.
        let attributes = try run(lookup).text
        let foundAccount = attributes
            .split(separator: "\n")
            .first { $0.contains("\"acct\"") }
            .flatMap(quotedValue)

        var secret = lookup
        secret.insert("-w", at: 1)
        var data = try run(secret).data
        // `-w` appends a newline. It also prints non-printable data as hex;
        // Claude Code's item is JSON text, so it comes back verbatim.
        if data.last == 0x0A {
            data.removeLast()
        }
        return KeychainRecord(service: service, account: foundAccount, data: data)
    }

    /// Overwrite an existing item in place. Claude OAuth refresh *rotates*
    /// the refresh token, so failing to persist bricks the owning app's login.
    /// `-U` updates the matching item, or creates it when there is none, which
    /// is what SecItemUpdate-then-SecItemAdd did before. The result is read
    /// back and compared, so a silent failure cannot pass as success.
    public static func updateGenericPassword(
        service: String,
        account: String?,
        data: Data,
        keychain: String? = nil
    ) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }
        let name = account.flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()

        var argv = ["add-generic-password", "-U", "-a", name, "-s", service, "-w", text]
        if let keychain {
            argv.append(keychain)
        }

        // `security -i` caps a line at 4096 bytes. Claude's item is one JSON
        // object that also holds mcpOAuth; quoting it for stdin blows past
        // that cap and the tool silently stores a truncated, illegal blob.
        // Argv has no such cap. Prefer stdin so the secret stays out of `ps`
        // when it fits; otherwise the same-user boundary already accepted
        // above is argv.
        var line = "add-generic-password -U -a \(quote(name)) -s \(quote(service)) -w \(quote(text))"
        if let keychain {
            line += " \(quote(keychain))"
        }
        if text.contains("\n") || text.contains("\r") || line.count > 3000 {
            _ = try run(argv)
        } else {
            _ = try run(["-i"], stdin: line + "\n")
        }

        let stored = try readGenericPassword(service: service, account: name, keychain: keychain)
        guard stored.data == data else {
            throw KeychainError.unexpectedStatus(errSecIO)
        }
    }

    // MARK: - Helpers

    private struct Output {
        var data: Data
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    private static func run(_ arguments: [String], stdin input: String? = nil) throws -> Output {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        if let input {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            // One command line, far below the pipe buffer, and `security`
            // drains stdin as it goes, so a synchronous write cannot block.
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw error(exit: process.terminationStatus)
        }
        return Output(data: data)
    }

    /// `security` exits with the low byte of the OSStatus it stopped on, so
    /// errSecItemNotFound (-25300) is 44 and errSecUserCanceled (-128) is 128.
    private static func error(exit status: Int32) -> KeychainError {
        switch status {
        case 44:
            return .notFound
        case 128, 51, 36:
            // errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed
            return .accessDenied
        default:
            return .unexpectedStatus(status)
        }
    }

    /// Interactive-mode quoting: double quotes with backslash escapes. The
    /// scratch-keychain test round-trips both characters.
    private static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                out += "\\\\"
            case "\"":
                out += "\\\""
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// `    "acct"<blob>="dhruv"` -> `dhruv`; `<NULL>` -> nil.
    private static func quotedValue(_ line: Substring) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let raw = line[line.index(after: eq)...]
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return nil }
        return String(raw.dropFirst().dropLast())
    }
}
