import Foundation

enum FinanceProjector {
    static let types: Set<EntityType> = [.reserveEntry, .dateEvent, .expense, .recurringBill, .billRevision, .billOccurrence, .financeSettings, .paymentMethod]
    static func apply(_ operations: [SyncOperation], context: ReplicaContext, snapshot: inout DomainSnapshot,audit:ProjectionAudit?=nil) {
        let ops = operations.filter { types.contains($0.entityType) }
        var drafts: [UUID: FinanceDraft] = [:]
        for op in ops where op.operationType == .create {
            guard OperationProjector.spaceValid(op.payload, context: context), op.payload["createdBy"]?.uuid == op.actorId,
                  validValues(op.payload, type: op.entityType, context: context, actor: op.actorId, creating: true) else {
                OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue
            }
            let before=drafts[op.entityId]?.values ?? [:]
            defer{audit?.record(op,before:before,after:drafts[op.entityId]?.values ?? [:])}
            if var prior = drafts[op.entityId] {
                // Deterministic settings/forecast/opening IDs can be initialized
                // independently while offline. Merge their mutable fields with
                // the same Lamport ordering as later patches, never double count.
                let keys: Set<String>
                if op.entityType == .financeSettings, prior.base.entityType == .financeSettings, op.payload["ownerId"] == prior.values["ownerId"], op.entityId == StableID.make("finance-settings:" + (op.payload["ownerId"]?.uuid?.uuidString ?? "shared")) {
                    keys = ["day", "zone", "salaryDay", "depositDay"]
                } else if op.entityType == .reserveEntry, prior.base.entityType == .reserveEntry, op.entityId == StableID.make("finance-reserves-opening"), (try? decode(ReserveEntryKind.self, op.payload["kind"])) == .opening, (try? decode(ReserveEntryKind.self, prior.values["kind"])) == .opening {
                    keys = ["amount", "date", "notes", "depositedBy"]
                } else if op.entityType == .billOccurrence, prior.base.entityType == .billOccurrence, op.payload["billId"] == prior.values["billId"], op.payload["month"] == prior.values["month"] {
                    keys = ["amount", "payment"]
                } else { continue }
                for key in keys { if let value = op.payload[key] { prior.assign(key, value, op) } }
                drafts[op.entityId] = prior
            } else { drafts[op.entityId] = FinanceDraft(op) }
        }
        for op in ops where op.operationType != .create {
            guard var draft = drafts[op.entityId], draft.base.entityType == op.entityType else { continue }
            var before=draft.values;before["deletedAt"] = .optionalDate(draft.deletedAt)
            defer{var after=draft.values;after["deletedAt"] = .optionalDate(draft.deletedAt);audit?.record(op,before:before,after:after)}
            guard op.entityType != .billRevision else { OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue }
            let owner = draft.values["ownerId"]?.uuid
            guard context.members.contains(op.actorId), (op.entityType != .paymentMethod || owner == op.actorId),
                  (op.entityType != .financeSettings || owner == nil || owner == op.actorId) else {
                OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue
            }
            if op.operationType == .delete { draft.deletedAt = draft.deletedAt ?? op.createdAt }
            else if op.operationType == .patch && validValues(op.payload, type: op.entityType, context: context, actor: op.actorId, creating: false) {
                if let owner = op.payload["ownerId"], owner != draft.base.payload["ownerId"] { OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue }
                var candidate = draft
                for (key, value) in op.payload { candidate.assign(key, value, op) }
                guard validValues(candidate.values, type: op.entityType, context: context, actor: draft.base.actorId, creating: true) else { OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue }
                draft = candidate
            } else { OperationProjector.conflict(op, Copy.text("finance.error.invalidRecord"), into: &snapshot); continue }
            drafts[op.entityId] = draft
        }
        var finance = FinanceSnapshot()
        for (id, d) in drafts {
            let f = d.values
            do {
                switch d.base.entityType {
                case .reserveEntry:
                    let kind = try decode(ReserveEntryKind.self, f["kind"])
                    let amount = try decode(FinanceAmount.self, f["amount"])
                    guard kind != .opening || id == StableID.make("finance-reserves-opening") else { throw FinanceError.invalidRecord }
                    finance.reserves[id] = .init(id: id, spaceId: context.spaceId, depositedBy: f["depositedBy"]!.uuid!, kind: kind, amount: amount, depositDate: try decode(CivilDate.self, f["date"]), createdAt: d.base.createdAt, notes: f["notes"]?.string ?? "", deletedAt: d.deletedAt)
                case .dateEvent:
                    finance.dateEvents[id] = .init(id: id, spaceId: context.spaceId, title: f["title"]!.string!, date: try decode(CivilDate.self, f["date"]), notes: f["notes"]?.string ?? "", createdBy: d.base.actorId, createdAt: d.base.createdAt, deletedAt: d.deletedAt)
                case .recurringBill:
                    finance.bills[id] = .init(id: id, spaceId: context.spaceId, title: f["title"]!.string!, defaultAmount: try decode(FinanceAmount.self, f["amount"]), defaultPayment: try decode(FinancePayment.self, f["payment"]), recurrenceDay: f["day"]!.integer!, timeZoneIdentifier: f["zone"]!.string!, minuteOfDay: f["minute"]?.integer, startMonth: try decode(FinanceMonth.self, f["startMonth"]), category: f["category"]?.string ?? "", createdBy: d.base.actorId, createdAt: d.base.createdAt, deletedAt: d.deletedAt)
                case .billRevision:
                    guard d.deletedAt == nil else { continue }
                    finance.revisions[id] = .init(id: id, billId: f["billId"]!.uuid!, effectiveMonth: try decode(FinanceMonth.self, f["month"]), amount: try optionalDecode(FinanceAmount.self, f["amount"]), payment: try optionalDecode(FinancePayment.self, f["payment"]), active: boolean(f["active"]), activeFromDay: try optionalDecode(CivilDate.self, f["activeFrom"]), createdBy: d.base.actorId, createdAt: d.base.createdAt, order: .init(d.lastOrder))
                case .billOccurrence:
                    guard d.deletedAt == nil else { continue }
                    let month = try decode(FinanceMonth.self, f["month"]), bill = f["billId"]!.uuid!
                    guard id == StableID.make("finance-forecast:\(bill.uuidString):\(month.iso)") else { throw FinanceError.invalidRecord }
                    finance.occurrenceOverrides[id] = .init(id: id, billId: bill, month: month, amount: try optionalDecode(FinanceAmount.self, f["amount"]), payment: try optionalDecode(FinancePayment.self, f["payment"]))
                case .financeSettings:
                    guard d.deletedAt == nil, id == StableID.make("finance-settings:" + (f["ownerId"]?.uuid?.uuidString ?? "shared")) else { throw FinanceError.invalidRecord }
                    finance.settings[id] = .init(id: id, ownerId: f["ownerId"]?.uuid, cycleStartDay: f["day"]!.integer!, timeZoneIdentifier: f["zone"]!.string!, salaryDay: f["salaryDay"]?.integer, plannedDepositDay: f["depositDay"]?.integer, updatedAt: d.lastDate)
                case .paymentMethod:
                    let item = try decode(PaymentMethodProfile.self, f["card"])
                    guard item.id == id, item.ownerId == d.base.actorId, item.isShared, item.isValid else { throw FinanceError.invalidCard }
                    var value = item; value.isShared = boolean(f["shared"]) ?? item.isShared; value.deletedAt = d.deletedAt; finance.paymentMethods[id] = value
                default: break
                }
            } catch { OperationProjector.conflict(d.base, Copy.text("finance.error.invalidRecord"), into: &snapshot) }
        }
        // Revisions affect defaults from the next natural month, never the financial cycle.
        finance.revisions = finance.revisions.filter { id, revision in
            guard let bill = finance.bills[revision.billId] else { return false }
            if revision.amount != nil || revision.payment != nil {
                guard revision.effectiveMonth >= FinanceMonth(revision.createdAt, timeZone: bill.timeZoneIdentifier).next else {
                    if let draft = drafts[id] { OperationProjector.conflict(draft.base, Copy.text("finance.error.invalidRecord"), into: &snapshot) }
                    return false
                }
            }
            return true
        }
        for (id, d) in drafts where d.base.entityType == .expense {
            let f = d.values
            do {
                var value = ExpenseEntry(id: id, spaceId: context.spaceId, title: f["title"]!.string!, amount: try decode(FinanceAmount.self, f["amount"]), payment: try decode(FinancePayment.self, f["payment"]), occurredOn: try decode(CivilDate.self, f["date"]), timeZoneIdentifier: f["zone"]!.string!, category: f["category"]?.string ?? "", notes: f["notes"]?.string ?? "", dateEventId: f["eventId"]?.uuid, recurringBillId: f["billId"]?.uuid, occurrenceMonth: try optionalDecode(FinanceMonth.self, f["month"]), status: ExpenseReviewStatus(rawValue: f["status"]!.string!)!, amountOverridden: boolean(f["amountOverridden"]) ?? false, paymentOverridden: boolean(f["paymentOverridden"]) ?? false, createdBy: d.base.actorId, createdAt: d.base.createdAt, deletedAt: d.deletedAt)
                if let eventId = value.dateEventId, finance.dateEvents[eventId] == nil { throw FinanceError.invalidRecord }
                if let billId = value.recurringBillId, let month = value.occurrenceMonth {
                    guard let bill = finance.bills[billId], id == StableID.make("finance-bill:\(billId.uuidString):\(month.iso)") else { throw FinanceError.invalidRecord }
                    let occurrence = try finance.occurrence(bill, month: month)
                    guard value.occurredOn == occurrence.date, value.timeZoneIdentifier == bill.timeZoneIdentifier else { throw FinanceError.invalidRecord }
                    if !value.amountOverridden { value.amount = occurrence.amount }
                    if !value.paymentOverridden { value.payment = occurrence.payment }
                    if !occurrence.isActive && value.status == .provisional && !value.amountOverridden && !value.paymentOverridden { value.status = .skipped }
                } else if value.recurringBillId != nil || value.occurrenceMonth != nil { throw FinanceError.invalidRecord }
                finance.expenses[id] = value
            } catch { OperationProjector.conflict(d.base, Copy.text("finance.error.invalidRecord"), into: &snapshot) }
        }
        snapshot.finance = finance
    }
    static func value<T: Encodable>(_ value: T) throws -> LogValue { .data(try CanonicalJSON.encode(value)) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: LogValue?) throws -> T {
        guard let data = value?.bytes, data.count <= 16_384 else { throw FinanceError.invalidRecord }
        return try CanonicalJSON.decode(type, from: data)
    }
    static func optionalDecode<T: Decodable>(_ type: T.Type, _ value: LogValue?) throws -> T? { value == nil || value == .null ? nil : try decode(type, value) }
    static func boolean(_ value: LogValue?) -> Bool? { if case let .boolean(result) = value { return result }; return nil }
    private static func validValues(_ p: [String: LogValue], type: EntityType, context: ReplicaContext, actor: UUID, creating: Bool) -> Bool {
        let common: Set<String> = creating ? ["spaceId", "createdBy"] : []
        let allowed: Set<String>
        switch type {
        case .reserveEntry: allowed = ["kind", "depositedBy", "amount", "date", "notes"]
        case .dateEvent: allowed = ["title", "date", "notes"]
        case .expense: allowed = ["title", "amount", "payment", "date", "zone", "category", "notes", "eventId", "billId", "month", "status", "amountOverridden", "paymentOverridden"]
        case .recurringBill: allowed = creating ? ["title", "amount", "payment", "day", "zone", "minute", "startMonth", "category"] : ["title", "category"]
        case .billRevision: allowed = creating ? ["billId", "month", "amount", "payment", "active", "activeFrom"] : []
        case .billOccurrence: allowed = ["billId", "month", "amount", "payment"]
        case .financeSettings: allowed = ["ownerId", "day", "zone", "salaryDay", "depositDay"]
        case .paymentMethod: allowed = ["ownerId", "card", "shared"]
        default: return false
        }
        guard Set(p.keys).isSubset(of: common.union(allowed)) else { return false }
        if let value = p["kind"], (try? decode(ReserveEntryKind.self, value)) == nil { return false }
        for key in ["title", "category", "notes"] {
            if let value = p[key], !OperationProjector.shortText(value, max: key == "notes" ? 2000 : 120, nonempty: key == "title") { return false }
        }
        if let value = p["amount"], value != .null {
            guard let amount = try? decode(FinanceAmount.self, value), amount.isValid else { return false }
            if type != .reserveEntry && (amount.originalMinor <= 0 || amount.finalCNYMinor < 0) { return false }
            if type == .reserveEntry && p["kind"] != nil, let kind = try? decode(ReserveEntryKind.self, p["kind"]), kind == .deposit, amount.originalMinor <= 0 || amount.finalCNYMinor < 0 { return false }
        }
        if let value = p["payment"], value != .null, (try? decode(FinancePayment.self, value).valid(members: context.members)) != true { return false }
        if let value = p["date"], (try? decode(CivilDate.self, value).isValid) != true { return false }
        for key in ["month", "startMonth"] { if let value = p[key], value != .null { guard let month = try? decode(FinanceMonth.self, value), FinanceMonth(iso: month.iso) != nil else { return false } } }
        for key in ["day", "salaryDay", "depositDay"] { if let value = p[key], value != .null, value.integer.map({ (1...31).contains($0) }) != true { return false } }
        if let value = p["minute"], value != .null, value.integer.map({ (0..<1440).contains($0) }) != true { return false }
        if let value = p["zone"], value.string.flatMap(TimeZone.init(identifier:)) == nil { return false }
        for key in ["depositedBy", "ownerId"] { if let value = p[key], value != .null, value.uuid.map(context.members.contains) != true { return false } }
        for key in ["billId", "eventId"] { if let value = p[key], value != .null, value.uuid == nil { return false } }
        if let value = p["activeFrom"], value != .null, (try? decode(CivilDate.self, value).isValid) != true { return false }
        for key in ["active", "amountOverridden", "paymentOverridden", "shared"] { if let value = p[key], value != .null, boolean(value) == nil { return false } }
        if let value = p["status"], value.string.flatMap(ExpenseReviewStatus.init(rawValue:)) == nil { return false }
        if let value = p["card"] { guard let card = try? decode(PaymentMethodProfile.self, value), card.ownerId == actor, context.members.contains(card.holderId), card.isShared, card.isValid else { return false } }
        if creating {
            let required: Set<String>
            switch type {
            case .reserveEntry: required = ["kind", "depositedBy", "amount", "date"]
            case .dateEvent: required = ["title", "date"]
            case .expense: required = ["title", "amount", "payment", "date", "zone", "status"]
            case .recurringBill: required = ["title", "amount", "payment", "day", "zone", "startMonth"]
            case .billRevision, .billOccurrence: required = ["billId", "month"]
            case .financeSettings: required = ["day", "zone"]
            case .paymentMethod: required = ["ownerId", "card"]
            default: return false
            }
            guard required.isSubset(of: Set(p.keys)) else { return false }
            if type == .reserveEntry && (try? decode(ReserveEntryKind.self, p["kind"])) == nil { return false }
            if type == .financeSettings, let owner = p["ownerId"]?.uuid, owner != actor { return false }
            if type == .paymentMethod && p["ownerId"]?.uuid != actor { return false }
            if type == .billRevision {
                guard p["amount"] != nil || p["payment"] != nil || boolean(p["active"]) != nil else { return false }
                if p["active"] != nil && (try? decode(CivilDate.self, p["activeFrom"]).isValid) != true { return false }
            }
        }
        return true
    }
}
private struct FinanceDraft {
    let base: SyncOperation
    var fields: [String: (LogValue, OperationOrder)]
    var lastOrder: OperationOrder; var lastDate: Date; var deletedAt: Date?
    init(_ op: SyncOperation) { base = op; fields = op.payload.mapValues { ($0, op.order) }; lastOrder = op.order; lastDate = op.createdAt }
    var values: [String: LogValue] { fields.mapValues { $0.0 } }
    mutating func assign(_ key: String, _ value: LogValue, _ op: SyncOperation) {
        if fields[key].map({ $0.1 < op.order }) ?? true { fields[key] = (value, op.order) }
        if lastOrder < op.order { lastOrder = op.order; lastDate = op.createdAt }
    }
}
