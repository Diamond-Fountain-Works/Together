import Foundation
import Testing

@testable import TogetherCore

@Suite("Independent device persistence progress") @MainActor struct DeviceAcknowledgementTests {
  @Test func myPhoneAckIsNotPartnerDeliveryAndOfflineDevicesDoNotBlockThePartnerAck() async throws {
    let f = try ReplicationFixture()
    let phone = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    let tablet = try DeviceIdentity(userId: f.b.descriptor.userId, protocolVersion: 4)
    var trust = try SpaceAuthorization(genesis: f.genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
    try trust.apply(trust.grant(tablet.descriptor, authorizedBy: f.b))
    func store(_ id: DeviceIdentity) throws -> AuthorizedReplicationStore {
      try AuthorizedReplicationStore(
        repository: TogetherRepository(inMemory: true), identity: id, authorization: trust)
    }
    let a = try store(f.a)
    let b = try store(f.b)
    let p = try store(phone)
    try await a.restore()
    try await b.restore()
    try await p.restore()
    let proof = try await a.append(f.operation(f.a))
    let entry = try InventoryEntry(ReplicationRecord.authorized(proof))
    let ledger = DeviceAcknowledgementLedger(
      repository: a.repository, index: a.index, identity: f.a)
    let initial = try await ledger.progress(
      for: entry, trust: trust, transferringTo: [phone.descriptor.deviceId])
    #expect(
      initial.localSaved && initial.status == .transferring && !initial.partnerHasPersisted
        && initial.remotePersistedDevices.isEmpty)
    try await p.receive([.authorized(proof)])
    let pl = DeviceAcknowledgementLedger(repository: p.repository, index: p.index, identity: phone)
    let own = try #require(await pl.receipt(entries: [entry], trust: trust))
    _ = try await ledger.accept(own, from: phone.descriptor, trust: trust)
    let ownProgress = try await ledger.progress(for: entry, trust: trust)
    #expect(
      ownProgress.remotePersistedDevices == [phone.descriptor.deviceId]
        && !ownProgress.partnerHasPersisted)
    try await b.receive([.authorized(proof)])
    let bl = DeviceAcknowledgementLedger(repository: b.repository, index: b.index, identity: f.b)
    let partner = try #require(await bl.receipt(entries: [entry], trust: trust))
    _ = try await ledger.accept(partner, from: f.b.descriptor, trust: trust)
    _ = try await ledger.accept(partner, from: f.b.descriptor, trust: trust)
    try await ChangeReviewService(repository: a.repository).mark([proof.id], as: .reviewed)
    let progress = try await ledger.progress(for: entry, trust: trust)
    #expect(progress.partnerHasPersisted && !progress.allAuthorizedDevicesHavePersisted)
    #expect(progress.pendingDevices == [tablet.descriptor.deviceId])
    #expect(progress.reviewDisposition == .reviewed && progress.status == .remotePersisted)
    #expect(progress.convergedDevices.isEmpty)
  }
  @Test func checkpointMembershipPagesSurviveRestartAndDoNotAcknowledgeLaterWrites() async throws {
    let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("together-ack-pages-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let a = try AuthorizedReplicationStore(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: f.a, authorization: trust)
    let b = try AuthorizedReplicationStore(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: f.b, authorization: trust)
    try await a.restore(); try await b.restore()
    for n in 0..<5 {
      let ops = try (0..<32).map { try f.operation(f.a, clock: Int64(n*32+$0+1)) }
      let records = try await a.appendBatch(ops)
      try await b.receive(records.map(ReplicationRecord.authorized))
    }
    let al = DeviceAcknowledgementLedger(repository: a.repository, index: a.index, identity: f.a)
    let bl = DeviceAcknowledgementLedger(repository: b.repository, index: b.index, identity: f.b)
    let checkpoint = try await a.index.checkpoint()
    let receipt = try #require(try await bl.convergenceReceipt(for: checkpoint, trust: trust))
    #expect(try await al.accept(receipt, from: f.b.descriptor, trust: trust))
    #expect(try await al.accept(receipt, from: f.b.descriptor, trust: trust))
    let prefix = "replication4/ack-membership/\(f.b.descriptor.deviceId)/"
    let pages = try a.repository.localPage(prefix: prefix)
    #expect(pages.count == 2) // 160 operations, not 160 per-operation models.
    let entries = try await a.index.page(after: nil, checkpoint: checkpoint).entries
    let entry = try #require(entries.first)
    #expect(try await al.partnerHasPersisted(entry, trust: trust))
    let next = try await a.append(f.operation(f.a, clock: 161))
    let nextEntry = try InventoryEntry(ReplicationRecord.authorized(next))
    #expect(!(try await al.partnerHasPersisted(nextEntry, trust: trust)))
    let repo = try TogetherRepository(url: root.appendingPathComponent("a.store"))
    let restored = DeviceAcknowledgementLedger(repository: repo, index: OperationInventoryIndex(repository: repo), identity: f.a)
    #expect(try await restored.partnerHasPersisted(entry, trust: trust))
    // A signed remote whole-set receipt alone cannot authenticate forged local
    // page membership. The local witness signature must remain valid as well.
    var json = try JSONSerialization.jsonObject(with: pages[0].bytes) as! [String: Any]
    json["signature"] = Data(repeating: 0, count: 64).base64EncodedString()
    try repo.commitReplication([], records: [pages[0].id: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])])
    #expect(!(try await restored.partnerHasPersisted(entry, trust: trust)))
  }
  @Test func alteredLegacyMembershipCannotBorrowAnUnrelatedSignedReceipt() async throws {
    let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
    let a = try AuthorizedReplicationStore(repository: TogetherRepository(inMemory: true), identity: f.a, authorization: trust)
    let b = try AuthorizedReplicationStore(repository: TogetherRepository(inMemory: true), identity: f.b, authorization: trust)
    try await a.restore(); try await b.restore()
    let first = try await a.append(f.operation(f.a))
    try await b.receive([.authorized(first)])
    let entry = try InventoryEntry(ReplicationRecord.authorized(first))
    let later = try await a.append(f.operation(f.a, clock: 2))
    let laterEntry = try InventoryEntry(ReplicationRecord.authorized(later))
    let remote = DeviceAcknowledgementLedger(repository: b.repository, index: b.index, identity: f.b)
    let receipt = try #require(try await remote.receipt(entries: [entry], trust: trust))
    let ledger = DeviceAcknowledgementLedger(repository: a.repository, index: a.index, identity: f.a)
    _ = try await ledger.accept(receipt, from: f.b.descriptor, trust: trust)
    let borrowed = AcknowledgedOperation(contentDigest: laterEntry.contentDigest, certificationDigest: laterEntry.certificationDigest, receiptDigest: try receipt.digest)
    try a.repository.save(borrowed, key: "replication4/ack/\(f.b.descriptor.deviceId)/\(later.id)")
    #expect(!(try await ledger.partnerHasPersisted(laterEntry, trust: trust)))
    #expect(try await ledger.partnerHasPersisted(entry, trust: trust))
  }
}
