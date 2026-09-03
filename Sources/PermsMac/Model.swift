//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  One object the windows watch. It looks at the permissions database and the startup folders,
//  keeps the history, and tells you when something new appears in a permission that matters.

import Foundation
import AppKit
import UserNotifications
import Combine

enum Prefs {
    static var defaults = UserDefaults.standard
    static var menuBar: Bool { get { defaults.object(forKey: "menuBar") as? Bool ?? true } set { defaults.set(newValue, forKey: "menuBar") } }
    static var notifyNewGrants: Bool { get { defaults.object(forKey: "notifyNewGrants") as? Bool ?? true } set { defaults.set(newValue, forKey: "notifyNewGrants") } }
    static var lookEveryMinutes: Int { get { max(1, defaults.object(forKey: "lookEveryMinutes") as? Int ?? 5) } set { defaults.set(newValue, forKey: "lookEveryMinutes") } }
    static var showApple: Bool { get { defaults.bool(forKey: "showApple") } set { defaults.set(newValue, forKey: "showApple") } }
    static var sinceDays: Int { get { max(1, defaults.object(forKey: "sinceDays") as? Int ?? 7) } set { defaults.set(newValue, forKey: "sinceDays") } }
}

@MainActor
final class PermsModel: ObservableObject {
    static let shared = PermsModel()

    @Published var grants: [Grant] = []
    @Published var startup: [StartupItem] = []
    @Published var complete = false           // both databases readable
    @Published var userReadable = false
    @Published var records: [Record] = []
    @Published var changes: [Change] = []
    @Published var lastLook: Date?
    @Published var sinceDays = Prefs.sinceDays { didSet { Prefs.sinceDays = sinceDays; recomputeChanges() } }
    private var timer: Timer?
    private var waitingForAccess: Timer?

    /// Services present on this Mac, most sensitive first, with their grants.
    var services: [(service: Service, grants: [Grant])] {
        let groups = Dictionary(grouping: grants, by: \.service)
        return groups.map { (Catalog.service($0.key), $0.value.sorted { Apps.resolve($0.client, isPath: $0.clientIsPath).name.localizedCaseInsensitiveCompare(Apps.resolve($1.client, isPath: $1.clientIsPath).name) == .orderedAscending }) }
            .sorted { a, b in a.service.tier != b.service.tier ? a.service.tier > b.service.tier : a.service.name < b.service.name }
    }
    var allowedHigh: [Grant] { grants.filter { $0.state != .denied && Catalog.service($0.service).tier == .high } }
    /// Distinct apps, not grants: one app with camera, mic and screen counts once.
    var appsWithHigh: Int { Set(allowedHigh.map(\.client)).count }
    var orphans: [Grant] { grants.filter { $0.state != .denied && Apps.isOrphan($0.client, isPath: $0.clientIsPath) } }
    var visibleStartup: [StartupItem] { Prefs.showApple ? startup : startup.filter { !Startup.isApple($0) } }

    func refresh(notify: Bool = true) {
        Apps.resetCache()
        let snap = TCC.read()
        grants = snap.grants
        complete = snap.complete
        userReadable = snap.userReadable
        startup = Startup.scan()
        lastLook = Date()
        if records.isEmpty { records = History.load() }
        let previous = records.last
        let record = Record(grants: grants, startup: startup, complete: complete)
        if History.append(record, to: &records) {
            History.save(records)
            if notify, let previous, previous.complete, complete, Prefs.notifyNewGrants {
                let fresh = History.diff(previous, record).filter { $0.area == .permission && $0.what != .removed && $0.after != Grant.State.denied.rawValue && Catalog.service(History.parts($0.key).service).tier == .high }
                for c in fresh { Notify.newGrant(c) }
            }
        }
        recomputeChanges()
        if !complete { waitForAccess() } else { waitingForAccess?.invalidate(); waitingForAccess = nil }
    }

    func recomputeChanges() {
        changes = History.changes(in: records, since: Date().addingTimeInterval(-Double(sinceDays) * 86400))
            .filter { Prefs.showApple || !(History.parts($0.key).client.hasPrefix("com.apple.") || $0.key.contains("/com.apple.")) }
    }

    func start() {
        refresh(notify: false)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(Prefs.lookEveryMinutes) * 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    /// While Full Disk Access is missing, look every two seconds so the window fills in the moment
    /// the switch is flipped.
    private func waitForAccess() {
        guard waitingForAccess == nil else { return }
        waitingForAccess = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in if TCC.hasFullDiskAccess { self?.refresh(notify: false) } }
        }
    }

    func relative(_ d: Date?) -> String {
        guard let d else { return "" }
        if Date().timeIntervalSince(d) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

enum Notify {
    static var enabled: Bool { Bundle.main.bundleIdentifier != nil && ProcessInfo.processInfo.environment["PERMSMAC_HOME"] == nil }
    static func requestPermissionIfNeeded() {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func newGrant(_ c: Change) {
        guard enabled else { return }
        let p = History.parts(c.key)
        let content = UNMutableNotificationContent()
        let app = Apps.resolve(p.client, isPath: p.client.hasPrefix("/")).name
        content.title = "\(app) now has \(Catalog.service(p.service).name)"
        content.body = Catalog.service(p.service).means
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: c.id, content: content, trigger: nil))
    }
}
