//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  Promo cards for the announcement, 1600×900 at 2×, rendered from the same demo screenshots.

import AppKit
import SwiftUI

enum Promo {
    @MainActor static func render(to dir: URL, screenshots: URL) throws -> [URL] {
        let out = dir.appendingPathComponent("promo"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var written: [URL] = []
        let cards: [(String, String, String, String?)] = [
            ("1-hero", "Every permission on your Mac.\nOne screen. Plain English.", "Camera, microphone, screen, keyboard, files, startup. What each app can do and what changed since last week.", "overview.png"),
            ("2-change", "Zoom was given Screen Recording.\nThursday.", "Permissions for Mac keeps a record each time it looks and tells you when something new appears.", "screen-recording.png"),
            ("3-honest", "It never changes a permission\nfor an app you have.", "One Full Disk Access grant so it can read the list. The switches stay in System Settings, one click away. Leftovers from apps you removed: one click, Apple's own tool.", "camera.png"),
            ("4-free", "Free. Open source. No account.", "MIT licensed, no server, no analytics. Also a real command line: permsmac changes --since 7d", nil),
        ]
        for (name, title, sub, shot) in cards {
            let view = Card(title: title, subtitle: sub, image: shot.flatMap { NSImage(contentsOf: screenshots.appendingPathComponent($0)) })
            let host = NSHostingView(rootView: view); host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false); w.contentView = host; w.orderFront(nil)
            Screenshots.settle()
            let url = out.appendingPathComponent("\(name).png")
            written.append(try Screenshots.capture(w, to: url)); w.orderOut(nil)
        }
        return written
    }

    struct Card: View {
        let title: String, subtitle: String, image: NSImage?
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.32), Color(red: 0.42, green: 0.16, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 12) { Image(systemName: "hand.raised.fill").font(.system(size: 34)); Text("Permissions for Mac").font(.system(size: 30, weight: .semibold)) }.foregroundStyle(.white.opacity(0.85))
                        Text(title).font(.system(size: image == nil ? 64 : 50, weight: .bold, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.system(size: 26)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    }.frame(width: image == nil ? 1300 : 620, alignment: .leading)
                    if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 820).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 30, y: 12) }
                }.padding(80)
            }.frame(width: 1600, height: 900)
        }
    }
}
