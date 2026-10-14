import Foundation
import CryptoKit
import SwiftData
import Testing
@testable import TogetherCore

@Suite("Existing user store copy upgrade") @MainActor struct ExistingStoreUpgradeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_EXISTING_COPY_FIXTURE"] != nil)) func existingDataCopySurvivesUpgradeAndRepeatedReopen() throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TOGETHER_EXISTING_COPY_FIXTURE"]))
        let expected = try CanonicalJSON.decode(ExistingCopyExpectation.self, from: Data(contentsOf: root.appendingPathComponent("existing-expected.json")))
        let m = expected.metadata, store = IdentityFileStore(directory: root.appendingPathComponent("Identity"))
        let originalKey = try #require(try store.load(deviceId: m.deviceId))
        var legacyReads = 0
        let key = try store.loadOrCreate(deviceId: m.deviceId, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { legacyReads += 1; return nil })
        #expect(key == originalKey && legacyReads == 0)
        for _ in 0..<3 {
            let identity = try DeviceIdentity.persistent(deviceId: m.deviceId, userId: m.userId, spaceId: m.spaceId, directory: root.appendingPathComponent("Identity"), needsExistingIdentity: true, migrateLegacy: true, timeZoneIdentifier: expected.timeZone, protocolVersion: 3)
            #expect(identity.descriptor.publicKey == expected.descriptor.publicKey && identity.descriptor.fingerprint == expected.descriptor.fingerprint)
            let repository = try TogetherRepository(url: root.appendingPathComponent("legacy.store"))
            let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: FixedDateProvider(expected.capturedAt))
            #expect(engine.peer == expected.peer)
            #expect(try repository.load(RelayBinding.self, key: "relay-binding") == expected.binding)
            #expect(try hashes(engine.snapshot) == expected.entities)
            #expect(engine.operations.count == expected.operationHashes.count)
            for operation in engine.operations { #expect(try hash(operation) == expected.operationHashes[operation.id.uuidString]) }
            let before = engine.snapshot, count = engine.operations.count
            try engine.merge(engine.operations)
            try engine.merge(engine.operations.reversed())
            #expect(engine.snapshot == before && engine.operations.count == count)
            let locals = Dictionary(uniqueKeysWithValues: try repository.container.mainContext.fetch(FetchDescriptor<LocalRecord>()).map { ($0.key, digest($0.body)) })
            for (key, value) in expected.localRecords { #expect(locals[key] == value) }
            #expect(engine.snapshot.finance == FinanceSnapshot())
            #expect(try store.load(deviceId: m.deviceId) == originalKey)
        }
    }
    private func hashes(_ snapshot: DomainSnapshot) throws -> [String: String] {
        var result: [String: String] = [:]
        func add<T: Encodable>(_ prefix: String, _ id: UUID, _ value: T) throws { result[prefix + id.uuidString] = try hash(value) }
        for item in snapshot.profiles.values { try add("profile:", item.id, item) }
        for item in snapshot.tasks.values { try add("task:", item.id, item) }
        for item in snapshot.rules.values { try add("rule:", item.id, item) }
        for item in snapshot.grants.values { try add("grant:", item.id, item) }
        for item in snapshot.wishes.values { try add("wish:", item.id, item) }
        for item in snapshot.gifts.values { try add("gift:", item.id, item) }
        for item in snapshot.mediaAssets.values { try add("media:", item.id, item) }
        result["adjustments"] = try hash(snapshot.adjustments); result["space"] = try hash(snapshot.space)
        return result
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func hash<T: Encodable>(_ value: T) throws -> String { digest(try CanonicalJSON.encode(value)) }
}
private struct ExistingCopyExpectation: Codable {
    let metadata: LocalIdentityMetadata; let descriptor: DeviceDescriptor; let capturedAt: Date; let timeZone: String
    let peer: PairedPeer?; let binding: RelayBinding?; let entities: [String: String]; let localRecords: [String: String]; let operationHashes: [String: String]
}
