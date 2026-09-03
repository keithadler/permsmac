//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum HistorySuite {
    static func grant(_ s: String, _ c: String, _ st: Grant.State = .allowed, scope: Grant.Scope = .user) -> Grant {
        Grant(service: s, client: c, clientIsPath: false, state: st, reason: .userConsent, target: nil, modified: nil, scope: scope)
    }
    static func item(_ label: String, runAtLoad: Bool = true) -> StartupItem {
        StartupItem(kind: .userAgent, label: label, program: "/usr/bin/true", path: "/tmp/\(label).plist", runAtLoad: runAtLoad, keepAlive: false, interval: nil, disabled: false)
    }
    static let suite = TestSuite(name: "History", cases: [
        TestCase(name: "diff finds added, removed and changed") { t in
            let a = Record(date: Date(timeIntervalSince1970: 1000), grants: [grant("kTCCServiceCamera", "a"), grant("kTCCServiceMicrophone", "a"), grant("kTCCServicePhotos", "b", .denied)], startup: [item("x")], complete: true)
            let b = Record(date: Date(timeIntervalSince1970: 2000), grants: [grant("kTCCServiceCamera", "a"), grant("kTCCServiceScreenCapture", "c", scope: .system), grant("kTCCServicePhotos", "b", .allowed)], startup: [item("x", runAtLoad: false), item("y")], complete: true)
            let d = History.diff(a, b)
            t.equal(d.filter { $0.area == .permission && $0.what == .added }.map(\.key), ["system|kTCCServiceScreenCapture|c|"], "added")
            t.equal(d.filter { $0.area == .permission && $0.what == .removed }.map(\.key), ["user|kTCCServiceMicrophone|a|"], "removed")
            t.equal(d.filter { $0.area == .permission && $0.what == .changed }.first?.after, "allowed", "changed")
            t.equal(d.filter { $0.area == .startup && $0.what == .added }.map(\.key), ["/tmp/y.plist"], "startup added")
            t.equal(d.filter { $0.area == .startup && $0.what == .changed }.count, 1, "startup changed")
            t.check(d.allSatisfy { $0.when == b.date }, "changes dated by the newer record")
        },
        TestCase(name: "partial reads never look like mass removal") { t in
            let full = Record(date: Date(timeIntervalSince1970: 1000), grants: [grant("kTCCServiceCamera", "a"), grant("kTCCServiceScreenCapture", "a", scope: .system)], startup: [], complete: true)
            let partial = Record(date: Date(timeIntervalSince1970: 2000), grants: [grant("kTCCServiceCamera", "a")], startup: [], complete: false)
            t.equal(History.diff(full, partial).count, 0, "no permission changes across a partial read")
            t.equal(History.diff(partial, full).count, 0, "nor the other way")
        },
        TestCase(name: "append skips identical looks within a day") { t in
            var records: [Record] = []
            let r1 = Record(date: Date(timeIntervalSince1970: 0), grants: [grant("kTCCServiceCamera", "a")], startup: [], complete: true)
            t.check(History.append(r1, to: &records), "first is kept")
            t.check(!History.append(Record(date: Date(timeIntervalSince1970: 100), grants: [grant("kTCCServiceCamera", "a")], startup: [], complete: true), to: &records), "same again is skipped")
            t.check(History.append(Record(date: Date(timeIntervalSince1970: 90_000), grants: [grant("kTCCServiceCamera", "a")], startup: [], complete: true), to: &records), "a day later is kept")
            t.check(History.append(Record(date: Date(timeIntervalSince1970: 90_001), grants: [], startup: [], complete: true), to: &records), "a difference is kept")
            t.equal(records.count, 3, "three records")
        },
        TestCase(name: "changes since a date span every pair") { t in
            let d = { (s: Double) in Date(timeIntervalSince1970: s) }
            let records = [
                Record(date: d(0), grants: [], startup: [], complete: true),
                Record(date: d(100), grants: [grant("kTCCServiceCamera", "a")], startup: [], complete: true),
                Record(date: d(200), grants: [], startup: [], complete: true),
                Record(date: d(300), grants: [grant("kTCCServiceMicrophone", "b")], startup: [], complete: true),
            ]
            let all = History.changes(in: records, since: d(0))
            t.equal(all.count, 3, "camera added, camera removed, mic added")
            t.equal(History.changes(in: records, since: d(200)).count, 1, "since 200 only the mic")
            t.equal(History.changes(in: records, since: d(250)).count, 1, "since between records rounds down")
            t.equal(History.changes(in: [records[0]], since: d(0)).count, 0, "one record: nothing")
        },
        TestCase(name: "saves and loads through the home folder") { t in
            var records: [Record] = []
            History.append(Record(date: Date(timeIntervalSince1970: 1_700_000_000), grants: [grant("kTCCServiceCamera", "a")], startup: [item("x")], complete: true), to: &records)
            History.save(records)
            t.check(History.file.path.hasPrefix(History.overrideHome!.path), "file under the test home")
            let back = History.load()
            t.equal(back.count, 1, "one back")
            t.equal(back.first?.grants, records.first?.grants, "grants round-trip")
            t.equal(back.first?.startup, records.first?.startup, "startup round-trip")
            t.equal(back.first?.date, records.first?.date, "date round-trip")
            t.check(History.load().count == 1, "idempotent")
        },
        TestCase(name: "keeps only the newest records") { t in
            var records = (0..<(History.keep + 50)).map { Record(date: Date(timeIntervalSince1970: Double($0) * 90_000), grants: [grant("kTCCServiceCamera", "\($0)")], startup: [], complete: true) }
            History.save(records); records = History.load()
            t.equal(records.count, History.keep, "trimmed")
            t.equal(records.last?.grants.keys.first, "user|kTCCServiceCamera|\(History.keep + 49)|", "newest kept")
        },
        TestCase(name: "keys split back into parts") { t in
            let p = History.parts("system|kTCCServiceAppleEvents|com.example.a|com.apple.finder")
            t.equal(p.scope, "system", "scope"); t.equal(p.service, "kTCCServiceAppleEvents", "service"); t.equal(p.client, "com.example.a", "client"); t.equal(p.target, "com.apple.finder", "target")
            t.check(History.parts("user|kTCCServiceCamera|a|").target == nil, "empty target is nil")
        },
    ])
}
