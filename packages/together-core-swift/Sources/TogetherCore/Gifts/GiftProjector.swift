import Foundation

enum GiftProjector {
    static func apply(_ operations: [SyncOperation], context: ReplicaContext, snapshot: inout DomainSnapshot,audit:ProjectionAudit?=nil) {
        let creator = context.spaceCreator
        var zone = context.sharedTimeZone
        for op in operations where op.entityType == .sharedSpace {
            guard op.operationType == .create, op.entityId == context.spaceId, op.actorId == creator.userId,
                  let value = op.payload["sharedTimeZoneIdentifier"]?.string, TimeZone(identifier: value) != nil else {
                OperationProjector.conflict(op, Copy.text("copy.error.250dc8567eab"), into: &snapshot); continue
            }
            if snapshot.space == nil {
                zone = value
                snapshot.space = SharedSpace(id: context.spaceId, memberIds: Array(context.members).sorted { $0.uuidString < $1.uuidString }, timeZoneIdentifier: zone)
            }
        }
        for op in operations where op.entityType == .mediaAsset {
            let p = op.payload
            guard op.operationType == .create, OperationProjector.spaceValid(p, context: context),
                  p["ownerId"]?.uuid == op.actorId,
                  let type = p["mediaType"]?.string.flatMap(MediaType.init(rawValue:)),
                  let filename = p["originalFilename"]?.string, filename.count <= 255,
                  let ext = p["fileExtension"]?.string, MediaStore.extensions.contains(ext),
                  let hash = p["sha256"]?.string, hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let bytes = p["byteCount"]?.integer, bytes > 0 else {
                OperationProjector.conflict(op, Copy.text("copy.error.d6baa26d4409"), into: &snapshot); continue
            }
            let asset = MediaAsset(assetId: op.entityId, spaceId: context.spaceId, ownerId: op.actorId, mediaType: type, originalFilename: filename, fileExtension: ext, sha256: hash, byteCount: Int64(bytes), createdAt: op.createdAt)
            if let prior = snapshot.mediaAssets[op.entityId], prior != asset {
                OperationProjector.conflict(op, Copy.text("copy.error.ab36ada08e6f"), into: &snapshot)
            } else { snapshot.mediaAssets[op.entityId] = asset }
        }
        var slots: [String: UUID] = [:]
        for op in operations where op.entityType == .loveGift && op.operationType == .create {
            let before=audit.map{_ in ProjectionAudit.fields(op.entityType,id:op.entityId,in:snapshot)}
            defer{if let before{audit?.record(op,before:before,after:ProjectionAudit.fields(op.entityType,id:op.entityId,in:snapshot))}}
            let p = op.payload
            let text = p["textContent"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let audio = p["audioAssetId"]?.uuid, photo = p["photoAssetId"]?.uuid
            guard context.peer != nil, p["spaceId"]?.uuid == context.spaceId,
                  p["senderId"]?.uuid == op.actorId, let recipient = p["recipientId"]?.uuid,
                  context.members.contains(recipient), recipient != op.actorId,
                  let sentAt = p["sentAt"]?.date,
                  let day = p["sentDayKey"]?.string, CivilDate(iso: day)?.iso == day,
                  p["sharedTimeZoneIdentifier"]?.string == zone,
                  (try? GiftCalendar.dayKey(at: sentAt, timeZoneIdentifier: zone)) == day,
                  (text?.count ?? 0) <= LoveGiftDraft.maximumCharacters, (text?.utf8.count ?? 0) <= 16_000,
                  !(text ?? "").isEmpty || audio != nil || photo != nil,
                  validAsset(audio, type: .audio, owner: op.actorId, snapshot: snapshot),
                  validAsset(photo, type: .photo, owner: op.actorId, snapshot: snapshot),
                  optionalIDValid(p["audioAssetId"]), optionalIDValid(p["photoAssetId"]), optionalIDValid(p["replyToGiftId"]) else {
                OperationProjector.conflict(op, Copy.text("copy.error.1c7c0658a09a"), into: &snapshot); continue
            }
            let slot = GiftCalendar.slot(space: context.spaceId, sender: op.actorId, day: day)
            if snapshot.gifts[op.entityId] != nil {
                OperationProjector.conflict(op, Copy.text("copy.error.0382006d422c"), into: &snapshot); continue
            }
            let effective = slots[slot] == nil
            if effective { slots[slot] = op.entityId }
            else { OperationProjector.conflict(op, Copy.text("copy.error.eeddcecb3dd8"), into: &snapshot) }
            snapshot.gifts[op.entityId] = DailyLoveGift(giftId: op.entityId, spaceId: context.spaceId, senderId: op.actorId, recipientId: recipient, textContent: text?.isEmpty == false ? text : nil, audioAssetId: audio, photoAssetId: photo, replyToGiftId: p["replyToGiftId"]?.uuid, sentAt: sentAt, sentDayKey: day, sharedTimeZoneIdentifier: zone, deletedAt: nil, creationOperationId: op.operationId, isEffective: effective)
        }
        // Apply tombstones after creations, including deletes that arrived before creation.
        for op in operations where op.entityType == .loveGift && op.operationType != .create {
            let before=audit.map{_ in ProjectionAudit.fields(op.entityType,id:op.entityId,in:snapshot)}
            defer{if let before{audit?.record(op,before:before,after:ProjectionAudit.fields(op.entityType,id:op.entityId,in:snapshot))}}
            guard op.operationType == .delete, var gift = snapshot.gifts[op.entityId], gift.senderId == op.actorId else {
                OperationProjector.conflict(op, Copy.text("copy.error.77bc37901b5c"), into: &snapshot); continue
            }
            gift.deletedAt = gift.deletedAt ?? op.createdAt; snapshot.gifts[op.entityId] = gift
        }
        for (id, var profile) in snapshot.profiles {
            if let assetId = profile.avatarAssetId, let asset = snapshot.mediaAssets[assetId], asset.ownerId != id || asset.mediaType != .avatar {
                profile.avatarAssetId = nil; snapshot.profiles[id] = profile
            }
        }
    }
    private static func optionalIDValid(_ value: LogValue?) -> Bool { value == nil || value == .null || value?.uuid != nil }
    private static func validAsset(_ id: UUID?, type: MediaType, owner: UUID, snapshot: DomainSnapshot) -> Bool {
        guard let id else { return true }
        return snapshot.mediaAssets[id].map { $0.mediaType == type && $0.ownerId == owner } ?? false
    }
}
