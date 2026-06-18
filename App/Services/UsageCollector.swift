import Foundation

/// Liest die JSONL-Sitzungsprotokolle von Claude Code ausschließlich lesend
/// und aggregiert Tokens und Aktivität der letzten Tage.
///
/// Zählregeln (empirisch gegen Claude Codes eigene /usage-Statistik verifiziert):
/// - Tokens = input + output je Assistant-Antwort, dedupliziert über message.id,
///   OHNE Sidechain-Nachrichten (Subagenten) — entspricht „Total tokens" in /usage.
///   Claude Code schreibt eine Antwort als MEHRERE JSONL-Zeilen (eine pro
///   Content-Block: Thinking, Text, jeder Tool-Use), alle mit derselben message.id
///   und identischem kumulativem usage-Block; pro Zeile zu summieren zählte eine
///   Antwort mit N Blöcken N-fach (~3× bei normaler Tool-Nutzung). Daher nur die
///   erste Zeile je message.id verbuchen — die identische usage macht das exakt.
/// - Nachrichten = Assistant-Antworten, ebenfalls über message.id allein
///   dedupliziert: Subagenten-Protokolle spiegeln Eltern-Nachrichten unter NEUER
///   Request-ID — eine zusammengesetzte ID (message.id + requestId) würde solche
///   Spiegelungen doppelt zählen.
/// - Cache-Tokens werden mitgeführt (Snapshot), aber nicht als „Tokens" angezeigt.
///
/// Als actor: collect()-Aufrufe sind serialisiert und laufen automatisch
/// abseits des MainActors — kein Data-Race auf fileCache möglich.
actor UsageCollector {
    private var fileCache: [String: (mtime: Date, size: Int64, entries: [Entry])] = [:]

    struct Entry {
        let date: Date
        let isSidechain: Bool
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let sessionId: String?
        let dedupeKey: String?
    }

    nonisolated var localDataAvailable: Bool {
        Self.projectDirectories().contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    /// Alle Orte, an denen Claude Code Sitzungsprotokolle ablegen kann
    /// (jeweils das projects-Unterverzeichnis). `CLAUDE_CONFIG_DIR` übersteuert
    /// — kommagetrennt, mit ~-Expansion, wie Claude Code selbst es versteht.
    /// Ohne Override gelten beide Standardorte zugleich, denn je nach
    /// Installation liegt das Verzeichnis unter ~/.claude oder im
    /// XDG-Config-Pfad; bei jedem collect() frisch geprüft, damit eine
    /// Erstinstallation von Claude Code zur Laufzeit erkannt wird.
    private static func projectDirectories() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let home = SnapshotLocation.realHome
        var roots: [URL] = []
        if let configured = env["CLAUDE_CONFIG_DIR"] {
            roots = configured.split(separator: ",").compactMap { entry in
                let path = entry.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { return nil }
                if path == "~" { return home }
                if path.hasPrefix("~/") {
                    return home.appendingPathComponent(String(path.dropFirst(2)))
                }
                return URL(fileURLWithPath: path)
            }
        }
        if roots.isEmpty {
            let xdg = env["XDG_CONFIG_HOME"].flatMap {
                $0.isEmpty ? nil : URL(fileURLWithPath: $0)
            } ?? home.appendingPathComponent(".config")
            roots = [home.appendingPathComponent(".claude"),
                     xdg.appendingPathComponent("claude")]
        }
        var seen = Set<String>()
        return roots.compactMap { root in
            let dir = root.appendingPathComponent("projects")
            guard seen.insert(dir.standardizedFileURL.path).inserted else { return nil }
            return dir
        }
    }

    func collect(daysBack: Int = 30) -> UsageSnapshot.LocalUsage {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return UsageSnapshot.LocalUsage(days: [])
        }

        let files = jsonlFiles(modifiedAfter: cutoff)
        var entries: [Entry] = []
        for url in files {
            entries.append(contentsOf: parse(file: url))
        }
        // Cache-Einträge für gelöschte/herausgealterte Dateien entfernen
        let activePaths = Set(files.map(\.path))
        fileCache = fileCache.filter { activePaths.contains($0.key) }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = .current

        var dayKeys: [String] = []
        for offset in stride(from: -(daysBack - 1), through: 0, by: 1) {
            if let d = calendar.date(byAdding: .day, value: offset, to: today) {
                dayKeys.append(dayFormatter.string(from: d))
            }
        }

        var stats: [String: UsageSnapshot.DayStat] = [:]
        var sessions: [String: Set<String>] = [:]
        for key in dayKeys {
            stats[key] = .empty(date: key)
            sessions[key] = []
        }

        var seenMessages = Set<String>()
        for e in entries {
            let key = dayFormatter.string(from: e.date)
            guard var stat = stats[key] else { continue }
            // Erste Begegnung dieser message.id? Tokens, Cache UND messageCount
            // ausschließlich beim ersten Auftreten verbuchen — eine Antwort mit
            // mehreren Content-Blöcken erscheint als mehrere Zeilen gleicher
            // message.id mit identischem usage-Block; jede zu summieren blähte
            // die Tokens auf (siehe Zählregeln im Header). Ohne message.id
            // (alte Logs) jede Zeile zählen.
            let firstSeen: Bool
            if let dedupeKey = e.dedupeKey {
                firstSeen = seenMessages.insert(dedupeKey).inserted
            } else {
                firstSeen = true
            }
            if firstSeen {
                if !e.isSidechain {
                    stat.inputTokens += e.input
                    stat.outputTokens += e.output
                    stat.cacheReadTokens += e.cacheRead
                    stat.cacheWriteTokens += e.cacheWrite
                }
                stat.messageCount += 1
            }
            if let sid = e.sessionId {
                sessions[key]?.insert(sid)
            }
            stats[key] = stat
        }

        let days: [UsageSnapshot.DayStat] = dayKeys.map { key in
            var stat = stats[key] ?? .empty(date: key)
            stat.sessionCount = sessions[key]?.count ?? 0
            return stat
        }
        return UsageSnapshot.LocalUsage(days: days)
    }

    // MARK: - Dateisuche

    private func jsonlFiles(modifiedAfter cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var result: [URL] = []
        for projectsDir in Self.projectDirectories() {
            guard let enumerator = FileManager.default.enumerator(
                at: projectsDir, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let mtime = values.contentModificationDate,
                      mtime >= cutoff else { continue }
                result.append(url)
            }
        }
        return result
    }

    // MARK: - Parsing

    private func parse(file url: URL) -> [Entry] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let mtime = values.contentModificationDate else { return [] }
        let size = Int64(values.fileSize ?? 0)

        if let cached = fileCache[url.path], cached.mtime == mtime, cached.size == size {
            return cached.entries
        }

        // Bewusst ungemappt lesen: mmap einer Datei, die ein anderer Prozess
        // truncaten könnte, würde mit SIGBUS crashen.
        guard let data = try? Data(contentsOf: url) else { return [] }

        var entries: [Entry] = []
        let decoder = JSONDecoder()
        let newline = UInt8(ascii: "\n")
        // Schneller Vorfilter: nur Zeilen mit "usage" überhaupt dekodieren
        let usageMarker = Data("\"usage\"".utf8)

        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newline) ?? data.endIndex
            defer { start = end < data.endIndex ? data.index(after: end) : data.endIndex }
            let line = data[start..<end]
            guard !line.isEmpty, line.range(of: usageMarker) != nil else { continue }
            guard let log = try? decoder.decode(LogLine.self, from: line) else { continue }
            guard log.type == "assistant",
                  let usage = log.message?.usage,
                  let timestamp = log.timestamp,
                  let date = Self.parseDate(timestamp) else { continue }
            if log.message?.model == "<synthetic>" { continue }

            // Dedupe allein über message.id — siehe Zählregeln im Header.
            let dedupeKey = log.message?.id
            entries.append(Entry(
                date: date,
                isSidechain: log.isSidechain ?? false,
                input: usage.input_tokens ?? 0,
                output: usage.output_tokens ?? 0,
                cacheRead: usage.cache_read_input_tokens ?? 0,
                cacheWrite: usage.cache_creation_input_tokens ?? 0,
                sessionId: log.sessionId,
                dedupeKey: dedupeKey
            ))
        }

        fileCache[url.path] = (mtime, size, entries)
        return entries
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    private struct LogLine: Decodable {
        let type: String?
        let timestamp: String?
        let sessionId: String?
        let isSidechain: Bool?
        let message: Msg?

        struct Msg: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }
}
