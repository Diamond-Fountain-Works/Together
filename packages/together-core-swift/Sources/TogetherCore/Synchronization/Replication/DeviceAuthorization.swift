import Foundation
import CryptoKit

public struct DeviceSignature: Codable, Equatable, Sendable {
    public var deviceId: UUID
    public var signature: Data
    public init(deviceId: UUID, signature: Data) { self.deviceId = deviceId; self.signature = signature }
}
public struct SpaceGenesisBody: Codable, Equatable, Sendable {
    public var version = 4
    public var spaceId: UUID
    public var memberIds: [UUID]
    public var roots: [DeviceDescriptor]
    public var legacySpaceIds: [UUID]
    public var sharedTimeZoneIdentifier: String
    public var legacyCheckpoint: InventoryCheckpoint
    public init(context: ReplicaContext, legacyCheckpoint: InventoryCheckpoint) {
        spaceId = context.spaceId; memberIds = context.members.sorted { $0.uuidString < $1.uuidString }
        roots = context.devices.values.sorted { $0.deviceId.uuidString < $1.deviceId.uuidString }
        legacySpaceIds = context.validSpaceIds.sorted { $0.uuidString < $1.uuidString }
        sharedTimeZoneIdentifier = context.sharedTimeZone; self.legacyCheckpoint = legacyCheckpoint
    }
}
public struct SignedSpaceGenesis: Codable, Equatable, Sendable {
    public var body: SpaceGenesisBody
    public var signatures: [DeviceSignature]
    public init(body: SpaceGenesisBody, signatures: [DeviceSignature]) { self.body = body; self.signatures = signatures }
    public static func sign(_ body: SpaceGenesisBody, with roots: [DeviceIdentity]) throws -> Self {
        let bytes = try CanonicalJSON.encode(body)
        return Self(body: body, signatures: try roots.map { DeviceSignature(deviceId: $0.descriptor.deviceId, signature: try $0.sign(bytes)) }.sorted { $0.deviceId.uuidString < $1.deviceId.uuidString })
    }
    public func verify(existingPins: ReplicaContext? = nil) throws {
        guard body.version == 4, body.roots.count == 2, body.memberIds.count == 2,
              body.memberIds==body.memberIds.sorted(by:{$0.uuidString<$1.uuidString}),
              body.roots.map(\.deviceId)==body.roots.map(\.deviceId).sorted(by:{$0.uuidString<$1.uuidString}),
              signatures.map(\.deviceId)==signatures.map(\.deviceId).sorted(by:{$0.uuidString<$1.uuidString}),
              Set(body.memberIds).count == 2, Set(body.roots.map(\.userId)) == Set(body.memberIds),
              Set(body.roots.map(\.deviceId)).count == 2, Set(body.roots.map(\.publicKey)).count == 2,
              body.legacySpaceIds.count <= 3,Set(body.legacySpaceIds).count==body.legacySpaceIds.count,
              body.legacySpaceIds==body.legacySpaceIds.sorted(by:{$0.uuidString<$1.uuidString}),Set(body.legacySpaceIds).contains(body.spaceId),
              body.legacyCheckpoint.count >= 0, ReplicationHash.valid(body.legacyCheckpoint.digest),
              TimeZone(identifier: body.sharedTimeZoneIdentifier) != nil,
              signatures.count == 2, Set(signatures.map(\.deviceId)) == Set(body.roots.map(\.deviceId)) else { throw ReplicationError.unauthorized }
        if let pins = existingPins {
            guard pins.spaceId == body.spaceId, pins.members == Set(body.memberIds),
                  pins.validSpaceIds == Set(body.legacySpaceIds), pins.sharedTimeZone == body.sharedTimeZoneIdentifier,
                  Set(pins.devices.keys) == Set(body.roots.map(\.deviceId)),
                  body.roots.allSatisfy({ root in pins.devices[root.deviceId].map { $0.publicKey == root.publicKey && $0.userId == root.userId && $0.initialSpaceId == root.initialSpaceId } ?? false }) else { throw ReplicationError.unauthorized }
        }
        let bytes = try CanonicalJSON.encode(body)
        for descriptor in body.roots {
            guard descriptor.publicKey.count == 32, descriptor.displayName.count <= 80,[2,3,4].contains(descriptor.protocolVersion),
                  let proof = signatures.first(where: { $0.deviceId == descriptor.deviceId }),
                  Self.verify(proof.signature, bytes: bytes, key: descriptor.publicKey) else { throw ReplicationError.invalidSignature }
        }
    }
    static func verify(_ signature: Data, bytes: Data, key: Data) -> Bool {
        guard signature.count == 64, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { return false }
        return key.isValidSignature(signature, for: bytes)
    }
    public var digest: String { get throws { ReplicationHash.digest(try CanonicalJSON.encode(self)) } }
}
public struct DeviceFrontier: Codable, Equatable, Sendable {
    public var sequence: Int64
    public var digest: String
    public init(sequence: Int64 = 0, digest: String = String(repeating: "0", count: 64)) { self.sequence = sequence; self.digest = digest }
    public var isValid: Bool { sequence >= 0 && sequence < 9_000_000_000_000_000 && ReplicationHash.valid(digest) && (sequence != 0 || digest == String(repeating: "0", count: 64)) }
}
public enum DeviceAuthorizationAction: String, Codable, Sendable { case grant, revoke }
public struct DeviceAuthorizationBody: Codable, Equatable, Sendable {
    public var version = 4
    public var spaceId: UUID
    public var ownerId: UUID
    public var revision: Int64
    public var previousDigest: String
    public var authorizerDeviceId: UUID
    public var action: DeviceAuthorizationAction
    public var device: DeviceDescriptor
    public var epochId: UUID
    public var cutoff: DeviceFrontier?
}
public struct SignedDeviceAuthorization: Codable, Equatable, Sendable {
    public var body: DeviceAuthorizationBody
    public var signature: Data
    public var digest: String { get throws { ReplicationHash.digest(try CanonicalJSON.encode(self)) } }
}
public struct AuthorizedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { descriptor.deviceId }
    public var descriptor: DeviceDescriptor
    public var epochId: UUID
    public var revokedAt: DeviceFrontier?
    public var isActive: Bool { revokedAt == nil }
}

/// Two stable members, an append-only per-owner authorization stream, and
/// independent keys for every replica. This is public routing/trust metadata.
public struct SpaceAuthorization: Equatable, Sendable {
    public let genesis: SignedSpaceGenesis
    public private(set) var events: [SignedDeviceAuthorization] = []
    public private(set) var devices: [UUID: AuthorizedDevice] = [:]
    private var ownerRevisions: [UUID: Int64] = [:]
    private var ownerHeads: [UUID: String] = [:]
    public init(genesis: SignedSpaceGenesis, existingPins: ReplicaContext? = nil) throws {
        try genesis.verify(existingPins: existingPins); self.genesis = genesis
        let digest = try genesis.digest
        for root in genesis.body.roots {
            devices[root.deviceId] = AuthorizedDevice(descriptor: root, epochId: Self.rootEpoch(spaceId: genesis.body.spaceId, deviceId: root.deviceId))
            ownerRevisions[root.userId] = 0; ownerHeads[root.userId] = digest
        }
    }
    public static func rootEpoch(spaceId: UUID, deviceId: UUID) -> UUID { StableID.make("Together-Device-Epoch-4:\(spaceId):\(deviceId)") }
    public var spaceId: UUID { genesis.body.spaceId }
    public var activeDevices: [AuthorizedDevice] { devices.values.filter(\.isActive).sorted { $0.id.uuidString < $1.id.uuidString } }
    public func root(for owner: UUID) -> DeviceDescriptor? { genesis.body.roots.first { $0.userId == owner } }
    public func containsActive(_ descriptor: DeviceDescriptor) -> Bool {
        devices[descriptor.deviceId].map { $0.isActive && $0.descriptor.publicKey == descriptor.publicKey && $0.descriptor.userId == descriptor.userId && $0.descriptor.initialSpaceId == descriptor.initialSpaceId } ?? false
    }
    public func grant(_ descriptor: DeviceDescriptor, authorizedBy identity: DeviceIdentity, epochId: UUID = UUID()) throws -> SignedDeviceAuthorization {
        try make(action: .grant, descriptor: descriptor, epochId: epochId, cutoff: nil, identity: identity)
    }
    public func revoke(_ deviceId: UUID, at frontier: DeviceFrontier, authorizedBy identity: DeviceIdentity) throws -> SignedDeviceAuthorization {
        guard let device = devices[deviceId], device.isActive else { throw ReplicationError.unauthorized }
        return try make(action: .revoke, descriptor: device.descriptor, epochId: device.epochId, cutoff: frontier, identity: identity)
    }
    private func make(action: DeviceAuthorizationAction, descriptor: DeviceDescriptor, epochId: UUID, cutoff: DeviceFrontier?, identity: DeviceIdentity) throws -> SignedDeviceAuthorization {
        guard let root = root(for: identity.descriptor.userId), root.deviceId == identity.descriptor.deviceId, root.publicKey == identity.descriptor.publicKey,
              let revision = ownerRevisions[root.userId], let head = ownerHeads[root.userId] else { throw ReplicationError.unauthorized }
        let body = DeviceAuthorizationBody(spaceId: spaceId, ownerId: root.userId, revision: revision + 1, previousDigest: head,
                                           authorizerDeviceId: root.deviceId, action: action, device: descriptor, epochId: epochId, cutoff: cutoff)
        let signed = SignedDeviceAuthorization(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
        var copy = self; try copy.apply(signed); return signed
    }
    public mutating func apply(_ event: SignedDeviceAuthorization) throws {
        if events.contains(event) { return }
        let b = event.body
        guard b.version == 4, b.spaceId == spaceId, let root = root(for: b.ownerId),
              b.ownerId == b.device.userId, b.authorizerDeviceId == root.deviceId,
              SignedSpaceGenesis.verify(event.signature, bytes: try CanonicalJSON.encode(b), key: root.publicKey) else { throw ReplicationError.unauthorized }
        guard b.revision == (ownerRevisions[b.ownerId] ?? -1) + 1, b.previousDigest == ownerHeads[b.ownerId] else { throw ReplicationError.authorizationFork }
        switch b.action {
        case .grant:
            guard devices[b.device.deviceId] == nil, activeDevices.count < 32, b.cutoff == nil, b.device.publicKey.count == 32,
                  !devices.values.contains(where: { $0.descriptor.publicKey == b.device.publicKey || $0.epochId == b.epochId }),
                  b.device.displayName.count <= 80,[2,3,4].contains(b.device.protocolVersion), TimeZone(identifier: b.device.initialTimeZoneIdentifier ?? "") != nil else { throw ReplicationError.unauthorized }
            devices[b.device.deviceId] = AuthorizedDevice(descriptor: b.device, epochId: b.epochId)
        case .revoke:
            guard var device = devices[b.device.deviceId], device.isActive, device.descriptor == b.device,
                  device.epochId == b.epochId, b.device.deviceId != root.deviceId,
                  let cutoff = b.cutoff, cutoff.isValid else { throw ReplicationError.unauthorized }
            device.revokedAt = cutoff; devices[b.device.deviceId] = device
        }
        ownerRevisions[b.ownerId] = b.revision; ownerHeads[b.ownerId] = try event.digest; events.append(event)
    }
    /// Persist only genesis and signed events. Never deserialize cached device
    /// dictionaries as authority; rebuilding revalidates every signature/link.
    public static func restore(_ archive: AuthorizationArchive, existingPins: ReplicaContext? = nil) throws -> Self {
        var value = try Self(genesis: archive.genesis, existingPins: existingPins)
        for event in archive.events { try value.apply(event) }; return value
    }
    public var archive: AuthorizationArchive { AuthorizationArchive(genesis: genesis, events: events.sorted{a,b in a.body.ownerId==b.body.ownerId ? a.body.revision<b.body.revision:a.body.ownerId.uuidString<b.body.ownerId.uuidString}) }
    public static func ==(a:Self,b:Self)->Bool{a.archive==b.archive}
}
public struct AuthorizationArchive: Codable, Equatable, Sendable {
    public var genesis: SignedSpaceGenesis
    public var events: [SignedDeviceAuthorization]
    public init(genesis: SignedSpaceGenesis, events: [SignedDeviceAuthorization]) { self.genesis = genesis; self.events = events }
}
public struct AuthorizedOperationBody: Codable, Equatable, Sendable {
    public var version = 4
    public var spaceId: UUID
    public var epochId: UUID
    public var sequence: Int64
    public var previousDigest: String
    public var signedOperation: SignedOperation
}
public struct AuthorizedOperation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { body.signedOperation.id }
    public var body: AuthorizedOperationBody
    public var signature: Data
    public var digest: String { get throws { ReplicationHash.digest(try CanonicalJSON.encode(self)) } }
    public static func sign(_ operation: SignedOperation, identity: DeviceIdentity, trust: SpaceAuthorization, previous: DeviceFrontier) throws -> Self {
        guard let device = trust.devices[identity.descriptor.deviceId], device.isActive, trust.containsActive(identity.descriptor), previous.isValid,
              operation.verified(by: device.descriptor), previous.sequence < 8_999_999_999_999_999 else { throw ReplicationError.unauthorized }
        let body = AuthorizedOperationBody(spaceId: trust.spaceId, epochId: device.epochId, sequence: previous.sequence + 1, previousDigest: previous.digest, signedOperation: operation)
        return AuthorizedOperation(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
    }
    public func verify(in trust: SpaceAuthorization) throws -> AuthorizedDevice {
        let b = body, op = b.signedOperation
        guard b.version == 4, b.spaceId == trust.spaceId, b.sequence > 0, b.sequence < 9_000_000_000_000_000,
              ReplicationHash.valid(b.previousDigest), let device = trust.devices[op.operation.deviceId], device.epochId == b.epochId,
              op.verified(by: device.descriptor), SignedSpaceGenesis.verify(signature, bytes: try CanonicalJSON.encode(b), key: device.descriptor.publicKey) else { throw ReplicationError.invalidSignature }
        if let cutoff = device.revokedAt, b.sequence > cutoff.sequence { throw ReplicationError.revoked }
        return device
    }
}
