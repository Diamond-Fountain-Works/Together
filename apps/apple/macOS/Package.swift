// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "TogetherMacOS", platforms: [.macOS(.v14)],
    products: [.executable(name: "Together", targets: ["TogetherApp"])],
    dependencies: [.package(path: "../../../packages/together-core-swift")],
    targets: [.executableTarget(name: "TogetherApp", dependencies: [.product(name: "TogetherCore", package: "together-core-swift")], path: "Sources/TogetherApp", exclude: ["Resources"])],
    swiftLanguageModes: [.v6]
)
