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
}
