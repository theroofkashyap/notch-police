import Foundation

enum AntigravityBridgeError: Error {
    case notRunning
    case unreachable
    case noQuota
    case rateLimited(Date?)
}

/// Discovers Antigravity's dynamically allocated local language-server port
/// and asks its Connect-RPC API for the same per-model quota shown by the app.
enum AntigravityBridge {
    struct Endpoint: Equatable, Sendable {
        var ports: [Int]
        var csrfToken: String
    }

    private static let service = "/exa.language_server_pb.LanguageServerService/"
    private static let quotaSummary = service + "RetrieveUserQuotaSummary"
    private static let userStatus = service + "GetUserStatus"
    private static let commandModels = service + "GetCommandModelConfigs"
    static let csrfHeader = "X-Codeium-Csrf-Token"

    static func discover(
        processTable: String? = nil,
        listeningPorts: ((Int) -> [Int])? = nil
    ) -> Endpoint? {
        let table = processTable ?? run("/bin/ps", ["-Ao", "pid=,command="])
        for rawLine in table.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let split = line.firstIndex(where: \.isWhitespace),
                  let pid = Int(line[..<split])
            else { continue }

            let command = String(line[split...]).trimmingCharacters(in: .whitespaces)
            let lower = command.lowercased()
            let isServer = lower.contains("language_server") || lower.contains("language-server")
            let hasAntigravityMarker = lower.contains("antigravity")
                || lower.contains("--app_data_dir antigravity")
                || lower.contains("--app_data_dir=antigravity")
            let isCLI = isAntigravityCLI(lower)
            guard (isServer && hasAntigravityMarker) || isCLI else { continue }

            let token = flag("--csrf_token", in: command)
                ?? flag("--csrf-token", in: command)
                ?? ""
            // Desktop/IDE servers require CSRF. The `agy` CLI is the only
            // supported tokenless process and intentionally accepts none.
            guard isCLI || !token.isEmpty else { continue }

            var ports = listeningPorts?(pid) ?? self.listeningPorts(ofPID: pid)
            for name in ["--extension_server_port", "--https_server_port", "--port"] {
                if let raw = flag(name, in: command), let port = Int(raw), port > 0 {
                    ports.append(port)
                }
            }
            ports = Array(Set(ports.filter { (1...65535).contains($0) })).sorted()
            guard !ports.isEmpty else { continue }
            return Endpoint(ports: ports, csrfToken: token)
        }
        return nil
    }

    static func flag(_ name: String, in command: String) -> String? {
        let parts = command.split(whereSeparator: \.isWhitespace)
        for (index, part) in parts.enumerated() {
            if part == Substring(name), index + 1 < parts.count {
                return String(parts[index + 1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            let prefix = name + "="
            if part.hasPrefix(prefix) {
                return String(part.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    static func parsePorts(fromLSOF output: String) -> [Int] {
        var result: [Int] = []
        for line in output.split(whereSeparator: \.isNewline) {
            for field in line.split(whereSeparator: \.isWhitespace).reversed() {
                guard field.contains(":") else { continue }
                let raw = field.split(separator: ":").last.map(String.init) ?? ""
                let digits = raw.prefix(while: \.isNumber)
                if let port = Int(digits), (1...65535).contains(port) {
                    result.append(port)
                    break
                }
            }
        }
        return Array(Set(result)).sorted()
    }

    static func listeningPorts(ofPID pid: Int) -> [Int] {
        parsePorts(
            fromLSOF: run(
                "/usr/sbin/lsof",
                ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"]
            )
        )
    }

    static func fetch(
        from endpoint: Endpoint,
        session: URLSession
    ) async throws -> AntigravityUsage.Parsed {
        var reachedServer = false
        var lastError: Error?

        for port in endpoint.ports {
            for scheme in ["https", "http"] {
                for path in [quotaSummary, userStatus, commandModels] {
                    do {
                        let response = try await request(
                            scheme: scheme,
                            port: port,
                            path: path,
                            token: endpoint.csrfToken,
                            session: session
                        )
                        reachedServer = true
                        if response.status == 429 {
                            throw AntigravityBridgeError.rateLimited(response.retryAfter())
                        }
                        guard response.status == 200 else { continue }

                        let parsed: AntigravityUsage.Parsed?
                        switch path {
                        case quotaSummary:
                            parsed = AntigravityUsage.parseQuotaSummary(response.data)
                        case userStatus:
                            parsed = AntigravityUsage.parseUserStatus(response.data)
                        default:
                            parsed = AntigravityUsage.parseCommandModels(response.data)
                        }
                        if let parsed, !parsed.windows.isEmpty { return parsed }
                    } catch let error as AntigravityBridgeError {
                        if case .rateLimited = error { throw error }
                        lastError = error
                    } catch {
                        lastError = error
                    }
                }
            }
        }
        if reachedServer { throw AntigravityBridgeError.noQuota }
        if lastError != nil { throw AntigravityBridgeError.unreachable }
        throw AntigravityBridgeError.notRunning
    }

    private static func request(
        scheme: String,
        port: Int,
        path: String,
        token: String,
        session: URLSession
    ) async throws -> PoliceResponse {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)") else {
            throw AntigravityBridgeError.unreachable
        }
        let bodyObject: [String: Any] = path == quotaSummary
            ? ["forceRefresh": true]
            : [
                "metadata": [
                    "ideName": "antigravity",
                    "extensionName": "antigravity",
                    "ideVersion": "unknown",
                    "locale": "en",
                ],
            ]
        let body = try JSONSerialization.data(withJSONObject: bodyObject)
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: csrfHeader)
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String {
                headers[key] = String(describing: value)
            }
        }
        return PoliceResponse(status: http?.statusCode ?? 0, data: data, headers: headers)
    }

    private static func isAntigravityCLI(_ command: String) -> Bool {
        let executable = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return name == "agy"
            || name == "antigravity-cli"
            || name == "antigravity_cli"
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
