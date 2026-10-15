import Foundation
import Testing

@testable import TogetherCore

@Suite("Universal effective-operation change review") @MainActor struct ChangeReviewTests {
  @Test func actualBeforeAfterFieldsAndAllBusinessDomains() async throws {
    let p = try TwoReplicas()
    let task = try p.a.createTask(title: "Before", notes: "Keep")
    try p.exchange()
    try p.b.editTask(
      task, title: "After", notes: "Keep", assignedTo: nil, dueAt: nil, recurrence: nil)
    let grant = try p.a.grant(
      fulfiller: p.a.identity.descriptor.userId, beneficiary: p.b.identity.descriptor.userId,
      quantity: 2, date: CivilDate(year: 2026, month: 10, day: 9), notes: "")
    try p.exchange()
    _ = try p.b.createWish(grantId: grant, title: "Synthetic wish", description: "")
    _ = try p.a.deposit(
      FinanceAmount(original: "10"), by: p.a.identity.descriptor.userId,
      on: CivilDate(year: 2026, month: 10, day: 9))
    try p.a.setProfile(name: "Synthetic name", label: .boyfriend)
    var draft = LoveGiftDraft()
    draft.text = "PRIVATE_NOT_FOR_CHANGE_REVIEW"
    _ = try p.a.sendGift(draft)
    try p.exchange()
    let events = OperationProjector.changes(p.a.operations, context: p.a.context)
    let patch = try #require(events.first { $0.entityId == task && $0.action == .patch })
    #expect(patch.before["title"]?.string == "Before" && patch.after["title"]?.string == "After")
    #expect(patch.origin(local: p.a.identity.descriptor) == .partner)
    #expect(
      Set(events.map(\.type)).isSuperset(of: [
        .profile, .task, .wishGrant, .wishItem, .loveGift, .reserveEntry,
      ]))
    #expect(
      !String(
        decoding: try CanonicalJSON.encode(events.filter { $0.type == .loveGift }), as: UTF8.self
      ).contains("PRIVATE_NOT_FOR_CHANGE_REVIEW"))
    let shuffled = OperationProjector.changes(p.a.operations.reversed(), context: p.a.context)
    #expect(shuffled == events)
  }
  @Test func invalidNoOpAndDuplicateCreatesAreNotSuccessfulChanges() throws {
    let f = try ReplicationFixture()
    let id = UUID()
    let create = try f.operation(f.a, entity: id, title: "Original")
    let duplicate = try f.operation(f.b, clock: 2, entity: id, title: "Ignored")
    let noOp = try f.operation(f.a, clock: 3, entity: id, action: .patch, title: "Original")
    let wrong = try f.a.sign(
      SyncOperation(
        deviceId: f.a.descriptor.deviceId, actorId: f.a.descriptor.userId, entityId: id,
        entityType: .task, operationType: .patch, lamportClock: 4, payload: ["title": .string("")]))
    let events = OperationProjector.changes([wrong, noOp, duplicate, create], context: f.context)
    #expect(events.map(\.id) == [create.id])
    #expect(
      OperationProjector.replay([wrong, noOp, duplicate, create], context: f.context).tasks[id]?
        .title == "Original")
  }
  @Test func ownOtherDeviceAndPartnerReviewsPersistWithoutBusinessApproval() async throws {
    let f = try ReplicationFixture()
    let phone = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
    var trust = try SpaceAuthorization(genesis: f.genesis)
    try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
    let repo = try TogetherRepository(inMemory: true)
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: f.a, authorization: trust)
    try await store.restore()
    let op = try f.operation(phone)
    let proof = try AuthorizedOperation.sign(
      op, identity: phone, trust: trust, previous: DeviceFrontier())
    try await store.receive([.authorized(proof)])
    let review = ChangeReviewService(repository: repo)
    let context = try await store.projectionContext()
    let pending = try await review.pending(context: context, local: f.a.descriptor)
    #expect(pending.count == 1 && pending[0].origin(local: f.a.descriptor) == .myOtherDevice)
    try await review.mark(pending.map(\.id), as: .reviewed)
    #expect(
      try await ChangeReviewService(repository: repo).pending(
        context: context, local: f.a.descriptor
      ).isEmpty)
    try await store.receive([.authorized(proof)])
    #expect(try await review.pending(context: context, local: f.a.descriptor).isEmpty)
    #expect(OperationProjector.replay(try repo.allOperations(), context: context).tasks.count == 1)
  }
  @Test func losingFieldUpdatesRemainHistoricalAndAreNotEffectiveNotifications() throws {
    let f = try ReplicationFixture()
    let id = UUID()
    let create = try f.operation(f.a, entity: id)
    let first = try f.operation(f.a, clock: 2, entity: id, action: .patch, title: "Earlier")
    let last = try f.operation(f.b, clock: 3, entity: id, action: .patch, title: "Winner")
    let events = OperationProjector.changes([last, create, first], context: f.context)
    #expect(events.first { $0.id == first.id }?.resolution == .superseded)
    #expect(events.first { $0.id == last.id }?.resolution == .effective)
    #expect(
      OperationProjector.replay([last, create, first], context: f.context).tasks[id]?.title
        == "Winner")
  }
  @Test func taskAndRecurrenceCreateAreOneTransaction() throws {
    let p = try TwoReplicas()
    let count = p.a.operations.count
    #expect(throws: (any Error).self) {
      try p.a.createTask(title: "", recurrence: RecurrenceDraft(mode: .regular))
    }
    #expect(p.a.operations.count == count)
    #expect(try p.a.repository.operationCount() == count)
  }
}
