import Foundation
import CryptoKit
import Testing
@testable import TogetherCore

@Suite("Local identity files") struct IdentityFileTests {
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("together-identity-test-\(UUID())") }

    @Test func newInstallAndRestartNeverReadKeychain() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = IdentityFileStore(directory: root), id = UUID()
        var reads = 0
        let first = try store.loadOrCreate(deviceId: id, needsExistingIdentity: false, legacyReader: { reads += 1; return nil })
        let second = try IdentityFileStore(directory: root).loadOrCreate(deviceId: id, needsExistingIdentity: true, legacyReader: { reads += 1; return nil })
        #expect(first == second && first.count == 32 && reads == 0)
        let file = try FileManager.default.attributesOfItem(atPath: store.keyURL(deviceId: id).path)
        let directory = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directory[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func oldIdentityRequiresExplicitMigrationAndDeniedAccessDoesNotRotate() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = IdentityFileStore(directory: root), id = UUID()
        var reads = 0
        #expect(throws: (any Error).self) { try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, legacyReader: { reads += 1; return Data(repeating: 1, count: 32) }) }
        #expect(reads == 0)
        #expect(throws: (any Error).self) { try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { reads += 1; throw CocoaError(.userCancelled) }) }
        #expect(reads == 1)
        #expect(!FileManager.default.fileExists(atPath: store.keyURL(deviceId: id).path))
        #expect(throws: (any Error).self) { try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { nil }) }
        #expect(!FileManager.default.fileExists(atPath: store.keyURL(deviceId: id).path))
    }

    @Test func legacyMigrationKeepsExactKeyAndRunsOnlyOnce() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = IdentityFileStore(directory: root), id = UUID(), key = Curve25519.Signing.PrivateKey().rawRepresentation
        var reads = 0
        let first = try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { reads += 1; return key })
        let second = try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { reads += 1; return nil })
        #expect(first == key && second == key && reads == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [store.keyURL(deviceId: id).lastPathComponent])
    }

    @Test func corruptionAndMismatchedLegacyKeyNeverGetReplaced() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = IdentityFileStore(directory: root), id = UUID()
        #expect(throws: (any Error).self) {
            try store.loadOrCreate(deviceId: id, needsExistingIdentity: true, migrateLegacy: true,
                                   legacyReader: { Data(repeating: 2, count: 32) }, validate: { _ in throw IdentityStorageError.identityMismatch })
        }
        #expect(!FileManager.default.fileExists(atPath: store.keyURL(deviceId: id).path))
        _ = try store.loadOrCreate(deviceId: id, needsExistingIdentity: false)
        let broken = Data([1, 2, 3]); try broken.write(to: store.keyURL(deviceId: id))
        #expect(throws: (any Error).self) { try store.loadOrCreate(deviceId: id, needsExistingIdentity: false) }
        #expect(try Data(contentsOf: store.keyURL(deviceId: id)) == broken)
    }

    @Test func simultaneousCreationUsesOnePersistedIdentity() async throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let store = IdentityFileStore(directory: root), id = UUID()
        let keys = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<12 { group.addTask { try store.loadOrCreate(deviceId: id, needsExistingIdentity: false) } }
            var results: [Data] = []; for try await key in group { results.append(key) }; return results
        }
        #expect(Set(keys).count == 1)
        #expect(try store.load(deviceId: id) == keys.first)
    }

    @Test @MainActor func migrationAndDatabaseReopenRetainTasksWishesAndPeer() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalKey = Curve25519.Signing.PrivateKey().rawRepresentation
        let identity = try DeviceIdentity(privateKeyData: originalKey, timeZoneIdentifier: "Asia/Shanghai")
        let partner = try DeviceIdentity(timeZoneIdentifier: "Asia/Shanghai")
        let database = root.appendingPathComponent("Together.store")
        var old: ReplicaEngine? = try ReplicaEngine(repository: TogetherRepository(url: database), identity: identity, mediaRoot: root.appendingPathComponent("Media"))
        try old!.authorize(PairedPeer(descriptor: partner.descriptor, host: "127.0.0.1", port: 58431, approvedAt: Date(timeIntervalSince1970: 1_791_547_200)))
        _ = try old!.createTask(title: "PERSISTED_TASK")
        let grant = try old!.grant(fulfiller: partner.descriptor.userId, beneficiary: identity.descriptor.userId, quantity: 3, date: CivilDate(year: 2026, month: 10, day: 9), notes: "")
        _ = try old!.createWish(grantId: grant, title: "PERSISTED_WISH", description: "")
        let snapshot = old!.snapshot, operations = old!.operations, peer = old!.peer
        old = nil
        let files = IdentityFileStore(directory: root.appendingPathComponent("Identity"))
        let key = try files.loadOrCreate(deviceId: identity.descriptor.deviceId, needsExistingIdentity: true, migrateLegacy: true, legacyReader: { originalKey })
        let reopenedIdentity = try DeviceIdentity(deviceId: identity.descriptor.deviceId, userId: identity.descriptor.userId, initialSpaceId: identity.descriptor.initialSpaceId, privateKeyData: key, timeZoneIdentifier: "Asia/Shanghai")
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: database), identity: reopenedIdentity, mediaRoot: root.appendingPathComponent("Media"))
        #expect(reopened.identity.descriptor == identity.descriptor)
        #expect(reopened.snapshot == snapshot && reopened.operations == operations && reopened.peer == peer)
        #expect(reopened.snapshot.balance(for: grant).remaining == 3)
    }
}
