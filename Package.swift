// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TemizMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TemizMac",
            path: "Sources/TemizMac"
        )
    ]
)
