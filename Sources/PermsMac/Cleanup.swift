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

    static func command(_ g: Grant) -> String { "tccutil reset \(serviceArgument(g.service)) \(g.client)" }

    /// The commands a person could run themselves, for the entries that qualify.
    static func commands(_ grants: [Grant]) -> [String] {
        Array(Set(grants.filter { objection($0) == nil }.map(command))).sorted()
    }

    static func run(_ grants: [Grant]) -> CleanupResult {
        var r = CleanupResult()
        var done = Set<String>()
        for g in grants {
            if let why = objection(g) { r.skipped.append((g, why)); continue }
            let key = "\(g.service)|\(g.client)"
            if done.contains(key) { r.cleared.append(g); continue }    // same entry in both databases: one reset covers it
            done.insert(key)
            let (code, out) = runner(["reset", serviceArgument(g.service), g.client])
            if code == 0 { r.cleared.append(g) } else { r.failed.append((g, out.isEmpty ? "tccutil exited \(code)" : out)) }
        }
        return r
    }
}
