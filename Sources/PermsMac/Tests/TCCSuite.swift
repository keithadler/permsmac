//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation
import CryptoKit
import SQLite3

enum TCCSuite {
    static let suite = TestSuite(name: "TCC", cases: [
        TestCase(name: "reads both databases and maps states") { t in
            try FakeTCC.write([
                .init(service: "kTCCServiceCamera", client: "com.example.zoom"),
                .init(service: "kTCCServiceMicrophone", client: "com.example.zoom", auth: 0),
                .init(service: "kTCCServicePhotos", client: "com.example.photos", auth: 3, reason: 3),
                .init(service: "kTCCServiceAppleEvents", client: "com.example.script", target: "com.apple.finder"),
            ], to: TCC.overrideUser!)
            try FakeTCC.write([
                .init(service: "kTCCServiceScreenCapture", client: "/usr/local/bin/tool", isPath: true, reason: 3),
                .init(service: "kTCCServiceAccessibility", client: "com.example.zoom", auth: 1),
            ], to: TCC.overrideSystem!)
            let snap = TCC.read()
            t.check(snap.complete, "complete")
            t.equal(snap.grants.count, 6, "six rows")
            let by = Dictionary(grouping: snap.grants, by: \.service)
            t.equal(by["kTCCServiceCamera"]?.first?.state, .allowed, "camera allowed")
            t.equal(by["kTCCServiceMicrophone"]?.first?.state, .denied, "mic denied")
            t.equal(by["kTCCServicePhotos"]?.first?.state, .limited, "photos limited")
            t.equal(by["kTCCServicePhotos"]?.first?.reason?.text, "set in System Settings", "reason")
            t.equal(by["kTCCServiceAppleEvents"]?.first?.target, "com.apple.finder", "automation target kept")
            t.check(by["kTCCServiceCamera"]?.first?.target == nil, "UNUSED target dropped")
            t.equal(by["kTCCServiceScreenCapture"]?.first?.clientIsPath, true, "path client")
            t.equal(by["kTCCServiceScreenCapture"]?.first?.scope, .system, "system scope")
            t.equal(by["kTCCServiceAccessibility"]?.first?.state, .unknown, "auth 1 is unknown")
            t.equal(by["kTCCServiceCamera"]?.first?.modified?.timeIntervalSince1970, 1_756_800_000, "date")
        },
        TestCase(name: "older schema with allowed column") { t in
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.old", auth: 2), .init(service: "kTCCServiceMicrophone", client: "com.example.old", auth: 0)], to: TCC.overrideUser!, legacy: true)
            try FakeTCC.write([], to: TCC.overrideSystem!)
            let snap = TCC.read()
            t.equal(snap.grants.filter { $0.state == .allowed }.count, 1, "one allowed")
            t.equal(snap.grants.filter { $0.state == .denied }.count, 1, "one denied")
            t.check(snap.grants.allSatisfy { $0.reason == nil && $0.target == nil }, "no reason or target columns")
        },
        TestCase(name: "unreadable database is reported, not invented") { t in
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.a")], to: TCC.overrideUser!)
            let snap = TCC.read()     // system.db never written
            t.check(snap.userReadable && !snap.systemReadable && !snap.complete, "partial read flagged")
            t.equal(snap.grants.count, 1, "user rows still returned")
            t.check(TCC.access(TCC.overrideSystem!) != .ok, "missing file is not ok")
            t.check(!TCC.hasFullDiskAccess, "no full access")
        },
        TestCase(name: "reading never changes the file") { t in
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.a")], to: TCC.overrideUser!)
            try FakeTCC.write([.init(service: "kTCCServiceScreenCapture", client: "com.example.a")], to: TCC.overrideSystem!)
            let before = (try Data(contentsOf: TCC.overrideUser!), try Data(contentsOf: TCC.overrideSystem!))
            let attrs = try FileManager.default.attributesOfItem(atPath: TCC.overrideUser!.path)
            for _ in 0..<3 { _ = TCC.read() }
            let after = (try Data(contentsOf: TCC.overrideUser!), try Data(contentsOf: TCC.overrideSystem!))
            t.check(before == after, "bytes identical after reading")
            t.equal((try FileManager.default.attributesOfItem(atPath: TCC.overrideUser!.path))[.modificationDate] as? Date, attrs[.modificationDate] as? Date, "mtime untouched")
            let dir = TCC.overrideUser!.deletingLastPathComponent()
            let extras = (try FileManager.default.contentsOfDirectory(atPath: dir.path)).filter { $0.contains("-journal") || $0.contains("-wal") || $0.contains("-shm") }
            t.check(extras.isEmpty, "no journal files created: \(extras)")
        },
        TestCase(name: "sees changes still sitting in the write-ahead log") { t in
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.a"), .init(service: "kTCCServiceCamera", client: "com.example.gone")], to: TCC.overrideUser!)
            try FakeTCC.write([], to: TCC.overrideSystem!)
            // Switch to WAL and delete a row on a connection that stays open, so the change lives only in -wal.
            var db: OpaquePointer?
            t.check(sqlite3_open(TCC.overrideUser!.path, &db) == SQLITE_OK, "open")
            t.check(sqlite3_exec(db, "PRAGMA journal_mode=WAL; DELETE FROM access WHERE client='com.example.gone'", nil, nil, nil) == SQLITE_OK, "delete in wal")
            t.check(FileManager.default.fileExists(atPath: TCC.overrideUser!.path + "-wal"), "wal file exists")
            let snap = TCC.read()
            t.equal(snap.grants.map(\.client), ["com.example.a"], "deleted row is gone even before checkpoint")
            sqlite3_close(db)
        },
        TestCase(name: "garbage file is not a database") { t in
            try Data("not a database".utf8).write(to: TCC.overrideUser!)
            try FakeTCC.write([], to: TCC.overrideSystem!)
            let snap = TCC.read()
            t.check(!snap.userReadable && snap.systemReadable, "bad file reported unreadable")
        },
        TestCase(name: "clients resolve to names and orphans") { t in
            let r = Apps.resolve("/System/Applications/Calculator.app", isPath: true)
            t.equal(r.name, "Calculator", "app path → name")
            t.check(!Apps.isOrphan("/System/Applications/Calculator.app", isPath: true), "installed app is not an orphan")
            t.check(Apps.isOrphan("com.example.definitely.not.installed.\(UUID().uuidString)", isPath: false), "missing bundle id is an orphan")
            t.check(!Apps.isOrphan("com.apple.something.internal", isPath: false), "apple ids are never flagged")
            t.equal(Apps.resolve("/usr/bin/say", isPath: true).name, "say", "tool path → basename")
            t.equal(Apps.resolve("/Applications/X.app/Contents/MacOS/helper", isPath: true).name, "X (helper)", "helper inside an app")
            t.equal(Apps.resolve("/Applications/Analog Lab V.app/Contents/MacOS/Analog Lab V", isPath: true).name, "Analog Lab V", "main executable is not repeated")
        },
    ])
}
