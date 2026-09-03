//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  The command-line face. Exit codes: 0 fine, 1 something to look at, 2 problem, 64 usage error.

import Foundation
import AppKit

enum CLI {
    static let usage = """
    permsmac — every permission on this Mac, in plain English (command-line face)

    USAGE
      permsmac list [--service <name>] [--all] [--json]   what every app is allowed to do (--all includes denied)
      permsmac changes [--since 7d|30d|24h] [--json]      what changed; exit 1 when something did
      permsmac startup [--apple] [--json]                 launch agents, daemons and login helpers
      permsmac orphans [--json]                           grants left behind by apps no longer installed
      permsmac orphans --commands                         the tccutil lines that would clear them, to run yourself
      permsmac orphans --clean [--json]                   clear them now with Apple's tccutil (only apps that are gone)
      permsmac explain <service>                          what a permission lets an app do
      permsmac open <service|login>                       the System Settings pane for it
      permsmac status [--json]                            can it read the database yet, when it last looked
      permsmac audit <policy.json> [--json]               exit 0 compliant, 1 violations, 2 could not check
      permsmac audit --example                            print a starter policy

    FLEET
      As root (an MDM agent), list/changes/audit read every account under /Users and tag each grant
      with its user; --user <name> limits that. Every JSON document carries host, user, when, version.
      permsmac screenshots <dir> [--announce]             render windows and promo cards from demo data
      permsmac selftest [--filter S] [--list] [--json]
      permsmac help | version

    `orphans --clean` is the one thing that changes anything, and only for apps that no longer exist on
    disk; entries for installed apps and Apple's own are always skipped.
    Reading the permissions database needs Full Disk Access for the process running this command:
    the app after you grant it, or Terminal if you have granted Terminal. Nothing here writes.
    Set PERMSMAC_HOME to keep the history somewhere else (tests do).
    """

    static var version: String {
        if Bundle.main.bundleIdentifier == "com.keithadler.permsmac", let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.permsmac",
               let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let h = env["PERMSMAC_HOME"], !h.isEmpty {     // integration runs: own history, own defaults, own databases
            Prefs.defaults = UserDefaults(suiteName: "com.keithadler.permsmac.test")!
            if let u = env["PERMSMAC_USER_DB"], !u.isEmpty { TCC.overrideUser = URL(fileURLWithPath: u) }
            if let s = env["PERMSMAC_SYSTEM_DB"], !s.isEmpty { TCC.overrideSystem = URL(fileURLWithPath: s) }
        }
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? { guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }; return a[i + 1] }
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []; var skip = false
        for x in a { if skip { skip = false; continue }; if ["--filter", "--service", "--since", "--user"].contains(x) { skip = true; continue }; if x.hasPrefix("--") { continue }; out.append(x) }
        return out
    }

    /// Fleet reads: root sees every account; anyone else sees their own.
    static var isRoot: Bool { geteuid() == 0 }
    static func snapshot(_ args: [String]) -> TCC.Snapshot {
        if isRoot || flag("--all-users", args) { return TCC.readAllUsers(only: value("--user", args)) }
        return TCC.read()
    }
    /// Every JSON document says which Mac, which account, when, and which version wrote it.
    static func envelope(_ body: [String: Any]) -> [String: Any] {
        var d = body
        d["host"] = ProcessInfo.processInfo.hostName; d["user"] = NSUserName(); d["when"] = ISO8601DateFormatter().string(from: Date()); d["version"] = version
        return d
    }
    /// Tests run commands silently.
    static var quiet = false
    static func out(_ s: String) { if !quiet { print(s) } }
    static func err(_ s: String) { if !quiet { fputs(s, stderr) } }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    /// "camera", "Screen Recording", "kTCCServiceCamera" all find the service.
    static func findService(_ s: String) -> Service? {
        let q = s.lowercased().replacingOccurrences(of: " ", with: "")
        return Catalog.services.first { $0.key.lowercased() == q || $0.name.lowercased().replacingOccurrences(of: " ", with: "") == q || $0.key.lowercased().hasSuffix(q) }
    }
    static func since(_ s: String?) -> TimeInterval {
        guard let s, let n = Double(s.dropLast()) else { return 7 * 86400 }
        switch s.last { case "h": return n * 3600; case "d": return n * 86400; case "w": return n * 7 * 86400; default: return 7 * 86400 }
    }
    static func dict(_ g: Grant) -> [String: Any] {
        let r = Apps.resolve(g.client, isPath: g.clientIsPath)
        var d: [String: Any] = ["service": g.service, "name": Catalog.service(g.service).name, "client": g.client, "app": r.name, "state": g.state.rawValue, "scope": g.scope.rawValue, "installed": !Apps.isOrphan(g.client, isPath: g.clientIsPath)]
        if let t = g.target { d["target"] = t }
        if let u = g.user { d["user"] = u }
        if let m = g.modified { d["modified"] = ISO8601DateFormatter().string(from: m) }
        if let re = g.reason { d["reason"] = re.text }
        return d
    }

    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let js = flag("--json", args)
        let pos = positional(args)
        switch cmd {
        case "help", "--help", "-h": out(usage); return 0
        case "version", "--version": out("permsmac \(version)"); return 0

        case "list", "orphans":
            let snap = snapshot(args)
            if !snap.complete && !js { err("note: " + (snap.userReadable ? "the Mac-wide database" : "the permissions database") + " is not readable from here (Full Disk Access). Showing what is.\n") }
            var grants = snap.grants
            if cmd == "orphans" { grants = grants.filter { $0.state != .denied && Apps.isOrphan($0.client, isPath: $0.clientIsPath) } }
            else if !flag("--all", args) { grants = grants.filter { $0.state != .denied } }
            if let s = value("--service", args) {
                guard let svc = findService(s) else { err("unknown permission: \(s)\n"); return 64 }
                grants = grants.filter { $0.service == svc.key }
            }
            if cmd == "orphans" && flag("--commands", args) {
                let c = Cleanup.commands(grants); for l in c { out(l) }
                if c.isEmpty { err("Nothing to clear.\n") }; return c.isEmpty ? 0 : 1
            }
            if cmd == "orphans" && flag("--clean", args) {
                let r = Cleanup.run(grants) { d, t in if !js { err("\(d) of \(t)\r") } }
                if js { out(json(envelope(["cleared": r.cleared.map(dict), "failed": r.failed.map { ["grant": dict($0.0), "error": $0.1] }, "skipped": r.skipped.map { ["grant": dict($0.0), "why": $0.1] }]))) }
                else {
                    for g in r.cleared { out("cleared  \(Catalog.service(g.service).name)  \(g.client)") }
                    for (g, e) in r.failed { out("failed   \(Catalog.service(g.service).name)  \(g.client): \(e)") }
                    for (g, w) in r.skipped { out("skipped  \(Catalog.service(g.service).name)  \(g.client): \(w)") }
                    out(r.summary)
                }
                return r.failed.isEmpty ? 0 : 2
            }
            if js { out(json(envelope(["complete": snap.complete, "grants": grants.map(dict)]))); return cmd == "orphans" && !grants.isEmpty ? 1 : 0 }
            let groups = Dictionary(grouping: grants, by: \.service)
            for (key, gs) in groups.sorted(by: { Catalog.service($0.key).tier != Catalog.service($1.key).tier ? Catalog.service($0.key).tier > Catalog.service($1.key).tier : $0.key < $1.key }) {
                let svc = Catalog.service(key)
                out("\(svc.name)  [\(svc.tier == .high ? "!!" : svc.tier == .medium ? "!" : " ")]  \(svc.means)")
                for g in gs.sorted(by: { $0.client < $1.client }) {
                    let r = Apps.resolve(g.client, isPath: g.clientIsPath)
                    let orphan = Apps.isOrphan(g.client, isPath: g.clientIsPath) ? "  (not installed)" : ""
                    let target = g.target.map { " → \(Apps.resolve($0, isPath: false).name)" } ?? ""
                    out(String(format: "  %-8@ %@%@%@", g.state.rawValue, r.name, target, orphan))
                }
            }
            if grants.isEmpty { out(cmd == "orphans" ? "Nothing left behind." : "No permissions found.") }
            return cmd == "orphans" && !grants.isEmpty ? 1 : 0

        case "changes":
            let snap = snapshot(args); let startup = Startup.scan()
            var records = History.load()
            if History.append(Record(grants: snap.grants, startup: startup, complete: snap.complete), to: &records) { History.save(records) }
            let changes = History.changes(in: records, since: Date().addingTimeInterval(-since(value("--since", args))))
            if js { out(json(envelope(["changes": changes.map { ["area": $0.area.rawValue, "what": $0.what.rawValue, "key": $0.key, "before": $0.before ?? "", "after": $0.after ?? "", "when": ISO8601DateFormatter().string(from: $0.when)] }]))); return changes.isEmpty ? 0 : 1 }
            if changes.isEmpty { out(records.count < 2 ? "Nothing to compare with yet; run again later." : "No changes."); return 0 }
            for c in changes { out("\(c.when.formatted(date: .abbreviated, time: .shortened))  \(ChangeRow(change: c).title)") }
            return 1

        case "startup":
            var items = Startup.scan()
            if !flag("--apple", args) { items = items.filter { !Startup.isApple($0) } }
            if js { out(json(envelope(["items": items.map { ["kind": $0.kind.rawValue, "label": $0.label, "program": $0.program, "path": $0.path, "summary": $0.summary] }]))); return 0 }
            for k in [StartupItem.Kind.userAgent, .systemAgent, .daemon, .loginHelper] {
                let group = items.filter { $0.kind == k }
                if group.isEmpty { continue }
                out(k.rawValue)
                for i in group { out("  \(i.label)  —  \(i.summary)\n      \(i.program)") }
            }
            if items.isEmpty { out("Nothing starts on its own besides Apple's own helpers.") }
            return 0

        case "explain":
            guard let s = pos.first, let svc = findService(s) else { err("which permission? e.g. permsmac explain camera\n"); return 64 }
            out("\(svc.name): an app with this can \(svc.means.prefix(1).lowercased())\(svc.means.dropFirst())")
            return 0

        case "open":
            guard let s = pos.first else { err("which pane? e.g. permsmac open camera, permsmac open login\n"); return 64 }
            if s == "login" { NSWorkspace.shared.open(Catalog.loginItemsURL); return 0 }
            guard let svc = findService(s), let url = svc.settingsURL else { err("no System Settings pane known for \(s)\n"); return 2 }
            NSWorkspace.shared.open(url); return 0

        case "status":
            let snap = snapshot(args); let records = History.load()
            let d: [String: Any] = ["fullDiskAccess": snap.complete, "userDatabase": snap.userReadable, "systemDatabase": snap.systemReadable, "grants": snap.grants.count, "records": records.count,
                                    "lastLook": records.last.map { ISO8601DateFormatter().string(from: $0.date) } ?? "", "root": isRoot]
            if js { out(json(envelope(d))) } else {
                out(snap.complete ? "Full Disk Access: yes" : "Full Disk Access: no (\(snap.userReadable ? "your database reads, the Mac-wide one does not" : "neither database is readable from this process"))")
                out("\(snap.grants.count) grants on record, \(records.count) history records" + (records.last.map { ", last look \($0.date.formatted())" } ?? ""))
            }
            return snap.complete ? 0 : 1

        case "audit":
            if flag("--example", args) { out(Audit.example); return 0 }
            guard let path = pos.first else { err("permsmac audit <policy.json>   (permsmac audit --example prints a starter)\n"); return 64 }
            let policy: Policy
            do { policy = try Audit.load(URL(fileURLWithPath: path)) } catch { err("\(error)\n"); return 64 }
            let snap = snapshot(args)
            guard snap.complete else {
                if js { out(json(envelope(["checked": false, "error": "permissions database not readable (Full Disk Access)", "violations": []]))) }
                else { err("could not check: the permissions database is not readable from this process (Full Disk Access).\n") }
                return 2
            }
            let v = Audit.run(policy, grants: snap.grants, startup: Startup.scan())
            if js { out(json(envelope(["checked": true, "policy": policy.name ?? path, "compliant": v.isEmpty, "grants": snap.grants.count, "violations": v.map(\.dict)]))) }
            else {
                for x in v { out("\(x.user.map { "\($0): " } ?? "")\(x.service == "startup" ? "Startup" : Catalog.service(x.service).name)  \(x.client)  —  \(x.why)") }
                out(v.isEmpty ? "Compliant with \(policy.name ?? path): \(snap.grants.count) grants checked." : "\(v.count) violation\(v.count == 1 ? "" : "s").")
            }
            return v.isEmpty ? 0 : 1

        case "screenshots":
            guard let dir = pos.first else { err("permsmac screenshots <dir>\n"); return 64 }
            do {
                let files = try MainActor.assumeIsolated { try Screenshots.render(to: URL(fileURLWithPath: dir), announce: flag("--announce", args)) }
                for f in files { out(f.path) }; return 0
            } catch { err("screenshots failed: \(error)\n"); return 2 }

        case "selftest":
            if flag("--list", args) { TestKit.list(); return 0 }
            let results = MainActor.assumeIsolated { TestKit.run(filter: value("--filter", args)) }
            return TestKit.report(results, json: js)

        default: err("unknown command \(cmd)\n\(usage)\n"); return 64
        }
    }
}
