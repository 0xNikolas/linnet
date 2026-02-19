// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinnetAI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LinnetAI", targets: ["LinnetAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.6"),
    ],
    targets: [
        .target(
            name: "LinnetAI",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),
        .testTarget(name: "LinnetAITests", dependencies: ["LinnetAI"]),
    ]
)
