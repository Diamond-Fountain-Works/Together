import Foundation
import Testing

@testable import TogetherCore

@Suite("Scoped projection equivalence") @MainActor struct ScopedProjectionTests {
  @Test func taskProfileAndFinanceWishGiftMutationsMatchTheUnchangedFullReplay() async throws {
    let p = try TwoReplicas()
    let day = CivilDate(year: 2026, month: 10, day: 9)
    func oracle(_ engine: ReplicaEngine) throws {
      #expect(
        engine.snapshot == OperationProjector.replay(engine.operations, context: engine.context))
    }
    for i in 0..<30 {
      let id = try p.a.createTask(title: "Synthetic \(i)", notes: "Initial")
      try oracle(p.a)
      try p.a.editTask(
        id, title: "Edited \(i)", notes: "Kept", assignedTo: p.b.identity.descriptor.userId,
        dueAt: Date(timeIntervalSince1970: 1_791_532_800.123456), recurrence: nil)
      try oracle(p.a)
      if i % 3 == 0 {
        try p.a.setCompleted(id, completed: true)
        try oracle(p.a)
      }
      if i % 4 == 0 {
        try p.a.deleteTask(id)
        try oracle(p.a)
      }
    }
    try p.a.setProfile(name: "Synthetic A", label: .boyfriend)
    try oracle(p.a)
    let grant = try p.a.grant(
      fulfiller: p.a.identity.descriptor.userId, beneficiary: p.b.identity.descriptor.userId,
      quantity: 3, date: day, notes: "")
    try oracle(p.a)
    try p.exchange()
    let wish = try p.b.createWish(grantId: grant, title: "Synthetic wish", description: "")
    try oracle(p.b)
    try p.exchange()
    try p.a.requestFulfillment(wish)
    try oracle(p.a)
    try p.exchange()
    try p.b.confirmFulfillment(wish)
    try oracle(p.b)
    let deposit = try p.a.deposit(
      FinanceAmount(original: "100"), by: p.a.identity.descriptor.userId, on: day)
    _ = deposit
    try oracle(p.a)
    _ = try p.a.createExpense(
      title: "Synthetic expense", amount: FinanceAmount(original: "1.01"),
      payment: .init(
        kind: .equalSplit,
        userIds: [p.a.identity.descriptor.userId, p.b.identity.descriptor.userId]), on: day)
    try oracle(p.a)
    var draft = LoveGiftDraft()
    draft.text = "Synthetic gift"
    _ = try p.a.sendGift(draft)
    try oracle(p.a)
  }
  @Test func uuidCollisionAcrossBasicTypesAndTombstoneOrderMatchFullReplay() throws {
    let f = try ReplicationFixture()
    let id = f.a.descriptor.userId
    let task = try f.operation(f.a, clock: 2, entity: id)
    let profile = try f.a.sign(
      SyncOperation(
        deviceId: f.a.descriptor.deviceId, actorId: id, entityId: id, entityType: .profile,
        operationType: .create, lamportClock: 1,
        payload: ["deviceId": .id(f.a.descriptor.deviceId), "displayName": .string("Synthetic")]))
    let before = OperationProjector.replay([task], context: f.context)
    let earlyTask=try f.operation(f.a,clock:0,entity:id)
    let shared=try f.a.sign(SyncOperation(deviceId:f.a.descriptor.deviceId,actorId:id,entityId:f.context.spaceId,entityType:.sharedSpace,operationType:.create,lamportClock:5,payload:["sharedTimeZoneIdentifier":.string(f.context.sharedTimeZone)]))
    let old=OperationProjector.replay([earlyTask,profile],context:f.context)
    #expect(ScopedProjection.replay(existing:old,log:[earlyTask,profile,shared],additions:[shared],context:f.context)==OperationProjector.replay([earlyTask,profile,shared],context:f.context))
    #expect(
      ScopedProjection.replay(
        existing: before, log: [task, profile], additions: [profile], context: f.context)
        == OperationProjector.replay([task, profile], context: f.context))
    let deleted = try f.operation(f.a, clock: 4, entity: task.operation.entityId, action: .delete)
    let late = try f.operation(f.b, clock: 3, entity: task.operation.entityId, action: .patch)
    let existing = OperationProjector.replay([task, deleted], context: f.context)
    #expect(
      ScopedProjection.replay(
        existing: existing, log: [late, deleted, task], additions: [late], context: f.context)
        == OperationProjector.replay([late, deleted, task], context: f.context))
  }
  @Test func invalidTaskEditDoesNotCommitItsRecurrenceChange() throws {
    let p = try TwoReplicas()
    let id = try p.a.createTask(title: "Keep", recurrence: RecurrenceDraft(mode: .regular))
    let before = p.a.snapshot
    let count = p.a.operations.count
    #expect(throws: (any Error).self) {
      try p.a.editTask(
        id, title: "", notes: "", assignedTo: nil, dueAt: nil,
        recurrence: RecurrenceDraft(mode: .regular, interval: 2))
    }
    #expect(p.a.snapshot == before && p.a.operations.count == count)
    #expect(try p.a.repository.operationCount() == count)
  }
  @Test func signedSubMillisecondInputPublishesOnlyPersistedCanonicalValues() throws {
    let p = try TwoReplicas()
    let due = Date(timeIntervalSince1970: 1_791_532_800.123456)
    _ = try p.a.createTask(title: "Canonical instant", dueAt: due)
    try p.exchange()
    #expect(p.a.snapshot == p.b.snapshot)
    #expect(
      p.a.operations.allSatisfy {
        (try? CanonicalJSON.decode(SignedOperation.self, from: CanonicalJSON.encode($0))) == $0
      })
  }
}
