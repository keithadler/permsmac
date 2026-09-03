//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  `permsmac audit policy.json`: does this Mac comply with a written policy about who may hold the
//  permissions that matter? Exit 0 when it does, 1 when it does not, 2 when it could not be checked.
//  Written for MDM scripts: a Jamf extension attribute or a JumpCloud command runs it daily and the
//  exit code and JSON go wherever the fleet's evidence goes.

import Foundation

struct Policy: Codable {
    struct Rule: Codable {
        var service: String          // "Screen Recording", "ScreenCapture" or "kTCCServiceScreenCapture"
        var allow: [String]          // bundle-id or path globs: "us.zoom.xos", "com.apple.*", "/usr/local/bin/*"
        var note: String?
    }
    struct StartupRule: Codable { var allow: [String] }
    var rules: [Rule]
    var startup: StartupRule?
    var denyOrphans: Bool?
    var name: String?
}

struct Violation: Hashable {
    let user: String?
    let service: String      // catalog key, or "startup"
    let client: String
    let why: String
    var dict: [String: Any] {
        var d: [String: Any] = ["service": service, "name": service == "startup" ? "Startup" : Catalog.service(service).name, "client": client, "why": why]
        if let user { d["user"] = user }
        return d
    }
}

enum Audit {
    enum PolicyError: Error, CustomStringConvertible {
        case unreadable(String), unknownService(String)
        var description: String { switch self { case .unreadable(let s): return "cannot read policy: \(s)"; case .unknownService(let s): return "policy names an unknown permission: \(s)" } }
    }

    static func load(_ url: URL) throws -> Policy {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw PolicyError.unreadable(error.localizedDescription) }
        let p: Policy
        do { p = try JSONDecoder().decode(Policy.self, from: data) } catch { throw PolicyError.unreadable("\(error)") }
        for r in p.rules where serviceKey(r.service) == nil { throw PolicyError.unknownService(r.service) }
        return p
    }

    static func serviceKey(_ s: String) -> String? {
        if let svc = CLI.findService(s) { return svc.key }
        if s.hasPrefix("kTCCService") { return s }
        return nil
    }

    /// Glob match on the client, case-insensitive: "com.apple.*", "/Applications/*", "*".
    static func matches(_ pattern: String, _ client: String) -> Bool {
        fnmatch(pattern.lowercased(), client.lowercased(), 0) == 0
    }

    static func run(_ policy: Policy, grants: [Grant], startup: [StartupItem]) -> [Violation] {
        var out: [Violation] = []
        for rule in policy.rules {
            guard let key = serviceKey(rule.service) else { continue }
            for g in grants where g.service == key && g.state != .denied {
                if !rule.allow.contains(where: { matches($0, g.client) }) {
                    out.append(Violation(user: g.user, service: key, client: g.client, why: "not in the allow list for \(Catalog.service(key).name)" + (rule.note.map { " (\($0))" } ?? "")))
                }
            }
        }
        if policy.denyOrphans == true {
            for g in grants where g.state != .denied && Apps.isOrphan(g.client, isPath: g.clientIsPath) && !g.client.hasPrefix("com.apple.") {
                out.append(Violation(user: g.user, service: g.service, client: g.client, why: "app no longer installed"))
            }
        }
        if let sr = policy.startup {
            for i in startup where !sr.allow.contains(where: { matches($0, i.label) || matches($0, i.program) }) {
                out.append(Violation(user: nil, service: "startup", client: i.label, why: "starts without the user and is not in the allow list (\(i.path))"))
            }
        }
        return Array(Set(out)).sorted { ($0.service, $0.client, $0.user ?? "") < ($1.service, $1.client, $1.user ?? "") }
    }

    static let example = """
    {
      "name": "Example endpoint policy",
      "rules": [
        { "service": "Screen Recording", "allow": ["com.apple.*", "us.zoom.xos", "com.microsoft.teams2"], "note": "approved meeting tools only" },
        { "service": "Accessibility",    "allow": ["com.apple.*", "com.jamf.*", "com.1password.*"] },
        { "service": "Full Disk Access", "allow": ["com.apple.*", "com.jamf.*", "com.crowdstrike.*", "/Library/PrivilegedHelperTools/*"] },
        { "service": "Input Monitoring", "allow": ["com.apple.*"] },
        { "service": "Microphone",       "allow": ["com.apple.*", "us.zoom.xos", "com.microsoft.teams2", "com.tinyspeck.slackmacgap"] }
      ],
      "startup": { "allow": ["com.apple.*", "com.jamf.*", "com.crowdstrike.*", "com.google.keystone.*", "com.microsoft.*"] },
      "denyOrphans": true
    }
    """
}
