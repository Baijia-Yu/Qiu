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
        .executableTarget(name: "QuickTranslate", dependencies: ["CTranslateBridge"]),
        .testTarget(name: "QuickTranslateTests", dependencies: ["QuickTranslate"])
    ]
)
