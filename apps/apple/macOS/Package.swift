// swift-tools-version: 6.0
import PackageDescription
import Foundation
// Native distribution is explicitly Apple Silicon / macOS 14.5+.
// The legacy switch remains available for C1/macOS 14 regression builds.
let nativeAcceptance = ProcessInfo.processInfo.environment["TOGETHER_NATIVE_ACCEPTANCE"] == "1"
let nativeTransport = nativeAcceptance || ProcessInfo.processInfo.environment["TOGETHER_LEGACY_C1"] != "1"
var dependencies: [Package.Dependency] = [.package(path: "../../../packages/together-core-swift")]
var appDependencies: [Target.Dependency] = [.product(name: "TogetherCore", package: "together-core-swift")]
if nativeTransport {
    dependencies.append(.package(path: "../../../packages/together-p2p-swift"))
    appDependencies.append(.product(name: "TogetherP2P", package: "together-p2p-swift"))
}
let package = Package(
    name: "TogetherMacOS", platforms: [.macOS(nativeTransport ? "14.5" : "14.0")],
    products: [.executable(name: "Together", targets: ["TogetherApp"])],
    dependencies: dependencies,
    targets: [.executableTarget(name: "TogetherApp", dependencies: appDependencies, path: "Sources/TogetherApp", exclude: ["Resources"],
        swiftSettings: (nativeTransport ? [.define("TOGETHER_NATIVE_TRANSPORT")] : []) + (nativeAcceptance ? [.define("TOGETHER_NATIVE_P2P_QA")] : [])),
        .testTarget(name: "TogetherAppTests", dependencies: ["TogetherApp", .product(name: "TogetherCore", package: "together-core-swift")], path: "Tests/TogetherAppTests", swiftSettings: nativeTransport ? [.define("TOGETHER_NATIVE_TRANSPORT")] : [])],
    swiftLanguageModes: [.v6]
)
