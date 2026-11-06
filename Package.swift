// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EyeTimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EyeTimer",
            path: "Sources/EyeTimer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
