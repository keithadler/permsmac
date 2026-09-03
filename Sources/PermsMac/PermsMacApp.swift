//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  Every permission on this Mac on one screen, in plain English, with what changed since last week.
//  It never changes a permission itself; each row has a button to the exact System Settings pane.

import SwiftUI
import AppKit
import ServiceManagement

@main
struct PermsMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = PermsModel.shared
    init() { CLI.runIfRequested() }

    var body: some Scene {
        WindowGroup("Permissions for Mac") {
            MainView().environmentObject(model)
                .frame(minWidth: 820, idealWidth: 960, minHeight: 520, idealHeight: 640)
                .onAppear { model.start() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Permissions for Mac Help") { Help.open() }
                Button("Check for Updates…") { Updates.checkAndPresent() }
                Divider()
                Button("Open Privacy & Security Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!) }
                Button("Open Login Items Settings") { NSWorkspace.shared.open(Catalog.loginItemsURL) }
            }
            CommandGroup(after: .newItem) { Button("Look Again") { model.refresh() }.keyboardShortcut("r") }
        }
        Settings { SettingsView().environmentObject(model) }
        MenuBarExtra(isInserted: .constant(Prefs.menuBar)) { MenuBarView().environmentObject(model) } label: {
            Image(systemName: model.changes.isEmpty ? "hand.raised" : "hand.raised.fill")
        }
    }
}

enum Section: Hashable { case overview, service(String), startup }

struct MainView: View {
    @EnvironmentObject var model: PermsModel
    @State private var selection: Section?
    init(initial: Section = .overview) { _selection = State(initialValue: initial) }
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Overview", systemImage: "hand.raised").tag(Section.overview)
                SwiftUI.Section("Permissions") {
                    ForEach(model.services, id: \.service.key) { entry in
                        HStack {
                            Circle().fill(tierColor(entry.service.tier)).frame(width: 8, height: 8)
                            Text(entry.service.name)
                            Spacer()
                            Text("\(entry.grants.filter { $0.state != .denied }.count)").foregroundStyle(.secondary).monospacedDigit()
                        }.tag(Section.service(entry.service.key))
                    }
                }
                SwiftUI.Section("Startup") {
                    HStack { Label("Starts without you", systemImage: "power"); Spacer(); Text("\(model.visibleStartup.count)").foregroundStyle(.secondary).monospacedDigit() }.tag(Section.startup)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch selection {
            case .service(let key): ServiceView(service: Catalog.service(key), grants: model.services.first { $0.service.key == key }?.grants ?? [])
            case .startup: StartupView()
            default: OverviewView()
            }
        }
        .toolbar {
            ToolbarItem { Button { model.refresh() } label: { Label("Look Again", systemImage: "arrow.clockwise") }.help("Read the permissions again now") }
        }
    }
}

func tierColor(_ t: Service.Tier) -> Color { t == .high ? .red : t == .medium ? .orange : .secondary }

struct AccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("One permission, so it can show you the rest", systemImage: "lock.open").font(.title3.bold())
            Text("macOS keeps the list of what every app is allowed to do in a file that only apps with Full Disk Access may read. Give Permissions for Mac that access and this window fills in on its own. It reads the file and never changes it; the switches stay in System Settings.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Full Disk Access Settings") { NSWorkspace.shared.open(TCC.fullDiskAccessURL) }.buttonStyle(.borderedProminent)
                Button("Show the App in Finder") { if let u = Bundle.main.bundleURL as URL?, u.pathExtension == "app" { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                Text("Drag the app into the list if it is not there, then turn its switch on.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding().background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct OverviewView: View {
    @EnvironmentObject var model: PermsModel
    @State private var confirmClean = false
    @State private var cleanResult: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.complete { AccessBanner() }
                HStack(spacing: 14) {
                    Stat(number: model.appsWithHigh, label: "apps that can see or control everything", color: .red)
                    Stat(number: model.grants.filter { $0.state != .denied }.count, label: "permissions granted in all", color: .primary)
                    Stat(number: model.visibleStartup.count, label: "things that start without you", color: .primary)
                    Stat(number: model.orphans.count, label: "grants left behind by apps no longer installed", color: model.orphans.isEmpty ? .secondary : .orange)
                }
                HStack {
                    Text("Since").font(.headline)
                    Picker("", selection: $model.sinceDays) { Text("yesterday").tag(1); Text("last week").tag(7); Text("last month").tag(30); Text("three months ago").tag(90) }.labelsHidden().frame(width: 170)
                    Spacer()
                    if let d = model.lastLook { Text("Last looked \(model.relative(d))").font(.caption).foregroundStyle(.secondary) }
                }
                if model.changes.isEmpty {
                    Text(model.records.count < 2 ? "Nothing to compare with yet. Permissions for Mac keeps a small record each time it looks; from the next change on, it shows up here." : "No changes.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) { ForEach(model.changes) { ChangeRow(change: $0) } }
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
                if !model.orphans.isEmpty || cleanResult != nil {
                    HStack {
                        Text("Left behind").font(.headline)
                        Spacer()
                        if !Cleanup.commands(model.orphans).isEmpty { Button("Clean Up…") { confirmClean = true } }
                    }
                    Text("These apps are gone but their permissions are still on the list. Clean Up clears them with Apple's own tccutil, one entry at a time; if one turns out to be a helper of an app you still use, that app simply asks again.").font(.callout).foregroundStyle(.secondary)
                    if let cleanResult { Text(cleanResult).font(.callout) }
                    VStack(spacing: 0) { ForEach(model.orphans) { GrantRow(grant: $0, showService: true) } }
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(20)
        }
        .navigationTitle("Overview")
        .sheet(isPresented: $confirmClean) { CleanupSheet(grants: model.orphans) { r in cleanResult = r.summary.prefix(1).uppercased() + r.summary.dropFirst() + "."; model.refresh(notify: false) } }
        .onChange(of: confirmClean) { _, open in if !open { model.refresh(notify: false) } }
    }
}

struct CleanupSheet: View {
    @Environment(\.dismiss) var dismiss
    let grants: [Grant]
    let done: (CleanupResult) -> Void
    @State private var running = false
    @State private var progress = (0, 0)
    @State private var result: CleanupResult?
    var body: some View {
        let groups = Cleanup.groups(grants)
        let unable = grants.filter { Cleanup.objection($0) != nil }
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                Text(result.summary.prefix(1).uppercased() + result.summary.dropFirst() + ".").font(.title3.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(Set(result.cleared.map(\.client))).sorted(), id: \.self) { Text("cleared  \($0)").font(.system(.caption, design: .monospaced)) }
                        ForEach(result.failed, id: \.0.id) { Text("failed   \($0.0.client): \($0.1)").font(.system(.caption, design: .monospaced)).foregroundStyle(.red) }
                        ForEach(result.skipped, id: \.0.id) { Text("skipped  \($0.0.client): \($0.1)").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 220).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
            } else {
                Text("Clear \(grants.count - unable.count) leftover \(grants.count - unable.count == 1 ? "permission" : "permissions") from \(groups.count) \(groups.count == 1 ? "app" : "apps")?").font(.title3.bold())
                Text("One call to Apple's tccutil per app that no longer exists on disk, about a second each. Nothing else is touched.").font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups, id: \.client) { g in Text("\(Cleanup.command(g.client))   (\(g.grants.map { Catalog.service($0.service).name }.joined(separator: ", ")))").font(.system(.caption, design: .monospaced)) }
                        if !unable.isEmpty {
                            Text("Left as they are:").font(.caption.bold()).padding(.top, 6)
                            ForEach(unable) { g in Text("\(Catalog.service(g.service).name) · \(g.client): \(Cleanup.objection(g) ?? "")").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(height: 220).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    if running { ProgressView(value: Double(progress.0), total: Double(max(progress.1, 1))).frame(width: 200); Text("\(progress.0) of \(progress.1)").font(.caption).monospacedDigit() }
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(running)
                    Button(running ? "Clearing…" : "Clear") { start() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(running || groups.isEmpty)
                }
            }
        }.padding(20).frame(width: 600)
    }
    private func start() {
        running = true; progress = (0, Cleanup.groups(grants).count)
        let grants = grants
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Cleanup.run(grants) { d, t in DispatchQueue.main.async { progress = (d, t) } }
            DispatchQueue.main.async { running = false; result = r; done(r) }
        }
    }
}

struct Stat: View {
    let number: Int, label: String, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number)").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ChangeRow: View {
    let change: Change
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: change.what == .added ? "plus.circle.fill" : change.what == .removed ? "minus.circle" : "arrow.triangle.2.circlepath")
                .foregroundStyle(change.what == .added ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(change.when.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 12).padding(.vertical, 8)
        Divider().padding(.leading, 12)
    }
    var title: String {
        if change.area == .startup {
            let label = (change.after ?? change.before ?? "").split(separator: "|").first.map(String.init) ?? change.key
            return change.what == .added ? "\(label) now starts on its own" : change.what == .removed ? "\(label) no longer starts on its own" : "\(label) changed how it starts"
        }
        let p = History.parts(change.key)
        let app = Apps.resolve(p.client, isPath: p.client.hasPrefix("/")).name
        let s = Catalog.service(p.service).name
        switch change.what {
        case .added: return change.after == "denied" ? "\(app) was refused \(s)" : "\(app) was given \(s)"
        case .removed: return "\(app) no longer has \(s)"
        case .changed: return "\(app): \(s) went from \(change.before ?? "?") to \(change.after ?? "?")"
        }
    }
    var detail: String {
        if change.area == .startup {
            let summary = (change.after ?? change.before ?? "").split(separator: "|").dropFirst().joined(separator: "|")
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return [summary, change.key.hasPrefix(home) ? "~" + change.key.dropFirst(home.count) : change.key].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return Catalog.service(History.parts(change.key).service).means
    }
}

struct ServiceView: View {
    @EnvironmentObject var model: PermsModel
    let service: Service
    let grants: [Grant]
    var body: some View {
        // One ScrollView with the header inside it: a header outside makes the split view's detail
        // column report an enormous ideal height (and blank screenshots).
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(tierColor(service.tier)).frame(width: 10, height: 10)
                        Text(service.name).font(.title2.bold())
                        Spacer()
                        if let url = service.settingsURL { Button("Change in System Settings…") { NSWorkspace.shared.open(url) } }
                    }
                    Text("An app with this can: \(service.means)").fixedSize(horizontal: false, vertical: true)
                    if service.tier == .high { Text("Give this only to apps you would trust with your unlocked Mac.").font(.callout).foregroundStyle(.secondary) }
                }
                VStack(spacing: 0) {
                    ForEach(grants) { g in
                        GrantRow(grant: g, showService: false).padding(.horizontal, 12).padding(.vertical, 6)
                        if g.id != grants.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }.padding(20)
        }
        .navigationTitle(service.name)
    }
}

struct GrantRow: View {
    let grant: Grant
    let showService: Bool
    var body: some View {
        let r = Apps.resolve(grant.client, isPath: grant.clientIsPath)
        let orphan = Apps.isOrphan(grant.client, isPath: grant.clientIsPath)
        HStack(spacing: 10) {
            Image(nsImage: Apps.icon(grant.client, isPath: grant.clientIsPath)).resizable().frame(width: 28, height: 28).opacity(orphan ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(r.name).font(.body)
                    if let t = grant.target { Text("→ \(Apps.resolve(t, isPath: false).name)").foregroundStyle(.secondary) }
                    if orphan { Text("not installed").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(.orange.opacity(0.2), in: Capsule()) }
                }
                Text(showService ? Catalog.service(grant.service).name : grant.client).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(grant.state == .allowed ? "Allowed" : grant.state == .limited ? "Limited" : grant.state == .denied ? "Denied" : "Unknown")
                    .font(.callout.weight(.medium)).foregroundStyle(grant.state == .denied ? .secondary : Color.primary)
                Text([grant.reason?.text, grant.modified.map { PermsModel.shared.relative($0) }].compactMap { $0 }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .help(r.url?.path ?? grant.client)
        .contextMenu {
            if let url = r.url, FileManager.default.fileExists(atPath: url.path) { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            if let s = Catalog.service(grant.service).settingsURL { Button("Change in System Settings…") { NSWorkspace.shared.open(s) } }
            Button("Copy Identifier") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(grant.client, forType: .string) }
        }
    }
}

struct StartupView: View {
    @EnvironmentObject var model: PermsModel
    @State private var showApple = Prefs.showApple
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Starts without you").font(.title2.bold())
                        Spacer()
                        Toggle("Show Apple's own", isOn: $showApple).toggleStyle(.checkbox).onChange(of: showApple) { _, v in Prefs.showApple = v; model.objectWillChange.send() }
                        Button("Login Items Settings…") { NSWorkspace.shared.open(Catalog.loginItemsURL) }
                    }
                    Text("Launch agents and daemons start at login or on a timer, whether or not you open the app that installed them. Most are harmless helpers; the ones you do not recognise are worth a look. Removing one is a Finder job: drag the file to the Trash and log out and in, or use the app's own uninstaller.").fixedSize(horizontal: false, vertical: true).font(.callout).foregroundStyle(.secondary)
                }
                ForEach([StartupItem.Kind.userAgent, .systemAgent, .daemon, .loginHelper], id: \.self) { kind in
                    let items = model.visibleStartup.filter { $0.kind == kind }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.rawValue).font(.headline)
                            VStack(spacing: 0) {
                                ForEach(items) { i in
                                    StartupRow(item: i).padding(.horizontal, 12).padding(.vertical, 6)
                                    if i.id != items.last?.id { Divider().padding(.leading, 46) }
                                }
                            }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                if model.visibleStartup.isEmpty { Text("Nothing starts on its own besides Apple's own helpers.").foregroundStyle(.secondary) }
            }.padding(20)
        }
        .navigationTitle("Startup")
    }
}

struct StartupRow: View {
    let item: StartupItem
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Apps.icon(item.program, isPath: true)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text("\(item.summary) · \(item.program)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .help(item.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
            if FileManager.default.fileExists(atPath: item.program) { Button("Show Program in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.program)]) } }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var model: PermsModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        if model.changes.isEmpty { Text("No changes since \(model.sinceDays == 1 ? "yesterday" : "\(model.sinceDays) days ago")") }
        else { ForEach(model.changes.prefix(8)) { c in Text(ChangeRow(change: c).title) } }
        Divider()
        Text("\(model.appsWithHigh) apps can see or control everything")
        Button("Open Permissions for Mac") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main"); NSApp.windows.first { $0.title == "Permissions for Mac" }?.makeKeyAndOrderFront(nil) }
        Button("Look Again") { model.refresh() }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: PermsModel
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var menuBar = Prefs.menuBar
    @State private var notify = Prefs.notifyNewGrants
    @State private var minutes = Prefs.lookEveryMinutes
    @State private var updates = Updates.enabled
    var body: some View {
        Form {
            Toggle("Open at login", isOn: $login).onChange(of: login) { _, v in if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
            Toggle("Show in the menu bar", isOn: $menuBar).onChange(of: menuBar) { _, v in Prefs.menuBar = v }
            Toggle("Tell me when an app gets a permission that can see or control everything", isOn: $notify).onChange(of: notify) { _, v in Prefs.notifyNewGrants = v; if v { Notify.requestPermissionIfNeeded() } }
            Picker("Look every", selection: $minutes) { Text("minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15); Text("hour").tag(60) }.onChange(of: minutes) { _, v in Prefs.lookEveryMinutes = v; model.start() }
            Toggle("Check for updates daily", isOn: $updates).onChange(of: updates) { _, v in Updates.enabled = v }
            Text("Permissions for Mac reads and never writes. The record of what it saw lives in ~/Library/Application Support/Permissions for Mac.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["PERMSMAC_HOME"] == nil, !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }
        Updates.scheduleBackgroundChecks()
        if Prefs.notifyNewGrants { Notify.requestPermissionIfNeeded() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Prefs.menuBar }
}

enum Help {
    static var pageName: String { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") ? "Help.es" : "Help" }
    static var bundledPage: URL? {
        if let url = Bundle.main.url(forResource: pageName, withExtension: "html") { return url }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let u = Bundle(url: url)?.url(forResource: pageName, withExtension: "html") { return u }
            url = url.deletingLastPathComponent()
        }
        return nil
    }
    @MainActor static func open() { NSWorkspace.shared.open(bundledPage ?? URL(string: "https://github.com/keithadler/permsmac#readme")!) }
}
