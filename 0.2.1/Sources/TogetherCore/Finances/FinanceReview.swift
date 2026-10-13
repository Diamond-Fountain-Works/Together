import Foundation

public struct FinanceChange: Identifiable, Equatable, Sendable {
    public var id: UUID; public var entityId: UUID; public var actorId: UUID; public var type: EntityType; public var action: OperationType
    public var title: String; public var oldCNYMinor: Int64?; public var newCNYMinor: Int64?; public var effectiveMonth: FinanceMonth?; public var createdAt: Date
    public var oldPayment: FinancePayment?; public var newPayment: FinancePayment?; public var reviewStatus: ExpenseReviewStatus?; public var active: Bool?
}
public enum FinanceReminderKind: String, Sendable { case forecast, reconcile, plannedDeposit }
public struct FinanceReminder: Identifiable, Equatable, Sendable {
    public var id: String; public var kind: FinanceReminderKind; public var title: String; public var amount: FinanceAmount?
    public var payment: FinancePayment?; public var billId: UUID?; public var expenseId: UUID?; public var month: FinanceMonth?; public var scheduledAt: Date
}
@MainActor public extension ReplicaEngine {
    func financialChanges(limit: Int = 80) -> [FinanceChange] {
        if let cache = financeChangeCache, cache.operationCount == operations.count, cache.members == context.members, cache.limit >= limit { return Array(cache.changes.prefix(limit)) }
        let ordered = operations.sorted { $0.operation.order < $1.operation.order }, invalid = Set(snapshot.conflicts.map(\.operationId))
        let selected = Set(ordered.filter { FinanceProjector.types.contains($0.operation.entityType) && !invalid.contains($0.id) }.suffix(limit).map(\.id))
        var prefix: [SignedOperation] = [], result: [FinanceChange] = [], created: Set<UUID> = []
        for signed in ordered {
            defer { prefix.append(signed) }
            let op = signed.operation
            if op.operationType == .create && !created.insert(op.entityId).inserted,
               op.entityType != .financeSettings && op.entityType != .billOccurrence && !(op.entityType == .reserveEntry && op.entityId == StableID.make("finance-reserves-opening")) { continue }
            guard selected.contains(op.id) else { continue }
            let before = OperationProjector.replay(prefix, context: context).finance
            let month = try? FinanceProjector.decode(FinanceMonth.self, op.payload["month"])
            let billId = op.payload["billId"]?.uuid
            let defaults = billId.flatMap { before.bills[$0] }.flatMap { bill in month.flatMap { try? before.occurrence(bill, month: $0) } }
            let old = before.reserves[op.entityId]?.amount ?? before.expenses[op.entityId]?.amount ?? defaults?.amount
            let new = try? FinanceProjector.optionalDecode(FinanceAmount.self, op.payload["amount"])
            let title = op.payload["title"]?.string ?? before.expenses[op.entityId]?.title ?? before.bills[op.entityId]?.title ?? before.dateEvents[op.entityId]?.title ?? billId.flatMap { before.bills[$0]?.title } ?? ""
            let payment = try? FinanceProjector.optionalDecode(FinancePayment.self, op.payload["payment"])
            result.append(.init(id: op.id, entityId: op.entityId, actorId: op.actorId, type: op.entityType, action: op.operationType, title: title, oldCNYMinor: old?.finalCNYMinor, newCNYMinor: new?.finalCNYMinor, effectiveMonth: month, createdAt: op.createdAt, oldPayment: before.expenses[op.entityId]?.payment ?? defaults?.payment, newPayment: payment, reviewStatus: op.payload["status"]?.string.flatMap(ExpenseReviewStatus.init(rawValue:)), active: FinanceProjector.boolean(op.payload["active"])))
        }
        let changes = Array(result.reversed())
        financeChangeCache = (operations.count, context.members, limit, changes)
        return changes
    }
    func financeReminders(at now: Date? = nil, includeFuture: Bool = false) throws -> [FinanceReminder] {
        let now = now ?? dateProvider.now(), finance = snapshot.finance
        var result: [FinanceReminder] = []
        for bill in finance.bills.values where bill.deletedAt == nil {
            let current = FinanceMonth(now, timeZone: bill.timeZoneIdentifier)
            for month in [current, current.next] {
                let instance = try finance.occurrence(bill, month: month)
                guard instance.isActive else { continue }
                let due = try FinancialCalendar.instant(instance.date, timeZone: bill.timeZoneIdentifier, minuteOfDay: bill.minuteOfDay)
                let before: Date
                if bill.minuteOfDay != nil { before = due.addingTimeInterval(-24 * 60 * 60) }
                else { before = try FinancialCalendar.instant(FinancialCalendar.shifted(instance.date, days: -1, timeZone: bill.timeZoneIdentifier), timeZone: bill.timeZoneIdentifier) }
                let nextDay = try FinancialCalendar.instant(FinancialCalendar.shifted(instance.date, days: 1, timeZone: bill.timeZoneIdentifier), timeZone: bill.timeZoneIdentifier)
                if before > now && includeFuture || (now >= before && now < due && finance.expenses[instance.id] == nil) {
                    result.append(.init(id: "forecast-" + instance.id.uuidString, kind: .forecast, title: bill.title, amount: instance.amount, payment: instance.payment, billId: bill.id, month: month, scheduledAt: before))
                }
                if includeFuture && nextDay > now && (finance.expenses[instance.id] == nil || finance.expenses[instance.id]?.status == .provisional) {
                    result.append(.init(id: "reconcile-" + instance.id.uuidString, kind: .reconcile, title: bill.title, amount: finance.expenses[instance.id]?.amount ?? instance.amount, payment: finance.expenses[instance.id]?.payment ?? instance.payment, billId: bill.id, expenseId: instance.id, month: month, scheduledAt: nextDay))
                }
            }
        }
        for expense in finance.expenses.values where expense.deletedAt == nil && expense.status == .provisional && expense.recurringBillId != nil {
            let next = try FinancialCalendar.instant(FinancialCalendar.shifted(expense.occurredOn, days: 1, timeZone: expense.timeZoneIdentifier), timeZone: expense.timeZoneIdentifier)
            if now >= next { result.append(.init(id: "reconcile-" + expense.id.uuidString, kind: .reconcile, title: expense.title, amount: expense.amount, payment: expense.payment, billId: expense.recurringBillId, expenseId: expense.id, month: expense.occurrenceMonth, scheduledAt: next)) }
        }
        let personal = finance.settings(for: identity.descriptor.userId, fallbackTimeZone: sharedSpace.timeZoneIdentifier)
        if let day = personal.plannedDepositDay {
            let month = FinanceMonth(now, timeZone: personal.timeZoneIdentifier), civil = try FinancialCalendar.day(in: month, requested: day, timeZone: personal.timeZoneIdentifier)
            if CivilDate(now, timeZone: TimeZone(identifier: personal.timeZoneIdentifier)!) == civil {
                result.append(.init(id: "planned-deposit-" + month.iso, kind: .plannedDeposit, title: Copy.text("finance.reminder.plannedDeposit"), scheduledAt: try FinancialCalendar.instant(civil, timeZone: personal.timeZoneIdentifier)))
            }
        }
        return Array(Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values).sorted { $0.scheduledAt < $1.scheduledAt }
    }
}
