// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ExeDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ExeDock",
            path: "Sources/ExeDock",
            exclude: ["Resources"]
        )
    ]
)
