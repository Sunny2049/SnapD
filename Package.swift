// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SnapD",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SnapD", path: "Sources/SnapD", linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("Vision"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("ImageIO"),
        ])
    ]
)
