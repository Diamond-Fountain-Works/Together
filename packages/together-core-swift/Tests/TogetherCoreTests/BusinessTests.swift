import Foundation
import Testing
@testable import TogetherCore

@Suite("Recurrence & Wishes") @MainActor struct BusinessTests {
    @Test func monthEndAndSingleNextInstance() throws {
        let p = try TwoReplicas()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
        let id = try p.a.createTask(title: "月末计划", dueAt: anchor, recurrence: RecurrenceDraft(mode: .regular, unit: .month, timeZoneIdentifier: calendar.timeZone.identifier))
        try p.exchange()
        try p.a.setCompleted(id, completed: true); try p.b.setCompleted(id, completed: true)
        try p.exchange()
        let next = p.a.snapshot.tasks.values.filter { $0.spawnedFromId == id }
        #expect(next.count == 1)
        #expect(calendar.component(.day, from: next.first!.dueAt!) == 28)
        let rule = p.a.snapshot.rules[p.a.snapshot.tasks[id]!.recurrenceRuleId!]!
        #expect(calendar.component(.day, from: RecurrenceCalculator.date(rule: rule, occurrenceIndex: 2)!) == 31)
        #expect(p.a.snapshot == p.b.snapshot)
    }
    @Test func daylightSavingCalendar() throws {
        let engine = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity())
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = c.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9, minute: 30))!
        let id = try engine.createTask(title: "Daily", dueAt: date, recurrence: RecurrenceDraft(mode: .regular, timeZoneIdentifier: c.timeZone.identifier))
        let rule = engine.snapshot.rules[engine.snapshot.tasks[id]!.recurrenceRuleId!]!
        let next = RecurrenceCalculator.date(rule: rule, occurrenceIndex: 1)!
        #expect(c.component(.hour, from: next) == 9)
        #expect(next.timeIntervalSince(date) == 23 * 3600)
    }
    @Test func flexibleDoesNotGuessAndRestoresTime() throws {
        let engine = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity())
        let id = try engine.createTask(title: "Flexible", recurrence: RecurrenceDraft(mode: .flexible))
        try engine.setCompleted(id, completed: true)
        #expect(engine.snapshot.tasks.count == 1)
        let date = Date.now.addingTimeInterval(86400)
        try engine.setNextTime(id, date: date)
        let future = engine.snapshot.tasks.values.first { $0.spawnedFromId == id }!
        #expect(future.visibleStatus(at: date.addingTimeInterval(-10)) == .scheduled)
        #expect(future.visibleStatus(at: date.addingTimeInterval(10)) == .pending)
        try engine.reconcileRecurrence(); #expect(engine.snapshot.tasks.count == 2)
    }
    @Test func wishHistoryFiveThenFour() throws {
        let p = try TwoReplicas(); let a = p.a.identity.descriptor.userId, b = p.b.identity.descriptor.userId
        let g1 = try p.a.grant(fulfiller: a, beneficiary: b, quantity: 3, date: CivilDate(year: 2026, month: 10, day: 9), notes: "第一批")
        let g2 = try p.a.grant(fulfiller: a, beneficiary: b, quantity: 2, date: CivilDate(year: 2026, month: 10, day: 15), notes: "第二批")
        try p.exchange()
        let wish = try p.b.createWish(grantId: g1, title: "一起散步", description: "周末")
        try p.exchange(); try p.a.requestFulfillment(wish); try p.exchange(); try p.b.confirmFulfillment(wish)
        try p.b.confirmFulfillment(wish); try p.exchange()
        #expect(p.a.snapshot.grants.count == 2)
        #expect(p.a.snapshot.grants[g1]?.grantedOn.iso == "2026-10-09")
        #expect(p.a.snapshot.balance(for: g1).remaining + p.a.snapshot.balance(for: g2).remaining == 4)
        #expect(p.a.snapshot.wishes.values.filter { $0.status == .fulfilled }.count == 1)
        #expect(p.a.snapshot == p.b.snapshot)
    }
    @Test func quotaConflictConvergesWithoutNegativeBalance() throws {
        let p = try TwoReplicas(); let a = p.a.identity.descriptor.userId, b = p.b.identity.descriptor.userId
        let grant = try p.a.grant(fulfiller: a, beneficiary: b, quantity: 1, date: CivilDate(year: 2026, month: 10, day: 9), notes: "")
        try p.exchange()
        let wish = try p.b.createWish(grantId: grant, title: "离线愿望", description: "")
        try p.a.adjustGrant(grant, delta: -1, notes: "离线修正")
        try p.exchange()
        #expect(p.a.snapshot == p.b.snapshot)
        #expect(p.a.snapshot.balance(for: grant).remaining >= 0)
        #expect(p.a.snapshot.wishes[wish]?.status == .conflict)
        #expect(!p.a.snapshot.conflicts.isEmpty)
        #expect(throws: (any Error).self) { try p.a.createWish(grantId: grant, title: "兑现者不能填写", description: "") }
    }
    @Test func civilDateIndependentOfTimezone() {
        let date = CivilDate(iso: "2026-10-09")!
        #expect(date.display == "2026年10月9日")
        #expect(CivilDate(iso: "2026-02-30") == nil)
    }
}
