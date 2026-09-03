//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum CleanupSuite {
    static func grant(_ s: String, _ c: String, path: Bool = false, scope: Grant.Scope = .user) -> Grant {
        Grant(service: s, client: c, clientIsPath: path, state: .allowed, reason: .userConsent, target: nil, modified: nil, scope: scope)
    }
    static let gone = "com.example.gone.\(UUID().uuidString)"
    static let suite = TestSuite(name: "Cleanup", cases: [
        TestCase(name: "commands use Apple's service names") { t in
            t.equal(Cleanup.serviceArgument("kTCCServiceScreenCapture"), "ScreenCapture", "prefix dropped")
            t.equal(Cleanup.serviceArgument("Odd"), "Odd", "unknown passes through")
            t.equal(Cleanup.command(gone), "tccutil reset All \(gone)", "command line")
            let cmds = Cleanup.commands([grant("kTCCServiceCamera", gone), grant("kTCCServiceMicrophone", gone), grant("kTCCServiceCamera", gone, scope: .system), grant("kTCCServiceMicrophone", "com.apple.FaceTime")])
            t.equal(cmds, ["tccutil reset All \(gone)"], "one command per app, Apple skipped")
        },
        TestCase(name: "refuses installed apps, paths and Apple") { t in
            t.check(Cleanup.objection(grant("kTCCServiceCamera", "/usr/bin/say", path: true)) != nil, "path refused")
            t.check(Cleanup.objection(grant("kTCCServiceCamera", "com.apple.Safari")) != nil, "apple refused")
            t.check(Cleanup.objection(grant("kTCCServiceCamera", "com.apple.Calculator")) != nil, "installed apple app refused")
            t.check(Cleanup.objection(grant("kTCCServiceCamera", gone)) == nil, "gone app allowed")
            // Something that is certainly installed and not Apple: this app's own build if registered, else skip the check.
            if let b = Bundle.main.bundleIdentifier, b == "com.keithadler.permsmac" { t.check(Cleanup.objection(grant("kTCCServiceCamera", b)) != nil, "installed non-Apple refused") }
        },
        TestCase(name: "runs one reset per app and reports") { t in
            var calls: [[String]] = []; var ticks: [(Int, Int)] = []
            let saved = Cleanup.runner; defer { Cleanup.runner = saved }
            Cleanup.runner = { args in calls.append(args); return args.last == "com.example.bad" ? (1, "tccutil: Failed to reset") : (0, "Successfully reset All") }
            let r = Cleanup.run([grant("kTCCServiceCamera", gone), grant("kTCCServiceCamera", gone, scope: .system), grant("kTCCServiceMicrophone", gone),
                                 grant("kTCCServiceCamera", "com.example.bad"), grant("kTCCServiceCamera", "/bin/x", path: true), grant("kTCCServiceCamera", "com.apple.x")]) { ticks.append(($0, $1)) }
            t.equal(calls.count, 2, "two apps, two calls, for four qualifying rows")
            t.equal(calls.first, ["reset", "All", "com.example.bad"], "arguments, sorted by client")
            t.equal(r.cleared.count, 3, "all three rows of the gone app cleared")
            t.equal(r.failed.count, 1, "one failure"); t.equal(r.failed.first?.1, "tccutil: Failed to reset", "failure text")
            t.equal(r.skipped.count, 2, "two skipped")
            t.equal(r.summary, "3 cleared, 1 failed, 2 skipped", "summary")
            t.equal(ticks.map(\.0), [1, 2], "progress after each app"); t.equal(ticks.first?.1, 2, "progress total")
        },
        TestCase(name: "never runs anything when nothing qualifies") { t in
            var ran = false
            let saved = Cleanup.runner; defer { Cleanup.runner = saved }
            Cleanup.runner = { _ in ran = true; return (0, "") }
            let r = Cleanup.run([grant("kTCCServiceCamera", "com.apple.x"), grant("kTCCServiceCamera", "/x", path: true)])
            t.check(!ran, "no command ran"); t.equal(r.cleared.count, 0, "nothing cleared"); t.equal(r.summary, "0 cleared, 2 skipped", "summary")
        },
    ])
}
