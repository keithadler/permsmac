//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  The one thing this app changes, and only when asked: permissions left behind by apps that no
//  longer exist on disk. It uses Apple's own `tccutil reset`, one entry at a time, the same thing
//  the "−" button in System Settings does. It refuses to touch an entry for an app that is still
//  installed, so the promise stays: it never changes a permission for an app you have.

import Foundation

struct CleanupResult {
    var cleared: [Grant] = []
    var failed: [(Grant, String)] = []
    var skipped: [(Grant, String)] = []
    var summary: String {
        var bits = ["\(cleared.count) cleared"]
        if !failed.isEmpty { bits.append("\(failed.count) failed") }
        if !skipped.isEmpty { bits.append("\(skipped.count) skipped") }
        return bits.joined(separator: ", ")
    }
}

enum Cleanup {
    /// Runs one command and returns (exit code, combined output). Tests replace this.
    static var runner: ([String]) -> (Int32, String) = { args in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil"); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (127, "\(error)") }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The tccutil service name is the key without its prefix: kTCCServiceCamera → Camera.
    static func serviceArgument(_ key: String) -> String { key.hasPrefix("kTCCService") ? String(key.dropFirst("kTCCService".count)) : key }

    /// Why an entry cannot be cleaned, or nil when it can.
    static func objection(_ g: Grant) -> String? {
        if g.clientIsPath || g.client.hasPrefix("/") { return "tccutil only works with bundle identifiers, not paths" }
        if g.client.hasPrefix("com.apple.") { return "Apple's own entries are left alone" }
        if !Apps.isOrphan(g.client, isPath: g.clientIsPath) { return "still installed; change it in System Settings" }
        return nil
    }

    /// One command per app, not per entry: `tccutil reset All <bundle-id>` clears every permission
    /// that app held. Ninety leftover entries are usually a dozen apps, and each call takes a second.
    static func command(_ client: String) -> String { "tccutil reset All \(client)" }

    /// The clients that qualify, in a stable order, with the entries each covers.
    static func groups(_ grants: [Grant]) -> [(client: String, grants: [Grant])] {
        let ok = grants.filter { objection($0) == nil }
        return Dictionary(grouping: ok, by: \.client).map { ($0.key, $0.value) }.sorted { $0.client < $1.client }
    }

    /// The commands a person could run themselves.
    static func commands(_ grants: [Grant]) -> [String] { groups(grants).map { command($0.client) } }

    /// Runs one reset per app. Safe to call off the main thread; `progress` is called after each app.
    static func run(_ grants: [Grant], progress: ((Int, Int) -> Void)? = nil) -> CleanupResult {
        var r = CleanupResult()
        r.skipped = grants.compactMap { g in objection(g).map { (g, $0) } }
        let gs = groups(grants)
        for (i, group) in gs.enumerated() {
            let (code, out) = runner(["reset", "All", group.client])
            if code == 0 { r.cleared += group.grants } else { r.failed += group.grants.map { ($0, out.isEmpty ? "tccutil exited \(code)" : out) } }
            progress?(i + 1, gs.count)
        }
        return r
    }
}
