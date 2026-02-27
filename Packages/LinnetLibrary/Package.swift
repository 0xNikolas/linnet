// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinnetLibrary",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LinnetLibrary", targets: ["LinnetLibrary"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.1"),
    ],
    targets: [
        .target(
            name: "LinnetLibrary",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "LinnetLibraryTests", dependencies: ["LinnetLibrary"]),
    ]
)
