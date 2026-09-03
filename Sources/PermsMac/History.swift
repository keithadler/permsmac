//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  "What changed since last week." Each time the app looks, it keeps a small record of what it saw;
//  the difference between two records is the list of changes. Records live in this app's own
//  folder in Application Support (or $PERMSMAC_HOME), never anywhere shared.

import Foundation

struct Record: Codable {
    var date: Date
    var grants: [String: String]     // Grant.key → state
    var startup: [String: String]    // path → label + summary
    var complete: Bool

    init(date: Date = Date(), grants: [Grant], startup: [StartupItem], complete: Bool) {
        self.date = date
        self.grants = Dictionary(grants.map { ($0.key, $0.state.rawValue) }, uniquingKeysWith: { a, _ in a })
        self.startup = Dictionary(startup.map { ($0.path, "\($0.label)|\($0.summary)") }, uniquingKeysWith: { a, _ in a })
        self.complete = complete
    }
}

struct Change: Hashable, Identifiable {
    enum What: String { case added, removed, changed }
    enum Area: String { case permission, startup }
    let area: Area
    let what: What
    let key: String
    let before: String?
    let after: String?
    let when: Date            // the record in which it first appeared
    var id: String { "\(area.rawValue)|\(what.rawValue)|\(key)|\(when.timeIntervalSince1970)" }
}

enum History {
    static var overrideHome: URL?
    static var home: URL {
        if let overrideHome { return overrideHome }
        if let h = ProcessInfo.processInfo.environment["PERMSMAC_HOME"], !h.isEmpty { return URL(fileURLWithPath: h, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Permissions for Mac", isDirectory: true)
    }
    static var file: URL { home.appendingPathComponent("history.json") }
    static let keep = 400   // records; at one per look this is months

    static func load() -> [Record] {
        guard let d = try? Data(contentsOf: file), let r = try? decoder.decode([Record].self, from: d) else { return [] }
        return r
    }
    static func save(_ records: [Record]) {
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let d = try? encoder.encode(Array(records.suffix(keep))) { try? d.write(to: file, options: .atomic) }
    }

    /// Adds a record only when something differs from the last one (or a day has passed), so the
    /// file stays small and the "since" dates mean something.
    @discardableResult
    static func append(_ r: Record, to records: inout [Record]) -> Bool {
        if let last = records.last, last.grants == r.grants, last.startup == r.startup, last.complete == r.complete,
           r.date.timeIntervalSince(last.date) < 86400 { return false }
        records.append(r); return true
    }

    /// Changes between the last record at or before `since` and the newest record. A grant that
    /// appeared and disappeared in between is not lost: each consecutive pair is compared.
    static func changes(in records: [Record], since: Date) -> [Change] {
        guard records.count >= 2 else { return [] }
        var start = 0
        for (i, r) in records.enumerated() where r.date <= since { start = i }
        var out: [Change] = []
        for i in start..<(records.count - 1) { out += diff(records[i], records[i + 1]) }
        return out
    }

    static func diff(_ a: Record, _ b: Record) -> [Change] {
        var out: [Change] = []
        // A partial read (no Full Disk Access yet) must not look like every permission vanished.
        if a.complete && b.complete || (!a.complete && !b.complete) {
            for (k, v) in b.grants {
                if let old = a.grants[k] { if old != v { out.append(Change(area: .permission, what: .changed, key: k, before: old, after: v, when: b.date)) } }
                else { out.append(Change(area: .permission, what: .added, key: k, before: nil, after: v, when: b.date)) }
            }
            for (k, v) in a.grants where b.grants[k] == nil { out.append(Change(area: .permission, what: .removed, key: k, before: v, after: nil, when: b.date)) }
        }
        for (k, v) in b.startup {
            if let old = a.startup[k] { if old != v { out.append(Change(area: .startup, what: .changed, key: k, before: old, after: v, when: b.date)) } }
            else { out.append(Change(area: .startup, what: .added, key: k, before: nil, after: v, when: b.date)) }
        }
        for (k, v) in a.startup where b.startup[k] == nil { out.append(Change(area: .startup, what: .removed, key: k, before: v, after: nil, when: b.date)) }
        return out.sorted { $0.key < $1.key }
    }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// "system|kTCCServiceCamera|com.example.app|" → parts a view can render.
    static func parts(_ grantKey: String) -> (scope: String, service: String, client: String, target: String?) {
        let p = grantKey.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return (p.count > 0 ? p[0] : "", p.count > 1 ? p[1] : "", p.count > 2 ? p[2] : "", p.count > 3 && !p[3].isEmpty ? p[3] : nil)
    }
}
