import Foundation

public struct SessionTurn: Equatable, Sendable {
    public var role: String
    public var text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

public struct SessionExcerpt: Equatable, Sendable {
    public var title: String?
    public var source: String
    /// The project the transcript belongs to, named so a wrong guess is
    /// visible to the user instead of silently pasted into another agent.
    public var project: String?
    public var turns: [SessionTurn]

    public init(title: String? = nil, source: String, project: String? = nil, turns: [SessionTurn]) {
        self.title = title
        self.source = source
        self.project = project
        self.turns = turns
    }
}

/// A transcript directory named after the working directory that produced it.
/// Claude writes `-Users-me-code-thing`, Cursor writes `Users-me-code-thing`,
/// so both are reduced to one comparable key.
public struct ProjectKey: Hashable, Sendable {
    public let directoryName: String
    public let normalized: String

    public init(directoryName: String) {
        self.directoryName = directoryName
        var slug = directoryName.lowercased()
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        let cleaned = slug.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        self.normalized = String(cleaned)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    /// Drops the `users-<name>` prefix so the label reads like a project.
    public var displayName: String {
        let parts = normalized.split(separator: "-").map(String.init)
        if parts.count > 2, parts[0] == "users" {
            return parts.dropFirst(2).joined(separator: "-")
        }
        return normalized
    }
}

public enum SessionContext {
    public static let maxTurns = 12
    public static let maxCharacters = 12_000
    /// Transcripts reach tens of megabytes and only the end is ever used.
    public static let maxReadBytes = 512 * 1024
    /// How many recently touched project folders are worth walking. A folder's
    /// timestamp moves when a session file is created, not when an existing one
    /// is appended to, so this is really "the most recently started sessions" —
    /// generous enough that a long-running session is still in the list.
    public static let projectSearchLimit = 12

    public static func latest(for kind: ProviderKind, demo: Bool = false) async -> SessionExcerpt? {
        if demo { return demoExcerpt(for: kind) }
        return await Task.detached(priority: .userInitiated) {
            let candidates = transcripts()
            if let excerpt = excerpt(for: kind, from: candidates, preferring: activeProject(in: candidates)) {
                return excerpt
            }
            return kind == .cursor ? composerExcerpt() : nil
        }.value
    }

    // MARK: - Selection

    struct Transcript: Sendable {
        var url: URL
        var modified: Date
        var project: ProjectKey?
        var kind: ProviderKind
    }

    /// The newest transcript on the machine is the best available signal for
    /// what the user is actually working on, and it is not necessarily from
    /// the provider being handed over.
    static func activeProject(in transcripts: [Transcript]) -> ProjectKey? {
        transcripts.max { $0.modified < $1.modified }?.project
    }

    /// Prefers the active project so a handover cannot paste an unrelated
    /// repository's conversation, and falls back to the provider's own newest
    /// transcript when it has nothing for that project.
    static func rank(_ transcripts: [Transcript], for kind: ProviderKind, preferring project: ProjectKey?) -> [URL] {
        let mine = transcripts.filter { $0.kind == kind }
        let scoped = project.map { key in
            mine.filter { $0.project?.normalized == key.normalized }
        } ?? []
        let chosen = scoped.isEmpty ? mine : scoped
        return chosen.sorted { $0.modified > $1.modified }.prefix(8).map(\.url)
    }

    private static func excerpt(
        for kind: ProviderKind,
        from transcripts: [Transcript],
        preferring project: ProjectKey?
    ) -> SessionExcerpt? {
        let byURL = Dictionary(transcripts.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        for url in rank(transcripts, for: kind, preferring: project) {
            guard let text = tail(of: url),
                  var excerpt = parseJSONL(text, source: sourceName(kind))
            else { continue }
            excerpt.project = byURL[url]?.project?.displayName
            return excerpt
        }
        return nil
    }

    private static func sourceName(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: return "Claude Code session"
        case .cursor: return "Cursor agent transcript"
        case .chatgpt: return "ChatGPT / Codex session"
        case .antigravity: return "Antigravity session"
        case .grok: return "Grok CLI session"
        }
    }

    // MARK: - Discovery

    static func roots(for kind: ProviderKind) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch kind {
        case .claude:
            return [
                home.appendingPathComponent(".claude/projects"),
                home.appendingPathComponent(".claude/sessions"),
            ]
        case .cursor:
            return [home.appendingPathComponent(".cursor/projects")]
        case .chatgpt:
            return [home.appendingPathComponent(".codex/sessions"), home.appendingPathComponent(".codex")]
        case .antigravity:
            return [
                home.appendingPathComponent(".gemini/antigravity"),
                home.appendingPathComponent(".gemini/antigravity-cli"),
                home.appendingPathComponent(".gemini/antigravity-ide"),
                home.appendingPathComponent(
                    "Library/Application Support/Antigravity/User/workspaceStorage"
                ),
            ]
        case .grok:
            return [
                home.appendingPathComponent(".grok/sessions"),
                home.appendingPathComponent(".grok"),
            ]
        }
    }

    static func transcripts() -> [Transcript] {
        var found: [Transcript] = []
        var seen: Set<URL> = []
        for kind in ProviderKind.allCases {
            for root in roots(for: kind) {
                for directory in recentDirectories(in: root, limit: projectSearchLimit) {
                    let key = ProjectKey(directoryName: directory.lastPathComponent)
                    for (url, modified) in jsonlFiles(in: directory) where seen.insert(url).inserted {
                        found.append(Transcript(url: url, modified: modified, project: key, kind: kind))
                    }
                }
                for (url, modified) in jsonlFiles(in: root, recursive: false) where seen.insert(url).inserted {
                    found.append(Transcript(url: url, modified: modified, project: nil, kind: kind))
                }
            }
        }
        return found
    }

    /// Project folders sorted newest first and capped, because walking every
    /// transcript ever written costs seconds on the app's main interaction.
    private static func recentDirectories(in root: URL, limit: Int) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard values?.isDirectory == true else { return nil }
                return (url, values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private static func jsonlFiles(in directory: URL, recursive: Bool = true) -> [(URL, Date)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        if !recursive {
            guard let entries = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return entries.compactMap(describe)
        }
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == "node_modules" || name == ".git" || name == ".build" || name == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }
            if let entry = describe(url) { files.append(entry) }
        }
        return files
    }

    private static func describe(_ url: URL) -> (URL, Date)? {
        guard url.pathExtension.lowercased() == "jsonl" else { return nil }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        guard values?.isRegularFile == true else { return nil }
        return (url, values?.contentModificationDate ?? .distantPast)
    }

    /// Reads only the end of a transcript. The leading partial line is dropped
    /// so the JSONL parse never sees half an object.
    static func tail(of url: URL, maxBytes: Int = SessionContext.maxReadBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard offset > 0, let newline = text.firstIndex(where: \.isNewline) else { return text }
        return String(text[text.index(after: newline)...])
    }

    // MARK: - Parsing

    public static func parseJSONL(_ text: String, source: String, title: String? = nil) -> SessionExcerpt? {
        var turns: [SessionTurn] = []
        var foundTitle = title
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if foundTitle == nil, let aiTitle = object["aiTitle"] as? String, !aiTitle.isEmpty {
                foundTitle = aiTitle
            }
            if let turn = turn(from: object) {
                turns.append(turn)
            }
        }
        let clipped = clip(turns)
        guard !clipped.isEmpty else { return nil }
        return SessionExcerpt(title: foundTitle, source: source, turns: clipped)
    }

    public static func clip(_ turns: [SessionTurn]) -> [SessionTurn] {
        let tail = Array(turns.suffix(maxTurns))
        var total = 0
        var kept: [SessionTurn] = []
        for turn in tail.reversed() {
            let next = total + turn.text.count
            if next > maxCharacters, !kept.isEmpty { break }
            kept.append(turn)
            total = next
        }
        return kept.reversed()
    }

    static func turn(from object: [String: Any]) -> SessionTurn? {
        let type = (object["type"] as? String) ?? ""
        let role = (object["role"] as? String)
            ?? ((object["message"] as? [String: Any])?["role"] as? String)
            ?? (type == "user" || type == "assistant" ? type : nil)
        guard let role, role == "user" || role == "assistant" else { return nil }

        let message = object["message"] as? [String: Any]
        let content = message?["content"] ?? object["content"] ?? object["text"]
        let text = flattenContent(content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return nil }
        return SessionTurn(role: role, text: text)
    }

    public static func flattenContent(_ raw: Any?) -> String {
        if let text = raw as? String { return text }
        if let blocks = raw as? [Any] {
            return blocks.compactMap { block -> String? in
                if let text = block as? String { return text }
                guard let dict = block as? [String: Any] else { return nil }
                let kind = dict["type"] as? String
                if kind == "tool_use" || kind == "tool_result" { return nil }
                if let text = dict["text"] as? String { return text }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Cursor composer fallback

    private static func composerExcerpt() -> SessionExcerpt? {
        let path = CursorProvider.stateDBPath()
        guard FileManager.default.fileExists(atPath: path),
              let db = try? SQLiteConnection(path: path),
              let headerJSON = db.string(
                  """
                  SELECT value FROM composerHeaders
                  ORDER BY COALESCE(lastUpdatedAt, recency, createdAt) DESC
                  LIMIT 1;
                  """
              ),
              let header = try? JSONSerialization.jsonObject(with: Data(headerJSON.utf8)) as? [String: Any],
              let composerID = header["composerId"] as? String,
              let dataJSON = db.string(
                  "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;",
                  ["composerData:\(composerID)"]
              ),
              let data = try? JSONSerialization.jsonObject(with: Data(dataJSON.utf8)) as? [String: Any],
              let headers = data["fullConversationHeadersOnly"] as? [[String: Any]]
        else { return nil }

        var turns: [SessionTurn] = []
        for item in headers.suffix(40) {
            guard let bubbleID = item["bubbleId"] as? String else { continue }
            let type = item["type"] as? Int ?? -1
            guard let role = type == 1 ? "user" : (type == 2 ? "assistant" : nil) else { continue }
            guard let bubbleJSON = db.string(
                      "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1;",
                      ["bubbleId:\(composerID):\(bubbleID)"]
                  ),
                  let bubble = try? JSONSerialization.jsonObject(with: Data(bubbleJSON.utf8)) as? [String: Any]
            else { continue }
            let text = flattenContent(bubble["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 8 else { continue }
            turns.append(SessionTurn(role: role, text: text))
        }
        let clipped = clip(turns)
        guard !clipped.isEmpty else { return nil }
        return SessionExcerpt(
            title: header["name"] as? String,
            source: "Cursor composer",
            turns: clipped
        )
    }

    // MARK: - Demo

    private static func demoExcerpt(for kind: ProviderKind) -> SessionExcerpt {
        SessionExcerpt(
            title: "Continue the Notch Police work",
            source: "\(kind.displayName) (demo)",
            project: "notch-police",
            turns: [
                SessionTurn(
                    role: "user",
                    text: "Keep building Notch Police. Next up: a button that copies session context when credits are about to die."
                ),
                SessionTurn(
                    role: "assistant",
                    text: "Working on a remaining-first notch for Claude, Cursor, ChatGPT, Antigravity, and Grok. Hovering a ring shows limit windows, and the handover button can copy local context."
                ),
            ]
        )
    }
}
