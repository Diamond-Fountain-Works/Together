// swift-tools-version: 6.0
import PackageDescription
import Foundation
// The pinned native transport is arm64/macOS 14.5+ only. It must never enter
// the existing universal macOS 14 release merely because this QA build exists.
let nativeAcceptance = ProcessInfo.processInfo.environment["TOGETHER_NATIVE_ACCEPTANCE"] == "1"
var dependencies: [Package.Dependency] = [.package(path: "../../../packages/together-core-swift")]
var appDependencies: [Target.Dependency] = [.product(name: "TogetherCore", package: "together-core-swift")]
if nativeAcceptance {
    dependencies.append(.package(path: "../../../packages/together-p2p-swift"))
    appDependencies.append(.product(name: "TogetherP2P", package: "together-p2p-swift"))
}
let package = Package(
    name: "TogetherMacOS", platforms: [.macOS(nativeAcceptance ? "14.5" : "14.0")],
    products: [.executable(name: "Together", targets: ["TogetherApp"])],
    dependencies: dependencies,
    targets: [.executableTarget(name: "TogetherApp", dependencies: appDependencies, path: "Sources/TogetherApp", exclude: ["Resources"],
        swiftSettings: nativeAcceptance ? [.define("TOGETHER_NATIVE_P2P_QA")] : [])],
    swiftLanguageModes: [.v6]
)
