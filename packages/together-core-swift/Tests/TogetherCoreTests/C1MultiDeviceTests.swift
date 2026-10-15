import CryptoKit
import Foundation
import Testing

@testable import TogetherCore

@Suite("C1 protocol 4 security and migration") @MainActor struct C1MultiDeviceTests {
  @Test func sameUserSessionRequiresSignedAuthorizationAndBindsEveryRecipient() throws {
    let f = try ReplicationFixture()
    let phone = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    var trust = try SpaceAuthorization(genesis: f.genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
    let ka = Curve25519.KeyAgreement.PrivateKey()
    let kb = Curve25519.KeyAgreement.PrivateKey()
    let ha = try RelaySecureSession.hello(
      identity: f.a, ephemeral: ka, routeId: trust.spaceId, profileName: "Synthetic A",
      authorization: trust)
    let hb = try RelaySecureSession.hello(
      identity: phone, ephemeral: kb, routeId: trust.spaceId, profileName: "Synthetic phone",
      authorization: trust)
    let a = try RelaySecureSession(
      identity: f.a, ephemeral: ka, local: ha, remote: hb, authorization: trust)
    let b = try RelaySecureSession(
      identity: phone, ephemeral: kb, local: hb, remote: ha, authorization: trust)
    let packet = try a.seal(Data("Synthetic same-user sync".utf8))
    #expect(packet.header?.version == 2)
    #expect(try b.open(packet) == Data("Synthetic same-user sync".utf8))
    #expect(throws: (any Error).self) { try b.open(packet) }
    #expect(throws: (any Error).self) {
      try RelaySecureSession(identity: f.a, ephemeral: ka, local: ha, remote: hb)
    }
    var otherTrust = trust
    try otherTrust.apply(
      otherTrust.revoke(phone.descriptor.deviceId, at: DeviceFrontier(), authorizedBy: f.a))
    #expect(throws: (any Error).self) {
      try RelaySecureSession(
        identity: f.a, ephemeral: ka, local: ha, remote: hb, authorization: otherTrust)
    }
  }
  @Test func deviceVersionUpgradeKeepsTheSameAuthorizedKeyAndSpace() throws {
    let privateBytes = Curve25519.Signing.PrivateKey().rawRepresentation
    let old = try DeviceIdentity(privateKeyData: privateBytes, protocolVersion: 3)
    let d = old.descriptor
    let partner = try DeviceIdentity(protocolVersion: 3)
    let upgraded = try DeviceIdentity(
      deviceId: d.deviceId, userId: d.userId, initialSpaceId: d.initialSpaceId,
      privateKeyData: privateBytes, timeZoneIdentifier: d.initialTimeZoneIdentifier!,
      protocolVersion: 4)
    let context = ReplicaContext(local: d, peer: partner.descriptor)
    let trust = try SpaceAuthorization(
      genesis: SignedSpaceGenesis.sign(
        SpaceGenesisBody(context: context, legacyCheckpoint: ReplicationHash.inventory([])),
        with: [old, partner]))
    let a = Curve25519.KeyAgreement.PrivateKey()
    let b = Curve25519.KeyAgreement.PrivateKey()
    let ha = try RelaySecureSession.hello(
      identity: upgraded, ephemeral: a, routeId: trust.spaceId, profileName: "Synthetic",
      authorization: trust)
    let hb = try RelaySecureSession.hello(
      identity: partner, ephemeral: b, routeId: trust.spaceId, profileName: "Synthetic",
      authorization: trust)
    let session = try RelaySecureSession(
      identity: partner, ephemeral: b, local: hb, remote: ha, expectedPeer: d, authorization: trust)
    #expect(
      session.remoteHello.body.descriptor.publicKey == d.publicKey
        && trust.spaceId == context.spaceId)
  }
  @Test func existingEngineWritesCertifiedFactsAndRestartsWithoutIdentityReset() async throws
  {
    let p = try TwoReplicas()
    let task = try p.a.createTask(title: "Preserved legacy task")
    try p.exchange()
    let before = p.a.identity.descriptor
    let space = p.a.context.spaceId
    let index = OperationInventoryIndex(repository: p.a.repository)
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(context: p.a.context, legacyCheckpoint: await index.checkpoint()),
      with: [p.a.identity, p.b.identity])
    let store = try await p.a.activateReplication4(
      AuthorizationArchive(genesis: genesis, events: []))
    #expect(p.a.context.spaceId == space && p.a.snapshot.tasks[task] != nil)
    let next = try p.a.createTask(title: "Certified offline task")
    let op = try #require(p.a.operations.first { $0.operation.entityId == next })
    guard case .authorized(let certified) = try await store.record(for: op) else {
      Issue.record("Missing certification")
      return
    }
    _ = try certified.verify(in: await store.authorization)
    #expect(p.a.identity.descriptor == before)
    #expect(throws: ReplicationError.incompatibleProtocol) { try p.a.merge(p.b.operations) }
    let reopened = try ReplicaEngine(repository: p.a.repository, identity: p.a.identity)
    #expect(
      reopened.usesReplication4 && reopened.context.spaceId == space
        && reopened.snapshot.tasks[next] != nil)
  }
  @Test func migrationCoSignaturesUseIndependentLocalKeysAndRequireMatchingHistory() async throws {
    let p = try TwoReplicas()
    try p.exchange()
    let body = try await C1ReplicationService.migrationProposal(engine: p.a)
    let signatures = try await [
      C1ReplicationService.signMigrationProposal(engine: p.a, proposal: body),
      C1ReplicationService.signMigrationProposal(engine: p.b, proposal: body),
    ]
    let genesis = SignedSpaceGenesis(
      body: body, signatures: signatures.sorted { $0.deviceId.uuidString < $1.deviceId.uuidString })
    try genesis.verify(existingPins: p.a.context)
    _ = try p.b.createTask(title: "Unshared offline candidate")
    await #expect(throws: ReplicationError.inventoryChanged) {
      try await C1ReplicationService.signMigrationProposal(engine: p.b, proposal: body)
    }
  }
  @Test func mediaReceiptsAreRoutedToTheSenderUserNotMyOtherDevice() async throws {
    let p = try TwoReplicas()
    var draft = LoveGiftDraft()
    draft.text = "Synthetic receipt scope"
    _ = try p.b.sendGift(draft)
    try p.exchange()
    let index = OperationInventoryIndex(repository: p.a.repository)
    let phone = try DeviceIdentity(userId: p.a.identity.descriptor.userId, protocolVersion: 4)
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(context: p.a.context, legacyCheckpoint: await index.checkpoint()),
      with: [p.a.identity, p.b.identity])
    var trust = try SpaceAuthorization(genesis: genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: p.a.identity))
    _ = try await p.a.activateReplication4(trust.archive)
    var ownPackets: [WirePayload] = []
    var partnerPackets: [WirePayload] = []
    let own = OperationLogSyncSession(engine: p.a, remote: phone.descriptor, mediaOnly: true) {
      ownPackets.append($0)
    }
    let partner = OperationLogSyncSession(
      engine: p.a, remote: p.b.identity.descriptor, mediaOnly: true
    ) { partnerPackets.append($0) }
    try own.synchronizeMedia()
    try partner.synchronizeMedia()
    #expect(ownPackets.isEmpty)
    #expect(partnerPackets.count == 1)
    guard case .giftReceipt = partnerPackets[0] else {
      Issue.record("Expected verified gift receipt")
      return
    }
  }
  @Test func oldReceiptCannotMarkADifferentGiftCandidateSynced() throws {
    let p = try TwoReplicas()
    var draft = LoveGiftDraft()
    draft.text = "Synthetic original"
    let id = try p.a.sendGift(draft)
    let gift = try #require(p.a.snapshot.gifts[id])
    let receipt = GiftReceipt(gift: gift, assets: p.a.snapshot.mediaAssets)
    try p.a.acceptReceipt(receipt, from: p.b.identity.descriptor)
    #expect(p.a.deliveryState(gift) == .synced)
    var changed = gift
    changed.creationOperationId = UUID()
    #expect(p.a.deliveryState(changed) == .pendingSync)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_RELAY_TESTS"] == "1"))
  func fourNativeClientsMigrateCatchUpMediaAndRevokeOverRealLocalWorker() async throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
      "together-c1-four-\(UUID())")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let clock = TestClock(instant("2026-10-09T04:00:00Z"))
    let ia = try DeviceIdentity(protocolVersion: 3)
    let ib = try DeviceIdentity(protocolVersion: 3)
    let a = try ReplicaEngine(
      repository: TogetherRepository(url: temp.appendingPathComponent("a.store")), identity: ia,
      mediaRoot: temp.appendingPathComponent("am"), dateProvider: clock)
    let b = try ReplicaEngine(
      repository: TogetherRepository(url: temp.appendingPathComponent("b.store")), identity: ib,
      mediaRoot: temp.appendingPathComponent("bm"), dateProvider: clock)
    let url = try #require(
      URL(
        string: ProcessInfo.processInfo.environment["TOGETHER_RELAY_TEST_URL"]
          ?? "http://127.0.0.1:8787"))
    let oldA = PairingService(engine: a, serviceURL: url)
    let oldB = PairingService(engine: b, serviceURL: url)
    defer {
      oldA.disconnect()
      oldB.disconnect()
    }
    await oldA.createInvitation()
    await oldB.joinInvitation(try #require(oldA.invitationCode))
    try await eventually({ oldA.proposal != nil && oldB.proposal != nil }, seconds: 20)
    await oldA.confirmPairing()
    await oldB.confirmPairing()
    try await eventually(
      { oldA.isOnline && oldB.isOnline && a.snapshot == b.snapshot }, seconds: 20)
    let oldBinding = try #require(try a.repository.load(RelayBinding.self, key: "relay-binding"))
    let space = a.context.spaceId
    oldA.disconnect()
    oldB.disconnect()
    let cp = try await OperationInventoryIndex(repository: a.repository).checkpoint()
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(context: a.context, legacyCheckpoint: cp), with: [ia, ib])
    let sa = try await C1ReplicationService.migrate(engine: a, genesis: genesis)
    let sb = try await C1ReplicationService.migrate(engine: b, genesis: genesis)
    defer {
      sa.stop()
      sb.stop()
    }
    await sa.start()
    await sb.start()
    try await eventually({ sa.state == .connected && sb.state == .connected }, seconds: 20)
    let ids = [
      try DeviceIdentity(userId: ia.descriptor.userId, protocolVersion: 4),
      try DeviceIdentity(userId: ib.descriptor.userId, protocolVersion: 4),
    ]
    try await sa.addMyDevice(ids[0].descriptor)
    try await sb.addMyDevice(ids[1].descriptor)
    // Each new device has a fresh independent key; only the signed public
    // authorization archive and authenticated bootstrap digest are copied.
    let archive = await sa.authorizationArchive()
    // Fetch the latest owner streams after the other root's grant.
    let state = try await RelayAPI(base: url, identity: ia).space4(space)
    _ = archive
    var engines: [ReplicaEngine] = [a, b]
    var services: [C1ReplicationService] = [sa, sb]
    defer { for service in services { service.stop() } }
    for (i, id) in ids.enumerated() {
      let repo = try TogetherRepository(url: temp.appendingPathComponent("child\(i).store"))
      let binding = C1ReplicationBinding(
        serviceURL: url, spaceId: space, legacyRouteId: oldBinding.routeId,
        localDeviceId: id.descriptor.deviceId)
      try C1ReplicationService.prepareAuthorizedDevice(
        repository: repo, identity: id, binding: binding, archive: state.archive,
        trustedGenesisDigest: genesis.digest)
      let engine = try ReplicaEngine(
        repository: repo, identity: id, mediaRoot: temp.appendingPathComponent("child\(i)m"),
        dateProvider: clock)
      let store = try AuthorizedReplicationStore(
        repository: repo, identity: id, authorization: SpaceAuthorization.restore(state.archive))
      try await store.restore()
      let service = try C1ReplicationService(engine: engine, binding: binding, store: store)
      engines.append(engine)
      services.append(service)
      await service.start()
    }
    do {
      try await eventually(
        {
          services.allSatisfy { $0.connectedDevices.count == 3 }
            && engines.allSatisfy { $0.snapshot == a.snapshot }
        }, seconds: 30)
    } catch {
      for s in services { Issue.record("C1 state \(s.state): \(s.errorMessage ?? "none")") }
      throw error
    }
    print("C1_STAGE four clients converged")
    for (i, engine) in engines.enumerated() {
      _ = try engine.createTask(title: "Synthetic device \(i)")
    }
    _ = try a.deposit(
      FinanceAmount(original: "100.01"), by: ia.descriptor.userId,
      on: CivilDate(year: 2026, month: 10, day: 9))
    _ = try engines[3].createExpense(
      title: "Synthetic AA", amount: FinanceAmount(original: "9.99"),
      payment: .init(kind: .equalSplit, userIds: [ia.descriptor.userId, ib.descriptor.userId]),
      on: CivilDate(year: 2026, month: 10, day: 9))
    try await eventually(
      { engines.allSatisfy { $0.snapshot == a.snapshot } && a.snapshot.tasks.count == 4 },
      seconds: 30)
    print("C1_STAGE tasks and finance converged")
    let photo = try await engines[2].importMedia(from: makeImage(in: temp), type: .photo)
    var draft = LoveGiftDraft()
    draft.text = "Synthetic certified media"
    draft.photoAssetId = photo.id
    let gift = try engines[2].sendGift(draft)
    #expect(engines[2].deliveryState(engines[2].snapshot.gifts[gift]!) == .pendingSync)
    do {
      try await eventually(
        {
          b.receivedGifts.contains { $0.id == gift && b.giftReady($0) }
            && engines[2].deliveryState(engines[2].snapshot.gifts[gift]!) == .synced
        }, seconds: 30)
    } catch {
      for (index, service) in services.enumerated() {
        Issue.record(
          "Gift stage device \(index): \(service.state), peers \(service.connectedDevices.count), \(service.errorMessage ?? "none"); ready \(engines[index].snapshot.gifts[gift].map(engines[index].giftReady) ?? false)"
        )
      }
      throw error
    }
    #expect(
      try b.mediaStore.digest(b.mediaStore.originalURL(b.snapshot.mediaAssets[photo.id]!))
        == photo.sha256)
    print("C1_STAGE gift and media received")
    services[3].stop()
    _ = try engines[3].createTask(title: "Offline child")
    await services[3].start()
    try await eventually(
      { engines.allSatisfy { $0.snapshot == a.snapshot } && a.snapshot.tasks.count == 5 },
      seconds: 30)
    print("C1_STAGE offline recovery converged")
    try await sa.revokeDevice(ids[0].descriptor.deviceId)
    do {
      try await eventually(
        {
          services[2].state == .error && sa.connectedDevices.count == 2
            && sb.connectedDevices.count == 2
        }, seconds: 30)
    } catch {
      for service in services {
        Issue.record(
          "Revocation result: \(service.state), connected \(service.connectedDevices.count), error \(service.errorMessage ?? "none")"
        )
      }
      throw error
    }
    #expect(a.context.spaceId == space && b.context.spaceId == space)
    #expect(try a.repository.load(RelayBinding.self, key: "relay-binding") == oldBinding)
    #expect(engines[2].identity.descriptor.publicKey != a.identity.descriptor.publicKey)
  }
}
