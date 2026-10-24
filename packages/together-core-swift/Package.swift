// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TogetherCore", defaultLocalization: "zh-Hans", platforms: [.macOS(.v11), .iOS(.v15)],
    products: [.library(name: "TogetherCore", targets: ["TogetherCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "TogetherCore", dependencies: ["CSQLite"], path: "Sources/TogetherCore", resources: [.process("Resources")]),
        .testTarget(name: "TogetherCoreTests", dependencies: ["TogetherCore"], path: "Tests/TogetherCoreTests")
    ], swiftLanguageModes: [.v6]
)
