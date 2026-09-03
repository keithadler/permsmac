//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum AuditSuite {
    static func grant(_ s: String, _ c: String, _ st: Grant.State = .allowed, user: String? = nil, path: Bool = false) -> Grant {
        Grant(service: s, client: c, clientIsPath: path, state: st, reason: .userConsent, target: nil, modified: nil, scope: .user, user: user)
    }
    static let gone = "com.example.gone.\(UUID().uuidString)"
    static let suite = TestSuite(name: "Audit", cases: [
        TestCase(name: "example policy loads and names real services") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let f = dir.appendingPathComponent("p.json"); try Data(Audit.example.utf8).write(to: f)
            let p = try Audit.load(f)
            t.equal(p.rules.count, 5, "five rules"); t.equal(p.denyOrphans, true, "orphans denied"); t.check(p.startup != nil, "startup rule")
            t.equal(Audit.serviceKey("Screen Recording"), "kTCCServiceScreenCapture", "display name"); t.equal(Audit.serviceKey("ScreenCapture"), "kTCCServiceScreenCapture", "short key")
            t.equal(Audit.serviceKey("kTCCServiceFuture"), "kTCCServiceFuture", "raw key passes"); t.check(Audit.serviceKey("nonsense") == nil, "nonsense rejected")
        },
        TestCase(name: "bad policies are refused with a reason") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let f = dir.appendingPathComponent("p.json")
            try Data("{\"rules\": [{\"service\": \"Teleportation\", \"allow\": []}]}".utf8).write(to: f)
            do { _ = try Audit.load(f); t.fail("should throw") } catch { t.check("\(error)".contains("Teleportation"), "names the service") }
            try Data("not json".utf8).write(to: f)
            do { _ = try Audit.load(f); t.fail("should throw") } catch { t.check("\(error)".contains("cannot read policy"), "unreadable") }
            do { _ = try Audit.load(dir.appendingPathComponent("missing.json")); t.fail("should throw") } catch { t.check(true, "missing") }
        },
        TestCase(name: "globs match case-insensitively") { t in
            t.check(Audit.matches("com.apple.*", "com.apple.Safari"), "prefix glob")
            t.check(Audit.matches("COM.APPLE.*", "com.apple.safari"), "case")
            t.check(Audit.matches("*", "anything"), "star")
            t.check(!Audit.matches("com.apple.*", "com.applesque.x"), "dot matters")
            t.check(Audit.matches("/Library/PrivilegedHelperTools/*", "/Library/PrivilegedHelperTools/com.docker.vmnetd"), "path glob")
        },
        TestCase(name: "finds violations and respects denied, orphans and startup") { t in
            Apps.demoNames = ["com.example.meetingbot": "MeetingBot", "com.anything.at.all": "Anything", "us.zoom.xos": "Zoom"]   // "installed" for this test
            defer { Apps.demoNames = nil }
            let policy = Policy(rules: [.init(service: "Screen Recording", allow: ["com.apple.*", "us.zoom.xos"], note: "meetings only"), .init(service: "Camera", allow: ["*"], note: nil)],
                                startup: .init(allow: ["com.apple.*", "com.google.keystone.*"]), denyOrphans: true, name: "test")
            let grants = [grant("kTCCServiceScreenCapture", "us.zoom.xos"), grant("kTCCServiceScreenCapture", "com.example.meetingbot", user: "sam"),
                          grant("kTCCServiceScreenCapture", "com.example.denied", .denied), grant("kTCCServiceCamera", "com.anything.at.all"),
                          grant("kTCCServiceMicrophone", gone), grant("kTCCServiceMicrophone", "com.apple.FaceTime")]
            let startup = [StartupItem(kind: .userAgent, label: "com.google.keystone.agent", program: "/x", path: "/a.plist", runAtLoad: true, keepAlive: false, interval: nil, disabled: false),
                           StartupItem(kind: .daemon, label: "com.oldbackup.agent", program: "/Library/OldBackup/agent", path: "/b.plist", runAtLoad: true, keepAlive: false, interval: nil, disabled: false)]
            let v = Audit.run(policy, grants: grants, startup: startup)
            t.equal(v.count, 3, "meetingbot, orphan mic, oldbackup startup")
            t.check(v.contains { $0.client == "com.example.meetingbot" && $0.user == "sam" && $0.why.contains("meetings only") }, "screen recording violation carries user and note")
            t.check(v.contains { $0.client == gone && $0.why == "app no longer installed" }, "orphan flagged")
            t.check(v.contains { $0.service == "startup" && $0.client == "com.oldbackup.agent" }, "startup flagged")
            t.check(!v.contains { $0.client == "com.example.denied" }, "denied grants are not violations")
            t.check(!v.contains { $0.client == "com.anything.at.all" }, "star allows")
            t.check(JSONSerialization.isValidJSONObject(v.map(\.dict)), "json-safe")
        },
        TestCase(name: "CLI audit exit codes") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let f = dir.appendingPathComponent("p.json"); try Data(Audit.example.utf8).write(to: f)
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.apple.FaceTime")], to: TCC.overrideUser!)
            try FakeTCC.write([.init(service: "kTCCServiceScreenCapture", client: "us.zoom.xos")], to: TCC.overrideSystem!)
            t.equal(CLI.run("audit", [f.path, "--json"]), 0, "compliant")
            try FakeTCC.write([.init(service: "kTCCServiceScreenCapture", client: "us.zoom.xos"), .init(service: "kTCCServiceScreenCapture", client: "com.example.spy")], to: TCC.overrideSystem!)
            t.equal(CLI.run("audit", [f.path, "--json"]), 1, "violation")
            try? FileManager.default.removeItem(at: TCC.overrideSystem!)
            t.equal(CLI.run("audit", [f.path, "--json"]), 2, "cannot check")
            t.equal(CLI.run("audit", ["--example"]), 0, "example prints")
            t.equal(CLI.run("audit", []), 64, "usage")
            t.equal(CLI.run("audit", [dir.appendingPathComponent("nope.json").path]), 64, "missing policy is usage")
        },
        TestCase(name: "root-style read walks every account") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let saved = TCC.usersRoot; defer { TCC.usersRoot = saved }
            TCC.usersRoot = dir
            for (u, client) in [("alice", "com.example.a"), ("bob", "com.example.b")] {
                let db = dir.appendingPathComponent(u).appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
                try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FakeTCC.write([.init(service: "kTCCServiceCamera", client: client)], to: db)
            }
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Shared"), withIntermediateDirectories: true)
            try FakeTCC.write([.init(service: "kTCCServiceScreenCapture", client: "com.example.s")], to: TCC.overrideSystem!)
            let snap = TCC.readAllUsers()
            t.equal(snap.grants.count, 3, "two users plus system")
            t.equal(snap.grants.compactMap(\.user).sorted(), ["alice", "bob"], "tagged with user")
            t.check(snap.complete, "complete")
            t.equal(TCC.readAllUsers(only: "bob").grants.filter { $0.user != nil }.count, 1, "--user filter")
            t.check(snap.grants.first { $0.user == "bob" }?.key.hasSuffix("|bob") == true, "user in the history key")
            t.equal(History.parts("user|kTCCServiceCamera|com.example.b||bob").user, "bob", "parts reads it back")
        },
    ])
}
