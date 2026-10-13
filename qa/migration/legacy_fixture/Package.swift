// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TogetherLegacyFixture", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../0.0.1")],
    targets: [.executableTarget(name: "LegacyFixture", dependencies: [.product(name: "TogetherCore", package: "0.0.1")])])
