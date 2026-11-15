// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magicstone",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Magicstone",
            path: "Sources/Magicstone"
        )
    ]
)
