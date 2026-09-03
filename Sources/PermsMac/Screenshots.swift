//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  `permsmac screenshots <dir>`: the windows rendered from a demo database, for the README.
//  Nothing here reads the real permissions or history.

import AppKit
import SwiftUI

enum Screenshots {
    @MainActor
    static func render(to dir: URL, announce: Bool) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.activate(ignoringOtherApps: true)
        if app.applicationIconImage.size.width == 0 || Bundle.main.bundleIdentifier == nil, let icon = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/AppIcon.icns") { app.applicationIconImage = icon }
        let tmp = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: tmp) }
        TCC.overrideUser = tmp.appendingPathComponent("user.db"); TCC.overrideSystem = tmp.appendingPathComponent("system.db")
        History.overrideHome = tmp.appendingPathComponent("home"); Startup.overrideRoots = try Demo.startup(in: tmp)
        Apps.demoNames = Demo.names
        Prefs.defaults = UserDefaults(suiteName: "com.keithadler.permsmac.screenshots")!
        defer { TCC.overrideUser = nil; TCC.overrideSystem = nil; History.overrideHome = nil; Startup.overrideRoots = nil; Prefs.defaults = .standard; Apps.demoNames = nil }
        try Demo.write(user: TCC.overrideUser!, system: TCC.overrideSystem!)
        let model = PermsModel.shared
        // Two records a week apart so the overview has changes to show.
        let earlier = TCC.read()
        var records = [Record(date: Date().addingTimeInterval(-8 * 86400), grants: earlier.grants.filter { !Demo.recent.contains($0.client) }, startup: [], complete: true)]
        History.append(Record(grants: earlier.grants, startup: [], complete: true), to: &records); History.save(records)
        model.records = records
        model.refresh(notify: false)

        var written: [URL] = []
        for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
            app.appearance = NSAppearance(named: appearance)
            for (name, section) in [("overview", Section.overview), ("screen-recording", .service("kTCCServiceScreenCapture")), ("camera", .service("kTCCServiceCamera")), ("startup", .startup)] {
                // The panes scroll rather than use List: a SwiftUI List reports an enormous ideal height
                // here and either stretches the window or leaves the visible part blank.
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                w.title = "Permissions for Mac"; w.contentView = NSHostingView(rootView: MainView(initial: section).environmentObject(model).frame(width: 960, height: 640)); w.center(); w.makeKeyAndOrderFront(nil)
                settle(); written.append(try capture(w, to: dir.appendingPathComponent("\(name)\(suffix).png"))); w.orderOut(nil)
            }
        }
        if announce { written += try Promo.render(to: dir, screenshots: dir) }
        return written
    }

    @MainActor static func settle() { let until = Date().addingTimeInterval(0.6); while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) } }

    @MainActor static func capture(_ window: NSWindow, to url: URL) throws -> URL {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { throw NSError(domain: "shots", code: 1) }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let img = fn(.null, 1 << 3 /* optionIncludingWindow */, UInt32(window.windowNumber), 1 << 0 | 1 << 4)?.takeRetainedValue() else { throw NSError(domain: "shots", code: 2) }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "shots", code: 3) }
        try png.write(to: url); return url
    }
}

/// Neutral demo data: Sam Rivera's Mac with a believable mix of apps.
enum Demo {
    static let recent = ["us.zoom.xos", "com.example.meetingbot"]
    static let names = ["us.zoom.xos": "Zoom", "com.example.meetingbot": "MeetingBot", "com.spotify.client": "Spotify", "com.tinyspeck.slackmacgap": "Slack",
                        "com.google.Chrome": "Google Chrome", "com.keithadler.clipmac": "Clip for Mac", "com.keithadler.permsmac": "Permissions for Mac",
                        "com.apple.FaceTime": "FaceTime", "com.apple.mail": "Mail", "com.apple.Preview": "Preview", "com.apple.Terminal": "Terminal", "com.apple.screencaptureui": "Screenshot", "com.apple.finder": "Finder"]
    static func startup(in tmp: URL) throws -> [(URL, StartupItem.Kind)] {
        let agents = tmp.appendingPathComponent("LaunchAgents"), daemons = tmp.appendingPathComponent("LaunchDaemons")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true); try FileManager.default.createDirectory(at: daemons, withIntermediateDirectories: true)
        let items: [(URL, [String: Any])] = [
            (agents.appendingPathComponent("com.google.keystone.agent.plist"), ["Label": "com.google.keystone.agent", "Program": "/Users/sam/Library/Google/GoogleSoftwareUpdate/GoogleSoftwareUpdate.bundle/Contents/MacOS/GoogleSoftwareUpdateAgent", "RunAtLoad": true, "StartInterval": 3600]),
            (agents.appendingPathComponent("us.zoom.ZoomDaemon.plist"), ["Label": "us.zoom.ZoomDaemon", "Program": "/Applications/zoom.us.app/Contents/Frameworks/ZoomDaemon", "RunAtLoad": true, "KeepAlive": true]),
            (agents.appendingPathComponent("com.example.meetingbot.helper.plist"), ["Label": "com.example.meetingbot.helper", "ProgramArguments": ["/Applications/MeetingBot.app/Contents/MacOS/helper", "--background"], "RunAtLoad": true, "KeepAlive": true]),
            (daemons.appendingPathComponent("com.docker.vmnetd.plist"), ["Label": "com.docker.vmnetd", "Program": "/Library/PrivilegedHelperTools/com.docker.vmnetd", "KeepAlive": false]),
            (daemons.appendingPathComponent("com.oldbackup.agent.plist"), ["Label": "com.oldbackup.agent", "Program": "/Library/OldBackup/agent", "RunAtLoad": true, "StartInterval": 900]),
        ]
        // The two startup changes should look like real files, not a temp folder: the demo home is tmp.
        let _: [(URL, [String: Any])] = [
        ]
        for (u, d) in items { try (try PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)).write(to: u) }
        return [(agents, .userAgent), (daemons, .daemon)]
    }
    static func write(user: URL, system: URL) throws {
        let now = Int(Date().timeIntervalSince1970)
        try FakeTCC.write([
            .init(service: "kTCCServiceCamera", client: "us.zoom.xos", modified: now - 3 * 86400),
            .init(service: "kTCCServiceCamera", client: "com.apple.FaceTime", reason: 4, modified: now - 300 * 86400),
            .init(service: "kTCCServiceCamera", client: "com.example.meetingbot", modified: now - 2 * 86400),
            .init(service: "kTCCServiceMicrophone", client: "us.zoom.xos", modified: now - 3 * 86400),
            .init(service: "kTCCServiceMicrophone", client: "com.apple.FaceTime", reason: 4, modified: now - 300 * 86400),
            .init(service: "kTCCServiceMicrophone", client: "com.example.meetingbot", modified: now - 2 * 86400),
            .init(service: "kTCCServiceMicrophone", client: "com.spotify.client", auth: 0, modified: now - 40 * 86400),
            .init(service: "kTCCServiceAddressBook", client: "com.apple.mail", reason: 4, modified: now - 300 * 86400),
            .init(service: "kTCCServiceAddressBook", client: "com.tinyspeck.slackmacgap", modified: now - 90 * 86400),
            .init(service: "kTCCServiceCalendar", client: "us.zoom.xos", modified: now - 3 * 86400),
            .init(service: "kTCCServicePhotos", client: "com.apple.Preview", auth: 3, reason: 3, modified: now - 20 * 86400),
            .init(service: "kTCCServiceAppleEvents", client: "com.apple.Terminal", target: "com.apple.finder", modified: now - 60 * 86400),
            .init(service: "kTCCServiceSystemPolicyDownloadsFolder", client: "com.google.Chrome", modified: now - 100 * 86400),
            .init(service: "kTCCServiceSystemPolicyDesktopFolder", client: "com.apple.Terminal", modified: now - 100 * 86400),
        ], to: user)
        try FakeTCC.write([
            .init(service: "kTCCServiceScreenCapture", client: "us.zoom.xos", modified: now - 3 * 86400),
            .init(service: "kTCCServiceScreenCapture", client: "com.example.meetingbot", modified: now - 2 * 86400),
            .init(service: "kTCCServiceScreenCapture", client: "com.apple.screencaptureui", reason: 4, modified: now - 300 * 86400),
            .init(service: "kTCCServiceAccessibility", client: "com.example.meetingbot", modified: now - 2 * 86400),
            .init(service: "kTCCServiceAccessibility", client: "com.keithadler.clipmac", reason: 3, modified: now - 10 * 86400),
            .init(service: "kTCCServiceSystemPolicyAllFiles", client: "com.apple.Terminal", reason: 3, modified: now - 200 * 86400),
            .init(service: "kTCCServiceSystemPolicyAllFiles", client: "com.keithadler.permsmac", reason: 3, modified: now - 86400),
            .init(service: "kTCCServiceSystemPolicyAllFiles", client: "com.oldbackup.agent", reason: 3, modified: now - 400 * 86400),
            .init(service: "kTCCServiceListenEvent", client: "com.keithadler.clipmac", reason: 3, modified: now - 10 * 86400),
            .init(service: "kTCCServiceDeveloperTool", client: "com.apple.Terminal", reason: 3, modified: now - 200 * 86400),
        ], to: system)
    }
}
