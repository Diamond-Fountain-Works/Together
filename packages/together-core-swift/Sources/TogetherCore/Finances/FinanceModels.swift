import Foundation

public enum FinancePaymentKind: String, Codable, CaseIterable, Sendable { case reserves, personal, equalSplit }
public struct FinancePayment: Codable, Equatable, Sendable {
    public var kind: FinancePaymentKind
    public var userIds: [UUID]
    public var paymentMethodId: UUID?
    public init(kind: FinancePaymentKind, userIds: [UUID] = [], paymentMethodId: UUID? = nil) { self.kind = kind; self.userIds = userIds.sorted { $0.uuidString < $1.uuidString }; self.paymentMethodId = paymentMethodId }
    public func valid(members: Set<UUID>) -> Bool {
        guard Set(userIds).count == userIds.count, Set(userIds).isSubset(of: members) else { return false }
        switch kind { case .reserves: return userIds.isEmpty; case .personal: return userIds.count == 1; case .equalSplit: return userIds.count == 2 }
    }
    public func allocations(amount: FinanceAmount) -> [ExpenseAllocation] {
        guard kind != .reserves else { return [] }
        let sorted = userIds.sorted { $0.uuidString < $1.uuidString }, n = Int64(sorted.count)
        guard n > 0 else { return [] }
        return sorted.enumerated().map { index, id in
            ExpenseAllocation(userId: id, originalMinor: amount.originalMinor / n + (Int64(index) < amount.originalMinor % n ? 1 : 0), cnyMinor: amount.finalCNYMinor / n + (Int64(index) < amount.finalCNYMinor % n ? 1 : 0))
        }
    }
}
public struct ExpenseAllocation: Codable, Equatable, Sendable { public var userId: UUID; public var originalMinor: Int64; public var cnyMinor: Int64 }
public enum ReserveEntryKind: String, Codable, Sendable { case opening, deposit }
public struct UnitedReservesLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var spaceId: UUID; public var depositedBy: UUID; public var kind: ReserveEntryKind
    public var amount: FinanceAmount; public var depositDate: CivilDate; public var createdAt: Date; public var notes: String; public var deletedAt: Date?
}
public struct DateEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var spaceId: UUID; public var title: String; public var date: CivilDate; public var notes: String; public var createdBy: UUID; public var createdAt: Date; public var deletedAt: Date?
}
public enum ExpenseReviewStatus: String, Codable, CaseIterable, Sendable { case provisional, reconciled, skipped }
public struct ExpenseEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var spaceId: UUID; public var title: String; public var amount: FinanceAmount; public var payment: FinancePayment
    public var occurredOn: CivilDate; public var timeZoneIdentifier: String; public var category: String; public var notes: String; public var dateEventId: UUID?
    public var recurringBillId: UUID?; public var occurrenceMonth: FinanceMonth?; public var status: ExpenseReviewStatus
    public var amountOverridden: Bool = false; public var paymentOverridden: Bool = false
    public var createdBy: UUID; public var createdAt: Date; public var deletedAt: Date?
    public var allocations: [ExpenseAllocation] { payment.allocations(amount: amount) }
    public var isEffective: Bool { deletedAt == nil && status != .skipped }
}
public struct RecurringBill: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var spaceId: UUID; public var title: String; public var defaultAmount: FinanceAmount; public var defaultPayment: FinancePayment
    public var recurrenceDay: Int; public var timeZoneIdentifier: String; public var minuteOfDay: Int?; public var startMonth: FinanceMonth
    public var category: String; public var createdBy: UUID; public var createdAt: Date; public var deletedAt: Date?
}
public struct RecurringBillRuleRevision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var billId: UUID; public var effectiveMonth: FinanceMonth
    public var amount: FinanceAmount?; public var payment: FinancePayment?; public var active: Bool?; public var activeFromDay: CivilDate?
    public var createdBy: UUID; public var createdAt: Date; public var order: FinanceRevisionOrder
}
public struct FinanceRevisionOrder: Codable, Equatable, Comparable, Sendable {
    public var clock: Int64; public var device: String; public var operation: String
    public init(_ order: OperationOrder) { clock = order.clock; device = order.device; operation = order.operation }
    public static func < (a: Self, b: Self) -> Bool { OperationOrder(clock: a.clock, device: a.device, operation: a.operation) < OperationOrder(clock: b.clock, device: b.device, operation: b.operation) }
}
public struct RecurringBillOccurrence: Identifiable, Equatable, Sendable {
    public var billId: UUID; public var month: FinanceMonth; public var date: CivilDate; public var amount: FinanceAmount; public var payment: FinancePayment; public var isActive: Bool
    public var id: UUID { StableID.make("finance-bill:\(billId.uuidString):\(month.iso)") }
}
public struct RecurringBillOccurrenceOverride: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var billId: UUID; public var month: FinanceMonth; public var amount: FinanceAmount?; public var payment: FinancePayment?
}
public struct FinanceSettings: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var ownerId: UUID?; public var cycleStartDay: Int; public var timeZoneIdentifier: String
    public var salaryDay: Int?; public var plannedDepositDay: Int?; public var updatedAt: Date
}
public enum PaymentCardKind: String, Codable, CaseIterable, Sendable { case debit, credit }
public struct PaymentMethodProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID; public var ownerId: UUID; public var holderId: UUID; public var bankName: String; public var name: String; public var cardKind: PaymentCardKind
    public var lastFour: String; public var currencyCode: String?; public var isShared: Bool; public var deletedAt: Date?
    public init(id: UUID = UUID(), ownerId: UUID, holderId: UUID? = nil, bankName: String, name: String, cardKind: PaymentCardKind, lastFour: String, currencyCode: String? = nil, isShared: Bool = false, deletedAt: Date? = nil) {
        self.id = id; self.ownerId = ownerId; self.holderId = holderId ?? ownerId; self.bankName = bankName; self.name = name; self.cardKind = cardKind; self.lastFour = lastFour; self.currencyCode = currencyCode; self.isShared = isShared; self.deletedAt = deletedAt
    }
    public var isValid: Bool { !name.isEmpty && name.count <= 60 && !bankName.isEmpty && bankName.count <= 100 && lastFour.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil && (currencyCode.map { FinanceCurrency.find($0) != nil } ?? true) }
}
public struct LocalFinancialReviewState: Codable, Equatable, Sendable {
    public var presentedOperationIds: Set<UUID> = []; public var dismissedReminderIds: Set<String> = []
    public init() {}
}
public struct FinanceSnapshot: Equatable, Sendable {
    public var reserves: [UUID: UnitedReservesLedgerEntry] = [:]; public var dateEvents: [UUID: DateEvent] = [:]
    public var expenses: [UUID: ExpenseEntry] = [:]; public var bills: [UUID: RecurringBill] = [:]
    public var revisions: [UUID: RecurringBillRuleRevision] = [:]; public var settings: [UUID: FinanceSettings] = [:]
    public var paymentMethods: [UUID: PaymentMethodProfile] = [:]
    public var occurrenceOverrides: [UUID: RecurringBillOccurrenceOverride] = [:]
    public init() {}
    public func occurrence(_ bill: RecurringBill, month: FinanceMonth) throws -> RecurringBillOccurrence {
        let day = try FinancialCalendar.day(in: month, requested: bill.recurrenceDay, timeZone: bill.timeZoneIdentifier)
        let due = try FinancialCalendar.instant(day, timeZone: bill.timeZoneIdentifier, minuteOfDay: bill.minuteOfDay)
        var amount = bill.defaultAmount, payment = bill.defaultPayment, active = true
        let revisions = revisions.values.filter { $0.billId == bill.id && $0.effectiveMonth <= month }.sorted { $0.effectiveMonth == $1.effectiveMonth ? $0.order < $1.order : $0.effectiveMonth < $1.effectiveMonth }
        for revision in revisions { if let value = revision.amount { amount = value }; if let value = revision.payment { payment = value } }
        for revision in revisions.sorted(by: { $0.order < $1.order }) { if let value = revision.active, let from = revision.activeFromDay, from <= day, revision.createdAt <= due { active = value } }
        if let special = occurrenceOverrides.values.first(where: { $0.billId == bill.id && $0.month == month }) {
            if let value = special.amount { amount = value }; if let value = special.payment { payment = value }
        }
        return .init(billId: bill.id, month: month, date: day, amount: amount, payment: payment, isActive: active && (bill.deletedAt.map { due <= $0 } ?? true) && month >= bill.startMonth)
    }
    public func settings(for owner: UUID?, fallbackTimeZone: String) -> FinanceSettings {
        settings[StableID.make("finance-settings:" + (owner?.uuidString ?? "shared"))] ?? FinanceSettings(id: StableID.make("finance-settings:" + (owner?.uuidString ?? "shared")), ownerId: owner, cycleStartDay: 1, timeZoneIdentifier: fallbackTimeZone, updatedAt: .distantPast)
    }
    public func isActive(_ bill: RecurringBill, at date: Date) -> Bool {
        guard bill.deletedAt == nil else { return false }
        let day = CivilDate(date, timeZone: TimeZone(identifier: bill.timeZoneIdentifier)!)
        return revisions.values.filter { $0.billId == bill.id && $0.activeFromDay.map { $0 <= day } == true && $0.active != nil }.max { $0.order < $1.order }?.active ?? true
    }
    public func statistics(in interval: DateInterval? = nil, timeZone: String = "Etc/UTC") throws -> FinanceStatistics {
        let entries = expenses.values.filter { entry in entry.isEffective && (interval.map { range in guard let at = try? FinancialCalendar.instant(entry.occurredOn, timeZone: entry.timeZoneIdentifier) else { return false }; return at >= range.start && at < range.end } ?? true) }
        let deposits = reserves.values.filter { entry in entry.deletedAt == nil && (interval.map { range in guard let at = try? FinancialCalendar.instant(entry.depositDate, timeZone: timeZone) else { return false }; return at >= range.start && at < range.end } ?? true) }
        let total = try FinanceMoney.sum(entries.map(\.amount.finalCNYMinor)), shared = entries.filter { $0.payment.kind == .reserves }
        var personal: [UUID: Int64] = [:], categories: [String: Int64] = [:]
        for entry in entries { categories[entry.category] = try FinanceMoney.sum([categories[entry.category] ?? 0, entry.amount.finalCNYMinor]); for share in entry.allocations { personal[share.userId] = try FinanceMoney.sum([personal[share.userId] ?? 0, share.cnyMinor]) } }
        let incoming = try FinanceMoney.sum(deposits.map(\.amount.finalCNYMinor)), sharedTotal = try FinanceMoney.sum(shared.map(\.amount.finalCNYMinor))
        let pending = try FinanceMoney.sum(shared.filter { $0.status == .provisional }.map(\.amount.finalCNYMinor))
        return .init(totalExpenses: total, reservesSpent: sharedTotal, personal: personal, categories: categories, bookBalance: try FinanceMoney.sum([incoming, -sharedTotal]), verifiedBalance: try FinanceMoney.sum([incoming, -sharedTotal, pending]), provisionalReservesAmount: pending, deposited: incoming)
    }
}
public struct FinanceStatistics: Equatable, Sendable {
    public var totalExpenses: Int64; public var reservesSpent: Int64; public var personal: [UUID: Int64]; public var categories: [String: Int64]
    public var bookBalance: Int64; public var verifiedBalance: Int64; public var provisionalReservesAmount: Int64; public var deposited: Int64
}
