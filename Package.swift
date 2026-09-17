// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuietDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuietDesk",
            path: "Sources/QuietDesk",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "QuietDeskTests",
            dependencies: ["QuietDesk"],
            path: "Tests/QuietDeskTests"
        ),
    ]
)
