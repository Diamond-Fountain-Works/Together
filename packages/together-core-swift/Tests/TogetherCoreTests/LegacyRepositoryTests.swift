import Foundation
import Testing
@testable import TogetherCore

@Suite("Legacy SQLite and unchanged signed facts") @MainActor struct LegacyRepositoryTests {
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Together-storage-compat-\(UUID())")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    private func data(_ value: some Encodable) throws -> Data { try CanonicalJSON.encode(value) }

    @Test func markedDatabaseReopensOnModernSystemWithoutChangingIdentityOrOperationBytes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("legacy.store"), fixture = try ReplicationFixture()
        let op = try fixture.operation(fixture.a), bytes = try data(op)
        let metadata = LocalIdentityMetadata(deviceId: fixture.a.descriptor.deviceId, userId: fixture.a.descriptor.userId, spaceId: fixture.context.spaceId)
        var repository: TogetherRepository? = try TogetherRepository(url: url, backend: .legacySQLite)
        try repository!.insert([op, op])
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try repository!.save(metadata, key: "local-identity")
        try repository!.save(fixture.b.descriptor, key: "paired-device")
        try repository!.saveAtomically(["ack/peer": data(DeviceFrontier(sequence: 1, digest: ReplicationHash.digest(bytes)))])
        #expect(try repository!.operationCount() == 1)
        repository = nil
        let reopened = try TogetherRepository(url: url)
        #expect(reopened.backendKind == .legacySQLite)
        #expect(try reopened.operationPage().map(\.bytes) == [bytes])
        #expect(try reopened.load(LocalIdentityMetadata.self, key: "local-identity")?.deviceId == metadata.deviceId)
        #expect(try reopened.load(LocalIdentityMetadata.self, key: "local-identity")?.userId == metadata.userId)
        #expect(try reopened.load(DeviceDescriptor.self, key: "paired-device") == fixture.b.descriptor)
        #expect(try reopened.load(DeviceFrontier.self, key: "ack/peer")?.sequence == 1)
        #expect(try reopened.allOperations()[0].verified(by: fixture.a.descriptor))
    }

    @Test func duplicateCollisionRollsBackTheWholeOperationBatchAndGiftSlot() throws {
        let fixture = try ReplicationFixture(), repository = try TogetherRepository(inMemory: true, backend: .legacySQLite)
        let original = try fixture.operation(fixture.a), added = try fixture.operation(fixture.b)
        let collision = try fixture.operation(fixture.a, id: original.id, title: "Different signed bytes")
        try repository.insert([original]); try repository.save("keep", key: "prior")
        let revision = repository.operationRevision
        #expect(throws: RepositoryError.reusedOperationId) {
            try repository.commitReplication([added, collision], records: ["ack": data("uncommitted")], removing: ["prior"])
        }
        #expect(try repository.operationCount() == 1 && repository.operationRevision == revision)
        #expect(try repository.load(String.self, key: "prior") == "keep")
        #expect(try repository.load(String.self, key: "ack") == nil)
        #expect(throws: RepositoryError.reusedOperationId) {
            try repository.commitGift([collision], giftId: UUID(), slot: "failed-slot", replicationRecords: [:])
        }
        #expect(try repository.load(UUID.self, key: "gift-slot:failed-slot") == nil)
        try repository.insert([original]); #expect(repository.operationRevision == revision)
    }

    @Test func giftQuotaIsSharedByIndependentConnectionsAndPersists() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("quota.store"), fixture = try ReplicationFixture()
        let a = try TogetherRepository(url: url, backend: .legacySQLite), b = try TogetherRepository(url: url)
        let gift = UUID(), first = try fixture.operation(fixture.a), second = try fixture.operation(fixture.b)
        try a.commitGift([first], giftId: gift, slot: "space/sender/2026-10-09", replicationRecords: ["receipt": data("first")])
        #expect(throws: TogetherError.self) {
            try b.commitGift([second], giftId: UUID(), slot: "space/sender/2026-10-09", replicationRecords: ["receipt": data("wrong")])
        }
        #expect(try b.operationCount() == 1)
        #expect(try b.load(UUID.self, key: "gift-slot:space/sender/2026-10-09") == gift)
        #expect(try b.load(String.self, key: "receipt") == "first")
    }

    @Test func certifiedCommitChecksAuthorizationAndHeadInsideTransaction() throws {
        let fixture = try ReplicationFixture(), repository = try TogetherRepository(inMemory: true, backend: .legacySQLite)
        let trust = try SpaceAuthorization(genesis: fixture.genesis), op = try fixture.operation(fixture.a)
        try repository.save(trust.archive, key: "replication4/authorization")
        let headKey = "replication4/head/fixture", next = DeviceFrontier(sequence: 1, digest: ReplicationHash.digest(try data(op)))
        try repository.commitCertified([op], records: [headKey: data(next), "signed-ack": data("persisted")], removing: [], headKey: headKey, expectedHead: DeviceFrontier(), authorizationDigest: trust.digest)
        #expect(try repository.operationCount() == 1 && repository.load(DeviceFrontier.self, key: headKey) == next)
        #expect(throws: ReplicationError.staleAuthorization) {
            try repository.commitCertified([fixture.operation(fixture.b)], records: ["wrong": data(true)], removing: ["signed-ack"], headKey: headKey, expectedHead: DeviceFrontier(), authorizationDigest: trust.digest)
        }
        #expect(try repository.load(String.self, key: "signed-ack") == "persisted")
        #expect(try repository.load(Bool.self, key: "wrong") == nil && repository.operationCount() == 1)
    }

    @Test func boundedPagesAndLocalPredecessorMatchExactByteOrdering() throws {
        let fixture = try ReplicationFixture(), repository = try TogetherRepository(inMemory: true, backend: .legacySQLite)
        let operations = try (0..<310).map { try fixture.operation(fixture.a, clock: Int64($0 + 1)) }
        try repository.insert(operations)
        var read: [StoredOperationBytes] = [], cursor: String?
        while true {
            let page = try repository.operationPage(after: cursor, limit: 128)
            if page.isEmpty { break }; read += page; cursor = page.last!.id
        }
        #expect(read.map(\.id) == operations.map { $0.id.uuidString }.sorted())
        #expect(Set(read.map(\.bytes)) == Set(try operations.map(data)))
        #expect(try repository.operationBytes(ids: [operations[0].id]).first?.bytes == data(operations[0]))
        #expect(throws: ReplicationError.bounds) { try repository.operationPage(limit: 257) }
        try repository.saveAtomically(["local/001": data(1), "local/003": data(3), "local/010": data(10), "other/001": data(9)])
        #expect(try repository.localPage(prefix: "local/", limit: 2).map(\.id) == ["local/001", "local/003"])
        #expect(try repository.localPage(prefix: "local/", after: "local/003").map(\.id) == ["local/010"])
        #expect(try repository.localAtOrBefore(prefix: "local/", suffix: "009")?.id == "local/003")
        #expect(try repository.localBytes(keys: ["local/003"]).first?.bytes == data(3))
        let oldRevision = repository.operationRevision
        #expect(try repository.cacheRows([.init(key: "task/cached", type: "task", bytes: data(true))], expectedRevision: oldRevision))
        try repository.insert([fixture.operation(fixture.b)])
        #expect(try !repository.cacheRows([.init(key: "task/cached", type: "task", bytes: nil)], expectedRevision: oldRevision))
    }

    @Test func newerSchemaAndForeignStoreFailClosedWithoutOverwritingFiles() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let foreign = root.appendingPathComponent("foreign.store"), original = Data("NOT_A_TOGETHER_DATABASE".utf8)
        try original.write(to: foreign)
        #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: foreign, backend: .legacySQLite) }
        #expect(try Data(contentsOf: foreign) == original)
        let linked = root.appendingPathComponent("linked.store")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: foreign)
        #expect(throws: RepositoryError.self) { try TogetherRepository(url: linked, backend: .legacySQLite) }
        #expect(try Data(contentsOf: foreign) == original)
        let url = root.appendingPathComponent("future.store")
        var repository: TogetherRepository? = try TogetherRepository(url: url, backend: .legacySQLite)
        try repository!.save("preserved", key: "sentinel"); repository = nil
        var bytes = try Data(contentsOf: url); bytes.replaceSubrange(60..<64, with: [0, 0, 0, 2]); try bytes.write(to: url)
        #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: url) }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func currentSwiftDataStoreKeepsItsBackendAndRejectsLegacyInterpretation() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("modern.store"), fixture = try ReplicationFixture(), op = try fixture.operation(fixture.a)
        let modern = try TogetherRepository(url: url, backend: .swiftData)
        try modern.insert([op]); try modern.save(fixture.a.descriptor, key: "local-device")
        let original = try Data(contentsOf: url)
        #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: url, backend: .legacySQLite) }
        #expect(try Data(contentsOf: url) == original)
        let reopened = try TogetherRepository(url: url)
        #expect(reopened.backendKind == .swiftData && reopened.swiftDataContainer != nil)
        #expect(try reopened.operationPage().map(\.bytes) == [data(op)])
        #expect(try reopened.load(DeviceDescriptor.self, key: "local-device") == fixture.a.descriptor)
    }

    @Test func mixedBackendsConvergeTasksWishesFinanceAndTombstones() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let aID = try DeviceIdentity(timeZoneIdentifier: "Asia/Shanghai"), bID = try DeviceIdentity(timeZoneIdentifier: "Asia/Shanghai")
        let clock = FixedDateProvider(instant("2026-10-09T04:00:00Z"))
        let a = try ReplicaEngine(repository: TogetherRepository(inMemory: true, backend: .legacySQLite), identity: aID, mediaRoot: root.appendingPathComponent("a-media"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: bID, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
        try a.authorize(PairedPeer(descriptor: bID.descriptor, host: "127.0.0.1", port: 0)); try b.authorize(PairedPeer(descriptor: aID.descriptor, host: "127.0.0.1", port: 0))
        func exchange() throws { for _ in 0..<3 { let left = a.operations, right = b.operations; try a.merge(right); try b.merge(left) } }
        try exchange()
        let task = try a.createTask(title: "SQLite task"), grant = try a.grant(fulfiller: aID.descriptor.userId, beneficiary: bID.descriptor.userId, quantity: 3, date: CivilDate(iso: "2026-10-09")!, notes: "")
        _ = try a.deposit(FinanceAmount(original: "100.01"), by: aID.descriptor.userId, on: CivilDate(iso: "2026-10-09")!)
        try exchange()
        let wish = try b.createWish(grantId: grant, title: "Shared wish", description: "")
        _ = try b.createExpense(title: "AA", amount: FinanceAmount(original: "0.03"), payment: .init(kind: .equalSplit, userIds: [aID.descriptor.userId, bID.descriptor.userId]), on: CivilDate(iso: "2026-10-09")!)
        try exchange(); try a.requestFulfillment(wish); try exchange(); try b.confirmFulfillment(wish)
        try a.deleteTask(task); try exchange()
        #expect(a.snapshot == b.snapshot)
        #expect(a.snapshot.balance(for: grant).remaining == 2)
        #expect(a.snapshot.tasks[task]?.deletedAt != nil)
        #expect(Set(try a.repository.allOperations().map(data)) == Set(try b.repository.allOperations().map(data)))
        #expect(a.snapshot.finance == b.snapshot.finance)
    }

    @Test func signedCatchUpAndLostAcknowledgementRecoverFromSQLiteAfterRestart() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
        let aURL = root.appendingPathComponent("a.store"), bURL = root.appendingPathComponent("b.store")
        let a = try AuthorizedReplicationStore(repository: TogetherRepository(url: aURL, backend: .legacySQLite), identity: f.a, authorization: trust)
        let b = try AuthorizedReplicationStore(repository: TogetherRepository(url: bURL, backend: .legacySQLite), identity: f.b, authorization: trust)
        try await a.restore(); try await b.restore()
        let al = DeviceAcknowledgementLedger(repository: a.repository, index: a.index, identity: f.a)
        let bl = DeviceAcknowledgementLedger(repository: b.repository, index: b.index, identity: f.b)
        let op = try f.operation(f.a); _ = try await a.append(op)
        let wire = ReplicationTestWire()
        let ab = PagedReplicationSession(store: a, ledger: al, remote: f.b.descriptor, send: { try await wire.send($0, to: 1) })
        let ba = PagedReplicationSession(store: b, ledger: bl, remote: f.a.descriptor, send: { try await wire.send($0, to: 0) })
        await wire.dropAcknowledgements(true)
        try await ab.synchronize(); try await ba.synchronize(); try await pump(wire, [ab, ba])
        #expect(try b.repository.operationCount() == 1)
        #expect(try await !al.partnerHasPersisted(a.index.entry(for: op.id), trust: a.authorization))
        await wire.dropAcknowledgements(false)
        try await ab.synchronize(); try await ba.synchronize(); try await pump(wire, [ab, ba])
        #expect(try await al.partnerHasPersisted(a.index.entry(for: op.id), trust: a.authorization))
        let recovered = try AuthorizedReplicationStore(repository: TogetherRepository(url: aURL), identity: f.a, authorization: trust)
        try await recovered.restore()
        let ledger = DeviceAcknowledgementLedger(repository: recovered.repository, index: recovered.index, identity: f.a)
        #expect(try await recovered.index.checkpoint() == b.index.checkpoint())
        #expect(try await ledger.partnerHasPersisted(recovered.index.entry(for: op.id), trust: recovered.authorization))
        #expect(try recovered.repository.operationPage().map(\.bytes) == [data(op)])
        await ab.invalidate(); await ba.invalidate()
    }
}
