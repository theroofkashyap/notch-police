import Foundation

public enum PoliceHTTPError: Error {
    case transport(Error)
    case status(Int, Data)
}

public struct PoliceResponse: Sendable {
    public var status: Int
    public var data: Data
    public var headers: [String: String]

    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }

    public var isRateLimited: Bool { status == 429 }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// `Retry-After` arrives either as delay-seconds or as an HTTP date.
    public func retryAfter(now: Date = Date()) -> Date? {
        guard let raw = header("Retry-After")?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        if let seconds = Double(raw) {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw)
    }
}

public enum PoliceHTTP {
    public static func get(
        _ url: URL,
        headers: [String: String],
        timeout: TimeInterval = 15
    ) async throws -> PoliceResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await send(request)
    }

    public static func post(
        _ url: URL,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval = 15
    ) async throws -> PoliceResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> PoliceResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            return PoliceResponse(status: http?.statusCode ?? 0, data: data, headers: headers)
        } catch {
            throw PoliceHTTPError.transport(error)
        }
    }
}

public enum JSONValue {
    public static func object(from data: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw PoliceHTTPError.status(0, data)
        }
        return object
    }

    public static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }
}
