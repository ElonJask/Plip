// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CraftAudio",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CraftAudioCore",
            path: "Sources/CraftAudioCore"
        ),
        .executableTarget(
            name: "CraftAudio",
            dependencies: ["CraftAudioCore"],
            path: "Sources/CraftAudio"
        ),
        .testTarget(
            name: "CraftAudioTests",
            dependencies: ["CraftAudioCore"],
            path: "Tests/CraftAudioTests"
        )
    ]
)
