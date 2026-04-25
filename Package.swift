// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeToTalk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TypeToTalk", targets: ["TypeToTalk"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.9")
    ],
    targets: [
        .executableTarget(
            name: "TypeToTalk",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/TypeToTalk",
            exclude: [
                "Resources/Info.plist"
            ]
        ),
        .testTarget(
            name: "TypeToTalkTests",
            dependencies: ["TypeToTalk"],
            path: "Tests/TypeToTalkTests"
        )
    ]
)
