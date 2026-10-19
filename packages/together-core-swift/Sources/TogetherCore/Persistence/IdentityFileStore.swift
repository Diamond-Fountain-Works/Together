import Foundation
import CryptoKit
import Security
import Darwin

/// Local identity persistence only. Keys never enter the operation log or relay.
public struct IdentityFileStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func keyURL(deviceId: UUID) -> URL { directory.appendingPathComponent("device-\(deviceId.uuidString).key") }

    public func load(deviceId: UUID) throws -> Data? {
        let url = keyURL(deviceId: deviceId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == 32 else { throw IdentityStorageError.invalidFile }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let data = try Data(contentsOf: url)
        guard data.count == 32 else { throw IdentityStorageError.invalidFile }
        return data
    }
    public func loadOrCreate(deviceId: UUID, needsExistingIdentity: Bool, migrateLegacy: Bool = false,
                             legacyReader: () throws -> Data? = { nil }, validate: (Data) throws -> Void = { _ in }) throws -> Data {
        if let stored = try load(deviceId: deviceId) { try validate(stored); return stored }
        if needsExistingIdentity && !migrateLegacy { throw IdentityStorageError.legacyMigrationRequired }
        let key: Data
        if needsExistingIdentity {
            guard let existing = try legacyReader() else { throw IdentityStorageError.legacyKeyMissing }
            key = existing
        } else { key = Curve25519.Signing.PrivateKey().rawRepresentation }
        guard key.count == 32 else { throw IdentityStorageError.invalidFile }
        _ = try Curve25519.Signing.PrivateKey(rawRepresentation: key)
        try validate(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".identity-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try key.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize(); try handle.close()
        if Darwin.link(temporary.path, keyURL(deviceId: deviceId).path) != 0 {
            if errno == EEXIST, let existing = try load(deviceId: deviceId) { try validate(existing); return existing }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard try load(deviceId: deviceId) == key else { throw IdentityStorageError.invalidFile }
        return key
    }

    /// Called only after the user chooses the explicit one-time migration action.
    public static func readLegacyKeychain(deviceId: UUID) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.together.app.identity",
                                   kSecAttrAccount as String: "device-\(deviceId.uuidString)",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw IdentityStorageError.keychain(status) }
        return data
    }
}

public enum IdentityStorageError: LocalizedError {
    case legacyMigrationRequired, legacyKeyMissing, invalidFile, identityMismatch, keychain(OSStatus)
    public var errorDescription: String? {
        switch self {
        case .legacyMigrationRequired: Copy.text("identity.migration.guidance")
        case .legacyKeyMissing: Copy.text("identity.error.legacyMissing")
        case .invalidFile: Copy.text("identity.error.invalidFile")
        case .identityMismatch: Copy.text("identity.error.mismatch")
        case .keychain: Copy.text("identity.error.keychainMigration")
        }
    }
}
