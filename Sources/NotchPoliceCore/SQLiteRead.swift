import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only handle onto a database another app owns. Cursor writes to its
/// state store while we read, so queries get a busy timeout rather than
/// failing the first time they collide, and values are bound rather than
/// interpolated into SQL.
public final class SQLiteConnection {
    private let handle: OpaquePointer

    public init(path: String, busyTimeoutMilliseconds: Int32 = 2_000) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw NSError(domain: "NotchPolice.SQLite", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not open \(path)",
            ])
        }
        sqlite3_busy_timeout(db, busyTimeoutMilliseconds)
        handle = db
    }

    deinit {
        sqlite3_close(handle)
    }

    public func string(_ sql: String, _ parameters: [String] = []) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in parameters.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), value, -1, sqliteTransient) == SQLITE_OK else {
                return nil
            }
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: cString)
    }
}

public enum SQLiteRead {
    public static func string(path: String, sql: String, parameters: [String] = []) throws -> String? {
        try SQLiteConnection(path: path).string(sql, parameters)
    }
}

public enum JWT {
    public static func expiry(jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let exp = object["exp"] as? Double {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = object["exp"] as? Int {
            return Date(timeIntervalSince1970: Double(exp))
        }
        return nil
    }

    public static func isExpired(_ jwt: String, now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        guard let expiry = expiry(jwt: jwt) else { return false }
        return expiry.addingTimeInterval(-skew) <= now
    }
}
