// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TTT",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TTT", targets: ["TTT"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0")
    ],
    targets: [
        .executableTarget(
            name: "TTT",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "Sources/TTT",
            resources: [
                .process("Resources/Info.plist")
            ]
        )
    ]
)
