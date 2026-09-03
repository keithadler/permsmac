//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  Reads the permissions database macOS keeps (TCC: "Transparency, Consent, and Control") and
//  nothing else. Two copies exist: one per user for camera, contacts and the like, and one for the
//  whole Mac for Accessibility, Screen Recording, Full Disk Access and Input Monitoring. Both are
//  readable only by apps that have Full Disk Access, so this app asks for that one permission and
//  opens the files read-only. It never writes; there is no code path that could.

import Foundation
import SQLite3
import AppKit

struct Grant: Hashable, Identifiable {
    enum State: String { case allowed, denied, limited, unknown }
    let service: String
    let client: String        // bundle id or an absolute path
    let clientIsPath: Bool
    let state: State
    let reason: Reason?
    let target: String?       // Automation: the app being controlled
    let modified: Date?
    let scope: Scope
    enum Scope: String { case user, system }
    var id: String { "\(scope.rawValue)|\(service)|\(client)|\(target ?? "")" }
    var key: String { id }
}

enum TCC {
    static let userDB = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    static let systemDB = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    /// Tests and screenshots point these at their own databases.
    static var overrideUser: URL?
    static var overrideSystem: URL?

    enum Access { case ok, needsFullDiskAccess, missing }
    static func access(_ url: URL) -> Access {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDir) || overrideUser != nil else { return .missing }
        return Foundation.access(url.path, R_OK) == 0 ? .ok : .needsFullDiskAccess
    }
    static var hasFullDiskAccess: Bool { access(overrideUser ?? userDB) == .ok && access(overrideSystem ?? systemDB) == .ok }

    struct Snapshot {
        var grants: [Grant]
        var userReadable: Bool
        var systemReadable: Bool
        var complete: Bool { userReadable && systemReadable }
    }

    static func read() -> Snapshot {
        let u = overrideUser ?? userDB, s = overrideSystem ?? systemDB
        let user = try? rows(u, scope: .user), system = try? rows(s, scope: .system)
        return Snapshot(grants: (user ?? []) + (system ?? []), userReadable: user != nil, systemReadable: system != nil)
    }

    enum ReadError: Error { case cannotOpen(String), badSchema }

    /// Opens with the immutable flag so a database tccd is writing to is read as-is, without touching
    /// its journal, and with read-only so nothing here could ever change it.
    static func rows(_ url: URL, scope: Grant.Scope) throws -> [Grant] {
        var db: OpaquePointer?
        let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"; sqlite3_close(db); throw ReadError.cannotOpen(msg)
        }
        defer { sqlite3_close(db) }
        let columns = try columnNames(db, table: "access")
        guard columns.contains("service"), columns.contains("client"), columns.contains("auth_value") || columns.contains("allowed") else { throw ReadError.badSchema }
        // Older macOS stored "allowed" instead of auth_value; newer adds indirect objects for Automation.
        let authCol = columns.contains("auth_value") ? "auth_value" : "allowed"
        let reasonCol = columns.contains("auth_reason") ? "auth_reason" : "NULL"
        let targetCol = columns.contains("indirect_object_identifier") ? "indirect_object_identifier" : "NULL"
        let modCol = columns.contains("last_modified") ? "last_modified" : "NULL"
        let typeCol = columns.contains("client_type") ? "client_type" : "0"
        let sql = "SELECT service, client, \(typeCol), \(authCol), \(reasonCol), \(targetCol), \(modCol) FROM access"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { throw ReadError.cannotOpen(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(st) }
        var out: [Grant] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let sv = sqlite3_column_text(st, 0), let cl = sqlite3_column_text(st, 1) else { continue }
            let auth = Int(sqlite3_column_int(st, 3))
            let state: Grant.State = authCol == "allowed" ? (auth == 1 ? .allowed : .denied) : (auth == 2 ? .allowed : auth == 3 ? .limited : auth == 0 ? .denied : .unknown)
            let reason = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : Reason(rawValue: Int(sqlite3_column_int(st, 4)))
            let target = sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : sqlite3_column_text(st, 5).map { String(cString: $0) }
            let mod = sqlite3_column_type(st, 6) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(st, 6)))
            out.append(Grant(service: String(cString: sv), client: String(cString: cl), clientIsPath: sqlite3_column_int(st, 2) == 1,
                             state: state, reason: reason, target: target.flatMap { $0 == "UNUSED" ? nil : $0 }, modified: mod, scope: scope))
        }
        return out
    }

    static func columnNames(_ db: OpaquePointer, table: String) throws -> Set<String> {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &st, nil) == SQLITE_OK, let st else { throw ReadError.badSchema }
        defer { sqlite3_finalize(st) }
        var names = Set<String>()
        while sqlite3_step(st) == SQLITE_ROW { if let n = sqlite3_column_text(st, 1) { names.insert(String(cString: n)) } }
        return names
    }

    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// Turns a bundle id or path into something a person recognises, with the icon Finder shows.
enum Apps {
    private static var cache: [String: (name: String, url: URL?)] = [:]
    /// Screenshots and tests: bundle id → display name for apps that are not really installed.
    static var demoNames: [String: String]?
    static func resolve(_ client: String, isPath: Bool) -> (name: String, url: URL?) {
        if let demoNames, let n = demoNames[client] { return (n, nil) }
        if let c = cache[client] { return c }
        var url: URL?
        if isPath || client.hasPrefix("/") { url = URL(fileURLWithPath: client) }
        else { url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) }
        var name = client
        if let url {
            if url.pathExtension == "app" || url.path.contains(".app/") {
                var appURL = url
                while appURL.pathExtension != "app", appURL.path != "/" { appURL = appURL.deletingLastPathComponent() }
                name = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
                if appURL != url { name += " (\(url.lastPathComponent))" }
            } else { name = url.lastPathComponent }
        } else if let short = friendlyBundleNames[client] { name = short }
        let r = (name, url); cache[client] = r; return r
    }
    static func icon(_ client: String, isPath: Bool) -> NSImage {
        let r = resolve(client, isPath: isPath)
        if let url = r.url, FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
    /// True when the client no longer exists on disk: a grant left behind by an uninstalled app.
    static func isOrphan(_ client: String, isPath: Bool) -> Bool {
        if let demoNames { return demoNames[client] == nil && !client.hasPrefix("com.apple.") }
        let r = resolve(client, isPath: isPath)
        guard let url = r.url else { return !client.hasPrefix("com.apple.") }
        return !FileManager.default.fileExists(atPath: url.path)
    }
    static let friendlyBundleNames: [String: String] = [
        "com.apple.Terminal": "Terminal", "com.apple.finder": "Finder", "com.apple.Safari": "Safari", "com.apple.systemevents": "System Events",
        "com.apple.controlcenter": "Control Center", "com.apple.screencaptureui": "Screenshot", "com.apple.Siri": "Siri", "com.apple.imagent": "iMessage",
    ]
    static func resetCache() { cache = [:] }
}
