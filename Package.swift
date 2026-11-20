// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DockPeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DockPeek",
            path: "Sources/DockPeek",
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))]
        )
    ]
)
