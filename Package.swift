// swift-tools-version: 6.0
import PackageDescription
import Foundation

let sentencePiecePrefix: String = {
    if let configured = ProcessInfo.processInfo.environment["SENTENCEPIECE_PREFIX"] {
        return configured
    }
    let candidates = ["/opt/homebrew/opt/sentencepiece", "/usr/local/opt/sentencepiece"]
    return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
}()

let package = Package(
    name: "QuickTranslate",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "QuickTranslate", targets: ["QuickTranslate"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CTranslateBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++17",
                    "-IVendor/CTranslate2/include",
                    "-I\(sentencePiecePrefix)/include",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    ".native-build/libquicktranslate-native.a",
                    "\(sentencePiecePrefix)/lib/libsentencepiece.a",
                ]),
                .linkedFramework("Accelerate"),
            ]
        ),
        .executableTarget(
            name: "QuickTranslate",
            dependencies: [
                "CTranslateBridge",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(name: "QuickTranslateTests", dependencies: ["QuickTranslate"])
    ]
)
