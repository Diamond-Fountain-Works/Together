#if TOGETHER_NATIVE_TRANSPORT
import Foundation
import TogetherCore
import TogetherP2P
import Darwin

/// Normal launch never accepts the QA workspace arguments. Storage and identity
/// remain owned by the existing production factory and its explicit migration.
@MainActor enum NativeProduction {
    static func validateLaunch(bundleIdentifier: String?, arguments: [String]) throws {
        guard bundleIdentifier == "com.together.app",
              !arguments.contains("--native-p2p-qa"),
              !arguments.contains("--ui-testing") else {
            throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
        }
    }

    static func build(migrateLegacyIdentity: Bool = false) throws -> ApplicationModel {
        try validateLaunch(bundleIdentifier: Bundle.main.bundleIdentifier,
                           arguments: ProcessInfo.processInfo.arguments)
        let systemSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(iOS)
        // Canonicalize only the trusted sandbox parent. A user-controlled
        // Together child still goes through the unchanged symlink rejection.
        let support = systemSupport.standardizedFileURL.resolvingSymlinksInPath()
        #else
        let support = systemSupport
        #endif
        let root = support.appendingPathComponent("Together", isDirectory: true)
        try validateStorageBoundary(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        // This preserves existing IDs, signature validation, system time zone,
        // active enrolled workspace and missing-key rejection. No temporary root
        // or test fixture is consulted by a normal launch.
        let engine = try ReplicaEngine.production(migrateLegacyIdentity: migrateLegacyIdentity)
        let model = ApplicationModel(engine: engine, useBundledService: false)
        // Old C1 bindings retain their transport. Upgrading the executable does
        // not silently replace an established route, identity or shared space.
        let legacy = try engine.repository.localBytes(keys: ["relay-binding", "replication4/relay-binding"])
        if legacy.isEmpty {
            guard let root = engine.repository.storageURL?.deletingLastPathComponent() else {
                throw IdentityStorageError.identityMismatch
            }
            model.nativeNetwork = try NativeAppPeerService(engine: engine, persistentRoot: root)
        }
        return model
    }

    /// Preflight before opening SQLite or creating a key. In particular, an
    /// existing symlink cannot redirect a normal launch into another workspace.
    static func validateStorageBoundary(_ root: URL) throws {
        guard root.lastPathComponent == "Together",
              root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw IdentityStorageError.identityMismatch
        }
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        let attrs = try manager.attributesOfItem(atPath: root.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw IdentityStorageError.identityMismatch
        }
        let active = try DeviceEnrollmentWorkspace(root: root).activeDirectory()
        for relative in ["Together.store", "Together.store-wal", "Together.store-shm", "Identity", "native-transport.key"] {
            let file = active.appendingPathComponent(relative)
            guard file.standardizedFileURL.path == file.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw IdentityStorageError.identityMismatch
            }
        }
    }
}
#endif
