// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TubeMacPlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TubeMacPlayer", path: "Sources/TubeMacPlayer")
    ]
)
