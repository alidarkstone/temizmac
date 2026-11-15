// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cleanstone",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Cleanstone",
            path: "Sources/Cleanstone"
        )
    ]
)
