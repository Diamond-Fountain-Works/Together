import Foundation
import CryptoKit
import Observation

public struct RecurrenceDraft: Sendable {
    public var mode: RecurrenceMode
    public var unit: RecurrenceUnit
    public var interval: Int
    public var timeZoneIdentifier: String
    public init(mode: RecurrenceMode, unit: RecurrenceUnit = .day, interval: Int = 1, timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.mode = mode; self.unit = unit; self.interval = interval; self.timeZoneIdentifier = timeZoneIdentifier
    }
}
public struct ListenerSettings: Codable, Sendable {
    public var host: String
    public var port: UInt16
    public var enabled: Bool
    public init(host: String = "127.0.0.1", port: UInt16 = 58431, enabled: Bool = false) { self.host = host; self.port = port; self.enabled = enabled }
}
public enum TogetherError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(text) = self { text } else { nil } }
}

@MainActor @Observable public final class ReplicaEngine {
    public let identity: DeviceIdentity
    public let repository: TogetherRepository
    public let mediaStore: MediaStore
    public let enrollmentRoot: URL?
    @ObservationIgnored public let dateProvider: any DateProvider
    public private(set) var mediaProgress: [UUID: MediaProgress] = [:]
    public private(set) var stagedAssets: [UUID: MediaAsset] = [:]
    public private(set) var peer: PairedPeer?
    public private(set) var snapshot = DomainSnapshot()
    public private(set) var operations: [SignedOperation] = []
    public private(set) var changeNumber = 0
    @ObservationIgnored public var onOperationsChanged: (() -> Void)?
    @ObservationIgnored private var mediaDownloadSources:[UUID:UUID]=[:]
    @ObservationIgnored private var giftSourceDevices: [UUID: UUID] = [:]
    @ObservationIgnored private var presentationCache: [UUID: GiftPresentationState] = [:]
    @ObservationIgnored private var progressPublishedAt: [UUID: ContinuousClock.Instant] = [:]
    @ObservationIgnored var financeChangeCache: (operationCount: Int, members: Set<UUID>, limit: Int, changes: [FinanceChange])?
    @ObservationIgnored private var replicationContext: ReplicaContext?
    @ObservationIgnored private var activatingReplication = false
    public var context: ReplicaContext { replicationContext ?? ReplicaContext(local: identity.descriptor, peer: peer?.descriptor) }
    public var usesReplication4: Bool { replicationContext != nil }
    public var isCompletingPartnership: Bool { (try? repository.load(Bool.self, key: "partner4/pending")) == true && !usesReplication4 }
    public var ownProfile: UserProfile? { snapshot.profiles[identity.descriptor.userId] }
    public var partnerProfile: UserProfile? { context.peer.flatMap { snapshot.profiles[$0.userId] } }
    public var sharedSpace: SharedSpace { snapshot.space ?? SharedSpace(id: context.spaceId, memberIds: context.members.sorted { $0.uuidString < $1.uuidString }, timeZoneIdentifier: context.sharedTimeZone) }
    private var validLamportMaximum:Int64 {operations.filter{context.acceptedContent?[$0.id] != nil || context.authorization==nil}.map(\.operation.lamportClock).max() ?? 0}
    func localFinanceDidChange() { changeNumber += 1 }

    public init(repository: TogetherRepository, identity: DeviceIdentity, mediaRoot: URL? = nil, dateProvider: any DateProvider = SystemDateProvider(), enrollmentRoot: URL? = nil) throws {
        self.repository = repository; self.identity = identity
        self.dateProvider = dateProvider
        self.enrollmentRoot = enrollmentRoot ?? repository.storageURL?.deletingLastPathComponent()
        mediaStore = try MediaStore(root: mediaRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("Together-tests-\(UUID())"))
        stagedAssets = Dictionary(uniqueKeysWithValues: (try repository.load([MediaAsset].self, key: "staged-media") ?? []).map { ($0.id, $0) })
        peer = try repository.load(PairedPeer.self, key: "paired-peer")
        operations = try repository.allOperations()
        try reloadReplicationContext()
        snapshot = OperationProjector.replay(operations, context: context)
        giftSourceDevices = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0.operation.deviceId) })
        if try usesReplication4 && repository.load(String.self,key:"replication4/legacy-seal") == nil { return }
        if let trust=context.authorization,!trust.containsActive(identity.descriptor){return}
        if isCompletingPartnership { return }
        if ownProfile == nil {
            try append(entity: identity.descriptor.userId, type: .profile, action: .create,
                       fields: ["deviceId": .id(identity.descriptor.deviceId), "displayName": .string("我"), "relationshipLabel": .string("unknown"), "avatarData": .null])
        }
        try ensureSharedSpace()
        try reconcileRecurrence()
        try reconcileFinanceBills()
    }

    public static func production(migrateLegacyIdentity: Bool = false) throws -> ReplicaEngine {
        guard Bundle.main.bundleIdentifier != "com.together.app.qa" else {throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))}
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Together", isDirectory: true)
        let directory = try DeviceEnrollmentWorkspace(root: root).activeDirectory()
        if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Together.store").path) {
            let keys = (try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Identity"), includingPropertiesForKeys: nil)) ?? []
            guard keys.isEmpty else { throw IdentityStorageError.identityMismatch }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = try TogetherRepository(url: directory.appendingPathComponent("Together.store"))
        let operations = try repository.allOperations()
        let existingMetadata = try repository.load(LocalIdentityMetadata.self, key: "local-identity")
        guard existingMetadata != nil || operations.isEmpty else { throw IdentityStorageError.identityMismatch }
        let metadata = existingMetadata ?? LocalIdentityMetadata()
        let enrolled = try repository.load(DeviceDescriptor.self, key: "replication4/local-device")
        if directory != root, existingMetadata == nil || enrolled == nil { throw IdentityStorageError.identityMismatch }
        if let enrolled { guard enrolled.deviceId == metadata.deviceId, enrolled.userId == metadata.userId, enrolled.initialSpaceId == metadata.spaceId else { throw IdentityStorageError.identityMismatch } }
        let storedZone = try repository.load(String.self, key: "initial-time-zone")
        let zone = enrolled?.initialTimeZoneIdentifier ?? storedZone ?? TimeZone.current.identifier
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
                                                     directory: directory.appendingPathComponent("Identity", isDirectory: true),
                                                     needsExistingIdentity: existingMetadata != nil || !operations.isEmpty || enrolled != nil, migrateLegacy: migrateLegacyIdentity, timeZoneIdentifier: zone, protocolVersion: enrolled?.protocolVersion ?? 3, displayName: enrolled?.displayName ?? "我") { key in
            let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: key).publicKey
            if let enrolled, enrolled.publicKey != publicKey.rawRepresentation { throw IdentityStorageError.identityMismatch }
            for operation in operations where operation.operation.deviceId == metadata.deviceId {
                guard try publicKey.isValidSignature(operation.signature, for: CanonicalJSON.encode(operation.operation)) else { throw IdentityStorageError.identityMismatch }
            }
        }
        try repository.save(metadata, key: "local-identity")
        try repository.save(zone, key: "initial-time-zone")
        return try ReplicaEngine(repository: repository, identity: identity, mediaRoot: directory.appendingPathComponent("Media"), enrollmentRoot: root)
    }

    public func authorize(_ proposed: PairedPeer) throws {
        try validatePeer(proposed)
        try repository.save(proposed, key: "paired-peer")
        peer = proposed
        try refresh()
        try ensureSharedSpace()
    }
    private func validatePeer(_ proposed: PairedPeer, nativePartner: Bool = false) throws {
        let d = proposed.descriptor
        guard d.deviceId != identity.descriptor.deviceId, d.userId != identity.descriptor.userId, d.publicKey.count == 32, (nativePartner ? [3, 4] : [2, 3]).contains(d.protocolVersion), d.initialTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil else { throw TogetherError.invalid(Copy.text("copy.error.b3dc19939872")) }
        if let peer, peer.descriptor.deviceId != d.deviceId || peer.descriptor.userId != d.userId || peer.descriptor.publicKey != d.publicKey || peer.descriptor.initialSpaceId != d.initialSpaceId { throw TogetherError.invalid(Copy.text("copy.error.9dfbef876584")) }
    }
    public func bindRelay(peer proposed: PairedPeer, binding: RelayBinding) throws {
        try validatePeer(proposed)
        guard binding.localDeviceId == identity.descriptor.deviceId, binding.peerDeviceId == proposed.descriptor.deviceId, binding.peerPublicKey == proposed.descriptor.publicKey else { throw TogetherError.invalid(Copy.text("copy.error.f39021f401d6")) }
        try repository.saveAtomically(["paired-peer": CanonicalJSON.encode(proposed), "relay-binding": CanonicalJSON.encode(binding)])
        peer = proposed; try refresh(); try ensureSharedSpace()
    }
    /// Called only after both signed consents and the route confirmation. Existing
    /// IDs, keys and signed facts remain in place while first partnership completes.
    public func bindNativePartner(peer proposed: PairedPeer, binding: RelayBinding) throws {
        guard !usesReplication4 else { throw ReplicationError.incompatibleProtocol }
        try validatePeer(proposed, nativePartner: true)
        guard binding.localDeviceId == identity.descriptor.deviceId,
              binding.peerDeviceId == proposed.descriptor.deviceId,
              binding.peerPublicKey == proposed.descriptor.publicKey else { throw ReplicationError.unauthorized }
        try repository.saveAtomically(["paired-peer": CanonicalJSON.encode(proposed), "relay-binding": CanonicalJSON.encode(binding)])
        peer = proposed; try refresh()
        if !isCompletingPartnership { try ensureSharedSpace() }
        try repository.save(true, key: "partner4/pending")
    }
    /// First-partnership pin after both signed human consents on a verified
    /// transport. This does not invent or activate a server route/binding.
    public func bindNativePartnerForTransport(peer proposed: PairedPeer) throws {
        guard !usesReplication4, peer == nil, !isCompletingPartnership,
              try repository.load(RelayBinding.self, key: "relay-binding") == nil,
              try repository.load(C1ReplicationBinding.self, key: "replication4/relay-binding") == nil else {
            throw ReplicationError.unauthorized
        }
        try validatePeer(proposed, nativePartner: true)
        try repository.save(proposed, key: "paired-peer")
        peer = proposed; try refresh()
        try ensureSharedSpace()
        try repository.save(true, key: "partner4/pending")
    }
    public func importPartnerHistory(_ incoming: [SignedOperation]) throws {
        guard isCompletingPartnership, incoming.count <= 32 else { throw ReplicationError.unauthorized }
        for operation in incoming {
            guard let device = context.devices[operation.operation.deviceId], operation.verified(by: device) else { throw ReplicationError.invalidSignature }
        }
        try repository.insert(incoming)
    }
    public func finishPartnerHistory() throws {
        guard isCompletingPartnership else { throw ReplicationError.unauthorized }
        try refresh()
    }
    public func merge(_ incoming: [SignedOperation]) throws {
        guard !activatingReplication else { throw ReplicationError.inventoryChanged }
        guard !usesReplication4 else { throw ReplicationError.incompatibleProtocol }
        guard incoming.count <= 10_000 else { throw TogetherError.invalid(Copy.text("copy.error.10abb8d8d023")) }
        for operation in incoming {
            guard let device = context.devices[operation.operation.deviceId], operation.verified(by: device) else { throw TogetherError.invalid(Copy.text("copy.error.76ef9b5cd8a8")) }
        }
        try repository.insert(incoming)
        try refresh()
        try reconcileRecurrence()
        try reconcileFinanceBills()
        onOperationsChanged?()
    }
    public func updateProfile(name: String, label: String, avatar: Data?) throws {
        guard avatar == nil || avatar!.count <= 131_072 else { throw TogetherError.invalid(Copy.text("copy.error.9d0b8ee35f75")) }
        try append(entity: identity.descriptor.userId, type: .profile, action: .patch,
                   fields: ["displayName": .string(name), "relationshipLabel": .string(RelationshipLabel(label).rawValue), "avatarData": avatar.map(LogValue.data) ?? .null])
    }
    public func setProfile(name: String, label: RelationshipLabel) throws {
        try append(entity: identity.descriptor.userId, type: .profile, action: .patch, fields: ["displayName": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "relationshipLabel": .string(label.rawValue)])
    }
    public func setAvatar(assetId: UUID?, crop: AvatarCrop = AvatarCrop()) throws {
        if let assetId {
            guard let asset = mediaAsset(assetId), asset.ownerId == identity.descriptor.userId, asset.mediaType == .avatar, mediaStore.hasVerified(asset), crop.isValid else { throw TogetherError.invalid(Copy.text("copy.error.f358769c9343")) }
            _ = try mediaStore.thumbnail(asset, crop: crop)
            if snapshot.mediaAssets[assetId] == nil { try append(entity: asset.id, type: .mediaAsset, action: .create, fields: assetFields(asset)) }
        }
        try append(entity: identity.descriptor.userId, type: .profile, action: .patch, fields: ["avatarAssetId": .id(assetId), "avatarCrop": assetId == nil ? .null : .data(try CanonicalJSON.encode(crop)), "avatarData": .null])
    }
    public func importMedia(from url: URL, type: MediaType) async throws -> MediaAsset {
        let store = mediaStore, owner = identity.descriptor.userId, space = context.spaceId, now = dateProvider.now()
        let asset = try await Task.detached(priority: .userInitiated) { try store.importOriginal(from: url, type: type, owner: owner, space: space, now: now) }.value
        var next = stagedAssets; next[asset.id] = asset
        try repository.save(Array(next.values), key: "staged-media"); stagedAssets = next
        setMediaProgress(MediaProgress(assetId: asset.id, transferred: asset.byteCount, total: asset.byteCount, status: .local))
        return asset
    }
    public func mediaAsset(_ id: UUID) -> MediaAsset? {
        guard var asset = snapshot.mediaAssets[id] ?? stagedAssets[id] else { return nil }
        asset.transferStatus = mediaStore.hasVerified(asset) ? .verified : mediaProgress[id]?.status ?? .pending
        return asset
    }
    public func discardUnpublishedMedia(_ id: UUID) throws {
        guard snapshot.mediaAssets[id] == nil, let asset = stagedAssets[id], asset.ownerId == identity.descriptor.userId else { return }
        let currentDraft = try draft()
        guard currentDraft.audioAssetId != id, currentDraft.photoAssetId != id else { throw TogetherError.invalid(Copy.text("copy.error.6e724e7a6794")) }
        var next = stagedAssets; next.removeValue(forKey: id)
        try repository.save(Array(next.values), key: "staged-media"); stagedAssets = next
        try mediaStore.removeUnpublishedOriginal(asset); mediaProgress.removeValue(forKey: id); changeNumber += 1
    }
    private func assetFields(_ asset: MediaAsset) -> [String: LogValue] {
        ["spaceId": .id(asset.spaceId), "ownerId": .id(asset.ownerId), "mediaType": .string(asset.mediaType.rawValue), "originalFilename": .string(asset.originalFilename), "fileExtension": .string(asset.fileExtension), "sha256": .string(asset.sha256), "byteCount": .integer(Int(asset.byteCount))]
    }
    public func setMediaProgress(_ progress: MediaProgress) {
        let now = ContinuousClock.now
        if progress.status == .transferring, mediaProgress[progress.assetId]?.status == .transferring,
           let previous = progressPublishedAt[progress.assetId], previous.duration(to: now) < .milliseconds(100) { return }
        progressPublishedAt[progress.assetId] = now; mediaProgress[progress.assetId] = progress; changeNumber += 1
    }
    public func draft() throws -> LoveGiftDraft { try repository.load(LoveGiftDraft.self, key: "love-gift-draft") ?? LoveGiftDraft() }
    public func saveDraft(_ draft: LoveGiftDraft) throws {
        guard draft.text.count <= LoveGiftDraft.maximumCharacters, draft.text.utf8.count <= 16_000 else { throw TogetherError.invalid(Copy.text("copy.error.0017db608c93")) }
        try repository.save(draft, key: "love-gift-draft")
    }
    public func hasSentGift(on date: Date) -> Bool {
        guard let day = try? GiftCalendar.dayKey(at: date, timeZoneIdentifier: sharedSpace.timeZoneIdentifier) else { return true }
        return snapshot.gifts.values.contains { $0.senderId == identity.descriptor.userId && $0.sentDayKey == day && $0.isEffective }
    }
    @discardableResult public func sendGift(_ draft: LoveGiftDraft) throws -> UUID {
        guard let partner=context.peer else { throw TogetherError.invalid(Copy.text("copy.error.cfd25e4c08e5")) }
        // Match the persisted millisecond precision without rounding the last instant of a day into tomorrow.
        let now = Date(timeIntervalSince1970: floor(dateProvider.now().timeIntervalSince1970 * 1000) / 1000), zone = sharedSpace.timeZoneIdentifier
        let day = try GiftCalendar.dayKey(at: now, timeZoneIdentifier: zone)
        guard !hasSentGift(on: now) else { throw TogetherError.invalid(Copy.text("copy.emotional.a75b098be556")) }
        if let latest = snapshot.gifts.values.filter({ $0.senderId == identity.descriptor.userId }).map(\.sentDayKey).max(), day < latest { throw TogetherError.invalid(Copy.text("copy.error.68590b799484")) }
        guard draft.hasContent, draft.text.count <= LoveGiftDraft.maximumCharacters, draft.text.utf8.count <= 16_000 else { throw TogetherError.invalid(Copy.text("copy.error.9ba418316fbb")) }
        for id in [draft.audioAssetId, draft.photoAssetId].compactMap({ $0 }) {
            guard let asset = mediaAsset(id), mediaStore.hasVerified(asset) else { throw TogetherError.invalid(Copy.text("copy.error.4868d57ad1cb")) }
        }
        let slot = GiftCalendar.slot(space: context.spaceId, sender: identity.descriptor.userId, day: day)
        let id = StableID.make("gift:" + slot)
        let fields: [String: LogValue] = ["spaceId": .id(context.spaceId), "senderId": .id(identity.descriptor.userId), "recipientId": .id(partner.userId), "textContent": .string(draft.text), "audioAssetId": .id(draft.audioAssetId), "photoAssetId": .id(draft.photoAssetId), "replyToGiftId": .id(draft.replyToGiftId), "sentAt": .date(now), "sentDayKey": .string(day), "sharedTimeZoneIdentifier": .string(zone)]
        var clock = validLamportMaximum + 1
        var assetOperations: [SignedOperation] = []
        for assetId in [draft.audioAssetId, draft.photoAssetId].compactMap({ $0 }) where snapshot.mediaAssets[assetId] == nil {
            guard let asset = stagedAssets[assetId] else { throw TogetherError.invalid(Copy.text("copy.error.2b3beaac2d7a")) }
            assetOperations.append(try identity.sign(SyncOperation(deviceId: identity.descriptor.deviceId, actorId: identity.descriptor.userId, entityId: assetId, entityType: .mediaAsset, operationType: .create, lamportClock: clock, payload: assetFields(asset), createdAt: asset.createdAt))); clock += 1
        }
        let operation = SyncOperation(deviceId: identity.descriptor.deviceId, actorId: identity.descriptor.userId, entityId: id, entityType: .loveGift, operationType: .create, lamportClock: clock, payload: fields, createdAt: now)
        let signed = try identity.sign(operation)
        let additions=assetOperations+[signed],preview=try previewContext(including:additions)
        let next = ScopedProjection.replay(existing:snapshot,log:operations+additions,additions:additions,context:preview)
        if let conflict = next.conflicts.first(where: { $0.id == signed.id }) { throw TogetherError.invalid(conflict.reason) }
        try repository.commitGift(assetOperations + [signed], giftId: id, slot: slot, replicationRecords: replicationMetadata(for:assetOperations + [signed]))
        publishLocal(additions,snapshot:next,context:preview);onOperationsChanged?()
        // Clearing the draft is secondary to the durable send; it must never undo the quota reservation.
        try? saveDraft(LoveGiftDraft())
        return id
    }
    public func deleteGift(_ id: UUID) throws { try append(entity: id, type: .loveGift, action: .delete, fields: [:]) }
    public var receivedGifts: [DailyLoveGift] { snapshot.gifts.values.filter { validReceivedGift($0) }.sorted { $0.sentAt > $1.sentAt } }
    public func validReceivedGift(_ gift: DailyLoveGift) -> Bool {
        guard let partner=context.peer, gift.isEffective, gift.deletedAt == nil, gift.spaceId == context.spaceId, gift.recipientId == identity.descriptor.userId, gift.senderId == partner.userId,
              snapshot.gifts[gift.id] == gift, let source=giftSourceDevices[gift.creationOperationId], context.devices[source]?.userId == partner.userId else { return false }
        // Snapshot was built only from verified, actor-bound signatures in OperationProjector.
        return true
    }
    public func giftReady(_ gift: DailyLoveGift) -> Bool { gift.assetIds.allSatisfy { snapshot.mediaAssets[$0].map(mediaStore.hasVerified) ?? false } }
    public func presentation(_ id: UUID) -> GiftPresentationState {
        _ = changeNumber
        if let cached = presentationCache[id] { return cached }
        let state = (try? repository.load(GiftPresentationState.self, key: "gift-presentation:\(id)")) ?? GiftPresentationState(giftId: id)
        presentationCache[id] = state; return state
    }
    public func markGiftPresented(_ id: UUID, automatic: Bool) throws {
        var state = presentation(id)
        if automatic && !state.hasAutoPresented { state.hasAutoPresented = true; state.autoPresentedAt = dateProvider.now() }
        try repository.save(state, key: "gift-presentation:\(id)"); presentationCache[id] = state; changeNumber += 1
    }
    public func markGiftOpened(_ id: UUID) throws {
        var state = presentation(id); state.openedAt = state.openedAt ?? dateProvider.now()
        try repository.save(state, key: "gift-presentation:\(id)"); presentationCache[id] = state; changeNumber += 1
    }
    public func deliveryState(_ gift: DailyLoveGift) -> GiftDeliveryState {
        _ = changeNumber
        return (try? repository.load(GiftReceipt.self,key:"gift-receipt:\(gift.id)")) == GiftReceipt(gift:gift,assets:snapshot.mediaAssets) ? .synced:.pendingSync
    }
    public func acceptReceipt(_ receipt: GiftReceipt, from device: DeviceDescriptor) throws {
        guard let partner=context.peer, device.userId == partner.userId, isAuthorizedRemote(device),
              let gift = snapshot.gifts[receipt.giftId], gift.senderId == identity.descriptor.userId, gift.recipientId == device.userId,
              receipt == GiftReceipt(gift: gift, assets: snapshot.mediaAssets) else { throw TogetherError.invalid(Copy.text("copy.error.47ef85d323e2")) }
        try repository.save(receipt, key: "gift-receipt:\(gift.id)"); changeNumber += 1
    }
    private func ensureSharedSpace() throws {
        guard context.peer != nil, context.spaceCreator.deviceId == identity.descriptor.deviceId, snapshot.space == nil else { return }
        try append(entity: context.spaceId, type: .sharedSpace, action: .create, fields: ["sharedTimeZoneIdentifier": .string(context.sharedTimeZone)])
    }

    @discardableResult public func createTask(title: String, notes: String = "", assignedTo: UUID? = nil, dueAt: Date? = nil, recurrence: RecurrenceDraft? = nil) throws -> UUID {
        let id=UUID(),ruleId=recurrence.map{_ in UUID()}
        var group:[(UUID,EntityType,OperationType,[String:LogValue])]=[]
        if let recurrence,let ruleId {group.append((ruleId,.recurrenceRule,.create,ruleFields(recurrence,anchor:dueAt ?? dateProvider.now(),includeIdentity:true)))}
        group.append((id,.task,.create,taskFields(title:title,notes:notes,assignedTo:assignedTo,dueAt:dueAt,ruleId:ruleId)))
        try appendGroup(group);return id
    }
    public func editTask(_ id: UUID, title: String, notes: String, assignedTo: UUID?, dueAt: Date?, recurrence: RecurrenceDraft?) throws {
        guard let task = snapshot.tasks[id], task.deletedAt == nil else { throw TogetherError.invalid(Copy.text("copy.error.c9e9d90c0c38")) }
        var ruleId:UUID?,group:[(UUID,EntityType,OperationType,[String:LogValue])]=[]
        if let recurrence {
            if let existing=task.recurrenceRuleId {
                group.append((existing,.recurrenceRule,.patch,ruleFields(recurrence,anchor:snapshot.rules[existing]?.anchorAt ?? dueAt ?? dateProvider.now(),includeIdentity:false)));ruleId=existing
            }else{
                let id=UUID();ruleId=id;group.append((id,.recurrenceRule,.create,ruleFields(recurrence,anchor:dueAt ?? dateProvider.now(),includeIdentity:true)))
            }
        }
        group.append((id,.task,.patch,["title":.string(title),"notes":.string(notes),"assignedTo":.id(assignedTo),"dueAt":.optionalDate(dueAt),"recurrenceRuleId":.id(ruleId)]))
        try appendGroup(group)
    }
    public func setCompleted(_ id: UUID, completed: Bool) throws {
        guard let task = snapshot.tasks[id], task.deletedAt == nil else { throw TogetherError.invalid(Copy.text("copy.error.c9e9d90c0c38")) }
        try append(entity: id, type: .task, action: completed ? .completeTask : .reopenTask, fields: [:])
        if completed { try reconcileRecurrence() }
    }
    public func deleteTask(_ id: UUID) throws { try append(entity: id, type: .task, action: .delete, fields: [:]) }
    public func setNextTime(_ id: UUID, date: Date) throws {
        guard let task = snapshot.tasks[id], task.deletedAt == nil,
              let ruleId = task.recurrenceRuleId, snapshot.rules[ruleId]?.mode == .flexible else { throw TogetherError.invalid(Copy.text("copy.error.cb51a0083b9b")) }
        try append(entity: id, type: .task, action: .patch, fields: ["nextAt": .date(date)])
        try reconcileRecurrence()
    }

    @discardableResult public func grant(fulfiller: UUID, beneficiary: UUID, quantity: Int, date: CivilDate, notes: String) throws -> UUID {
        let id = UUID()
        try append(entity: id, type: .wishGrant, action: .create, fields: ["spaceId": .id(context.spaceId), "fulfillerId": .id(fulfiller), "beneficiaryId": .id(beneficiary), "quantity": .integer(quantity), "grantedOn": .string(date.iso), "createdBy": .id(identity.descriptor.userId), "notes": .string(notes)])
        return id
    }
    public func adjustGrant(_ grantId: UUID, delta: Int, notes: String) throws {
        try append(entity: UUID(), type: .grantAdjustment, action: .create, fields: ["grantId": .id(grantId), "delta": .integer(delta), "notes": .string(notes)])
    }
    @discardableResult public func createWish(grantId: UUID, title: String, description: String) throws -> UUID {
        let id = UUID()
        try append(entity: id, type: .wishItem, action: .create, fields: ["grantId": .id(grantId), "title": .string(title), "description": .string(description), "createdBy": .id(identity.descriptor.userId)])
        return id
    }
    public func requestFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .requestFulfillment, fields: [:]) }
    public func confirmFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .confirmFulfillment, fields: [:]) }
    public func rejectFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .rejectFulfillment, fields: [:]) }

    func append(entity: UUID, type: EntityType, action: OperationType, fields: [String: LogValue], createdAt: Date? = nil) throws {
        try appendGroup([(entity,type,action,fields)],createdAt:createdAt)
    }
    private func appendGroup(_ group:[(UUID,EntityType,OperationType,[String:LogValue])],createdAt:Date?=nil)throws {
        guard !isCompletingPartnership else { throw TogetherError.invalid(Copy.text("pairing.status.finishing")) }
        guard !group.isEmpty,group.count<=32 else{throw ReplicationError.bounds}
        var clock=validLamportMaximum+1
        let signed=try group.map{entry in
            defer{clock+=1}
            return try identity.sign(SyncOperation(deviceId:identity.descriptor.deviceId,actorId:identity.descriptor.userId,entityId:entry.0,entityType:entry.1,operationType:entry.2,lamportClock:clock,payload:entry.3,createdAt:createdAt ?? dateProvider.now()))
        }
        let preview=try previewContext(including:signed),next=ScopedProjection.replay(existing:snapshot,log:operations+signed,additions:signed,context:preview),ids=Set(signed.map(\.id))
        if let failure=next.conflicts.first(where:{ids.contains($0.id)}){throw TogetherError.invalid(failure.reason)}
        try repository.commitReplication(signed,records:replicationMetadata(for:signed))
        publishLocal(signed,snapshot:next,context:preview);onOperationsChanged?()
    }
    private func publishLocal(_ additions:[SignedOperation],snapshot next:DomainSnapshot,context nextContext:ReplicaContext){
        let before=snapshot
        operations+=additions;snapshot=next;if usesReplication4{replicationContext=nextContext}
        for op in additions{giftSourceDevices[op.id]=op.operation.deviceId}
        if let rows=try? ProjectionCacheDelta.rows(before:before,after:next,additions:additions){for offset in stride(from:0,to:rows.count,by:256){_ = try? repository.cacheRows(Array(rows[offset..<min(offset+256,rows.count)]),expectedRevision:repository.operationRevision)}}
        changeNumber+=1
    }
    private func refresh() throws {
        operations = try repository.allOperations()
        try reloadReplicationContext()
        snapshot = OperationProjector.replay(operations, context: context)
        giftSourceDevices = Dictionary(uniqueKeysWithValues: operations.map { ($0.id, $0.operation.deviceId) })
        try repository.cache(snapshot)
        changeNumber += 1
    }
    private func taskFields(title: String, notes: String, assignedTo: UUID?, dueAt: Date?, ruleId: UUID?, index: Int = 0, parent: UUID? = nil, availableAt: Date? = nil) -> [String: LogValue] {
        ["spaceId": .id(context.spaceId), "title": .string(title), "notes": .string(notes), "createdBy": .id(identity.descriptor.userId), "assignedTo": .id(assignedTo), "dueAt": .optionalDate(dueAt), "status": .string("pending"), "recurrenceRuleId": .id(ruleId), "occurrenceIndex": .integer(index), "spawnedFromId": .id(parent), "availableAt": .optionalDate(availableAt)]
    }
    private func ruleFields(_ draft: RecurrenceDraft, anchor: Date, includeIdentity: Bool) -> [String: LogValue] {
        var fields: [String: LogValue] = ["mode": .string(draft.mode.rawValue), "unit": .string(draft.unit.rawValue), "interval": .integer(draft.interval), "anchorAt": .date(anchor), "timeZoneIdentifier": .string(draft.timeZoneIdentifier)]
        if includeIdentity { fields["spaceId"] = .id(context.spaceId); fields["createdBy"] = .id(identity.descriptor.userId) }
        return fields
    }
    private func createRule(_ draft: RecurrenceDraft, anchor: Date) throws -> UUID {
        let id = UUID(); try append(entity: id, type: .recurrenceRule, action: .create, fields: ruleFields(draft, anchor: anchor, includeIdentity: true)); return id
    }
    public func reconcileRecurrence() throws {
        let completed = snapshot.tasks.values.filter { $0.status == .completed && $0.deletedAt == nil && $0.recurrenceRuleId != nil }.sorted { $0.taskId.uuidString < $1.taskId.uuidString }
        for task in completed {
            guard let ruleId = task.recurrenceRuleId, let rule = snapshot.rules[ruleId] else { continue }
            let index = task.occurrenceIndex + 1
            let date: Date?
            let id: UUID
            if rule.mode == .regular { date = RecurrenceCalculator.date(rule: rule, occurrenceIndex: index); id = RecurrenceCalculator.instanceId(ruleId: ruleId, occurrenceIndex: index) }
            else { date = task.nextAt; id = RecurrenceCalculator.flexibleInstanceId(parentTaskId: task.taskId) }
            guard let date else { continue }
            if let next = snapshot.tasks[id] {
                if rule.mode == .flexible, next.status != .completed, next.deletedAt == nil, next.dueAt != date {
                    try append(entity: id, type: .task, action: .patch, fields: ["dueAt": .date(date), "availableAt": .date(date)])
                }
            } else {
                try append(entity: id, type: .task, action: .create, fields: taskFields(title: task.title, notes: task.notes, assignedTo: task.assignedTo, dueAt: date, ruleId: ruleId, index: index, parent: task.taskId, availableAt: date))
            }
        }
    }
}


extension ReplicaEngine {
    func claimMediaDownload(_ id:UUID,from device:UUID)->Bool {
        guard mediaDownloadSources[id]==nil || mediaDownloadSources[id]==device else{return false}
        mediaDownloadSources[id]=device;return true
    }
    func releaseMediaDownload(_ id:UUID,from device:UUID){if mediaDownloadSources[id]==device{mediaDownloadSources.removeValue(forKey:id)}}
    public func isAuthorizedRemote(_ device:DeviceDescriptor) -> Bool {
        if let trust=context.authorization {return device.deviceId != identity.descriptor.deviceId && trust.containsActive(device)}
        return peer?.descriptor.deviceId==device.deviceId && peer?.descriptor.publicKey==device.publicKey && peer?.descriptor.userId==device.userId
    }
    /// Explicit activation only; the old peer, route, identity and original
    /// signed operation bytes remain in their existing records.
    public func activateReplication4(_ archive:AuthorizationArchive) async throws -> AuthorizedReplicationStore {
        guard !activatingReplication else { throw ReplicationError.inventoryChanged }
        activatingReplication = true
        defer { activatingReplication = false }
        let pins=peer.map{ReplicaContext(local:identity.descriptor,peer:$0.descriptor)}
        let trust=try SpaceAuthorization.restore(archive,existingPins:pins)
        if !usesReplication4 {
            guard try await OperationInventoryIndex(repository:repository).checkpoint() == trust.genesis.body.legacyCheckpoint else { throw ReplicationError.inventoryChanged }
        }
        let store=try AuthorizedReplicationStore(repository:repository,identity:identity,authorization:trust)
        try await store.restore()
        try await refreshFromReplication(store)
        return store
    }
    public func refreshFromReplication(_ store:AuthorizedReplicationStore) async throws {
        try await refreshFromReplication(store,project:{log,context in
            await Task.detached(priority:.utility){OperationProjector.replay(log,context:context)}.value
        })
    }
    func refreshFromReplication(_ store:AuthorizedReplicationStore,project:@escaping @Sendable ([SignedOperation],ReplicaContext)async -> DomainSnapshot)async throws {
        while true {
            let revision=repository.operationRevision
            let input=try await store.projectionInput(),verified=input.context,log=input.operations,before=snapshot
            let projected=await project(log,verified)
            let cacheRows=try await Task.detached(priority:.utility){
                try ProjectionCacheDelta.rows(before:before,after:projected)
            }.value
            let expectedAuthorization=try verified.authorization?.digest
            func authorizationStillMatches()throws -> Bool {
                let current=try repository.load(AuthorizationArchive.self,key:"replication4/authorization")
                return try current.map{ReplicationHash.digest(try CanonicalJSON.encode($0))}==expectedAuthorization
            }
            guard repository.operationRevision==revision,try authorizationStillMatches() else {continue}
            replicationContext=verified;operations=log;snapshot=projected
            giftSourceDevices=Dictionary(uniqueKeysWithValues:log.map{($0.id,$0.operation.deviceId)})
            changeNumber+=1
            for offset in stride(from:0,to:cacheRows.count,by:256){
                guard try authorizationStillMatches() else{break}
                guard (try? repository.cacheRows(Array(cacheRows[offset..<min(offset+256,cacheRows.count)]),expectedRevision:revision)) == true else{break}
                await Task.yield()
            }
            return
        }
    }
    private func reloadReplicationContext() throws {
        guard let archive=try repository.load(AuthorizationArchive.self,key:"replication4/authorization") else {return}
        let trust=try SpaceAuthorization.restore(archive)
        if let previous=replicationContext?.authorization {guard try previous.genesis.digest==trust.genesis.digest else {throw ReplicationError.unauthorized}}
        else if let peer { _=try SpaceAuthorization.restore(archive,existingPins:ReplicaContext(local:identity.descriptor,peer:peer.descriptor)) }
        var accepted:[UUID:String]=[:],revokedIDs:Set<UUID>=[]
        if trust.devices.values.contains(where:{$0.revokedAt != nil}) {
            let proofs=try operations.compactMap{try repository.load(AuthorizedOperation.self,key:"replication4/proof/"+$0.id.uuidString)}
            for device in trust.devices.values where device.revokedAt != nil {if let chain=try RevokedPrefix.resolve(device,proofs:proofs,trust:trust){revokedIDs.formUnion(chain.map(\.id))}}
        }
        if try repository.load(String.self,key:"replication4/legacy-seal")==trust.genesis.body.legacyCheckpoint.digest {
            for op in operations {
                let entry=try InventoryEntry(op)
                if let proof=try repository.load(AuthorizedOperation.self,key:"replication4/proof/"+op.id.uuidString) {
                    guard proof.body.signedOperation==op else {throw ReplicationError.contentCollision}
                    if (try? proof.verify(in:trust)) != nil,trust.devices[op.operation.deviceId]?.revokedAt == nil || revokedIDs.contains(op.id) {accepted[op.id]=entry.contentDigest}
                }else if try repository.load(String.self,key:"replication4/legacy/"+op.id.uuidString)==entry.contentDigest {accepted[op.id]=entry.contentDigest}
            }
        }
        replicationContext=try ReplicaContext(local:identity.descriptor,authorization:trust,acceptedContent:accepted)
    }
    private func previewContext(including additions:[SignedOperation]) throws -> ReplicaContext {
        guard let trust=context.authorization else {return context}
        var accepted=context.acceptedContent ?? [:]
        for op in additions {accepted[op.id]=try InventoryEntry(op).contentDigest}
        return try ReplicaContext(local:identity.descriptor,authorization:trust,acceptedContent:accepted)
    }
    /// Called synchronously on the repository's owning actor: sequence read,
    /// signatures, quota and fact commit cannot be interleaved by another task.
    private func replicationMetadata(for log:[SignedOperation]) throws -> [String:Data] {
        guard !activatingReplication || usesReplication4 else { throw ReplicationError.inventoryChanged }
        guard let trust=context.authorization else {
            guard try repository.load(AuthorizationArchive.self,key:"replication4/authorization")==nil else{throw ReplicationError.staleAuthorization};return [:]
        }
        guard let saved=try repository.load(AuthorizationArchive.self,key:"replication4/authorization"),try SpaceAuthorization.restore(saved).digest==trust.digest else{throw ReplicationError.staleAuthorization}
        guard trust.containsActive(identity.descriptor),let own=trust.devices[identity.descriptor.deviceId],
              try repository.load(String.self,key:"replication4/legacy-seal")==trust.genesis.body.legacyCheckpoint.digest else {throw ReplicationError.unauthorized}
        let headKey="replication4/head/"+own.epochId.uuidString
        var head=try repository.load(DeviceFrontier.self,key:headKey) ?? DeviceFrontier(),records:[String:Data]=[:]
        for op in log {
            let proof=try AuthorizedOperation.sign(op,identity:identity,trust:trust,previous:head)
            records["replication4/proof/"+op.id.uuidString]=try CanonicalJSON.encode(proof)
            head=try DeviceFrontier(sequence:proof.body.sequence,digest:proof.digest)
        }
        records[headKey]=try CanonicalJSON.encode(head);return records
    }
}
