//  Permissions for Mac — MIT licensed. See LICENSE.
//
//  What each macOS permission actually lets an app do, in one sentence a person can act on, plus
//  where Apple hid the switch. Keys are the service names macOS stores in its permissions database
//  (TCC). Anything not listed still shows up, with its raw name, so nothing is silently dropped.

import Foundation

struct Service: Hashable, Identifiable {
    enum Tier: Int, Comparable { case low = 0, medium, high; static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue } }
    let key: String            // kTCCServiceCamera
    let name: String           // Camera
    let means: String          // "See through the camera whenever it wants, not only when you click record."
    let tier: Tier
    let pane: String?          // Privacy_Camera → System Settings anchor
    var id: String { key }
    var settingsURL: URL? { pane.map { URL(string: "x-apple.systempreferences:com.apple.preference.security?\($0)")! } }
}

enum Catalog {
    static let services: [Service] = [
        Service(key: "kTCCServiceScreenCapture", name: "Screen Recording", means: "Read everything on your screen, including passwords and messages as you type them.", tier: .high, pane: "Privacy_ScreenCapture"),
        Service(key: "kTCCServiceAccessibility", name: "Accessibility", means: "Control the Mac like a person at the keyboard: press keys, click, and read any window.", tier: .high, pane: "Privacy_Accessibility"),
        Service(key: "kTCCServiceSystemPolicyAllFiles", name: "Full Disk Access", means: "Open every file on the Mac, including Mail, Messages, Safari history and other apps' data.", tier: .high, pane: "Privacy_AllFiles"),
        Service(key: "kTCCServiceListenEvent", name: "Input Monitoring", means: "See every key you press and every mouse move, in every app.", tier: .high, pane: "Privacy_ListenEvent"),
        Service(key: "kTCCServicePostEvent", name: "Send Keystrokes", means: "Type and click on your behalf.", tier: .high, pane: "Privacy_Accessibility"),
        Service(key: "kTCCServiceCamera", name: "Camera", means: "Use the camera whenever it wants, not only when you press record.", tier: .high, pane: "Privacy_Camera"),
        Service(key: "kTCCServiceMicrophone", name: "Microphone", means: "Listen through the microphone whenever it is running.", tier: .high, pane: "Privacy_Microphone"),
        Service(key: "kTCCServiceAudioCapture", name: "System Audio Recording", means: "Record whatever the Mac is playing: calls, videos, music.", tier: .high, pane: "Privacy_AudioCapture"),
        Service(key: "kTCCServiceAppleEvents", name: "Automation", means: "Drive another app by remote control, with that app's own permissions.", tier: .medium, pane: "Privacy_Automation"),
        Service(key: "kTCCServiceDeveloperTool", name: "Developer Tools", means: "Run software that does not meet the Mac's usual security checks.", tier: .medium, pane: "Privacy_DevTools"),
        Service(key: "kTCCServiceEndpointSecurityClient", name: "Endpoint Security", means: "Watch every process and file on the Mac, the way security software does.", tier: .high, pane: nil),
        Service(key: "kTCCServiceSystemPolicySysAdminFiles", name: "Administrator Files", means: "Read and change system files that are normally off limits.", tier: .high, pane: nil),
        Service(key: "kTCCServiceAddressBook", name: "Contacts", means: "Read everyone in your Contacts: names, numbers, emails, addresses.", tier: .medium, pane: "Privacy_Contacts"),
        Service(key: "kTCCServiceContactsFull", name: "Contacts (full)", means: "Read everyone in your Contacts: names, numbers, emails, addresses.", tier: .medium, pane: "Privacy_Contacts"),
        Service(key: "kTCCServiceContactsLimited", name: "Contacts (limited)", means: "Read the contacts you chose to share, and no others.", tier: .low, pane: "Privacy_Contacts"),
        Service(key: "kTCCServiceCalendar", name: "Calendars", means: "Read and change your calendar events.", tier: .medium, pane: "Privacy_Calendars"),
        Service(key: "kTCCServiceReminders", name: "Reminders", means: "Read and change your reminders.", tier: .low, pane: "Privacy_Reminders"),
        Service(key: "kTCCServicePhotos", name: "Photos", means: "Read your whole photo library, including locations and faces.", tier: .medium, pane: "Privacy_Photos"),
        Service(key: "kTCCServicePhotosAdd", name: "Photos (add only)", means: "Add pictures to your library without seeing what is already there.", tier: .low, pane: "Privacy_Photos"),
        Service(key: "kTCCServiceMediaLibrary", name: "Music and Apple TV", means: "Read your music and video library and what you play.", tier: .low, pane: "Privacy_Media"),
        Service(key: "kTCCServiceSpeechRecognition", name: "Speech Recognition", means: "Send your voice to Apple to turn it into text.", tier: .medium, pane: "Privacy_SpeechRecognition"),
        Service(key: "kTCCServiceBluetoothAlways", name: "Bluetooth", means: "Talk to nearby Bluetooth devices, which can also reveal where you are.", tier: .low, pane: "Privacy_Bluetooth"),
        Service(key: "kTCCServiceWillow", name: "Home", means: "Control your HomeKit devices: locks, lights, cameras.", tier: .medium, pane: "Privacy_HomeKit"),
        Service(key: "kTCCServiceMotion", name: "Motion and Fitness", means: "Read the Mac's motion sensors.", tier: .low, pane: "Privacy_Motion"),
        Service(key: "kTCCServiceFocusStatus", name: "Focus Status", means: "Know when you have a Focus on, like Do Not Disturb.", tier: .low, pane: "Privacy_Focus"),
        Service(key: "kTCCServiceUserAvailability", name: "Availability", means: "Know when you are busy or free.", tier: .low, pane: nil),
        Service(key: "kTCCServiceSiri", name: "Siri", means: "Handle requests you make through Siri.", tier: .low, pane: nil),
        Service(key: "kTCCServiceUbiquity", name: "iCloud Drive", means: "Read and write files in your iCloud Drive.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyDesktopFolder", name: "Desktop Folder", means: "Read and change files on your Desktop.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyDocumentsFolder", name: "Documents Folder", means: "Read and change files in Documents.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyDownloadsFolder", name: "Downloads Folder", means: "Read and change files in Downloads.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyRemovableVolumes", name: "External Drives", means: "Read and change files on USB drives and SD cards.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyNetworkVolumes", name: "Network Drives", means: "Read and change files on network shares.", tier: .medium, pane: "Privacy_FilesAndFolders"),
        Service(key: "kTCCServiceSystemPolicyAppBundles", name: "App Management", means: "Change other apps on the Mac, including replacing them.", tier: .high, pane: "Privacy_AppBundles"),
        Service(key: "kTCCServiceSystemPolicyAppData", name: "App Data", means: "Read other apps' private data.", tier: .high, pane: nil),
        Service(key: "kTCCServiceFileProviderDomain", name: "File Provider", means: "Appear as a folder in Finder, like a cloud drive does.", tier: .low, pane: nil),
        Service(key: "kTCCServiceFileProviderPresence", name: "Files Presence", means: "Know which of its files you have open.", tier: .low, pane: nil),
        Service(key: "kTCCServiceUserTracking", name: "Tracking", means: "Follow you across other companies' apps and websites for advertising.", tier: .medium, pane: nil),
        Service(key: "kTCCServiceWebBrowserPublicKeyCredential", name: "Passkeys", means: "Use your passkeys to sign in to websites.", tier: .medium, pane: nil),
        Service(key: "kTCCServiceLiverpool", name: "Location", means: "Know where the Mac is.", tier: .medium, pane: "Privacy_LocationServices"),
        Service(key: "kTCCServiceCalendarFull", name: "Calendars (full)", means: "Read and change your calendar events.", tier: .medium, pane: "Privacy_Calendars"),
        Service(key: "kTCCServiceCalendarLimited", name: "Calendars (add only)", means: "Add events without reading the ones you have.", tier: .low, pane: "Privacy_Calendars"),
        Service(key: "kTCCServicePrototype3Rights", name: "Voice Memos (legacy)", means: "A permission left over from an older macOS.", tier: .low, pane: nil),
        Service(key: "kTCCServiceLocalNetwork", name: "Local Network", means: "Find and talk to other devices on your Wi-Fi.", tier: .low, pane: "Privacy_LocalNetwork"),
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: services.map { ($0.key, $0) })

    /// Never returns nil: unknown keys become a readable name from the key itself.
    static func service(_ key: String) -> Service {
        if let s = byKey[key] { return s }
        var name = key.hasPrefix("kTCCService") ? String(key.dropFirst("kTCCService".count)) : key
        name = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return Service(key: key, name: name, means: "A permission this version of Permissions for Mac does not have a description for yet.", tier: .low, pane: nil)
    }

    /// Services shown with "watch" on: a new grant here gets a notification.
    static var watched: [Service] { services.filter { $0.tier == .high } }

    static let loginItemsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
    static let profilesURL = URL(string: "x-apple.systempreferences:com.apple.Profiles-Settings.extension")!
}

/// Why the permissions database says a grant exists. Numbers from Apple's tccd.
enum Reason: Int {
    case error = 1, userConsent = 2, userSet = 3, systemSet = 4, servicePolicy = 5, mdmPolicy = 6, overridePolicy = 7, missingUsageString = 8, promptTimeout = 9, preflightUnknown = 10, entitled = 11, appTypePolicy = 12
    /// Set by a profile or by macOS itself: System Settings will not let a person remove these.
    var fromProfile: Bool { [.systemSet, .mdmPolicy, .overridePolicy].contains(self) }
    var text: String {
        switch self {
        case .userConsent: return "you clicked Allow"
        case .userSet: return "set in System Settings"
        case .systemSet: return "set by macOS"
        case .servicePolicy, .appTypePolicy: return "set by policy"
        case .mdmPolicy, .overridePolicy: return "set by a management profile"
        case .entitled: return "Apple entitlement"
        case .missingUsageString: return "app never explained why"
        case .promptTimeout: return "prompt timed out"
        case .error, .preflightUnknown: return "unclear"
        }
    }
}
