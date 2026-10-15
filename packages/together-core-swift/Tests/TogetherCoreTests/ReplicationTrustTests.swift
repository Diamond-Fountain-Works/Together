import Foundation
import Testing

@testable import TogetherCore

struct ReplicationFixture {
  let a: DeviceIdentity
  let b: DeviceIdentity
  let context: ReplicaContext
  let genesis: SignedSpaceGenesis
  init(legacy: [SignedOperation] = []) throws {
    a = try DeviceIdentity(
      displayName: "Synthetic A", timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
    b = try DeviceIdentity(
      displayName: "Synthetic B", timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
    context = ReplicaContext(local: a.descriptor, peer: b.descriptor)
    genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(
        context: context,
        legacyCheckpoint: ReplicationHash.inventory(try legacy.map(InventoryEntry.init))),
      with: [a, b])
  }
  func operation(
    _ identity: DeviceIdentity, id: UUID = UUID(), clock: Int64 = 1, entity: UUID = UUID(),
    action: OperationType = .create, title: String = "Synthetic task"
  ) throws -> SignedOperation {
    try identity.sign(
      SyncOperation(
        operationId: id, deviceId: identity.descriptor.deviceId,
        actorId: identity.descriptor.userId,
        entityId: entity, entityType: .task, operationType: action, lamportClock: clock,
        payload: action == .create
          ? [
            "spaceId": .id(context.spaceId), "createdBy": .id(identity.descriptor.userId),
            "title": .string(title),
          ] : ["title": .string(title)], createdAt: Date(timeIntervalSince1970: 1_791_532_800)))
  }
}
@Suite("Version 4 trust and immutable inventory") struct ReplicationTrustTests {
  @Test func preservesTwoUsersSpaceKeysAndOriginalProtocol3Bytes() throws {
    let f = try ReplicationFixture()
    let op = try f.operation(f.a)
    let original = try CanonicalJSON.encode(op)
    var trust = try SpaceAuthorization(genesis: f.genesis, existingPins: f.context)
    let phone = try DeviceIdentity(
      userId: f.a.descriptor.userId, displayName: "Synthetic phone", protocolVersion: 4)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
    let certified = try AuthorizedOperation.sign(
      op, identity: f.a, trust: trust, previous: DeviceFrontier())
    _ = try certified.verify(in: trust)
    let context = try ReplicaContext(
      local: phone.descriptor, authorization: trust,
      acceptedContent: [op.id: InventoryEntry(op).contentDigest])
    #expect(context.spaceId == f.context.spaceId)
    #expect(context.validSpaceIds == f.context.validSpaceIds)
    #expect(context.members == f.context.members)
    #expect(context.devices.count == 3)
    #expect(try CanonicalJSON.encode(certified.body.signedOperation) == original)
    #expect(OperationProjector.replay([op], context: context).tasks.count == 1)
  }
  @Test func sameUserClaimAndOtherPartnerCannotGrantDevices() throws {
    let f = try ReplicationFixture()
    let trust = try SpaceAuthorization(genesis: f.genesis)
    let forged = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    #expect(!trust.containsActive(forged.descriptor))
    #expect(throws: ReplicationError.self) {
      try trust.grant(forged.descriptor, authorizedBy: forged)
    }
    #expect(throws: ReplicationError.self) { try trust.grant(forged.descriptor, authorizedBy: f.b) }
    let op = try f.operation(forged)
    #expect(throws: ReplicationError.self) {
      try AuthorizedOperation.sign(op, identity: forged, trust: trust, previous: DeviceFrontier())
    }
  }
  @Test func signedGrantForkAndTamperedArchiveFailClosed() throws {
    let f = try ReplicationFixture()
    var trust = try SpaceAuthorization(genesis: f.genesis)
    let p = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    let q = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    let first = try trust.grant(p.descriptor, authorizedBy: f.a)
    let fork = try trust.grant(q.descriptor, authorizedBy: f.a)
    try trust.apply(first)
    try trust.apply(first)
    #expect(throws: ReplicationError.authorizationFork) { try trust.apply(fork) }
    var archive = trust.archive
    archive.events[0].body.device.userId = f.b.descriptor.userId
    #expect(throws: ReplicationError.self) { try SpaceAuthorization.restore(archive) }
    #expect(try SpaceAuthorization.restore(trust.archive) == trust)
  }
  @Test func revocationDoesNotTrustCreatedAtOrEraseHistoricalSignature() throws {
    let f = try ReplicationFixture()
    var trust = try SpaceAuthorization(genesis: f.genesis)
    let p = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    try trust.apply(trust.grant(p.descriptor, authorizedBy: f.a))
    let old = try AuthorizedOperation.sign(
      f.operation(p), identity: p, trust: trust, previous: DeviceFrontier())
    let head = try DeviceFrontier(sequence: 1, digest: old.digest)
    let newer = try AuthorizedOperation.sign(
      f.operation(p, clock: 2), identity: p, trust: trust, previous: head)
    try trust.apply(trust.revoke(p.descriptor.deviceId, at: head, authorizedBy: f.a))
    #expect(!trust.containsActive(p.descriptor))
    _ = try old.verify(in: trust)
    #expect(throws: ReplicationError.revoked) { try newer.verify(in: trust) }
    #expect(throws: ReplicationError.self) {
      try trust.revoke(f.a.descriptor.deviceId, at: DeviceFrontier(), authorizedBy: f.a)
    }
  }
  @Test func sameIdDifferentContentProducesDifferentInventory() throws {
    let f = try ReplicationFixture()
    let id = UUID()
    let a = try InventoryEntry(f.operation(f.a, id: id))
    let b = try InventoryEntry(f.operation(f.a, id: id, title: "changed"))
    #expect(a.contentDigest != b.contentDigest)
    #expect(try ReplicationHash.inventory([a]) != ReplicationHash.inventory([b]))
    #expect(throws: ReplicationError.invalidPage) { try ReplicationHash.inventory([a, b]) }
  }
  @Test @MainActor func inventoryBindsTheAuthorizationCertificateAsWellAsSignedContent()
    async throws
  {
    let f = try ReplicationFixture()
    let trust = try SpaceAuthorization(genesis: f.genesis)
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.a, authorization: trust)
    try await store.restore()
    let proof = try await store.append(f.operation(f.a))
    var fork = proof
    fork.body.sequence = 2
    fork.body.previousDigest = String(repeating: "a", count: 64)
    fork.signature = try f.a.sign(CanonicalJSON.encode(fork.body))
    let first = try InventoryEntry(ReplicationRecord.authorized(proof))
    let second = try InventoryEntry(ReplicationRecord.authorized(fork))
    #expect(
      first.contentDigest == second.contentDigest
        && first.certificationDigest != second.certificationDigest)
    await #expect(throws: ReplicationError.contentCollision) {
      try await store.index.missing([second])
    }
    #expect(try ReplicationHash.inventory([first]) != ReplicationHash.inventory([second]))
  }
  @Test @MainActor func removesOnlyOrphanedInventoryCachesNotSignedHistory() async throws {
    let f = try ReplicationFixture()
    let repo = try TogetherRepository(inMemory: true)
    let op = try f.operation(f.a)
    try repo.insert([op])
    try repo.save(
      [InventoryEntry(op)], key: "replication4/inventory/previous-process/snapshot/start")
    _ = try await OperationInventoryIndex(repository: repo).checkpoint()
    #expect(try repo.localPage(prefix: "replication4/inventory/previous-process/").isEmpty)
    #expect(try repo.allOperations() == [op])
  }
  @Test @MainActor func indexedStoreRejectsCollisionsAtomicallyAndSurvivesReopen() async throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
      "together-v4-\(UUID())")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let f = try ReplicationFixture()
    let id = UUID()
    let a = try f.operation(f.a, id: id)
    let b = try f.operation(f.a, id: id, title: "collision")
    let repo = try TogetherRepository(url: temp.appendingPathComponent("test.store"))
    let index = OperationInventoryIndex(repository: repo)
    try repo.insert([a, a])
    #expect(try repo.operationCount() == 1)
    #expect(throws: RepositoryError.self) {
      try repo.commitReplication([b], records: ["should-not-commit": Data("true".utf8)])
    }
    #expect(try repo.load(Bool.self, key: "should-not-commit") == nil)
    let cp = try await index.checkpoint()
    #expect(cp.count == 1)
    let page = try await index.page(after: nil, checkpoint: cp)
    try page.validate()
    await #expect(throws: ReplicationError.contentCollision) {
      try await index.missing([InventoryEntry(b)])
    }
    let reopened = try TogetherRepository(url: temp.appendingPathComponent("test.store"))
    #expect(try await OperationInventoryIndex(repository: reopened).checkpoint() == cp)
    #expect(try reopened.allOperations() == [a])
  }
}
