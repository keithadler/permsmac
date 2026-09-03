//  Permissions for Mac — MIT licensed. See LICENSE.
import Foundation

enum CatalogSuite {
    static let suite = TestSuite(name: "Catalog", cases: [
        TestCase(name: "known keys have names and sentences") { t in
            let cam = Catalog.service("kTCCServiceCamera")
            t.equal(cam.name, "Camera", "camera name")
            t.check(cam.tier == .high, "camera is high tier")
            t.check(cam.settingsURL?.absoluteString.contains("Privacy_Camera") == true, "camera pane")
            for s in Catalog.services {
                t.check(!s.means.isEmpty && s.means.hasSuffix("."), "\(s.key) has a sentence")
                t.check(s.key.hasPrefix("kTCCService"), "\(s.key) is a TCC key")
            }
            t.equal(Set(Catalog.services.map(\.key)).count, Catalog.services.count, "no duplicate keys")
        },
        TestCase(name: "unknown keys still get a readable name") { t in
            let s = Catalog.service("kTCCServiceFutureThing")
            t.equal(s.name, "Future Thing", "spaced name")
            t.check(s.tier == .low && s.pane == nil, "unknown is low tier without a pane")
            t.equal(Catalog.service("weird").name, "weird", "non-TCC key passes through")
        },
        TestCase(name: "reasons read as sentences") { t in
            t.equal(Reason(rawValue: 2)?.text, "you clicked Allow", "consent")
            t.equal(Reason(rawValue: 6)?.text, "set by a management profile", "mdm")
            t.check(Reason(rawValue: 99) == nil, "unknown reason is nil")
            t.check(Reason.mdmPolicy.fromProfile && Reason.systemSet.fromProfile && !Reason.userConsent.fromProfile, "profile reasons")
        },
        TestCase(name: "CLI finds services by any spelling") { t in
            t.equal(CLI.findService("camera")?.key, "kTCCServiceCamera", "lowercase")
            t.equal(CLI.findService("Screen Recording")?.key, "kTCCServiceScreenCapture", "display name")
            t.equal(CLI.findService("kTCCServiceAccessibility")?.key, "kTCCServiceAccessibility", "raw key")
            t.equal(CLI.findService("fulldiskaccess")?.key, "kTCCServiceSystemPolicyAllFiles", "squashed")
            t.check(CLI.findService("nonsense") == nil, "nonsense is nil")
        },
    ])
}
