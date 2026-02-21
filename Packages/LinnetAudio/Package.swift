// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinnetAudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LinnetAudio", targets: ["LinnetAudio"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "LinnetAudio"),
        .testTarget(name: "LinnetAudioTests", dependencies: ["LinnetAudio"]),
    ]
)
