import Foundation

public enum OperationProjector {
    public static func replay(_ signed: [SignedOperation], context: ReplicaContext) -> DomainSnapshot {
        var result = DomainSnapshot()
        let operations = signed.filter { item in
            guard let descriptor = context.devices[item.operation.deviceId], item.verified(by: descriptor) else {
                result.conflicts.append(DomainConflict(operationId: item.id, entityId: item.operation.entityId, reason: "操作签名或用户身份不匹配")); return false
            }
            return true
        }.map(\.operation).sorted { $0.order < $1.order }
        var drafts: [UUID: EntityDraft] = [:]
        for operation in operations where operation.operationType == .create {
            guard [.profile, .task, .recurrenceRule].contains(operation.entityType), drafts[operation.entityId] == nil else { continue }
            if creationValid(operation, context: context) { drafts[operation.entityId] = EntityDraft(operation) }
            else { conflict(operation, Copy.text("copy.error.90a1871c6212"), into: &result) }
        }
        for operation in operations {
            guard var draft = drafts[operation.entityId], draft.base.entityType == operation.entityType else { continue }
            let allowed: Bool
            switch operation.entityType {
            case .profile: allowed = operation.actorId == operation.entityId
            case .task, .recurrenceRule: allowed = context.members.contains(operation.actorId)
            default: allowed = false
            }
            guard allowed else { conflict(operation, Copy.text("copy.error.3d3054c36e6d"), into: &result); continue }
            if operation.operationType == .create { continue }
            if operation.entityType == .task, operation.operationType == .delete {
                draft.tombstone = draft.tombstone ?? operation.createdAt
            } else if operation.entityType == .task, [.completeTask, .reopenTask].contains(operation.operationType) {
                draft.assign("status", .string(operation.operationType == .completeTask ? "completed" : "pending"), operation)
                draft.assign("completedAt", operation.operationType == .completeTask ? .date(operation.createdAt) : .null, operation)
            } else if operation.operationType == .patch {
                guard patchValid(operation, context: context) else { conflict(operation, Copy.text("copy.error.bc0dfeab7ee4"), into: &result); continue }
                for (key, value) in operation.payload { draft.assign(key, value, operation) }
            } else { conflict(operation, Copy.text("copy.error.7187d4f67320"), into: &result); continue }
            drafts[operation.entityId] = draft
        }
        for (id, draft) in drafts {
            let f = draft.values
            switch draft.base.entityType {
            case .profile:
                result.profiles[id] = UserProfile(userId: id, deviceId: draft.base.deviceId, displayName: f["displayName"]!.string!, relationshipLabel: f["relationshipLabel"]?.string ?? "unknown", avatarData: f["avatarData"]?.bytes, updatedAt: draft.lastDate, avatarAssetId: f["avatarAssetId"]?.uuid, avatarCrop: f["avatarCrop"]?.bytes.flatMap { try? CanonicalJSON.decode(AvatarCrop.self, from: $0) })
            case .task:
                result.tasks[id] = TodoTask(taskId: id, spaceId: context.spaceId, title: f["title"]!.string!, notes: f["notes"]?.string ?? "", createdBy: draft.base.actorId, assignedTo: f["assignedTo"]?.uuid, dueAt: f["dueAt"]?.date, status: TaskStatus(rawValue: f["status"]?.string ?? "pending") ?? .pending, createdAt: draft.base.createdAt, updatedAt: draft.lastDate, completedAt: f["completedAt"]?.date, recurrenceRuleId: f["recurrenceRuleId"]?.uuid, deletedAt: draft.tombstone, occurrenceIndex: f["occurrenceIndex"]?.integer ?? 0, spawnedFromId: f["spawnedFromId"]?.uuid, availableAt: f["availableAt"]?.date, nextAt: f["nextAt"]?.date)
            case .recurrenceRule:
                result.rules[id] = RecurrenceRule(id: id, spaceId: context.spaceId, mode: RecurrenceMode(rawValue: f["mode"]!.string!)!, unit: RecurrenceUnit(rawValue: f["unit"]!.string!)!, interval: f["interval"]!.integer!, anchorAt: f["anchorAt"]!.date!, timeZoneIdentifier: f["timeZoneIdentifier"]!.string!, createdBy: draft.base.actorId, updatedAt: draft.lastDate)
            default: break
            }
        }
        WishProjector.apply(operations, context: context, snapshot: &result)
        GiftProjector.apply(operations, context: context, snapshot: &result)
        result.conflicts = Array(Dictionary(result.conflicts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values).sorted { $0.id.uuidString < $1.id.uuidString }
        return result
    }

    static func conflict(_ operation: SyncOperation, _ reason: String, into snapshot: inout DomainSnapshot) {
        snapshot.conflicts.append(DomainConflict(operationId: operation.operationId, entityId: operation.entityId, reason: reason))
    }
    static func spaceValid(_ payload: [String: LogValue], context: ReplicaContext) -> Bool { payload["spaceId"]?.uuid.map { context.validSpaceIds.contains($0) } ?? false }
    static func shortText(_ value: LogValue?, max: Int, nonempty: Bool = false) -> Bool {
        guard let text = value?.string, text.count <= max else { return false }
        return !nonempty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func creationValid(_ op: SyncOperation, context: ReplicaContext) -> Bool {
        let p = op.payload
        switch op.entityType {
        case .profile:
            return op.entityId == op.actorId && p["deviceId"]?.uuid == op.deviceId && shortText(p["displayName"], max: 80, nonempty: true) && (p["avatarData"]?.bytes?.count ?? 0) <= 131_072
        case .task:
            return spaceValid(p, context: context) && p["createdBy"]?.uuid == op.actorId && shortText(p["title"], max: 200, nonempty: true)
                && shortText(p["notes"] ?? .string(""), max: 10_000) && validTaskValues(p, context: context)
        case .recurrenceRule:
            return spaceValid(p, context: context) && p["createdBy"]?.uuid == op.actorId && ruleValuesValid(p, requireAll: true)
        default: return false
        }
    }
    private static func patchValid(_ op: SyncOperation, context: ReplicaContext) -> Bool {
        let p = op.payload
        switch op.entityType {
        case .profile:
            guard Set(p.keys).isSubset(of: ["displayName", "relationshipLabel", "avatarData", "avatarAssetId", "avatarCrop"]) else { return false }
            if let v = p["displayName"], !shortText(v, max: 80, nonempty: true) { return false }
            if let v = p["relationshipLabel"], !shortText(v, max: 40) { return false }
            if let v = p["avatarData"], v != .null && (v.bytes == nil || v.bytes!.count > 131_072) { return false }
            if let v = p["avatarAssetId"], v != .null && v.uuid == nil { return false }
            if let v = p["avatarCrop"], v != .null {
                guard let data = v.bytes, data.count < 1024, let crop = try? CanonicalJSON.decode(AvatarCrop.self, from: data), crop.isValid else { return false }
            }
            return true
        case .task:
            guard Set(p.keys).isSubset(of: ["title", "notes", "assignedTo", "dueAt", "recurrenceRuleId", "nextAt", "availableAt"]) else { return false }
            if let title = p["title"], !shortText(title, max: 200, nonempty: true) { return false }
            if let notes = p["notes"], !shortText(notes, max: 10_000) { return false }
            return validTaskValues(p, context: context)
        case .recurrenceRule:
            return Set(p.keys).isSubset(of: ["mode", "unit", "interval", "anchorAt", "timeZoneIdentifier"]) && ruleValuesValid(p, requireAll: false)
        default: return false
        }
    }
    private static func validTaskValues(_ p: [String: LogValue], context: ReplicaContext) -> Bool {
        if let assignee = p["assignedTo"], assignee != .null && (assignee.uuid == nil || !context.members.contains(assignee.uuid!)) { return false }
        for key in ["dueAt", "nextAt", "availableAt"] {
            if let v = p[key], v != .null && (v.date == nil || !v.date!.timeIntervalSince1970.isFinite) { return false }
        }
        if let rule = p["recurrenceRuleId"], rule != .null && rule.uuid == nil { return false }
        if let index = p["occurrenceIndex"], index.integer == nil || !(0...1_000_000).contains(index.integer!) { return false }
        return true
    }
    private static func ruleValuesValid(_ p: [String: LogValue], requireAll: Bool) -> Bool {
        if requireAll && !Set(["mode", "unit", "interval", "anchorAt", "timeZoneIdentifier"]).isSubset(of: Set(p.keys)) { return false }
        if let v = p["mode"], v.string.flatMap(RecurrenceMode.init(rawValue:)) == nil { return false }
        if let v = p["unit"], v.string.flatMap(RecurrenceUnit.init(rawValue:)) == nil { return false }
        if let v = p["interval"], v.integer == nil || !(1...1000).contains(v.integer!) { return false }
        if let v = p["anchorAt"], v.date == nil || !v.date!.timeIntervalSince1970.isFinite { return false }
        if let v = p["timeZoneIdentifier"], v.string.flatMap(TimeZone.init(identifier:)) == nil { return false }
        return true
    }
}

private struct EntityDraft {
    let base: SyncOperation
    var fields: [String: (LogValue, OperationOrder)]
    var lastOrder: OperationOrder
    var lastDate: Date
    var tombstone: Date?
    init(_ operation: SyncOperation) {
        base = operation; fields = operation.payload.mapValues { ($0, operation.order) }
        lastOrder = operation.order; lastDate = operation.createdAt
    }
    var values: [String: LogValue] { fields.mapValues { $0.0 } }
    mutating func assign(_ key: String, _ value: LogValue, _ operation: SyncOperation) {
        if fields[key].map({ $0.1 < operation.order }) ?? true { fields[key] = (value, operation.order) }
        if lastOrder < operation.order { lastOrder = operation.order; lastDate = operation.createdAt }
    }
}
