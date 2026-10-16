import CryptoKit
import Foundation
import Testing

@testable import TogetherCore

@Suite("Adversarial handshake and durable recovery") struct ReplicationAdversarialRecoveryTests {
  @Test func retiredHelloCannotReconstructAnOldCounterSpace() throws {
    let f = try ReplicationFixture()
    let trust = try SpaceAuthorization(genesis: f.genesis)
    for version4 in [false, true] {
      let localKey = Curve25519.KeyAgreement.PrivateKey()
      let remote1 = Curve25519.KeyAgreement.PrivateKey()
      let remote2 = Curve25519.KeyAgreement.PrivateKey()
      let authorization = version4 ? trust : nil
      let local = try RelaySecureSession.hello(
        identity: f.a, ephemeral: localKey, routeId: trust.spaceId, profileName: "Synthetic",
        authorization: authorization)
      let one = try RelaySecureSession.hello(
        identity: f.b, ephemeral: remote1, routeId: trust.spaceId, profileName: "Synthetic",
        authorization: authorization)
      let two = try RelaySecureSession.hello(
        identity: f.b, ephemeral: remote2, routeId: trust.spaceId, profileName: "Synthetic",
        authorization: authorization)
      var history = RelayHandshakeHistory()
      try history.accept(one)
      let first = try RelaySecureSession(
        identity: f.a, ephemeral: localKey, local: local, remote: one, authorization: authorization)
      let packet = try first.seal(Data("First synthetic payload".utf8))
      try history.accept(two)
      let second = try RelaySecureSession(
        identity: f.a, ephemeral: localKey, local: local, remote: two, authorization: authorization)
      #expect(first.transcript != second.transcript && packet.header?.sequence == 1)
      #expect(throws: ReplicationError.unauthorized) { try history.accept(one) }
      // A physical reconnect uses a genuinely new local ephemeral key.
      let freshKey = Curve25519.KeyAgreement.PrivateKey()
      let fresh = try RelaySecureSession.hello(
        identity: f.a, ephemeral: freshKey, routeId: trust.spaceId, profileName: "Synthetic",
        authorization: authorization)
      let restarted = try RelaySecureSession(
        identity: f.a, ephemeral: freshKey, local: fresh, remote: one, authorization: authorization)
      #expect(restarted.transcript != first.transcript)
    }
  }
  @Test @MainActor func knownInvalidStagingIsQuarantinedAndRestartCanRepairTheGap() async throws {
    let f = try ReplicationFixture()
    let trust = try SpaceAuthorization(genesis: f.genesis)
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await store.restore()
    let first = try AuthorizedOperation.sign(
      f.operation(f.a), identity: f.a, trust: trust, previous: DeviceFrontier())
    var badFirst = first
    badFirst.body.previousDigest = String(repeating: "a", count: 64)
    badFirst.signature = try f.a.sign(CanonicalJSON.encode(badFirst.body))
    await #expect(throws: ReplicationError.invalidSignature) {
      try await store.receive([.authorized(badFirst)])
    }
    #expect(try repo.operationCount() == 0)
    // Rehearse a poisoned staging record written by the pre-fix build.
    try repo.save(
      ReplicationRecord.authorized(badFirst), key: "replication4/stage/" + badFirst.id.uuidString)
    try repo.save(
      badFirst.id,
      key: "replication4/sequence/" + badFirst.body.epochId.uuidString + "/00000000000000000001")
    try await store.restore()
    #expect(
      try repo.load(ReplicationRecord.self, key: "replication4/stage/" + badFirst.id.uuidString)
        == nil)
    let second = try AuthorizedOperation.sign(
      f.operation(f.a, clock: 2), identity: f.a, trust: trust,
      previous: DeviceFrontier(sequence: 1, digest: first.digest))
    var badSecond = second
    badSecond.body.previousDigest = String(repeating: "b", count: 64)
    badSecond.signature = try f.a.sign(CanonicalJSON.encode(badSecond.body))
    _ = try badSecond.verify(in: trust)
    try await store.receive([.authorized(badSecond)])
    try await store.receive([.authorized(first)])
    #expect(try repo.operationCount() == 1)
    #expect(
      try repo.load(ReplicationRecord.self, key: "replication4/stage/" + badSecond.id.uuidString)
        == nil)
    #expect(
      try repo.load(
        AuthorizedOperation.self, key: "replication4/quarantine/" + (try badSecond.digest))
        == badSecond)
    let reopened = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await reopened.restore()
    try await reopened.receive([.authorized(second)])
    #expect(try repo.operationCount() == 2)
    #expect(try await reopened.projectionInput().operations.count == 2)
  }
  @Test @MainActor func strippedPostMigrationRecordCannotPermanentlyPoisonTheLegacySeal()
    async throws
  {
    let f = try ReplicationFixture()
    let legacy = try f.operation(f.a)
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(
        context: f.context, legacyCheckpoint: ReplicationHash.inventory([InventoryEntry(legacy)])),
      with: [f.a, f.b])
    let trust = try SpaceAuthorization(genesis: genesis)
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await store.restore()
    let post = try AuthorizedOperation.sign(
      f.operation(f.a, clock: 2), identity: f.a, trust: trust, previous: DeviceFrontier())
    await #expect(throws: ReplicationError.contentCollision) {
      try await store.receive([.legacy(post.body.signedOperation)])
    }
    #expect(
      try repo.load(Int.self, key: "replication4/legacy-count") == 0 && repo.operationCount() == 0)
    let reopened = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await reopened.restore()
    try await reopened.receive([.legacy(legacy)])
    let input = try await reopened.projectionInput()
    #expect(input.operations == [legacy])
    #expect(try repo.operationCount() == 1)
  }
  @Test @MainActor func revokedEquivocationRetainsRawHistoryButAcceptsOnlyThePinnedBranch()
    async throws
  {
    let f = try ReplicationFixture()
    let phone = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    var trust = try SpaceAuthorization(genesis: f.genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await store.restore()
    let honest = try AuthorizedOperation.sign(
      f.operation(phone, title: "Synthetic pinned branch"), identity: phone, trust: trust,
      previous: DeviceFrontier())
    let divergent = try AuthorizedOperation.sign(
      f.operation(phone, title: "Synthetic divergent branch"), identity: phone, trust: trust,
      previous: DeviceFrontier())
    try await store.receive([.authorized(divergent)])
    try trust.apply(
      trust.revoke(
        phone.descriptor.deviceId, at: DeviceFrontier(sequence: 1, digest: honest.digest),
        authorizedBy: f.a))
    try await store.updateAuthorization(trust.archive)
    #expect(try await store.projectionInput().operations.isEmpty)
    #expect(try await store.index.checkpoint().count == 0 && repo.operationCount() == 1)
    let excluded = try InventoryEntry(ReplicationRecord.authorized(divergent))
    #expect(try await store.index.missing([excluded]) == [excluded])
    let ledger = DeviceAcknowledgementLedger(repository: repo, index: store.index, identity: f.b)
    #expect(try await ledger.receipt(entries: [excluded], trust: trust) == nil)
    await #expect(throws: ReplicationError.unauthorized) {
      try await store.record(for: divergent.body.signedOperation)
    }
    let before = try ReplicaEngine(repository: repo, identity: f.b)
    #expect(before.snapshot.tasks.isEmpty && before.context.spaceId == f.context.spaceId)
    let countBefore = try repo.operationCount()
    try await store.receive([.authorized(honest)])
    let accepted = try await store.projectionInput().operations.map(\.id)
    #expect(accepted.contains(honest.id) && !accepted.contains(divergent.id))
    #expect(
      try await store.index.checkpoint().count == countBefore
        && repo.operationCount() == countBefore + 1)
    let restored = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await restored.restore()
    let restoredIds = try await restored.projectionInput().operations.map(\.id)
    #expect(restoredIds.contains(honest.id) && !restoredIds.contains(divergent.id))
    let after = try ReplicaEngine(repository: repo, identity: f.b)
    #expect(
      after.snapshot.tasks.count == 1
        && after.snapshot.tasks[divergent.body.signedOperation.operation.entityId] == nil)
  }
  @Test @MainActor func partiallyPoisonedLegacyPoolCanRetryAnHonestFullBatch() async throws {
    let f = try ReplicationFixture()
    let one = try f.operation(f.a)
    let two = try f.operation(f.a, clock: 2)
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(
        context: f.context,
        legacyCheckpoint: ReplicationHash.inventory([InventoryEntry(one), InventoryEntry(two)])),
      with: [f.a, f.b])
    let trust = try SpaceAuthorization(genesis: genesis)
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await store.restore()
    try await store.receive([.legacy(f.operation(f.a, clock: 3))])
    await #expect(throws: ReplicationError.contentCollision) {
      try await store.receive([.legacy(one), .legacy(two)])
    }
    #expect(try repo.load(Int.self, key: "replication4/legacy-count") == 0)
    let restored = try AuthorizedReplicationStore(
      repository: repo, identity: f.b, authorization: trust)
    try await restored.restore()
    try await restored.receive([.legacy(one), .legacy(two)])
    #expect(try await restored.projectionInput().operations.count == 2)
  }
  @Test @MainActor func staleDetachedProjectionCannotReinstallRevokedAuthorization() async throws {
    let pair = try TwoReplicas()
    try pair.exchange()
    let body = try await C1ReplicationService.migrationProposal(engine: pair.b)
    let genesis = try SignedSpaceGenesis.sign(body, with: [pair.a.identity, pair.b.identity])
    let phone = try DeviceIdentity(userId: pair.a.identity.descriptor.userId, protocolVersion: 4)
    var trust = try SpaceAuthorization(genesis: genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: pair.a.identity))
    let store = try await pair.b.activateReplication4(trust.archive)
    let signed = try phone.sign(
      SyncOperation(
        deviceId: phone.descriptor.deviceId, actorId: phone.descriptor.userId, entityId: UUID(),
        entityType: .task, operationType: .create, lamportClock: 100,
        payload: [
          "spaceId": .id(trust.spaceId), "createdBy": .id(phone.descriptor.userId),
          "title": .string("Synthetic revoked task"),
        ]))
    let record = try AuthorizedOperation.sign(
      signed, identity: phone, trust: trust, previous: DeviceFrontier())
    try await store.receive([.authorized(record)])
    try await pair.b.refreshFromReplication(store)
    #expect(pair.b.snapshot.tasks.count == 1)
    let gate = ProjectionPause()
    let old = Task {
      try await pair.b.refreshFromReplication(
        store,
        project: { log, context in
          await gate.pauseFirst()
          return OperationProjector.replay(log, context: context)
        })
    }
    while !(await gate.hasEntered) { await Task.yield() }
    try trust.apply(
      trust.revoke(phone.descriptor.deviceId, at: DeviceFrontier(), authorizedBy: pair.a.identity))
    try await store.updateAuthorization(trust.archive)
    try await pair.b.refreshFromReplication(store)
    #expect(pair.b.snapshot.tasks.isEmpty && !pair.b.isAuthorizedRemote(phone.descriptor))
    await gate.release()
    try await old.value
    #expect(pair.b.snapshot.tasks.isEmpty && !pair.b.isAuthorizedRemote(phone.descriptor))
    #expect(pair.b.context.spaceId == body.spaceId)
  }

}

private actor ProjectionPause {
  var hasEntered = false
  private var continuation: CheckedContinuation<Void, Never>?
  func pauseFirst() async {
    guard !hasEntered else { return }
    hasEntered = true
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}
