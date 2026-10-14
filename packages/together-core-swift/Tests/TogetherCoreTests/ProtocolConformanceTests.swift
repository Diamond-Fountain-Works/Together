import Foundation
import CryptoKit
import Testing
@testable import TogetherCore

@Suite("Portable protocol conformance") @MainActor struct ProtocolConformanceTests {
    private func repositoryRoot() throws -> URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("qa/project.json").path) { return root }
            root.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
    private func vectors() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: repositoryRoot().appendingPathComponent("protocol/fixtures/conformance-v1.json"))) as! [String: Any]
    }
    private func object(_ name: String) throws -> [String: Any] { try vectors()[name] as! [String: Any] }
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    private let space = UUID(uuidString: "00000000-0000-0000-0000-000000000200")!

    @Test func publicDTOSnapshotsMatchPortableContract() throws {
        var records: [String: Any] = [:]
        func add<T: Encodable>(_ name: String, _ value: T) throws { records[name] = try JSONSerialization.jsonObject(with: CanonicalJSON.encode(value)) }
        let date = instant("2026-10-09T04:00:00Z"), day = CivilDate(year: 2026, month: 10, day: 9), month = FinanceMonth(year: 2026, month: 10)
        let money = try FinanceAmount(original: "100.01", currency: "USD", actualCNY: "700.07")
        let payment = FinancePayment(kind: .equalSplit, userIds: [b, a])
        let identity = try DeviceIdentity(deviceId: a, userId: a, initialSpaceId: space, privateKeyData: Data(SHA256.hash(data: Data("Together synthetic public conformance".utf8))), displayName: "SYNTHETIC", timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
        let op = SyncOperation(operationId: a, deviceId: a, actorId: a, entityId: b, entityType: .task, operationType: .create, lamportClock: 7, payload: ["title":.string("SYNTHETIC"), "amount":.data(try CanonicalJSON.encode(money)), "dueAt":.date(date), "missing":.null], createdAt: date)
        try add("SharedSpace", SharedSpace(id: space, memberIds: [a,b], timeZoneIdentifier: "Asia/Shanghai"))
        try add("DeviceIdentity", identity.descriptor)
        try add("UserProfile", UserProfile(userId: a, deviceId: a, displayName: "SYNTHETIC", relationshipLabel: "unknown", avatarData: nil, updatedAt: date))
        try add("SyncOperation", op); try add("SignedOperation", identity.sign(op))
        try add("TodoTask", TodoTask(taskId: b, spaceId: space, title: "SYNTHETIC", notes: "", createdBy: a, assignedTo: b, dueAt: date, status: .pending, createdAt: date, updatedAt: date, completedAt: nil, recurrenceRuleId: nil, deletedAt: nil, occurrenceIndex: 0, spawnedFromId: nil, availableAt: nil, nextAt: nil))
        try add("RecurrenceRule", RecurrenceRule(id: b, spaceId: space, mode: .regular, unit: .month, interval: 1, anchorAt: date, timeZoneIdentifier: "Asia/Shanghai", createdBy: a, updatedAt: date))
        try add("WishGrant", WishGrant(grantId: b, spaceId: space, fulfillerId: a, beneficiaryId: b, quantity: 3, grantedOn: day, createdAt: date, createdBy: a, notes: ""))
        try add("WishItem", WishItem(wishId: a, grantId: b, title: "SYNTHETIC", description: "", beneficiaryId: b, fulfillerId: a, createdBy: b, status: .open, createdAt: date, fulfilledAt: nil, conflictReason: nil))
        try add("DailyLoveGift", DailyLoveGift(giftId: a, spaceId: space, senderId: a, recipientId: b, textContent: "SYNTHETIC", audioAssetId: nil, photoAssetId: nil, replyToGiftId: nil, sentAt: date, sentDayKey: "2026-10-09", sharedTimeZoneIdentifier: "Asia/Shanghai", deletedAt: nil, creationOperationId: a, isEffective: true))
        try add("FinanceAmount", money); try add("FinancePayment", payment)
        try add("UnitedReservesLedgerEntry", UnitedReservesLedgerEntry(id: a, spaceId: space, depositedBy: a, kind: .deposit, amount: money, depositDate: day, createdAt: date, notes: "", deletedAt: nil))
        try add("DateEvent", DateEvent(id: a, spaceId: space, title: "SYNTHETIC", date: day, notes: "", createdBy: a, createdAt: date, deletedAt: nil))
        try add("ExpenseEntry", ExpenseEntry(id: a, spaceId: space, title: "SYNTHETIC", amount: money, payment: payment, occurredOn: day, timeZoneIdentifier: "Asia/Shanghai", category: "SYNTHETIC", notes: "", dateEventId: nil, recurringBillId: nil, occurrenceMonth: nil, status: .provisional, createdBy: a, createdAt: date, deletedAt: nil))
        try add("RecurringBill", RecurringBill(id: a, spaceId: space, title: "SYNTHETIC", defaultAmount: money, defaultPayment: payment, recurrenceDay: 31, timeZoneIdentifier: "Asia/Shanghai", minuteOfDay: nil, startMonth: month, category: "SYNTHETIC", createdBy: a, createdAt: date, deletedAt: nil))
        try add("RecurringBillRuleRevision", RecurringBillRuleRevision(id: a, billId: b, effectiveMonth: month.next, amount: money, payment: payment, active: nil, activeFromDay: nil, createdBy: a, createdAt: date, order: FinanceRevisionOrder(op.order)))
        try add("FinanceSettings", FinanceSettings(id: a, ownerId: nil, cycleStartDay: 31, timeZoneIdentifier: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil, updatedAt: date))
        let media = Data("Together synthetic media fixture\n".utf8)
        try add("MediaAsset", MediaAsset(assetId: a, spaceId: space, ownerId: a, mediaType: .audio, originalFilename: "SYNTHETIC.bin", fileExtension: "bin", sha256: SHA256.hash(data: media).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(media.count), createdAt: date))
        let serialized = try JSONSerialization.data(withJSONObject: ["synthetic": true, "samples": records], options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        let target = try repositoryRoot().appendingPathComponent("protocol/fixtures/dto-snapshots-v3.json")
        if ProcessInfo.processInfo.environment["TOGETHER_EXPORT_PROTOCOL_FIXTURES"] == "1" { try serialized.write(to: target) }
        var expected = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as! [String: Any]
        var expectedRecords = expected["samples"] as! [String: Any]
        let expectedSigned = try CanonicalJSON.decode(SignedOperation.self, from: JSONSerialization.data(withJSONObject: expectedRecords.removeValue(forKey: "SignedOperation")!))
        #expect(expectedSigned.operation == op && expectedSigned.verified(by: identity.descriptor))
        let actualSigned = try CanonicalJSON.decode(SignedOperation.self, from: JSONSerialization.data(withJSONObject: records.removeValue(forKey: "SignedOperation")!))
        #expect(actualSigned.operation == op && actualSigned.verified(by: identity.descriptor))
        // A valid signature is the contract; regenerating a signature need not
        // produce identical bytes across CryptoKit/platform implementations.
        expected["samples"] = expectedRecords
        #expect((expected as NSDictionary) == (["synthetic":true,"samples":records] as NSDictionary))
    }
    @Test func UUIDDateAndSharedZoneVectors() throws {
        let v = try object("uuid"); #expect(UUID(uuidString: v["input"] as! String)!.uuidString == v["canonical"] as! String)
        let time = try object("time"); let date = instant(time["instant"] as! String)
        #expect(String(data: try CanonicalJSON.encode(date), encoding: .utf8) == String(time["epochMilliseconds"] as! Int64))
        #expect(try GiftCalendar.dayKey(at: date, timeZoneIdentifier: time["sharedZone"] as! String) == time["dayKey"] as! String)
    }
    @Test func DecimalAndAARemainderVectors() throws {
        for v in try vectors()["money"] as! [[String: String]] {
            let amount = try FinanceAmount(original: v["original"]!, currency: v["currency"]!, actualCNY: v["actualCNY"])
            #expect(String(amount.originalMinor) == v["originalMinor"] && String(amount.finalCNYMinor) == v["cnyMinor"])
        }
        let v = try object("aa"), amount = try FinanceAmount(original: v["totalCNY"] as! String)
        let payment = FinancePayment(kind: .equalSplit, userIds: [b,a]); let values = payment.allocations(amount: amount)
        #expect(values.map(\.userId) == [a,b]); #expect(values.map { String($0.cnyMinor) } == v["sharesMinor"] as! [String])
        #expect(values.reduce(0) { $0 + $1.cnyMinor } == amount.finalCNYMinor)
    }
    @Test func MonthDayAndCycleVectors() throws {
        for v in try vectors()["monthly31"] as! [[String: Any]] {
            let month = FinanceMonth(iso: v["month"] as! String)!
            #expect(try FinancialCalendar.day(in: month, requested: 31, timeZone: v["zone"] as! String).iso == v["date"] as! String)
        }
        let v = try object("cycle"), period = try FinancialCalendar.cycle(containing: instant(v["instant"] as! String), startDay: v["startDay"] as! Int, timeZone: v["zone"] as! String)
        #expect(period.start == instant(v["start"] as! String) && period.end == instant(v["end"] as! String))
        let following = try FinancialCalendar.cycle(containing: period.end, startDay: v["startDay"] as! Int, timeZone: v["zone"] as! String)
        #expect(following.start == period.end)
    }
    @Test func NextNaturalMonthRuleVector() throws {
        let v = try object("revision"), p = try FinancePair(date: v["changedAt"] as! String)
        let id = try p.a.createRecurringBill(title: "SYNTHETIC", amount: FinanceAmount(original: v["before"] as! String), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        _ = try p.a.reviseBillDefaults(id, amount: FinanceAmount(original: v["after"] as! String), payment: p.own)
        let bill = try #require(p.a.snapshot.finance.bills[id])
        #expect(try p.a.snapshot.finance.occurrence(bill, month: FinanceMonth(iso: v["currentMonth"] as! String)!).amount.finalCNYMinor == 6800)
        #expect(try p.a.snapshot.finance.occurrence(bill, month: FinanceMonth(iso: v["effectiveMonth"] as! String)!).amount.finalCNYMinor == 8800)
    }
    @Test func LogDuplicateConflictAndTombstoneVector() throws {
        let p = try FinancePair(); let id = try p.a.createTask(title: "SYNTHETIC"); try p.exchange()
        try p.a.editTask(id, title: "LEFT", notes: "", assignedTo: nil, dueAt: nil, recurrence: nil)
        try p.b.editTask(id, title: "RIGHT", notes: "", assignedTo: nil, dueAt: nil, recurrence: nil)
        try p.exchange(); #expect(p.a.snapshot == p.b.snapshot)
        #expect(p.a.snapshot.tasks[id]?.title == "RIGHT")
        let older = p.a.operations; try p.a.deleteTask(id); try p.exchange(); let count = p.b.operations.count
        try p.b.merge(p.a.operations.reversed()); try p.b.merge(older)
        #expect(p.b.operations.count == count && p.b.snapshot.tasks[id]?.deletedAt != nil)
        #expect(p.a.snapshot == p.b.snapshot)
    }
    @Test func StableIDAndMediaSHA256Vectors() throws {
        let v = try object("stableID"); #expect(StableID.make(v["seed"] as! String).uuidString == v["uuid"] as! String)
        let media = try object("media"), data = Data(base64Encoded: media["base64"] as! String)!
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == media["sha256"] as! String)
        #expect(data.count == media["byteCount"] as! Int)
    }
    @Test func signedReorderedDuplicateAndDeletedLogFixture() throws {
        let left = try DeviceIdentity(deviceId: a, userId: a, initialSpaceId: space, privateKeyData: Data(SHA256.hash(data: Data("SYNTHETIC log vector LEFT".utf8))), protocolVersion: 3)
        let right = try DeviceIdentity(deviceId: b, userId: b, initialSpaceId: space, privateKeyData: Data(SHA256.hash(data: Data("SYNTHETIC log vector RIGHT".utf8))), protocolVersion: 3)
        let context = ReplicaContext(local: left.descriptor, peer: right.descriptor)
        let entity = UUID(uuidString: "00000000-0000-0000-0000-000000000300")!
        var operations: [SignedOperation] = []
        func append(_ index: Int, _ identity: DeviceIdentity, _ action: OperationType, _ clock: Int64, _ fields: [String:LogValue]) throws {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 400 + index))!
            let op = SyncOperation(operationId: id, deviceId: identity.descriptor.deviceId, actorId: identity.descriptor.userId, entityId: entity, entityType: .task, operationType: action, lamportClock: clock, payload: fields, createdAt: instant("2026-10-09T04:00:00Z"))
            operations.append(try identity.sign(op))
        }
        try append(1,left,.create,10,["spaceId":.id(context.spaceId),"createdBy":.id(a),"title":.string("SYNTHETIC"),"notes":.string("")])
        try append(2,left,.patch,20,["title":.string("LEFT"),"notes":.string("INDEPENDENT_FIELD")])
        try append(3,right,.patch,20,["title":.string("RIGHT")])
        try append(4,left,.delete,30,[:])
        try append(5,right,.patch,40,["title":.string("LATE_PATCH_MUST_NOT_REVIVE")])
        let record = SignedLogVector(synthetic: true, devices: [left.descriptor,right.descriptor], operations: operations, expectedDistinctOperations: 5, expectedTitleBeforeDeletion: "RIGHT", expectedIndependentNotes: "INDEPENDENT_FIELD", expectedDeleted: true)
        let file = try repositoryRoot().appendingPathComponent("protocol/fixtures/signed-log-v3.json")
        if ProcessInfo.processInfo.environment["TOGETHER_EXPORT_PROTOCOL_FIXTURES"] == "1" { try CanonicalJSON.encode(record).write(to: file) }
        let fixture = try CanonicalJSON.decode(SignedLogVector.self, from: Data(contentsOf: file))
        #expect(fixture.devices == record.devices && fixture.operations.map(\.operation) == record.operations.map(\.operation))
        for signed in fixture.operations {
            #expect(signed.verified(by: try #require(context.devices[signed.operation.deviceId])))
        }
        let clock = FixedDateProvider(instant("2026-10-09T04:00:00Z"))
        let before = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: left, dateProvider: clock)
        try before.authorize(PairedPeer(descriptor:right.descriptor,host:"127.0.0.1",port:0))
        try before.merge(Array(fixture.operations.prefix(3)).reversed())
        #expect(before.snapshot.tasks[entity]?.title == fixture.expectedTitleBeforeDeletion)
        #expect(before.snapshot.tasks[entity]?.notes == fixture.expectedIndependentNotes)
        var snapshots: [DomainSnapshot] = []
        for input in [fixture.operations,fixture.operations.reversed().map { $0 },fixture.operations + fixture.operations] {
            let engine = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity:left, dateProvider: clock)
            try engine.authorize(PairedPeer(descriptor:right.descriptor,host:"127.0.0.1",port:0))
            try engine.merge(input)
            #expect(engine.operations.filter { $0.operation.entityId == entity }.count == fixture.expectedDistinctOperations)
            #expect((engine.snapshot.tasks[entity]?.deletedAt != nil) == fixture.expectedDeleted)
            // Compare the fixture projection, excluding independently generated
            // boot operations (their UUIDs are intentionally random).
            let projection = OperationProjector.replay(input, context: context)
            #expect(engine.snapshot.tasks[entity] == projection.tasks[entity])
            snapshots.append(projection)
        }
        #expect(snapshots[0] == snapshots[1] && snapshots[1] == snapshots[2])
    }
}
private struct SignedLogVector: Codable, Equatable {
    var synthetic: Bool
    var devices: [DeviceDescriptor]
    var operations: [SignedOperation]
    var expectedDistinctOperations: Int
    var expectedTitleBeforeDeletion: String
    var expectedIndependentNotes: String
    var expectedDeleted: Bool
}
