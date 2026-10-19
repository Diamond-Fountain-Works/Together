import Foundation
import CryptoKit

public struct DeviceDescriptor: Codable, Equatable, Sendable {
    public var deviceId: UUID
    public var userId: UUID
    public var initialSpaceId: UUID
    public var publicKey: Data
    public var displayName: String
    public var protocolVersion: Int = 2
    public var initialTimeZoneIdentifier: String? = nil
    public var fingerprint: String { SHA256.hash(data: publicKey).map { String(format: "%02X", $0) }.joined().chunked(4).joined(separator: " ") }
}
public struct DeviceIdentity: Sendable {
    public let descriptor: DeviceDescriptor
    private let privateKeyData: Data
    public init(deviceId: UUID = UUID(), userId: UUID = UUID(), initialSpaceId: UUID = UUID(), privateKeyData: Data? = nil, displayName: String = "我", timeZoneIdentifier: String = TimeZone.current.identifier, protocolVersion: Int = 2) throws {
        let key = try privateKeyData.map { try Curve25519.Signing.PrivateKey(rawRepresentation: $0) } ?? Curve25519.Signing.PrivateKey()
        self.privateKeyData = key.rawRepresentation
        descriptor = DeviceDescriptor(deviceId: deviceId, userId: userId, initialSpaceId: initialSpaceId, publicKey: key.publicKey.rawRepresentation, displayName: displayName, protocolVersion: protocolVersion, initialTimeZoneIdentifier: timeZoneIdentifier)
    }
    public func sign(_ bytes: Data) throws -> Data { try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData).signature(for: bytes) }
    public func sign(_ operation: SyncOperation) throws -> SignedOperation { try SignedOperation(operation: operation, signature: sign(CanonicalJSON.encode(operation))) }
    public static func persistent(deviceId: UUID, userId: UUID, spaceId: UUID, directory: URL,
                                  needsExistingIdentity: Bool, migrateLegacy: Bool = false,
                                  timeZoneIdentifier: String = TimeZone.current.identifier, protocolVersion: Int = 2, validateKey: (Data) throws -> Void = { _ in }) throws -> DeviceIdentity {
        let data = try IdentityFileStore(directory: directory).loadOrCreate(deviceId: deviceId, needsExistingIdentity: needsExistingIdentity, migrateLegacy: migrateLegacy, legacyReader: {
            try IdentityFileStore.readLegacyKeychain(deviceId: deviceId)
        }, validate: validateKey)
        return try DeviceIdentity(deviceId: deviceId, userId: userId, initialSpaceId: spaceId, privateKeyData: data, timeZoneIdentifier: timeZoneIdentifier, protocolVersion: protocolVersion)
    }
}
public struct PairedPeer: Codable, Equatable, Sendable {
    public var descriptor: DeviceDescriptor
    public var host: String
    public var port: UInt16
    public var approvedAt: Date
    public init(descriptor: DeviceDescriptor, host: String, port: UInt16, approvedAt: Date = .now) {
        self.descriptor = descriptor; self.host = host; self.port = port; self.approvedAt = approvedAt
    }
}
public struct ReplicaContext: Equatable, Sendable {
    public var local: DeviceDescriptor
    public var peer: DeviceDescriptor?
    public init(local: DeviceDescriptor, peer: DeviceDescriptor? = nil) { self.local = local; self.peer = peer }
    public var devices: [UUID: DeviceDescriptor] { Dictionary(uniqueKeysWithValues: [local, peer].compactMap { $0 }.map { ($0.deviceId, $0) }) }
    public var members: Set<UUID> { Set(devices.values.map(\.userId)) }
    public var spaceId: UUID {
        guard let peer else { return local.initialSpaceId }
        return StableID.make("space:" + [local.deviceId.uuidString, peer.deviceId.uuidString].sorted().joined(separator: ":"))
    }
    public var validSpaceIds: Set<UUID> { Set([local.initialSpaceId, peer?.initialSpaceId, spaceId].compactMap { $0 }) }
    public var spaceCreator: DeviceDescriptor { devices.values.min { $0.deviceId.uuidString < $1.deviceId.uuidString } ?? local }
    public var sharedTimeZone: String { spaceCreator.initialTimeZoneIdentifier.flatMap { TimeZone(identifier: $0)?.identifier } ?? "Etc/UTC" }
}
private extension String {
    func chunked(_ size: Int) -> [String] { stride(from: 0, to: count, by: size).map { String(dropFirst($0).prefix(size)) } }
}
