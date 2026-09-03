//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  Things that start without you: launch agents (per user and for every user), launch daemons
//  (root, at boot), and helper apps bundled inside applications for the older login-item API.
//  All of these are plain files anyone can read, so this needs no permission.

import Foundation

struct StartupItem: Hashable, Identifiable {
    enum Kind: String { case userAgent = "Launch agent (you)", systemAgent = "Launch agent (all users)", daemon = "Launch daemon (root)", loginHelper = "Login item helper" }
    let kind: Kind
    let label: String
    let program: String
    let path: String        // the plist or helper bundle
    let runAtLoad: Bool
    let keepAlive: Bool
    let interval: Int?      // seconds, StartInterval
    let disabled: Bool
    var id: String { path }
    var owner: String { Apps.resolve(program, isPath: true).name }
    var summary: String {
        var bits: [String] = []
        if runAtLoad { bits.append("starts at login") }
        if keepAlive { bits.append("restarts if it stops") }
        if let interval { bits.append(interval >= 3600 ? "every \(interval / 3600) h" : "every \(max(interval / 60, 1)) min") }
        if disabled { bits.append("disabled") }
        return bits.isEmpty ? "starts when something asks for it" : bits.joined(separator: ", ")
    }
}

enum Startup {
    static var roots: [(URL, StartupItem.Kind)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [(home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
                (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
                (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon)]
    }
    static var overrideRoots: [(URL, StartupItem.Kind)]?
    static var appFolders: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]

    static func scan() -> [StartupItem] {
        var out: [StartupItem] = []
        for (dir, kind) in overrideRoots ?? roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names.sorted() where n.hasSuffix(".plist") {
                if let item = parse(dir.appendingPathComponent(n), kind: kind) { out.append(item) }
            }
        }
        if overrideRoots == nil { out += loginHelpers() }
        return out
    }

    static func parse(_ url: URL, kind: StartupItem.Kind) -> StartupItem? {
        guard let data = try? Data(contentsOf: url), let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let label = p["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        var program = p["Program"] as? String ?? (p["ProgramArguments"] as? [String])?.first ?? ""
        if program.isEmpty, let bundle = p["BundleProgram"] as? String { program = bundle }
        let keepAlive: Bool = (p["KeepAlive"] as? Bool) ?? ((p["KeepAlive"] as? [String: Any]).map { !$0.isEmpty } ?? false)
        return StartupItem(kind: kind, label: label, program: program, path: url.path,
                           runAtLoad: p["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive,
                           interval: p["StartInterval"] as? Int, disabled: p["Disabled"] as? Bool ?? false)
    }

    /// Apps that ship a helper in Contents/Library/LoginItems use the older login-item API; the
    /// helper starts at login if the app ever turned it on.
    static func loginHelpers() -> [StartupItem] {
        var out: [StartupItem] = []
        for folder in appFolders {
            guard let apps = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for a in apps where a.hasSuffix(".app") {
                let dir = folder.appendingPathComponent(a).appendingPathComponent("Contents/Library/LoginItems")
                guard let helpers = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
                for h in helpers where h.hasSuffix(".app") {
                    let hp = dir.appendingPathComponent(h)
                    let bid = Bundle(url: hp)?.bundleIdentifier ?? h
                    out.append(StartupItem(kind: .loginHelper, label: bid, program: folder.appendingPathComponent(a).path, path: hp.path, runAtLoad: true, keepAlive: false, interval: nil, disabled: false))
                }
            }
        }
        return out
    }

    /// Apple's own agents are not interesting to most people; they can be shown with a toggle.
    static func isApple(_ item: StartupItem) -> Bool { item.label.hasPrefix("com.apple.") }
}
