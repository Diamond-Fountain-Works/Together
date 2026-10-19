// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TogetherP2P",
    platforms: [.macOS("14.5")],
    products: [.library(name: "TogetherP2P", targets: ["TogetherP2P"])],
    dependencies: [
        .package(url: "https://github.com/n0-computer/iroh-ffi.git", revision: "5e451092dba0c1a09ee83ff6e5be37b1152a5c58"),
        .package(path: "../together-core-swift")
    ],
    targets: [
        .target(name: "TogetherP2P", dependencies: [
            .product(name: "IrohLib", package: "iroh-ffi"),
            .product(name: "TogetherCore", package: "together-core-swift")
        ]),
        .testTarget(name: "TogetherP2PTests", dependencies: ["TogetherP2P"])
    ],
    swiftLanguageModes: [.v6]
)
