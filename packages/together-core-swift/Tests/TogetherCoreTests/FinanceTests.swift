import Foundation
import Testing
import CryptoKit
@testable import TogetherCore

@MainActor final class FinancePair {
    let clock: TestClock
    let a: ReplicaEngine
    let b: ReplicaEngine
    init(date: String = "2024-01-15T04:00:00Z") throws {
        clock = TestClock(instant(date))
        let ia = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
        let ib = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!, timeZoneIdentifier: "America/Los_Angeles", protocolVersion: 3)
        a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ia, dateProvider: clock)
        b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ib, dateProvider: clock)
        try a.authorize(PairedPeer(descriptor: ib.descriptor, host: "127.0.0.1", port: 0))
        try b.authorize(PairedPeer(descriptor: ia.descriptor, host: "127.0.0.1", port: 0)); try exchange()
    }
    func exchange() throws { for _ in 0..<4 { let left = a.operations, right = b.operations; try a.merge(right); try b.merge(left) } }
    var day: CivilDate { CivilDate(clock.now(), timeZone: TimeZone(identifier: "Asia/Shanghai")!) }
    var own: FinancePayment { .init(kind: .personal, userIds: [a.identity.descriptor.userId]) }
    var partner: FinancePayment { .init(kind: .personal, userIds: [b.identity.descriptor.userId]) }
    var aa: FinancePayment { .init(kind: .equalSplit, userIds: [a.identity.descriptor.userId, b.identity.descriptor.userId]) }
    var reserves: FinancePayment { .init(kind: .reserves) }
}
@Suite("Finance merge permissions and review") @MainActor struct FinanceRobustnessTests {
    @Test func independentForecastInitializersAndUntouchedCycleSettingsArePreserved() throws {
        let p = try FinancePair(), bill = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        try p.exchange(); let month = FinanceMonth(year: 2024, month: 1), item = try p.a.snapshot.finance.occurrence(p.a.snapshot.finance.bills[bill]!, month: month)
        try p.a.overrideBillOccurrence(bill, month: month, amount: FinanceAmount(original: "78"), payment: item.payment, editingBaseline: item)
        try p.b.overrideBillOccurrence(bill, month: month, amount: item.amount, payment: p.partner, editingBaseline: item)
        let originalCycle = p.a.snapshot.finance.settings(for: nil, fallbackTimeZone: "Asia/Shanghai")
        try p.b.setFinanceSettings(owner: nil, startDay: 31, timeZone: "America/New_York", salaryDay: nil, plannedDepositDay: nil)
        try p.a.merge(p.b.operations)
        try p.a.setFinanceSettings(owner: nil, startDay: 1, timeZone: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil, editingBaseline: originalCycle)
        try p.exchange()
        let result = try p.a.snapshot.finance.occurrence(p.a.snapshot.finance.bills[bill]!, month: month)
        #expect(result.amount.finalCNYMinor == 7800 && result.payment == p.partner)
        #expect(p.a.snapshot.finance.settings(for: nil, fallbackTimeZone: "Asia/Shanghai").cycleStartDay == 31 && p.a.snapshot.finance == p.b.snapshot.finance)
    }
    @Test func editingOpenBeforeIncomingChangesDoesNotRevertUntouchedAmounts() throws {
        let p = try FinancePair(), id = try p.a.createExpense(title: "EXPENSE", amount: FinanceAmount(original: "218"), payment: p.own, on: p.day)
        try p.exchange(); let baseline = try #require(p.a.snapshot.finance.expenses[id])
        try p.b.editExpense(id, title: baseline.title, amount: FinanceAmount(original: "238"), payment: baseline.payment, on: p.day, category: "", notes: "", dateEventId: nil)
        try p.a.merge(p.b.operations)
        try p.a.editExpense(id, title: baseline.title, amount: baseline.amount, payment: baseline.payment, on: p.day, category: "", notes: "LOCAL_NOTE", dateEventId: nil, editingBaseline: baseline)
        #expect(p.a.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 23800 && p.a.snapshot.finance.expenses[id]?.notes == "LOCAL_NOTE")
        #expect(throws: (any Error).self) { try p.a.editExpense(id, title: baseline.title, amount: baseline.amount, payment: baseline.payment, on: p.day, category: "", notes: "LOCAL_NOTE", dateEventId: nil, reviewed: true, editingBaseline: baseline) }
    }
    @Test func offlineInitialSharedSettingsOpeningAndForecastUseLamportFieldMerge() throws {
        let p = try FinancePair()
        try p.a.setOpeningBalance(FinanceAmount(original: "500"), on: p.day)
        try p.b.setOpeningBalance(FinanceAmount(original: "600"), on: p.day)
        try p.a.setFinanceSettings(owner: nil, startDay: 15, timeZone: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil)
        try p.b.setFinanceSettings(owner: nil, startDay: 31, timeZone: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil)
        try p.exchange()
        #expect(p.a.snapshot.finance.reserves.count == 1 && p.a.snapshot.finance.settings(for: nil, fallbackTimeZone: "Etc/UTC").cycleStartDay == 31)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == 60000)
        let bill = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        try p.exchange()
        let month = FinanceMonth(year: 2024, month: 1)
        try p.a.overrideBillOccurrence(bill, month: month, amount: FinanceAmount(original: "78"), payment: p.own)
        try p.b.overrideBillOccurrence(bill, month: month, amount: FinanceAmount(original: "88"), payment: p.partner)
        try p.exchange()
        #expect(p.a.snapshot.finance.occurrenceOverrides.count == 1 && p.a.snapshot.finance == p.b.snapshot.finance)
        let instance = try p.a.snapshot.finance.occurrence(p.a.snapshot.finance.bills[bill]!, month: month)
        #expect(instance.amount.finalCNYMinor == 8800 && instance.payment == p.partner)
    }
    @Test func tinyForeignAmountsRoundToZeroWithoutLosingTheRecordAndLocalCardChangesPublish() throws {
        let p = try FinancePair(), rate = try ExchangeRateSnapshot(rate: "0.001", source: "REFERENCE", quotedOn: p.day)
        let id = try p.a.createExpense(title: "TINY", amount: FinanceAmount(original: "1", currency: "KRW", exchangeRate: rate), payment: p.aa, on: p.day)
        #expect(p.a.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 0)
        #expect(try p.a.snapshot.finance.statistics().totalExpenses == 0 && p.a.snapshot.finance.expenses[id]?.allocations.map(\.originalMinor).reduce(0,+) == 1)
        let card = PaymentMethodProfile(ownerId: p.a.identity.descriptor.userId, bankName: "LOCAL", name: "LOCAL", cardKind: .debit, lastFour: "1234")
        let before = p.a.changeNumber, count = p.a.operations.count
        try p.a.savePaymentMethod(card); #expect(p.a.changeNumber > before && p.a.operations.count == count)
        try p.a.deletePaymentMethod(card.id); #expect(p.a.visiblePaymentMethods.isEmpty && p.a.operations.count == count)
    }
    @Test func terminationKeepsHistoricalBackfillAndSuppressesFutureCandidates() throws {
        let p = try FinancePair(date: "2024-01-15T04:00:00Z")
        let bill = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 10, timeZone: "Asia/Shanghai", startMonth: .init(year: 2024, month: 1))
        try p.exchange(); p.clock.advance(60 * 86400)
        try p.a.deleteFinance(bill, type: .recurringBill)
        #expect(p.a.snapshot.finance.expenses.count == 3)
        let count = p.a.snapshot.finance.expenses.count; p.clock.advance(60 * 86400); try p.a.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses.count == count)
        try p.b.reconcileFinanceBills(); try p.exchange()
        #expect(p.a.snapshot.finance == p.b.snapshot.finance)
        #expect(p.a.snapshot.finance.expenses.values.filter(\.isEffective).count == count)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == -20400)
    }
    @Test func pausingFutureDoesNotReverseAlreadyDueProvisionalExpense() throws {
        let p = try FinancePair(date: "2024-01-10T04:00:00Z")
        let bill = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 10, timeZone: "Asia/Shanghai")
        try p.a.setBillActive(bill, active: false)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == -6800)
        p.clock.advance(40 * 86400); try p.a.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses.count == 1)
    }
    @Test func independentFieldEditsAndSameFieldConflictConverge() throws {
        let p = try FinancePair(), id = try p.a.createExpense(title: "EXPENSE", amount: FinanceAmount(original: "10"), payment: p.own, on: p.day)
        try p.exchange()
        try p.a.editExpense(id, title: "EXPENSE", amount: FinanceAmount(original: "12"), payment: p.own, on: p.day, category: "", notes: "", dateEventId: nil)
        try p.b.editExpense(id, title: "EXPENSE", amount: FinanceAmount(original: "10"), payment: p.own, on: p.day, category: "", notes: "INDEPENDENT_NOTE", dateEventId: nil)
        try p.exchange()
        #expect(p.a.snapshot.finance == p.b.snapshot.finance)
        #expect(p.a.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 1200 && p.a.snapshot.finance.expenses[id]?.notes == "INDEPENDENT_NOTE")
        try p.a.editExpense(id, title: "EXPENSE", amount: FinanceAmount(original: "13"), payment: p.own, on: p.day, category: "", notes: "INDEPENDENT_NOTE", dateEventId: nil)
        try p.b.editExpense(id, title: "EXPENSE", amount: FinanceAmount(original: "14"), payment: p.own, on: p.day, category: "", notes: "INDEPENDENT_NOTE", dateEventId: nil)
        try p.exchange(); #expect(p.a.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 1400)
        let count = p.a.operations.count; try p.a.merge(p.b.operations); #expect(p.a.operations.count == count && p.a.snapshot.finance == p.b.snapshot.finance)
    }
    @Test func foreignHistoricalSettlementNeverRecalculates() throws {
        let p = try FinancePair(), quote = try ExchangeRateSnapshot(rate: "7", source: "REFERENCE", quotedOn: p.day)
        let id = try p.a.createExpense(title: "USD", amount: FinanceAmount(original: "10", currency: "USD", exchangeRate: quote), payment: p.own, on: p.day)
        _ = try p.b.deposit(FinanceAmount(original: "10", currency: "USD", actualCNY: "80"), by: p.b.identity.descriptor.userId, on: p.day)
        try p.exchange(); p.clock.advance(40 * 86400); try p.a.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 7000)
        var json = try JSONSerialization.jsonObject(with: CanonicalJSON.encode(p.a.snapshot.finance.expenses[id]!.amount)) as! [String: Any]
        json["finalCNYMinor"] = "8000"
        #expect(throws: (any Error).self) { try CanonicalJSON.decode(FinanceAmount.self, from: JSONSerialization.data(withJSONObject: json)) }
    }
    @Test func financeCatalogCoversSupportedCurrenciesAndStatuses() {
        #expect(FinanceCurrency.supported.count >= 160)
        for currency in FinanceCurrency.supported { #expect(Copy.text("finance.currency." + currency.code) != "finance.currency." + currency.code) }
        for error in [FinanceError.invalidAmount, .invalidCurrency, .missingSettlement, .invalidRate, .invalidPayment, .invalidDate, .invalidRecord, .missingRecord, .overflow, .peerUpgrade, .invalidCard, .recordChanged] { #expect(error.localizedDescription != "finance.error." + error.rawValue) }
        for status in ExpenseReviewStatus.allCases { #expect(Copy.text("finance.status." + status.rawValue) != "finance.status." + status.rawValue) }
    }
    @Test func privateSettingsAndCardOwnershipCannotBeForged() throws {
        let p = try FinancePair(), owner = p.a.identity.descriptor.userId
        try p.a.setFinanceSettings(owner: owner, startDay: 15, timeZone: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil)
        try p.exchange()
        let id = StableID.make("finance-settings:" + owner.uuidString)
        let forged = SyncOperation(deviceId: p.b.identity.descriptor.deviceId, actorId: p.b.identity.descriptor.userId, entityId: id, entityType: .financeSettings, operationType: .patch, lamportClock: 1000, payload: ["day": .integer(31)], createdAt: p.clock.now())
        try p.a.merge([p.b.identity.sign(forged)])
        #expect(p.a.snapshot.finance.settings[id]?.cycleStartDay == 15)
        #expect(p.a.snapshot.conflicts.contains { $0.operationId == forged.id })
        let card = PaymentMethodProfile(ownerId: owner, holderId: p.b.identity.descriptor.userId, bankName: "BANK", name: "CARD", cardKind: .debit, lastFour: "1234", isShared: true)
        try p.a.savePaymentMethod(card); try p.exchange()
        #expect(throws: (any Error).self) { try p.b.deletePaymentMethod(card.id) }
        let payment = FinancePayment(kind: .reserves, paymentMethodId: card.id)
        let expense = try p.a.createExpense(title: "CARD_SOURCE_SEPARATE", amount: FinanceAmount(original: "1"), payment: payment, on: p.day)
        #expect(p.a.snapshot.finance.expenses[expense]?.payment.kind == .reserves)
    }
    @Test func invalidCurrentMonthRevisionIsDiagnosableAndHistoryImmutable() throws {
        let p = try FinancePair(), bill = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        let forged = SyncOperation(deviceId: p.a.identity.descriptor.deviceId, actorId: p.a.identity.descriptor.userId, entityId: UUID(), entityType: .billRevision, operationType: .create, lamportClock: 1000, payload: ["spaceId": .id(p.a.context.spaceId), "createdBy": .id(p.a.identity.descriptor.userId), "billId": .id(bill), "month": try FinanceProjector.value(FinanceMonth(year: 2024, month: 1)), "amount": try FinanceProjector.value(FinanceAmount(original: "88"))], createdAt: p.clock.now())
        try p.a.merge([p.a.identity.sign(forged)])
        #expect(p.a.snapshot.finance.revisions[forged.entityId] == nil && p.a.snapshot.conflicts.contains { $0.operationId == forged.id })
        let revision = try p.a.reviseBillDefaults(bill, amount: FinanceAmount(original: "88"), payment: p.own)
        #expect(throws: (any Error).self) { try p.a.deleteFinance(revision, type: .billRevision) }
        let change = try #require(p.a.financialChanges().first { $0.entityId == revision })
        #expect(change.title == "BILL" && change.oldCNYMinor == 6800 && change.newCNYMinor == 8800 && change.newPayment == p.own)
    }
    @Test func protocolUpgradeKeepsPinsAndRejectsOldClientBeforeFinanceFrames() throws {
        let a = try DeviceIdentity(protocolVersion: 3), old = try DeviceIdentity(protocolVersion: 2)
        let ka = Curve25519.KeyAgreement.PrivateKey(), kb = Curve25519.KeyAgreement.PrivateKey(), route = UUID()
        let ha = try RelaySecureSession.hello(identity: a, ephemeral: ka, routeId: route, profileName: "A"), hb = try RelaySecureSession.hello(identity: old, ephemeral: kb, routeId: route, profileName: "B")
        #expect(hb.verified())
        #expect(throws: (any Error).self) { try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb) }
    }
    @Test func reviewedCorrectionUsesOneExpenseAndCancelsFutureReviewReminder() throws {
        let p = try FinancePair(date: "2024-01-10T04:00:00Z")
        _ = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 10, timeZone: "Asia/Shanghai")
        let prior = try #require(p.a.snapshot.finance.expenses.values.first)
        try p.a.editExpense(prior.id, title: prior.title, amount: FinanceAmount(original: "88"), payment: prior.payment, on: prior.occurredOn, category: prior.category, notes: prior.notes, dateEventId: nil, reviewed: true)
        #expect(p.a.snapshot.finance.expenses.count == 1 && p.a.snapshot.finance.expenses[prior.id]?.status == .reconciled)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == -8800)
        #expect(try !p.a.financeReminders(includeFuture: true).contains { $0.expenseId == prior.id })
    }
}
@Suite("Finance amounts and calendars") struct FinanceCalculationTests {
    @Test func editorPreservesHistoricalReferenceBasisQuoteDateAndClearsCurrencyValues() throws {
        let quote = try ExchangeRateSnapshot(rate: "7.12345", source: "REFERENCE", quotedOn: CivilDate(year: 2024, month: 1, day: 15))
        let amount = try FinanceAmount(original: "10.01", currency: "USD", exchangeRate: quote)
        var draft = FinanceAmountDraft(amount, now: instant("2026-10-09T04:00:00Z"))
        let restored = try draft.amount()
        #expect(draft.actualCNY.isEmpty && restored == amount)
        #expect(try draft.amount().exchangeRate?.quotedOn == quote.quotedOn)
        draft.changeCurrency("JPY")
        #expect(draft.original.isEmpty && draft.actualCNY.isEmpty && draft.rate.isEmpty && draft.rateSource.isEmpty)
    }
    @Test func noFloatingPointAndSettlementPriority() throws {
        #expect(try FinanceMoney.sum([FinanceMoney.minor("0.1", currency: "CNY"), FinanceMoney.minor("0.2", currency: "CNY")]) == 30)
        let rate = try ExchangeRateSnapshot(rate: "7.12345", source: "REFERENCE", quotedOn: CivilDate(year: 2024, month: 1, day: 15))
        #expect(try FinanceAmount(original: "10", currency: "USD", actualCNY: "70.005", exchangeRate: rate).finalCNYMinor == 7001)
        #expect(try FinanceAmount(original: "10", currency: "USD", exchangeRate: rate).finalCNYMinor == 7123)
        #expect(throws: (any Error).self) { try FinanceAmount(original: "1", currency: "USD") }
        #expect(throws: (any Error).self) { try FinanceMoney.minor("NaN", currency: "CNY") }
        #expect(throws: (any Error).self) { try FinanceMoney.minor("999999999999999999999", currency: "CNY") }
    }
    @Test func currencyPrecisionAndPlatformNeutralIntegerStrings() throws {
        #expect(try FinanceMoney.minor("123", currency: "JPY") == 123)
        #expect(throws: (any Error).self) { try FinanceMoney.minor("1.01", currency: "JPY") }
        #expect(try FinanceMoney.minor("1.001", currency: "KWD") == 1001)
        let item = try FinanceAmount(original: "123", currency: "JPY", actualCNY: "5.62")
        let data = try CanonicalJSON.encode(item), obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["originalMinor"] as? String == "123" && obj["finalCNYMinor"] as? String == "562")
        #expect(try CanonicalJSON.decode(FinanceAmount.self, from: data) == item)
    }
    @Test func deterministicAARemainderInBothCurrencies() throws {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let pay = FinancePayment(kind: .equalSplit, userIds: [high, low]), amount = try FinanceAmount(original: "101", currency: "JPY", actualCNY: "5.01")
        let shares = pay.allocations(amount: amount)
        #expect(shares[0].userId == low && shares[0].originalMinor == 51 && shares[0].cnyMinor == 251)
        #expect(shares.reduce(0) { $0 + $1.originalMinor } == 101 && shares.reduce(0) { $0 + $1.cnyMinor } == 501)
    }
    @Test func shortMonthsLeapYearAndRestoredThirtyFirst() throws {
        for (year, month, expected) in [(2024,2,29),(2023,2,28),(2024,4,30),(2024,5,31)] {
            #expect(try FinancialCalendar.day(in: .init(year: year, month: month), requested: 31, timeZone: "America/New_York").day == expected)
        }
    }
    @Test func cyclesAreContinuousAcrossDSTAndClampedMonthEnds() throws {
        for zone in ["Asia/Shanghai","America/New_York"] {
            for day in [1,15,31] {
                let date = instant("2024-02-29T12:00:00Z"), first = try FinancialCalendar.cycle(containing: date, startDay: day, timeZone: zone)
                let next = try FinancialCalendar.cycle(containing: first.end, startDay: day, timeZone: zone)
                #expect(first.end == next.start && first.start < date && date < first.end)
            }
        }
    }
}
@Suite("Unified finance ledger") @MainActor struct FinanceLedgerTests {
    @Test func depositsOpeningNegativeBalancesAndCurrencyHistory() throws {
        let p = try FinancePair()
        try p.a.setOpeningBalance(FinanceAmount(original: "-10"), on: p.day)
        let dep = try p.a.deposit(FinanceAmount(original: "100", currency: "USD", actualCNY: "701.23"), by: p.b.identity.descriptor.userId, on: p.day)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == 69123)
        try p.a.editDeposit(dep, amount: FinanceAmount(original: "100", currency: "USD", actualCNY: "702"), by: p.b.identity.descriptor.userId, on: p.day, notes: "CORRECTION")
        _ = try p.a.createExpense(title: "RESERVES", amount: FinanceAmount(original: "1000"), payment: p.reserves, on: p.day)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == -30800)
        try p.a.deleteFinance(dep, type: .reserveEntry)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == -101000)
        try p.exchange(); #expect(p.a.snapshot.finance == p.b.snapshot.finance)
    }
    @Test func fourPaymentsSingleLedgerAndDateEvents() throws {
        let p = try FinancePair(), event1 = try p.a.createDateEvent(title: "FIRST", on: p.day), event2 = try p.a.createDateEvent(title: "SECOND", on: p.day)
        #expect(event1 != event2)
        _ = try p.a.deposit(FinanceAmount(original: "100"), by: p.a.identity.descriptor.userId, on: p.day)
        for (name,pay,event) in [("SHARED",p.reserves,Optional(event1)),("OWN",p.own,Optional(event2)),("PARTNER",p.partner,nil),("AA",p.aa,nil)] {
            _ = try p.a.createExpense(title: name, amount: FinanceAmount(original: "10.01"), payment: pay, on: p.day, category: "FOOD", dateEventId: event)
        }
        let stats = try p.a.snapshot.finance.statistics()
        #expect(stats.totalExpenses == 4004 && stats.reservesSpent == 1001 && stats.bookBalance == 8999)
        #expect(try FinanceMoney.sum(stats.personal.values) + stats.reservesSpent == stats.totalExpenses)
        #expect(p.a.snapshot.finance.expenses.count == 4 && p.a.snapshot.finance.dateEvents.count == 2)
        #expect(stats.categories["FOOD"] == 4004)
    }
    @Test func repeatedAndOutOfOrderOperationsAndTombstones() throws {
        let p = try FinancePair(), id = try p.a.createExpense(title: "BEFORE", amount: FinanceAmount(original: "218"), payment: p.own, on: p.day)
        let create = p.a.operations.last!
        try p.a.editExpense(id, title: "AFTER", amount: FinanceAmount(original: "238"), payment: p.aa, on: p.day, category: "", notes: "", dateEventId: nil)
        let edit = p.a.operations.last!
        try p.b.merge([edit]); try p.b.merge([create, edit, create]); #expect(p.b.snapshot.finance.expenses[id]?.amount.finalCNYMinor == 23800)
        try p.a.deleteFinance(id, type: .expense); try p.exchange(); try p.b.merge([create, edit])
        #expect(try p.b.snapshot.finance.statistics().totalExpenses == 0 && p.a.snapshot == p.b.snapshot)
    }
    @Test func financialChangeReviewUsesRealOldAndNewAmounts() throws {
        let p = try FinancePair(), id = try p.a.createExpense(title: "DINNER", amount: FinanceAmount(original: "218"), payment: p.own, on: p.day)
        try p.a.editExpense(id, title: "DINNER", amount: FinanceAmount(original: "238"), payment: p.own, on: p.day, category: "", notes: "", dateEventId: nil)
        let change = try #require(p.a.financialChanges().first)
        #expect(change.oldCNYMinor == 21800 && change.newCNYMinor == 23800 && change.entityId == id)
    }
    @Test func privateCardsNeverEnterLogAndSharedVisibilityIsAuditable() throws {
        let p = try FinancePair(), card = PaymentMethodProfile(ownerId: p.a.identity.descriptor.userId, bankName: "BANK", name: "PERSONAL", cardKind: .debit, lastFour: "1234")
        let count = p.a.operations.count; try p.a.savePaymentMethod(card)
        #expect(p.a.operations.count == count && p.b.visiblePaymentMethods.isEmpty)
        var shared = card; shared.isShared = true; try p.a.savePaymentMethod(shared); try p.exchange()
        #expect(p.b.visiblePaymentMethods.count == 1)
        var hidden = shared; hidden.isShared = false; hidden.name = "PRIVATE_EDIT"; try p.a.savePaymentMethod(hidden); try p.exchange()
        #expect(p.b.visiblePaymentMethods.isEmpty)
        #expect(!String(data: try CanonicalJSON.encode(p.a.operations), encoding: .utf8)!.contains("PRIVATE_EDIT"))
        let bad = PaymentMethodProfile(ownerId: p.a.identity.descriptor.userId, bankName: "BANK", name: "FULL", cardKind: .credit, lastFour: "1234567890123456")
        #expect(throws: (any Error).self) { try p.a.savePaymentMethod(bad) }
    }
}
@Suite("Finance recurring bills") @MainActor struct FinanceBillsTests {
    @Test func noUnrequestedBillsNoRemindersOrExpenses() throws {
        let p = try FinancePair(); #expect(p.a.snapshot.finance.bills.isEmpty && p.a.snapshot.finance.expenses.isEmpty)
        #expect(try p.a.financeReminders().isEmpty); try p.a.reconcileFinanceBills(); #expect(p.a.snapshot.finance.expenses.isEmpty)
    }
    @Test func defaultsChangeNextNaturalMonthEvenWithDifferentCycle() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        try p.a.setFinanceSettings(owner: nil, startDay: 20, timeZone: "Asia/Shanghai", salaryDay: nil, plannedDepositDay: nil)
        _ = try p.a.reviseBillDefaults(id, amount: FinanceAmount(original: "88"), payment: p.own)
        let bill = try #require(p.a.snapshot.finance.bills[id])
        let current = try p.a.snapshot.finance.occurrence(bill, month: .init(year: 2024, month: 1)), next = try p.a.snapshot.finance.occurrence(bill, month: .init(year: 2024, month: 2))
        #expect(current.amount.finalCNYMinor == 6800 && current.payment == p.reserves)
        #expect(next.amount.finalCNYMinor == 8800 && next.payment == p.own && next.date.day == 29)
        #expect(bill.recurrenceDay == 31)
    }
    @Test func beforeDateOverrideIsNotAnExpenseAndDoesNotChangeNextDefault() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        try p.a.overrideBillOccurrence(id, month: .init(year: 2024, month: 1), amount: FinanceAmount(original: "71"), payment: p.aa)
        #expect(p.a.snapshot.finance.expenses.isEmpty)
        p.clock.advance(17 * 24 * 3600); try p.a.reconcileFinanceBills()
        let expense = try #require(p.a.snapshot.finance.expenses.values.first)
        #expect(expense.amount.finalCNYMinor == 7100 && expense.payment == p.aa)
        let bill = try #require(p.a.snapshot.finance.bills[id]); #expect(try p.a.snapshot.finance.occurrence(bill, month: .init(year: 2024, month: 2)).amount.finalCNYMinor == 6800)
    }
    @Test func provisionalConfirmModifySkipNeverDoubleDeduct() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 15, timeZone: "Asia/Shanghai")
        let expense = try #require(p.a.snapshot.finance.expenses.values.first)
        let before = try p.a.snapshot.finance.statistics()
        #expect(before.bookBalance == -6800 && before.verifiedBalance == 0 && before.provisionalReservesAmount == 6800)
        try p.a.reviewExpense(expense.id, status: .reconciled)
        let confirmed = try p.a.snapshot.finance.statistics(); #expect(confirmed.bookBalance == -6800 && confirmed.verifiedBalance == -6800)
        try p.a.editExpense(expense.id, title: expense.title, amount: FinanceAmount(original: "70"), payment: p.own, on: expense.occurredOn, category: "", notes: "", dateEventId: nil)
        #expect(try p.a.snapshot.finance.statistics().bookBalance == 0)
        try p.a.reviewExpense(expense.id, status: .skipped); #expect(try p.a.snapshot.finance.statistics().totalExpenses == 0)
        #expect(p.a.snapshot.finance.expenses.count == 1)
        let bill = try #require(p.a.snapshot.finance.bills[id]); #expect(try p.a.snapshot.finance.occurrence(bill, month: .init(year: 2024, month: 2)).amount.finalCNYMinor == 6800)
    }
    @Test func bothOfflineDevicesGenerateSameOccurrenceAndConverge() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 31, timeZone: "Asia/Shanghai")
        try p.exchange(); p.clock.advance(17 * 24 * 3600)
        try p.a.reconcileFinanceBills(); try p.b.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses.count == 1 && p.b.snapshot.finance.expenses.count == 1)
        try p.exchange(); #expect(p.a.snapshot == p.b.snapshot && p.a.snapshot.finance.expenses.count == 1)
        try p.a.reconcileFinanceBills(); #expect(p.a.snapshot.finance.expenses.count == 1)
        #expect(p.a.snapshot.finance.expenses.values.first?.recurringBillId == id)
    }
    @Test func missingMonthBackfillPauseAndResumeRespectHistory() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "10"), payment: p.own, day: 1, timeZone: "Asia/Shanghai", startMonth: .init(year: 2023, month: 11))
        #expect(p.a.snapshot.finance.expenses.count == 3)
        try p.a.setBillActive(id, active: false); p.clock.advance(32 * 24 * 3600); try p.a.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses.count == 3)
        try p.a.setBillActive(id, active: true); p.clock.advance(20 * 24 * 3600); try p.a.reconcileFinanceBills()
        #expect(p.a.snapshot.finance.expenses.count == 4)
        #expect(!p.a.snapshot.finance.expenses.values.contains { $0.occurrenceMonth == FinanceMonth(year: 2024, month: 2) })
    }
    @Test func remindersUseCalendarDayAndReviewStateIsLocal() throws {
        let p = try FinancePair(date: "2024-01-30T04:00:00Z")
        _ = try p.a.createRecurringBill(title: "MONTH_END", amount: FinanceAmount(original: "10"), payment: p.own, day: 31, timeZone: "Asia/Shanghai")
        let forecast = try #require(p.a.financeReminders().first); #expect(forecast.kind == .forecast)
        p.clock.advance(2 * 24 * 3600); try p.a.reconcileFinanceBills()
        #expect(try p.a.financeReminders().contains { $0.kind == .reconcile })
        var state = try p.a.financialReviewState(); state.dismissedReminderIds.insert(forecast.id); try p.a.saveFinancialReviewState(state)
        try p.exchange(); #expect(try p.b.financialReviewState().dismissedReminderIds.isEmpty)
    }
    @Test func lateRevisionAndConcurrentAmountPaymentConverge() throws {
        let p = try FinancePair(), id = try p.a.createRecurringBill(title: "BILL", amount: FinanceAmount(original: "68"), payment: p.reserves, day: 1, timeZone: "Asia/Shanghai", startMonth: .init(year: 2024, month: 2))
        try p.exchange(); _ = try p.a.reviseBillDefaults(id, amount: FinanceAmount(original: "88")); _ = try p.b.reviseBillDefaults(id, payment: p.own)
        p.clock.advance(18 * 24 * 3600); try p.a.reconcileFinanceBills(); try p.b.reconcileFinanceBills(); try p.exchange()
        let e = try #require(p.a.snapshot.finance.expenses.values.first)
        #expect(e.amount.finalCNYMinor == 8800 && e.payment == p.own && p.a.snapshot == p.b.snapshot)
    }
}
