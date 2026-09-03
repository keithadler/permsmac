//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum StartupSuite {
    static func plist(_ dict: [String: Any], to url: URL) throws {
        try (try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)).write(to: url)
    }
    static let suite = TestSuite(name: "Startup", cases: [
        TestCase(name: "parses agents and daemons") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let agents = dir.appendingPathComponent("LaunchAgents"), daemons = dir.appendingPathComponent("LaunchDaemons")
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: daemons, withIntermediateDirectories: true)
            try plist(["Label": "com.example.updater", "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/updater", "--check"], "RunAtLoad": true, "StartInterval": 3600], to: agents.appendingPathComponent("com.example.updater.plist"))
            try plist(["Label": "com.example.helper", "Program": "/Library/PrivilegedHelperTools/helper", "KeepAlive": ["SuccessfulExit": false]], to: daemons.appendingPathComponent("com.example.helper.plist"))
            try plist(["Label": "com.apple.thing", "Program": "/usr/libexec/thing", "Disabled": true], to: agents.appendingPathComponent("com.apple.thing.plist"))
            try Data("junk".utf8).write(to: agents.appendingPathComponent("broken.plist"))
            try Data("x".utf8).write(to: agents.appendingPathComponent("notes.txt"))
            Startup.overrideRoots = [(agents, .userAgent), (daemons, .daemon)]
            let items = Startup.scan()
            t.equal(items.count, 3, "three plists parsed, junk skipped")
            let up = items.first { $0.label == "com.example.updater" }
            t.equal(up?.program, "/Applications/Example.app/Contents/MacOS/updater", "program from arguments")
            t.equal(up?.summary, "starts at login, every 1 h", "summary")
            t.equal(up?.kind, .userAgent, "kind")
            let helper = items.first { $0.label == "com.example.helper" }
            t.equal(helper?.keepAlive, true, "KeepAlive dictionary counts")
            t.equal(helper?.summary, "restarts if it stops", "helper summary")
            t.equal(helper?.kind, .daemon, "daemon kind")
            let apple = items.first { $0.label == "com.apple.thing" }
            t.check(apple.map(Startup.isApple) == true, "apple detected")
            t.equal(apple?.summary, "disabled", "disabled shows")
            t.equal(items.filter { !Startup.isApple($0) }.count, 2, "apple filtered out")
        },
        TestCase(name: "label falls back to the file name") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            try plist(["Program": "/bin/true"], to: dir.appendingPathComponent("org.thing.agent.plist"))
            Startup.overrideRoots = [(dir, .systemAgent)]
            let i = Startup.scan().first
            t.equal(i?.label, "org.thing.agent", "label from file")
            t.equal(i?.summary, "starts when something asks for it", "on-demand summary")
            t.equal(i?.interval, nil, "no interval")
        },
        TestCase(name: "missing folders are not errors") { t in
            Startup.overrideRoots = [(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), .userAgent)]
            t.equal(Startup.scan().count, 0, "empty")
        },
    ])
}
