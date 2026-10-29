import Foundation
import CryptoKit

extension ReplicaEngine {
    public static func production(migrateLegacyIdentity: Bool = false) throws -> ReplicaEngine {
        guard !["com.together.app.qa", "com.together.app.ios.qa"].contains(Bundle.main.bundleIdentifier ?? "") else {throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))}
        let systemSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(iOS)
        // Canonicalize only the OS-provided parent (/var's sandbox alias),
        // never the user-controlled Together child or identity workspace.
        let support = systemSupport.resolvingSymlinksInPath()
        #else
        let support = systemSupport
        #endif
        let root = support.appendingPathComponent("Together", isDirectory: true)
        let directory = try DeviceEnrollmentWorkspace(root: root).activeDirectory()
        if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Together.store").path) {
            let keys = (try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Identity"), includingPropertiesForKeys: nil)) ?? []
            guard keys.isEmpty else { throw IdentityStorageError.identityMismatch }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = try TogetherRepository(url: directory.appendingPathComponent("Together.store"))
        let operations = try repository.allOperations()
        let existingMetadata = try repository.load(LocalIdentityMetadata.self, key: "local-identity")
        guard existingMetadata != nil || operations.isEmpty else { throw IdentityStorageError.identityMismatch }
        let metadata = existingMetadata ?? LocalIdentityMetadata()
        let enrolled = try repository.load(DeviceDescriptor.self, key: "replication4/local-device")
        if directory != root, existingMetadata == nil || enrolled == nil { throw IdentityStorageError.identityMismatch }
        if let enrolled { guard enrolled.deviceId == metadata.deviceId, enrolled.userId == metadata.userId, enrolled.initialSpaceId == metadata.spaceId else { throw IdentityStorageError.identityMismatch } }
        let storedZone = try repository.load(String.self, key: "initial-time-zone")
        let zone = enrolled?.initialTimeZoneIdentifier ?? storedZone ?? TimeZone.current.identifier
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
                                                     directory: directory.appendingPathComponent("Identity", isDirectory: true),
                                                     needsExistingIdentity: existingMetadata != nil || !operations.isEmpty || enrolled != nil, migrateLegacy: migrateLegacyIdentity, timeZoneIdentifier: zone, protocolVersion: enrolled?.protocolVersion ?? 3, displayName: enrolled?.displayName ?? "我") { key in
            let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: key).publicKey
            if let enrolled, enrolled.publicKey != publicKey.rawRepresentation { throw IdentityStorageError.identityMismatch }
            for operation in operations where operation.operation.deviceId == metadata.deviceId {
                guard try publicKey.isValidSignature(operation.signature, for: CanonicalJSON.encode(operation.operation)) else { throw IdentityStorageError.identityMismatch }
            }
        }
        try repository.save(metadata, key: "local-identity")
        try repository.save(zone, key: "initial-time-zone")
        return try ReplicaEngine(repository: repository, identity: identity, mediaRoot: directory.appendingPathComponent("Media"), enrollmentRoot: root)
    }

}
