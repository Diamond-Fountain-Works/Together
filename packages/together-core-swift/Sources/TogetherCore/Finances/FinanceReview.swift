import Foundation

public struct FinanceChange: Identifiable, Equatable, Sendable {
    public var id: UUID; public var entityId: UUID; public var actorId: UUID; public var type: EntityType; public var action: OperationType
    public var title: String; public var oldCNYMinor: Int64?; public var newCNYMinor: Int64?; public var effectiveMonth: FinanceMonth?; public var createdAt: Date
    public var resolution:ChangeResolution = .effective
    public var oldPayment: FinancePayment?; public var newPayment: FinancePayment?; public var reviewStatus: ExpenseReviewStatus?; public var active: Bool?
}
public enum FinanceReminderKind: String, Sendable { case forecast, reconcile, plannedDeposit }
public struct FinanceReminder: Identifiable, Equatable, Sendable {
    public var id: String; public var kind: FinanceReminderKind; public var title: String; public var amount: FinanceAmount?
    public var payment: FinancePayment?; public var billId: UUID?; public var expenseId: UUID?; public var month: FinanceMonth?; public var scheduledAt: Date
}
@MainActor public extension ReplicaEngine {
    func financialChanges(limit: Int = 80) -> [FinanceChange] {
        if let cache=financeChangeCache,cache.operationCount==changeNumber,cache.members==context.members,cache.limit>=limit{return Array(cache.changes.prefix(limit))}
        return financialChanges(projectedEvents:OperationProjector.changes(operations,context:context),limit:limit)
    }
    func financialChanges(projectedEvents:[ChangeEvent],limit:Int=80)->[FinanceChange] {
        let events=projectedEvents.filter{FinanceProjector.types.contains($0.type)}.prefix(max(0,limit))
        let changes=events.map{event -> FinanceChange in
            let old=try? FinanceProjector.optionalDecode(FinanceAmount.self,event.before["amount"])
            let new=try? FinanceProjector.optionalDecode(FinanceAmount.self,event.after["amount"])
            let billId=event.after["billId"]?.uuid ?? event.before["billId"]?.uuid
            let month=try? FinanceProjector.optionalDecode(FinanceMonth.self,event.after["month"])
            let oldPayment=try? FinanceProjector.optionalDecode(FinancePayment.self,event.before["payment"])
            let newPayment=try? FinanceProjector.optionalDecode(FinancePayment.self,event.after["payment"])
            var defaults:RecurringBillOccurrence?
            if let billId,let month,let bill=snapshot.finance.bills[billId] {
                var prior=snapshot.finance
                let order=FinanceRevisionOrder(OperationOrder(clock:event.order.clock,device:event.order.device,operation:event.order.operation))
                prior.revisions=prior.revisions.filter{$0.value.order<order}
                defaults=try? prior.occurrence(bill,month:month)
            }
            let title=event.title.isEmpty ? billId.flatMap{snapshot.finance.bills[$0]?.title} ?? "":event.title
            return FinanceChange(id:event.id,entityId:event.entityId,actorId:event.actorId,type:event.type,action:event.action,title:title,oldCNYMinor:old?.finalCNYMinor ?? defaults?.amount.finalCNYMinor,newCNYMinor:new?.finalCNYMinor,effectiveMonth:month,createdAt:event.occurredAt,resolution:event.resolution,oldPayment:oldPayment ?? defaults?.payment,newPayment:newPayment,reviewStatus:event.after["status"]?.string.flatMap(ExpenseReviewStatus.init(rawValue:)),active:FinanceProjector.boolean(event.after["active"]))
        }
        financeChangeCache=(changeNumber,context.members,limit,changes);return changes
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
