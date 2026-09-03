//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  In-module test kit: `permsmac selftest` runs without Xcode; Tests/ bridges to XCTest with it.
//  Every case runs against its own temporary databases and history folder, never the real ones.

import Foundation

final class T {
    private(set) var failures: [String] = []
    private(set) var checks = 0
    var skipped: String?
    func check(_ c: @autoclosure () -> Bool, _ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; if !c() { failures.append("\(what)  (\(file):\(line))") } }
    func equal<E: Equatable>(_ a: E, _ b: E, _ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; if a != b { failures.append("\(what): got \(a), expected \(b)  (\(file):\(line))") } }
    func fail(_ what: String, file: StaticString = #fileID, line: UInt = #line) { checks += 1; failures.append("\(what)  (\(file):\(line))") }
    func skip(_ why: String) { skipped = why }
}

struct TestCase { let name: String; let run: @MainActor (T) throws -> Void }
struct TestSuite { let name: String; let cases: [TestCase] }

enum TestKit {
    static var suites: [TestSuite] { [CatalogSuite.suite, TCCSuite.suite, HistorySuite.suite, StartupSuite.suite, CLISuite.suite, CleanupSuite.suite] }

    struct Result { let suite: String, name: String, failures: [String], skipped: String?, checks: Int, ms: Double; var passed: Bool { failures.isEmpty && skipped == nil } }

    /// A fresh temporary directory per case; removed afterwards.
    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("permsmac-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @MainActor
    static func run(filter: String? = nil) -> [Result] {
        var out: [Result] = []
        for s in suites {
            for c in s.cases {
                let full = "\(s.name)/\(c.name)"
                if let filter, !full.localizedCaseInsensitiveContains(filter) { continue }
                let t = T(); let start = Date()
                let dir = tempDir()
                History.overrideHome = dir.appendingPathComponent("home")
                TCC.overrideUser = dir.appendingPathComponent("user.db"); TCC.overrideSystem = dir.appendingPathComponent("system.db")
                Startup.overrideRoots = []
                Prefs.defaults = UserDefaults(suiteName: "com.keithadler.permsmac.selftest")!
                Prefs.defaults.removePersistentDomain(forName: "com.keithadler.permsmac.selftest")
                do { try c.run(t) } catch { t.fail("threw \(error)") }
                History.overrideHome = nil; TCC.overrideUser = nil; TCC.overrideSystem = nil; Startup.overrideRoots = nil; Prefs.defaults = .standard
                try? FileManager.default.removeItem(at: dir)
                out.append(Result(suite: s.name, name: c.name, failures: t.failures, skipped: t.skipped, checks: t.checks, ms: Date().timeIntervalSince(start) * 1000))
            }
        }
        return out
    }

    static func report(_ results: [Result], json: Bool) -> Int32 {
        let failed = results.filter { !$0.failures.isEmpty }
        if json {
            print(CLI.json(["passed": results.filter(\.passed).count, "failed": failed.count, "checks": results.reduce(0) { $0 + $1.checks },
                            "results": results.map { ["suite": $0.suite, "name": $0.name, "failures": $0.failures, "ms": Int($0.ms)] }]))
        } else {
            var last = ""
            for r in results {
                if r.suite != last { print(r.suite); last = r.suite }
                print(String(format: "  %@ %@ (%d checks, %.0f ms)", r.skipped != nil ? "–" : (r.failures.isEmpty ? "✓" : "✗"), r.name, r.checks, r.ms))
                for f in r.failures { print("      \(f)") }
            }
            print("\(results.filter(\.passed).count) passed, \(failed.count) failed, \(results.reduce(0) { $0 + $1.checks }) checks")
        }
        return failed.isEmpty ? 0 : 2
    }

    static func list() { for s in suites { for c in s.cases { print("\(s.name)/\(c.name)") } } }
}

/// Builds a permissions database with the same shape macOS uses, for tests and screenshots.
enum FakeTCC {
    struct Row { var service: String; var client: String; var isPath = false; var auth = 2; var reason = 2; var target: String? = nil; var modified: Int = 1_756_800_000 }
    static func write(_ rows: [Row], to url: URL, legacy: Bool = false) throws {
        try? FileManager.default.removeItem(at: url)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw TCC.ReadError.cannotOpen("create") }
        defer { sqlite3_close(db) }
        let schema = legacy
            ? "CREATE TABLE access (service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL, allowed INTEGER NOT NULL, prompt_count INTEGER NOT NULL, csreq BLOB, policy_id INTEGER, last_modified INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)))"
            : "CREATE TABLE access (service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL, auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL, csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER, indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB, flags INTEGER, last_modified INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)), pid INTEGER, pid_version INTEGER, boot_uuid TEXT NOT NULL DEFAULT 'UNUSED', last_reminded INTEGER NOT NULL DEFAULT 0)"
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw TCC.ReadError.badSchema }
        for r in rows {
            let sql = legacy
                ? "INSERT INTO access (service, client, client_type, allowed, prompt_count, last_modified) VALUES ('\(r.service)', '\(r.client)', \(r.isPath ? 1 : 0), \(r.auth == 2 ? 1 : 0), 1, \(r.modified))"
                : "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, last_modified) VALUES ('\(r.service)', '\(r.client)', \(r.isPath ? 1 : 0), \(r.auth), \(r.reason), 1, '\(r.target ?? "UNUSED")', \(r.modified))"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TCC.ReadError.badSchema }
        }
    }
}
import SQLite3
