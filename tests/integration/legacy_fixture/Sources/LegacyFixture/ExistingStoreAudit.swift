import Foundation
import CryptoKit
import SwiftData
import TogetherCore

/// Called only for an owner-only temporary copy. Never reads the live store or
/// Keychain. Report hashes/counts, not private user text or raw identity keys.
enum ExistingStoreAudit {
    @MainActor static func run(_ requested: URL) throws {
        let root = requested.standardizedFileURL.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard root.path.hasPrefix(temporary.path + "/"), root.lastPathComponent.hasPrefix("together-ui-existing-") else { throw FixtureError.invalidPath }
        let repository = try TogetherRepository(url: root.appendingPathComponent("legacy.store"))
        guard let metadata = try repository.load(LocalIdentityMetadata.self, key: "local-identity"),
              let key = try IdentityFileStore(directory: root.appendingPathComponent("Identity")).load(deviceId: metadata.deviceId) else { throw FixtureError.invalidPath }
        let zone = try repository.load(String.self, key: "initial-time-zone") ?? "Etc/UTC"
        let identity = try DeviceIdentity(deviceId: metadata.deviceId, userId: metadata.userId, initialSpaceId: metadata.spaceId, privateKeyData: key, timeZoneIdentifier: zone)
        let capturedAt = Date(), clock = FixedDateProvider(capturedAt)
        let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: clock)
        var entities: [String: String] = [:]
        func add<T: Encodable>(_ prefix: String, _ id: UUID, _ value: T) throws { entities[prefix + id.uuidString] = try hash(value) }
        for item in engine.snapshot.profiles.values { try add("profile:", item.id, item) }
        for item in engine.snapshot.tasks.values { try add("task:", item.id, item) }
        for item in engine.snapshot.rules.values { try add("rule:", item.id, item) }
        for item in engine.snapshot.grants.values { try add("grant:", item.id, item) }
        for item in engine.snapshot.wishes.values { try add("wish:", item.id, item) }
        for item in engine.snapshot.gifts.values { try add("gift:", item.id, item) }
        for item in engine.snapshot.mediaAssets.values { try add("media:", item.id, item) }
        entities["adjustments"] = try hash(engine.snapshot.adjustments)
        entities["space"] = try hash(engine.snapshot.space)
        let localRows = try repository.container.mainContext.fetch(FetchDescriptor<LocalRecord>())
        let locals = Dictionary(uniqueKeysWithValues: localRows.map { ($0.key, digest($0.body)) })
        let operations = Dictionary(uniqueKeysWithValues: try engine.operations.map { ($0.id.uuidString, try hash($0)) })
        let report = ExistingCopyExpectation(metadata: metadata, descriptor: identity.descriptor, capturedAt: capturedAt, timeZone: zone, peer: engine.peer, binding: try repository.load(RelayBinding.self, key: "relay-binding"), entities: entities, localRecords: locals, operationHashes: operations)
        try CanonicalJSON.encode(report).write(to: root.appendingPathComponent("existing-expected.json"), options: .atomic)
        print("Existing isolated legacy copy audited: \(operations.count) operations, \(entities.count) entity hashes")
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func hash<T: Encodable>(_ value: T) throws -> String { digest(try CanonicalJSON.encode(value)) }
}
struct ExistingCopyExpectation: Codable {
    let metadata: LocalIdentityMetadata; let descriptor: DeviceDescriptor; let capturedAt: Date; let timeZone: String
    let peer: PairedPeer?; let binding: RelayBinding?; let entities: [String: String]; let localRecords: [String: String]; let operationHashes: [String: String]
}
