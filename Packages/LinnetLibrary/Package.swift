// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinnetLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LinnetLibrary", targets: ["LinnetLibrary"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "LinnetLibrary"),
        .testTarget(name: "LinnetLibraryTests", dependencies: ["LinnetLibrary"]),
    ]
)
