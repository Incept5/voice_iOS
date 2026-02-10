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
        .package(path: "Packages/mlx-audio-ios")
    ],
    targets: [
        .target(
            name: "VoiceApp",
            dependencies: [
                .product(name: "MLXAudio", package: "mlx-audio-ios")
            ],
            path: "VoiceApp",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        )
    ]
)
