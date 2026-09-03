//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  The one thing this app changes, and only when asked: permissions left behind by apps that no
//  longer exist on disk. It uses Apple's own `tccutil reset All <bundle-id>`, the same thing the
//  "−" button in System Settings does. It refuses to touch an entry for an app that is still
//  installed, so the promise stays: it never changes a permission for an app you have.
//
//  One wrinkle: tccutil asks Launch Services whether the bundle identifier exists before it does
//  anything, and for an app that is gone the answer is no (error -10814). So for each app this makes
//  an empty placeholder bundle with that identifier inside its own Application Support folder,
//  registers it for the length of one tccutil call, then unregisters and deletes it. The placeholder
//  has no code of its own (its executable is a copy of /usr/bin/true) and never leaves that folder.

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

    /// Registers or unregisters a bundle with Launch Services. Tests replace this.
    static var register: (URL, Bool) -> Int32 = { url, on in
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        p.arguments = [on ? "-f" : "-u", url.path]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 127 }
        p.waitUntilExit(); return p.terminationStatus
    }

    static var placeholderRoot: URL { History.home.appendingPathComponent("placeholder", isDirectory: true) }

    /// An empty app bundle carrying `client` as its identifier, so tccutil accepts the name.
    static func makePlaceholder(_ client: String) throws -> URL {
        let dir = placeholderRoot.appendingPathComponent(client, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let app = dir.appendingPathComponent("Placeholder.app", isDirectory: true)
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("Placeholder"))
        let plist: [String: Any] = ["CFBundleIdentifier": client, "CFBundleName": "Placeholder", "CFBundleExecutable": "Placeholder", "CFBundlePackageType": "APPL",
                                    "CFBundleShortVersionString": "0", "CFBundleVersion": "0", "LSUIElement": true]
        try (try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    static func removePlaceholder(_ client: String) {
        try? FileManager.default.removeItem(at: placeholderRoot.appendingPathComponent(client, isDirectory: true))
        if (try? FileManager.default.contentsOfDirectory(atPath: placeholderRoot.path))?.isEmpty == true { try? FileManager.default.removeItem(at: placeholderRoot) }
    }

    /// Runs one reset per app. Safe to call off the main thread; `progress` is called after each app.
    static func run(_ grants: [Grant], progress: ((Int, Int) -> Void)? = nil) -> CleanupResult {
        var r = CleanupResult()
        r.skipped = grants.compactMap { g in objection(g).map { (g, $0) } }
        let gs = groups(grants)
        for (i, group) in gs.enumerated() {
            defer { progress?(i + 1, gs.count) }
            let app: URL
            do { app = try makePlaceholder(group.client) } catch { r.failed += group.grants.map { ($0, "could not make the placeholder: \(error.localizedDescription)") }; continue }
            defer { _ = register(app, false); removePlaceholder(group.client) }
            guard register(app, true) == 0 else { r.failed += group.grants.map { ($0, "Launch Services would not register the placeholder") }; continue }
            let (code, out) = runner(["reset", "All", group.client])
            if code == 0 { r.cleared += group.grants } else { r.failed += group.grants.map { ($0, out.isEmpty ? "tccutil exited \(code)" : out) } }
        }
        Apps.resetCache()
        return r
    }
}
