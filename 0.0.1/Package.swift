// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Together",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TogetherCore", targets: ["TogetherCore"]), .executable(name: "Together", targets: ["TogetherApp"])],
    targets: [
        .target(name: "TogetherCore", path: "Sources/TogetherCore", resources: [.process("Resources")]),
        .executableTarget(name: "TogetherApp", dependencies: ["TogetherCore"], path: "Sources/TogetherApp", exclude: ["Resources"]),
        .testTarget(name: "TogetherCoreTests", dependencies: ["TogetherCore"], path: "Tests/TogetherCoreTests")
    ],
    swiftLanguageModes: [.v6]
)
