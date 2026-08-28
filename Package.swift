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
        ),
        .testTarget(
            name: "ExeDockTests",
            dependencies: ["ExeDock"],
            path: "Tests/ExeDockTests",
            // This machine only has Command Line Tools, not Xcode.app - neither XCTest.framework
            // nor Swift Testing's runtime support are wired up automatically the way Xcode wires
            // them. The plugin flag makes @Test/#expect compile; the rpath makes the built test
            // binary able to find Testing.framework at run time (a plain DYLD_FRAMEWORK_PATH env
            // var gets silently stripped for this helper process, so it has to be baked in here).
            swiftSettings: [
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ]
)
