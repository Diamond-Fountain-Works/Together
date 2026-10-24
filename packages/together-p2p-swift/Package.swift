// swift-tools-version: 6.0
import PackageDescription
import Foundation
import CryptoKit

// The upstream v1.1.0 binary contains vulnerable Rust core 1.0.2. Always use
// our source-built, receipt-verified core 1.1.0; there is no remote fallback.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let secureSources = repository.appendingPathComponent("packages/together-native-source")
let nativePackage = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOGETHER_IROH_SECURE_PACKAGE"]
    ?? repository.appendingPathComponent(".native-build/apple/iroh-ffi").path).standardizedFileURL
func fail(_ message: String) -> Never {
    fatalError("Secure Iroh build required: \(message). Run python3 scripts/rebuild_apple_native.py --jobs 2 from the repository root.")
}
func checksum(_ url: URL) -> String {
    guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
          let stream = try? FileHandle(forReadingFrom: url) else { fail("invalid file \(url.lastPathComponent)") }
    defer { try? stream.close() }
    var hash = SHA256()
    do {
        while let bytes = try stream.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
    } catch { fail("unreadable file \(url.lastPathComponent)") }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func json(_ url: URL) -> [String: Any] {
    guard let bytes = try? Data(contentsOf: url),
          let result = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { fail("missing provenance \(url.lastPathComponent)") }
    return result
}
guard ProcessInfo.processInfo.environment["IROH_FORCE_REMOTE_XCFRAMEWORK"] != "1",
      nativePackage.lastPathComponent == "iroh-ffi",
      nativePackage.path.hasPrefix(repository.appendingPathComponent(".native-build").path + "/"),
      nativePackage.path == nativePackage.resolvingSymlinksInPath().path else { fail("unapproved native package path or remote override") }
let receipt = json(nativePackage.appendingPathComponent("secure-build.json"))
let secureLock = "0904d9b3cc5c1b5c3384f2a8fc8881da91bcee6231ad1c8813a1ae6eaae268e5"
let sourceManifest = secureSources.appendingPathComponent("source-manifest.json")
let bindingManifest = secureSources.appendingPathComponent("apple-bindings-manifest.json")
let platformPolicy = secureSources.appendingPathComponent("platform-support.json")
guard receipt["format"] as? String == "together-secure-apple-iroh-source-build-v2",
      receipt["sourceCommit"] as? String == "5e451092dba0c1a09ee83ff6e5be37b1152a5c58",
      receipt["secureCargoLockSHA256"] as? String == secureLock,
      checksum(secureSources.appendingPathComponent("Cargo.lock")) == secureLock,
      receipt["sourceManifestSHA256"] as? String == checksum(sourceManifest),
      receipt["appleBindingsManifestSHA256"] as? String == checksum(bindingManifest),
      receipt["ffiExportCount"] as? Int == 413,
      receipt["ffiExportsEqual"] as? Bool == true,
      receipt["architecture"] as? String == "arm64",
      receipt["minimumMacOS"] as? String == "11.0",
      receipt["minimumIOS"] as? String == "15.0",
      receipt["platformPolicySHA256"] as? String == checksum(platformPolicy),
      let versions = receipt["dependencyVersions"] as? [String: String],
      ["iroh", "iroh-base", "iroh-relay"].allSatisfy({ versions[$0] == "1.1.0" }),
      let files = receipt["files"] as? [String: String], !files.isEmpty else { fail("stale or unreviewed provenance") }
let identifiers = ["macos": "macos-arm64", "ios": "ios-arm64", "ios-simulator": "ios-arm64-simulator"]
guard let platforms = receipt["platforms"] as? [String], !platforms.isEmpty,
      Set(platforms).count == platforms.count, platforms.allSatisfy({ identifiers[$0] != nil }) else { fail("unreviewed platform slices") }
var requiredFiles: Set<String> = ["Package.swift", "IrohLib/Sources/IrohLib/IrohLib.swift", "Iroh.xcframework/Info.plist"]
for platform in platforms {
    let prefix = "Iroh.xcframework/" + identifiers[platform]!
    requiredFiles.insert(prefix + "/libiroh_ffi.a")
    for name in ["Export.h", "iroh_ffiFFI.h", "module.modulemap"] { requiredFiles.insert(prefix + "/Headers/" + name) }
}
guard Set(files.keys) == requiredFiles else { fail("incomplete native artifact layout") }
for (name, expected) in files {
    guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."),
          checksum(nativePackage.appendingPathComponent(name)) == expected else { fail("artifact integrity: \(name)") }
}
let bindings = json(bindingManifest)["files"] as? [String: String] ?? [:]
guard bindings.count == 4 else { fail("missing tracked ABI files") }
for platform in platforms {
    for (name, expected) in bindings {
        let generated = name.hasPrefix("IrohLib/") ? name : "Iroh.xcframework/" + identifiers[platform]! + "/" + name
        guard checksum(secureSources.appendingPathComponent("apple-bindings/" + name)) == expected,
              files[generated] == expected else { fail("tracked/generated ABI integrity") }
    }
}

let package = Package(
    name: "TogetherP2P",
    platforms: [.macOS("11.0"), .iOS("15.0")],
    products: [
        .library(name: "TogetherP2P", targets: ["TogetherP2P"]),
        // Explicit QA executable: never opens an application/default store.
        .executable(name: "TogetherP2PPublicQA", targets: ["TogetherP2PPublicQA"])
    ],
    dependencies: [
        .package(path: nativePackage.path),
        .package(path: "../together-core-swift")
    ],
    targets: [
        .target(name: "TogetherP2P", dependencies: [
            .product(name: "IrohLib", package: "iroh-ffi"),
            .product(name: "TogetherCore", package: "together-core-swift")
        ]),
        .executableTarget(name: "TogetherP2PPublicQA", dependencies: [
            "TogetherP2P", .product(name: "TogetherCore", package: "together-core-swift")
        ]),
        .testTarget(name: "TogetherP2PTests", dependencies: ["TogetherP2P"])
    ],
    swiftLanguageModes: [.v6]
)
