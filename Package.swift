// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceApp",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(name: "VoiceApp", targets: ["VoiceApp"])
    ],
    dependencies: [
        .package(path: "Packages/mlx-audio-ios"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .target(
            name: "VoiceApp",
            dependencies: [
                .product(name: "MLXAudio", package: "mlx-audio-ios"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "VoiceApp",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        )
    ]
)
