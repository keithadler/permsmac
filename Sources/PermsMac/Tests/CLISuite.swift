//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum CLISuite {
    static let suite = TestSuite(name: "CLI", cases: [
        TestCase(name: "quiet") { _ in CLI.quiet = true },
        TestCase(name: "since parses units") { t in
            t.equal(CLI.since("24h"), 86400, "hours"); t.equal(CLI.since("30d"), 30 * 86400, "days"); t.equal(CLI.since("2w"), 14 * 86400, "weeks")
            t.equal(CLI.since(nil), 7 * 86400, "default week"); t.equal(CLI.since("junk"), 7 * 86400, "junk defaults")
        },
        TestCase(name: "positional skips option values") { t in
            t.equal(CLI.positional(["--service", "camera", "--json", "x"]), ["x"], "service value skipped")
            t.equal(CLI.value("--since", ["changes", "--since", "3d"]), "3d", "value")
        },
        TestCase(name: "grant dictionary is JSON-safe") { t in
            let g = Grant(service: "kTCCServiceCamera", client: "com.example.a", clientIsPath: false, state: .allowed, reason: .userConsent, target: "com.apple.finder", modified: Date(timeIntervalSince1970: 0), scope: .user)
            let d = CLI.dict(g)
            t.check(JSONSerialization.isValidJSONObject(d), "valid json")
            t.equal(d["name"] as? String, "Camera", "name"); t.equal(d["reason"] as? String, "you clicked Allow", "reason"); t.equal(d["target"] as? String, "com.apple.finder", "target")
            t.equal(d["installed"] as? Bool, false, "orphan flagged")
        },
        TestCase(name: "unknown commands are usage errors") { t in
            t.equal(CLI.run("bogus", []), 64, "exit 64")
            t.equal(CLI.run("explain", []), 64, "explain needs an argument")
            t.equal(CLI.run("explain", ["camera"]), 0, "explain works")
            t.equal(CLI.run("open", ["nonsense"]), 2, "no pane")
            t.equal(CLI.run("version", []), 0, "version")
        },
        TestCase(name: "changes exits 1 when something changed") { t in
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.a")], to: TCC.overrideUser!)
            try FakeTCC.write([], to: TCC.overrideSystem!)
            t.equal(CLI.run("changes", ["--json"]), 0, "first look: nothing to compare")
            var records = History.load(); records[0].date = Date().addingTimeInterval(-100_000); History.save(records)
            try FakeTCC.write([.init(service: "kTCCServiceCamera", client: "com.example.a"), .init(service: "kTCCServiceScreenCapture", client: "com.example.a")], to: TCC.overrideSystem!)
            t.equal(CLI.run("changes", ["--json"]), 1, "second look: a change")
            t.equal(CLI.run("list", ["--json"]), 0, "list")
            t.equal(CLI.run("list", ["--service", "nothing-like-this", "--json"]), 64, "bad service")
            t.equal(CLI.run("orphans", ["--json"]), 1, "example app is an orphan")
            t.equal(CLI.run("status", ["--json"]), 0, "status with both databases")
        },
    ])
}
