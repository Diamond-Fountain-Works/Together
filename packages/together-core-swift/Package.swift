// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TogetherCore", defaultLocalization: "zh-Hans", platforms: [.macOS(.v14)],
    products: [.library(name: "TogetherCore", targets: ["TogetherCore"])],
    targets: [
        .target(name: "TogetherCore", path: "Sources/TogetherCore", resources: [.process("Resources")]),
        .testTarget(name: "TogetherCoreTests", dependencies: ["TogetherCore"], path: "Tests/TogetherCoreTests")
    ], swiftLanguageModes: [.v6]
)
