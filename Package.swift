// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PermsMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PermsMac", path: "Sources/PermsMac", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "PermsMacTests", dependencies: ["PermsMac"], path: "Tests/PermsMacTests"),
    ]
)
