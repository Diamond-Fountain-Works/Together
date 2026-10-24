#if TOGETHER_NATIVE_P2P_QA
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import TogetherCore
import TogetherP2P

/// Separate bundle, explicit argument and bounded temporary storage are all
/// mandatory. No error or retry path is allowed to fall back to production().
@MainActor enum NativeAcceptance {
    static func build() throws -> ApplicationModel {
        let args = ProcessInfo.processInfo.arguments
        guard Bundle.main.bundleIdentifier == "com.together.app.qa.p2p",
              let flag = args.firstIndex(of: "--native-p2p-qa"), flag + 1 < args.count else {
            throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
        }
        let input = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        let root = input.standardizedFileURL.resolvingSymlinksInPath()
        let parent = root.deletingLastPathComponent().path
        let allowed = ["/tmp", "/private/tmp", FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path]
        guard root.lastPathComponent.hasPrefix("together-native-app-"), allowed.contains(parent),
              FileManager.default.fileExists(atPath: root.path) else {
            throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let repository = try TogetherRepository(url: root.appendingPathComponent("Together.store"))
        let saved = try repository.load(LocalIdentityMetadata.self, key: "local-identity")
        let hasFacts = try repository.operationCount() > 0
        guard saved != nil || !hasFacts else { throw IdentityStorageError.identityMismatch }
        let metadata = saved ?? LocalIdentityMetadata()
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
            directory: root.appendingPathComponent("Identity"), needsExistingIdentity: saved != nil || hasFacts,
            migrateLegacy: false, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4)
        try repository.save(metadata, key: "local-identity")
        let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: root.appendingPathComponent("Media"))
        let suite = "com.together.app.qa.p2p." + root.lastPathComponent
        guard let defaults = UserDefaults(suiteName: suite) else { throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch")) }
        let model = ApplicationModel(engine: engine, defaults: defaults, serviceURL: nil, useBundledService: false)
        model.nativeNetwork = try NativeAppPeerService(engine: engine, root: root)
        return model
    }
}

#endif
