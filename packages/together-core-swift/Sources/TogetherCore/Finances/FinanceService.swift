import Foundation

@MainActor public extension ReplicaEngine {
    private func financeWrite(_ id: UUID, type: EntityType, action: OperationType, fields: [String: LogValue]) throws {
        if action == .patch && fields.isEmpty { return }
        var payload = fields
        if action == .create { payload["spaceId"] = .id(context.spaceId); payload["createdBy"] = .id(identity.descriptor.userId) }
        try append(entity: id, type: type, action: action, fields: payload, createdAt: dateProvider.now())
    }
    @discardableResult func deposit(_ amount: FinanceAmount, by user: UUID, on date: CivilDate, notes: String = "", id: UUID = UUID()) throws -> UUID {
        guard amount.originalMinor > 0 && amount.finalCNYMinor >= 0 else { throw FinanceError.invalidAmount }
        guard snapshot.finance.reserves[id] == nil else { throw FinanceError.invalidRecord }
        try financeWrite(id, type: .reserveEntry, action: .create, fields: ["kind": try FinanceProjector.value(ReserveEntryKind.deposit), "amount": try FinanceProjector.value(amount), "depositedBy": .id(user), "date": try FinanceProjector.value(date), "notes": .string(notes)])
        return id
    }
    func setOpeningBalance(_ amount: FinanceAmount, on date: CivilDate) throws {
        let id = StableID.make("finance-reserves-opening")
        var fields: [String: LogValue] = ["amount": try FinanceProjector.value(amount), "date": try FinanceProjector.value(date), "notes": .string("")]
        let exists = snapshot.finance.reserves[id] != nil
        if !exists { fields["kind"] = try FinanceProjector.value(ReserveEntryKind.opening); fields["depositedBy"] = .id(identity.descriptor.userId) }
        try financeWrite(id, type: .reserveEntry, action: exists ? .patch : .create, fields: fields)
    }
    func editDeposit(_ id: UUID, amount: FinanceAmount, by user: UUID, on date: CivilDate, notes: String, editingBaseline: UnitedReservesLedgerEntry? = nil) throws {
        guard let prior = snapshot.finance.reserves[id], prior.deletedAt == nil else { throw FinanceError.missingRecord }
        guard prior.kind == .opening || (amount.originalMinor > 0 && amount.finalCNYMinor >= 0) else { throw FinanceError.invalidAmount }
        let baseline = editingBaseline ?? prior
        var fields: [String: LogValue] = [:]
        if amount != baseline.amount { fields["amount"] = try FinanceProjector.value(amount) }
        if user != baseline.depositedBy { fields["depositedBy"] = .id(user) }
        if date != baseline.depositDate { fields["date"] = try FinanceProjector.value(date) }
        if notes != baseline.notes { fields["notes"] = .string(notes) }
        try financeWrite(id, type: .reserveEntry, action: .patch, fields: fields)
    }
    @discardableResult func createDateEvent(title: String, on day: CivilDate, notes: String = "", id: UUID = UUID()) throws -> UUID {
        guard snapshot.finance.dateEvents[id] == nil else { throw FinanceError.invalidRecord }
        try financeWrite(id, type: .dateEvent, action: .create, fields: ["title": .string(title), "date": try FinanceProjector.value(day), "notes": .string(notes)]); return id
    }
    func editDateEvent(_ id: UUID, title: String, on day: CivilDate, notes: String) throws {
        guard snapshot.finance.dateEvents[id]?.deletedAt == nil, snapshot.finance.dateEvents[id] != nil else { throw FinanceError.missingRecord }
        try financeWrite(id, type: .dateEvent, action: .patch, fields: ["title": .string(title), "date": try FinanceProjector.value(day), "notes": .string(notes)])
    }
    @discardableResult func createExpense(title: String, amount: FinanceAmount, payment: FinancePayment, on date: CivilDate, category: String = "", notes: String = "", dateEventId: UUID? = nil, timeZone: String? = nil, id: UUID = UUID()) throws -> UUID {
        guard snapshot.finance.expenses[id] == nil else { throw FinanceError.invalidRecord }
        try financeWrite(id, type: .expense, action: .create, fields: ["title": .string(title), "amount": try FinanceProjector.value(amount), "payment": try FinanceProjector.value(payment), "date": try FinanceProjector.value(date), "zone": .string(timeZone ?? sharedSpace.timeZoneIdentifier), "category": .string(category), "notes": .string(notes), "eventId": .id(dateEventId), "status": .string(ExpenseReviewStatus.reconciled.rawValue)])
        return id
    }
    func editExpense(_ id: UUID, title: String, amount: FinanceAmount, payment: FinancePayment, on date: CivilDate, category: String, notes: String, dateEventId: UUID?, reviewed: Bool = false, editingBaseline: ExpenseEntry? = nil) throws {
        guard let prior = snapshot.finance.expenses[id], prior.deletedAt == nil else { throw FinanceError.missingRecord }
        let baseline = editingBaseline ?? prior
        guard baseline.id == id else { throw FinanceError.invalidRecord }
        if reviewed && ((amount == baseline.amount && prior.amount != baseline.amount) || (payment == baseline.payment && prior.payment != baseline.payment)) { throw FinanceError.recordChanged }
        var fields: [String: LogValue] = [:]
        if title != baseline.title { fields["title"] = .string(title) }
        if amount != baseline.amount || reviewed { fields["amount"] = try FinanceProjector.value(amount); fields["amountOverridden"] = .boolean(true) }
        if payment != baseline.payment || reviewed { fields["payment"] = try FinanceProjector.value(payment); fields["paymentOverridden"] = .boolean(true) }
        if date != baseline.occurredOn { fields["date"] = try FinanceProjector.value(date) }
        if category != baseline.category { fields["category"] = .string(category) }
        if notes != baseline.notes { fields["notes"] = .string(notes) }
        if dateEventId != baseline.dateEventId { fields["eventId"] = .id(dateEventId) }
        if reviewed { fields["status"] = .string(ExpenseReviewStatus.reconciled.rawValue) }
        try financeWrite(id, type: .expense, action: .patch, fields: fields)
    }
    func reviewExpense(_ id: UUID, status: ExpenseReviewStatus) throws {
        guard let prior = snapshot.finance.expenses[id], prior.deletedAt == nil else { throw FinanceError.missingRecord }
        var fields: [String: LogValue] = ["status": .string(status.rawValue)]
        if status == .reconciled {
            fields["amount"] = try FinanceProjector.value(prior.amount); fields["payment"] = try FinanceProjector.value(prior.payment)
            fields["amountOverridden"] = .boolean(true); fields["paymentOverridden"] = .boolean(true)
        }
        try financeWrite(id, type: .expense, action: .patch, fields: fields)
    }
    func deleteFinance(_ id: UUID, type: EntityType) throws {
        guard FinanceProjector.types.contains(type), type != .financeSettings, type != .billRevision else { throw FinanceError.invalidRecord }
        if type == .recurringBill { try reconcileFinanceBills() }
        try financeWrite(id, type: type, action: .delete, fields: [:])
    }
    @discardableResult func createRecurringBill(title: String, amount: FinanceAmount, payment: FinancePayment, day: Int, timeZone: String, startMonth: FinanceMonth? = nil, minuteOfDay: Int? = nil, category: String = "", id: UUID = UUID()) throws -> UUID {
        guard snapshot.finance.bills[id] == nil else { throw FinanceError.invalidRecord }
        let now = dateProvider.now(), month = FinanceMonth(now, timeZone: timeZone)
        let scheduled = try FinancialCalendar.day(in: month, requested: day, timeZone: timeZone)
        let today = CivilDate(now, timeZone: TimeZone(identifier: timeZone)!)
        let start = startMonth ?? (scheduled < today ? month.next : month)
        try financeWrite(id, type: .recurringBill, action: .create, fields: ["title": .string(title), "amount": try FinanceProjector.value(amount), "payment": try FinanceProjector.value(payment), "day": .integer(day), "zone": .string(timeZone), "startMonth": try FinanceProjector.value(start), "minute": minuteOfDay.map(LogValue.integer) ?? .null, "category": .string(category)])
        try reconcileFinanceBills(); return id
    }
    func editBillTitle(_ id: UUID, title: String, category: String, editingBaseline: RecurringBill? = nil) throws {
        guard let bill = snapshot.finance.bills[id], bill.deletedAt == nil else { throw FinanceError.missingRecord }
        var fields: [String: LogValue] = [:]
        let baseline = editingBaseline ?? bill
        if title != baseline.title { fields["title"] = .string(title) }
        if category != baseline.category { fields["category"] = .string(category) }
        try financeWrite(id, type: .recurringBill, action: .patch, fields: fields)
    }
    @discardableResult func reviseBillDefaults(_ id: UUID, amount: FinanceAmount? = nil, payment: FinancePayment? = nil) throws -> UUID {
        guard let bill = snapshot.finance.bills[id], bill.deletedAt == nil, amount != nil || payment != nil else { throw FinanceError.missingRecord }
        let next = FinanceMonth(dateProvider.now(), timeZone: bill.timeZoneIdentifier).next, revisionId = UUID()
        var fields: [String: LogValue] = ["billId": .id(id), "month": try FinanceProjector.value(next)]
        if let amount { fields["amount"] = try FinanceProjector.value(amount) }; if let payment { fields["payment"] = try FinanceProjector.value(payment) }
        try financeWrite(revisionId, type: .billRevision, action: .create, fields: fields); return revisionId
    }
    func setBillActive(_ id: UUID, active: Bool) throws {
        guard let bill = snapshot.finance.bills[id], bill.deletedAt == nil else { throw FinanceError.missingRecord }
        let now = dateProvider.now(), month = FinanceMonth(now, timeZone: bill.timeZoneIdentifier), day = CivilDate(now, timeZone: TimeZone(identifier: bill.timeZoneIdentifier)!)
        try financeWrite(UUID(), type: .billRevision, action: .create, fields: ["billId": .id(id), "month": try FinanceProjector.value(month), "active": .boolean(active), "activeFrom": try FinanceProjector.value(day)])
        try reconcileFinanceBills()
    }
    func overrideBillOccurrence(_ id: UUID, month: FinanceMonth, amount: FinanceAmount, payment: FinancePayment, editingBaseline: RecurringBillOccurrence? = nil) throws {
        guard let bill = snapshot.finance.bills[id], bill.deletedAt == nil else { throw FinanceError.missingRecord }
        let occurrence = try snapshot.finance.occurrence(bill, month: month)
        guard dateProvider.now() < (try FinancialCalendar.instant(occurrence.date, timeZone: bill.timeZoneIdentifier, minuteOfDay: bill.minuteOfDay)) else { throw FinanceError.invalidDate }
        let forecastId = StableID.make("finance-forecast:\(id.uuidString):\(month.iso)")
        var fields: [String: LogValue] = [:]
        if editingBaseline == nil || amount != editingBaseline?.amount { fields["amount"] = try FinanceProjector.value(amount) }
        if editingBaseline == nil || payment != editingBaseline?.payment { fields["payment"] = try FinanceProjector.value(payment) }
        guard !fields.isEmpty else { return }
        let exists = snapshot.finance.occurrenceOverrides[forecastId] != nil
        if !exists { fields["billId"] = .id(id); fields["month"] = try FinanceProjector.value(month) }
        try financeWrite(forecastId, type: .billOccurrence, action: exists ? .patch : .create, fields: fields)
    }
    func reconcileFinanceBills() throws {
        for bill in snapshot.finance.bills.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let current = FinanceMonth(min(dateProvider.now(), bill.deletedAt ?? .distantFuture), timeZone: bill.timeZoneIdentifier)
            var month = bill.startMonth
            while month <= current {
                let occurrence = try snapshot.finance.occurrence(bill, month: month)
                let due = try FinancialCalendar.instant(occurrence.date, timeZone: bill.timeZoneIdentifier, minuteOfDay: bill.minuteOfDay)
                if occurrence.isActive, due <= dateProvider.now(), snapshot.finance.expenses[occurrence.id] == nil {
                    try financeWrite(occurrence.id, type: .expense, action: .create, fields: ["title": .string(bill.title), "amount": try FinanceProjector.value(occurrence.amount), "payment": try FinanceProjector.value(occurrence.payment), "date": try FinanceProjector.value(occurrence.date), "zone": .string(bill.timeZoneIdentifier), "category": .string(bill.category), "notes": .string(""), "billId": .id(bill.id), "month": try FinanceProjector.value(month), "status": .string(ExpenseReviewStatus.provisional.rawValue)])
                }
                month = month.next
            }
        }
    }
    func setFinanceSettings(owner: UUID?, startDay: Int, timeZone: String, salaryDay: Int?, plannedDepositDay: Int?, editingBaseline: FinanceSettings? = nil) throws {
        guard owner == nil || owner == identity.descriptor.userId else { throw FinanceError.invalidRecord }
        let id = StableID.make("finance-settings:" + (owner?.uuidString ?? "shared"))
        let exists = snapshot.finance.settings[id] != nil
        let baseline = editingBaseline ?? snapshot.finance.settings[id]
        var fields: [String: LogValue] = [:]
        if baseline?.cycleStartDay != startDay { fields["day"] = .integer(startDay) }
        if baseline?.timeZoneIdentifier != timeZone { fields["zone"] = .string(timeZone) }
        if baseline?.salaryDay != salaryDay { fields["salaryDay"] = salaryDay.map(LogValue.integer) ?? .null }
        if baseline?.plannedDepositDay != plannedDepositDay { fields["depositDay"] = plannedDepositDay.map(LogValue.integer) ?? .null }
        guard !fields.isEmpty else { return }
        if !exists && !fields.isEmpty { fields = ["ownerId": .id(owner), "day": .integer(startDay), "zone": .string(timeZone), "salaryDay": salaryDay.map(LogValue.integer) ?? .null, "depositDay": plannedDepositDay.map(LogValue.integer) ?? .null] }
        try financeWrite(id, type: .financeSettings, action: exists ? .patch : .create, fields: fields)
    }
    var ownPrivatePaymentMethods: [PaymentMethodProfile] {
        _ = changeNumber
        return ((try? repository.load([PaymentMethodProfile].self, key: "private-payment-methods")) ?? []).filter { $0.ownerId == identity.descriptor.userId && $0.deletedAt == nil }
    }
    var visiblePaymentMethods: [PaymentMethodProfile] {
        (ownPrivatePaymentMethods + snapshot.finance.paymentMethods.values.filter { entry in entry.deletedAt == nil && entry.isShared && !ownPrivatePaymentMethods.contains(where: { card in card.id == entry.id }) }).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func savePaymentMethod(_ item: PaymentMethodProfile) throws {
        guard item.ownerId == identity.descriptor.userId, context.members.contains(item.holderId), item.isValid else { throw FinanceError.invalidCard }
        guard snapshot.finance.paymentMethods[item.id].map({ $0.ownerId == item.ownerId }) ?? true else { throw FinanceError.invalidCard }
        var local = (try repository.load([PaymentMethodProfile].self, key: "private-payment-methods")) ?? []
        local.removeAll { $0.id == item.id }
        if item.isShared {
            let exists = snapshot.finance.paymentMethods[item.id] != nil
            guard !exists || snapshot.finance.paymentMethods[item.id]?.deletedAt == nil else { throw FinanceError.invalidCard }
            try financeWrite(item.id, type: .paymentMethod, action: exists ? .patch : .create, fields: ["ownerId": .id(item.ownerId), "card": try FinanceProjector.value(item), "shared": .boolean(true)])
        } else {
            local.append(item)
            if let shared = snapshot.finance.paymentMethods[item.id], shared.deletedAt == nil && shared.isShared { try financeWrite(item.id, type: .paymentMethod, action: .patch, fields: ["shared": .boolean(false)]) }
        }
        try repository.save(local, key: "private-payment-methods")
        localFinanceDidChange()
    }
    func deletePaymentMethod(_ id: UUID) throws {
        var local = (try repository.load([PaymentMethodProfile].self, key: "private-payment-methods")) ?? []
        guard local.contains(where: { $0.id == id && $0.ownerId == identity.descriptor.userId }) || snapshot.finance.paymentMethods[id]?.ownerId == identity.descriptor.userId else { throw FinanceError.invalidCard }
        local.removeAll { $0.id == id }; try repository.save(local, key: "private-payment-methods")
        if let shared = snapshot.finance.paymentMethods[id], shared.ownerId == identity.descriptor.userId, shared.deletedAt == nil { try deleteFinance(id, type: .paymentMethod) }
        localFinanceDidChange()
    }
    func financialReviewState() throws -> LocalFinancialReviewState { try repository.load(LocalFinancialReviewState.self, key: "financial-review-state") ?? .init() }
    func saveFinancialReviewState(_ value: LocalFinancialReviewState) throws { try repository.save(value, key: "financial-review-state") }
}
