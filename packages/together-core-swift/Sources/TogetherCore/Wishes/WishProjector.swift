import Foundation

enum WishProjector {
    static func apply(_ operations: [SyncOperation], context: ReplicaContext, snapshot: inout DomainSnapshot) {
        for op in operations where op.entityType == .wishGrant && op.operationType == .create && snapshot.grants[op.entityId] == nil {
            let p = op.payload
            guard OperationProjector.spaceValid(p, context: context), p["createdBy"]?.uuid == op.actorId,
                  let fulfiller = p["fulfillerId"]?.uuid, let beneficiary = p["beneficiaryId"]?.uuid,
                  fulfiller != beneficiary, context.members.contains(fulfiller), context.members.contains(beneficiary),
                  let quantity = p["quantity"]?.integer, (1...10_000).contains(quantity),
                  let date = p["grantedOn"]?.string.flatMap(CivilDate.init(iso:)) else {
                OperationProjector.conflict(op, Copy.text("copy.error.37cd9c49b83e"), into: &snapshot); continue
            }
            snapshot.grants[op.entityId] = WishGrant(grantId: op.entityId, spaceId: context.spaceId, fulfillerId: fulfiller, beneficiaryId: beneficiary, quantity: quantity, grantedOn: date, createdAt: op.createdAt, createdBy: op.actorId, notes: p["notes"]?.string ?? "")
        }
        var totals = snapshot.grants.mapValues(\.quantity)
        var occupied: [UUID: Set<UUID>] = [:]
        var deferred: [UUID: [SyncOperation]] = [:]
        for op in operations {
            switch op.entityType {
            case .grantAdjustment:
                guard op.operationType == .create, let grantId = op.payload["grantId"]?.uuid,
                      let grant = snapshot.grants[grantId], grant.createdBy == op.actorId,
                      let delta = op.payload["delta"]?.integer, delta != 0, (-10_000...10_000).contains(delta),
                      OperationProjector.shortText(op.payload["notes"], max: 5000, nonempty: true) else {
                    OperationProjector.conflict(op, Copy.text("copy.error.258efd44ba1b"), into: &snapshot); continue
                }
                if snapshot.adjustments.contains(where: { $0.id == op.entityId }) { continue }
                let proposed = totals[grantId, default: grant.quantity] + delta
                let effective = proposed >= occupied[grantId, default: []].count && proposed >= 0
                snapshot.adjustments.append(GrantAdjustment(id: op.entityId, grantId: grantId, delta: delta, notes: op.payload["notes"]!.string!, createdBy: op.actorId, createdAt: op.createdAt, isEffective: effective))
                if effective { totals[grantId] = proposed }
                else { OperationProjector.conflict(op, Copy.text("copy.error.e318bd530064"), into: &snapshot) }
            case .wishItem:
                if op.operationType == .create {
                    guard snapshot.wishes[op.entityId] == nil else { continue }
                    guard let grantId = op.payload["grantId"]?.uuid, let grant = snapshot.grants[grantId], op.actorId == grant.beneficiaryId,
                          op.payload["createdBy"]?.uuid == op.actorId, OperationProjector.shortText(op.payload["title"], max: 200, nonempty: true),
                          OperationProjector.shortText(op.payload["description"] ?? .string(""), max: 10_000) else {
                        OperationProjector.conflict(op, Copy.text("copy.error.780d3e6eefe5"), into: &snapshot); continue
                    }
                    let valid = occupied[grantId, default: []].count < totals[grantId, default: 0]
                    snapshot.wishes[op.entityId] = WishItem(wishId: op.entityId, grantId: grantId, title: op.payload["title"]!.string!, description: op.payload["description"]?.string ?? "", beneficiaryId: grant.beneficiaryId, fulfillerId: grant.fulfillerId, createdBy: op.actorId, status: valid ? .open : .conflict, createdAt: op.createdAt, fulfilledAt: nil, conflictReason: valid ? nil : "超出本批愿望额度")
                    if valid { occupied[grantId, default: []].insert(op.entityId) }
                    else { OperationProjector.conflict(op, Copy.text("copy.error.6031747cf298"), into: &snapshot) }
                    for pending in deferred.removeValue(forKey: op.entityId) ?? [] { applyWishAction(pending, snapshot: &snapshot) }
                } else if snapshot.wishes[op.entityId] != nil { applyWishAction(op, snapshot: &snapshot) }
                else { deferred[op.entityId, default: []].append(op) }
            default: break
            }
        }
        for ops in deferred.values { for op in ops { OperationProjector.conflict(op, Copy.text("copy.error.8dea963dccc2"), into: &snapshot) } }
    }

    private static func applyWishAction(_ op: SyncOperation, snapshot: inout DomainSnapshot) {
        guard var wish = snapshot.wishes[op.entityId] else { return }
        guard wish.status != .conflict else { OperationProjector.conflict(op, Copy.text("copy.error.8e322a238953"), into: &snapshot); return }
        switch op.operationType {
        case .patch:
            guard op.actorId == wish.beneficiaryId, wish.status != .fulfilled,
                  Set(op.payload.keys).isSubset(of: ["title", "description"]) else { OperationProjector.conflict(op, Copy.text("copy.error.fd385fcd0bf8"), into: &snapshot); return }
            if let title = op.payload["title"] {
                guard OperationProjector.shortText(title, max: 200, nonempty: true) else { return }
                wish.title = title.string!
            }
            if let details = op.payload["description"] {
                guard OperationProjector.shortText(details, max: 10_000) else { return }
                wish.description = details.string!
            }
        case .requestFulfillment:
            guard op.actorId == wish.fulfillerId else { OperationProjector.conflict(op, Copy.text("copy.error.9f0b823c8528"), into: &snapshot); return }
            if wish.status != .fulfilled { wish.status = .completionRequested }
        case .confirmFulfillment:
            guard op.actorId == wish.beneficiaryId else { OperationProjector.conflict(op, Copy.text("copy.error.96926fae02a3"), into: &snapshot); return }
            if wish.status == .fulfilled { break }
            guard wish.status == .completionRequested else { OperationProjector.conflict(op, Copy.text("copy.error.25ca0067a317"), into: &snapshot); return }
            wish.status = .fulfilled; wish.fulfilledAt = op.createdAt
        case .rejectFulfillment:
            guard op.actorId == wish.beneficiaryId else { OperationProjector.conflict(op, Copy.text("copy.error.2cac0c2b75a0"), into: &snapshot); return }
            if wish.status != .fulfilled { wish.status = .open }
        default: OperationProjector.conflict(op, Copy.text("copy.error.f7fc8d38ad57"), into: &snapshot); return
        }
        snapshot.wishes[op.entityId] = wish
    }
}
