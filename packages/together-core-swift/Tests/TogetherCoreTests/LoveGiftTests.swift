import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TogetherCore

final class TestClock: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: Double) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Suite("Relationship Labels & Copy") struct RelationshipTests {
    @Test func normalizedLabelsAndNeutralFallback() {
        #expect(RelationshipLabel("  BOYFRIEND\n") == .boyfriend)
        #expect(RelationshipLabel(" Girlfriend ") == .girlfriend)
        #expect(RelationshipLabel("男朋友") == .boyfriend)
        #expect(RelationshipLabel("女朋友") == .girlfriend)
        for value: String? in [nil, "", " \n", "Partner", "unknown", "parent", "🐶"] {
            let role = RelationshipLabel(value)
            #expect(role == .unknown && role.affectionateName == "TA" && role.pronoun == "TA")
        }
        #expect(LoveCopy.ending(sender: .boyfriend).contains("找他"))
        #expect(LoveCopy.ending(sender: .girlfriend).contains("找她"))
        #expect(LoveCopy.ending(sender: .unknown).contains("找 TA"))
        #expect(LoveCopy.prompt(partner: .boyfriend).contains("小男友"))
        #expect(LoveCopy.prompt(partner: .girlfriend).contains("小女友"))
        #expect(LoveCopy.prompt(partner: .unknown).contains("TA"))
        #expect(LoveCopy.avatarPrompt(partner: .unknown).contains("TA"))
    }
    @Test func textAndAttachmentOnlyCopy() {
        #expect(LoveCopy.title(sender: .boyfriend, hasText: true) == "这是小男友专门送给你的情话 ♡")
        #expect(LoveCopy.title(sender: .girlfriend, hasText: true) == "这是小女友专门送给你的情话 ♡")
        #expect(LoveCopy.title(sender: .unknown, hasText: true) == "这是 TA 专门送给你的一份爱意 ♡")
        for role in RelationshipLabel.allCases { #expect(LoveCopy.title(sender: role, hasText: false).contains("小礼物")) }
    }
    @Test func legacyProfileMissingOrNullRelationship() throws {
        let profile = UserProfile(userId: UUID(), deviceId: UUID(), displayName: "保留昵称", relationshipLabel: "Boyfriend", avatarData: nil, updatedAt: instant("2026-10-09T12:00:00Z"))
        let data = try CanonicalJSON.encode(profile)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "relationshipLabel")
        let missing = try CanonicalJSON.decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(missing.role == .unknown && missing.displayName == profile.displayName && missing.userId == profile.userId)
        object["relationshipLabel"] = NSNull()
        #expect(try CanonicalJSON.decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: object)).role == .unknown)
    }
}

@Suite("Daily Love Gifts") @MainActor struct LoveGiftTests {
    private func pair(clock: TestClock, root: URL? = nil) throws -> (ReplicaEngine, ReplicaEngine) {
        let ia = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, timeZoneIdentifier: "Asia/Shanghai")
        let ib = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, timeZoneIdentifier: "America/Los_Angeles")
        let a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ia, mediaRoot: root?.appendingPathComponent("a"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ib, mediaRoot: root?.appendingPathComponent("b"), dateProvider: clock)
        try a.authorize(PairedPeer(descriptor: ib.descriptor, host: "127.0.0.1", port: 58432))
        try b.authorize(PairedPeer(descriptor: ia.descriptor, host: "127.0.0.1", port: 58431))
        try a.merge(b.operations); try b.merge(a.operations)
        return (a, b)
    }
    @Test func offlineQuotaDedupeDeleteAndReply() throws {
        let clock = TestClock(instant("2026-10-09T15:59:58Z")), (a, b) = try pair(clock: clock)
        var draft = LoveGiftDraft(); draft.text = "晚安 ♡"
        let id = try a.sendGift(draft)
        #expect(a.snapshot.gifts[id]?.sentDayKey == "2026-10-09")
        #expect(a.deliveryState(a.snapshot.gifts[id]!) == .pendingSync)
        #expect(throws: (any Error).self) { try a.sendGift(draft) }
        try b.merge(a.operations + a.operations)
        #expect(b.receivedGifts.count == 1)
        #expect(a.deliveryState(a.snapshot.gifts[id]!) == .pendingSync) // logs alone aren't an acknowledgement
        var reply = LoveGiftDraft(); reply.text = "也想你"; reply.replyToGiftId = id
        let replyId = try b.sendGift(reply)
        #expect(b.snapshot.gifts[replyId]?.replyToGiftId == id)
        #expect(throws: (any Error).self) { try b.sendGift(reply) }
        try a.deleteGift(id); try b.merge(a.operations)
        #expect(b.receivedGifts.isEmpty && a.hasSentGift(on: clock.now()))
        #expect(throws: (any Error).self) { try a.sendGift(draft) }
        clock.advance(3)
        #expect(!a.hasSentGift(on: clock.now()))
        let tomorrow = try a.sendGift(draft)
        #expect(a.snapshot.gifts[tomorrow]?.sentDayKey == "2026-10-10")
        clock.advance(-86400)
        #expect(throws: (any Error).self) { try a.sendGift(draft) }
    }
    @Test func sharedTimezoneDSTAndMidnight() throws {
        #expect(try GiftCalendar.dayKey(at: instant("2026-10-09T16:00:00Z"), timeZoneIdentifier: "Asia/Shanghai") == "2026-10-10")
        #expect(try GiftCalendar.dayKey(at: instant("2026-10-09T16:00:00Z"), timeZoneIdentifier: "America/Los_Angeles") == "2026-10-09")
        #expect(try GiftCalendar.dayKey(at: instant("2026-03-08T09:59:59Z"), timeZoneIdentifier: "America/Los_Angeles") == "2026-03-08")
        #expect(try GiftCalendar.dayKey(at: instant("2026-03-08T10:00:01Z"), timeZoneIdentifier: "America/Los_Angeles") == "2026-03-08")
        #expect(try GiftCalendar.dayKey(at: instant("2026-11-01T09:30:00Z"), timeZoneIdentifier: "America/Los_Angeles") == "2026-11-01")
        let clock = TestClock(instant("2026-10-09T16:00:00Z")), (a, b) = try pair(clock: clock)
        #expect(a.sharedSpace.timeZoneIdentifier == b.sharedSpace.timeZoneIdentifier && a.sharedSpace.timeZoneIdentifier == "Asia/Shanghai")
        let edgeClock = TestClock(instant("2026-10-09T15:59:59Z").addingTimeInterval(0.9999)), (edge, _) = try pair(clock: edgeClock)
        var draft = LoveGiftDraft(); draft.text = "午夜前最后一瞬"
        let id = try edge.sendGift(draft)
        #expect(edge.snapshot.gifts[id]?.sentDayKey == "2026-10-09")
    }
    @Test func draftMissingProfileSameRoleAndPresentationPersistence() throws {
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), (a, b) = try pair(clock: clock)
        try a.setProfile(name: "A", label: .boyfriend); try b.setProfile(name: "B", label: .boyfriend)
        var draft = LoveGiftDraft(); draft.text = "两个小男友也没问题"
        try a.saveDraft(draft); #expect(try a.draft() == draft)
        let id = try a.sendGift(draft)
        let withoutProfile = a.operations.filter { $0.operation.entityType != .profile }
        let snapshot = OperationProjector.replay(withoutProfile, context: b.context)
        #expect(snapshot.gifts[id] != nil)
        let neutralTitle = LoveCopy.title(sender: snapshot.profiles[a.identity.descriptor.userId]?.role ?? .unknown, hasText: true)
        #expect(neutralTitle.contains("TA"))
        try b.merge(a.operations)
        try b.markGiftPresented(id, automatic: true)
        #expect(b.presentation(id).hasAutoPresented && b.presentation(id).openedAt == nil)
        try b.markGiftOpened(id)
        try a.setProfile(name: "A", label: .girlfriend); try b.merge(a.operations)
        #expect(b.snapshot.profiles[a.identity.descriptor.userId]?.role == .girlfriend)
        #expect(b.presentation(id).hasAutoPresented && b.presentation(id).openedAt != nil)
        try a.deleteGift(id); try b.merge(a.operations)
        #expect(b.presentation(id).hasAutoPresented && b.presentation(id).openedAt != nil)
    }
    @Test func rejectWrongIdentitiesAndDeterministicCandidateConflict() throws {
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), (a, b) = try pair(clock: clock)
        var draft = LoveGiftDraft(); draft.text = "合法礼物"
        let id = try a.sendGift(draft)
        let original = a.operations.first { $0.operation.entityId == id }!.operation
        var illegal = original; illegal.operationId = UUID(); illegal.entityId = UUID(); illegal.payload["recipientId"] = .id(a.identity.descriptor.userId)
        try b.merge([a.identity.sign(illegal)])
        #expect(b.snapshot.gifts[illegal.entityId] == nil && !b.snapshot.conflicts.isEmpty)
        illegal.operationId = UUID(); illegal.payload["recipientId"] = .id(b.identity.descriptor.userId); illegal.payload["senderId"] = .id(b.identity.descriptor.userId)
        try b.merge([a.identity.sign(illegal)])
        #expect(b.snapshot.gifts[illegal.entityId] == nil)
        var second = original; second.operationId = UUID(); second.entityId = UUID(); second.lamportClock += 1
        try a.merge(b.operations); try a.merge([a.identity.sign(second)]); try b.merge(a.operations)
        #expect(a.snapshot == b.snapshot)
        #expect(a.snapshot.gifts.values.filter(\.isEffective).count == 1)
        #expect(a.snapshot.gifts[second.entityId]?.isEffective == false)
        #expect(throws: (any Error).self) { try b.deleteGift(id) }
    }
    @Test func durableGiftReservationAndLocalDraftAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Together-gift-reopen-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), ia = try DeviceIdentity(), ib = try DeviceIdentity()
        let url = directory.appendingPathComponent("Together.store")
        let first = try ReplicaEngine(repository: TogetherRepository(url: url), identity: ia, mediaRoot: directory.appendingPathComponent("Media"), dateProvider: clock)
        var draft = LoveGiftDraft(); draft.text = "草稿不消耗额度"
        try first.saveDraft(draft)
        #expect(!first.hasSentGift(on: clock.now()))
        #expect(throws: (any Error).self) { try first.sendGift(draft) }
        try first.authorize(PairedPeer(descriptor: ib.descriptor, host: "127.0.0.1", port: 58432))
        let id = try first.sendGift(draft); try first.deleteGift(id)
        try first.markGiftPresented(id, automatic: true); try first.markGiftOpened(id)
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: url), identity: ia, mediaRoot: directory.appendingPathComponent("Media"), dateProvider: clock)
        #expect(reopened.snapshot.gifts[id]?.deletedAt != nil)
        #expect(reopened.hasSentGift(on: clock.now()) && reopened.presentation(id).hasAutoPresented)
        #expect(throws: (any Error).self) { try reopened.sendGift(draft) }
    }
    @Test func startupPrioritySingleRevealAndNonInterruptingLaterGift() throws {
        #expect(AutomaticModal.allCases.sorted() == [.initialSetup, .giftReveal, .whatsNew, .advisor])
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), (a, b) = try pair(clock: clock)
        var draft = LoveGiftDraft(); draft.text = "启动时拆开的爱意"
        let first = try a.sendGift(draft); try b.merge(a.operations)
        var policy = GiftLaunchPolicy(cachedInboxIds: [])
        policy.noteFirstSync(inboxIds: b.receivedGifts.map(\.id))
        #expect(policy.eligible(inbox: b.receivedGifts, readyIds: [], presentations: [:]).isEmpty)
        #expect(policy.eligible(inbox: b.receivedGifts, readyIds: [first], presentations: [:]) == [first])
        policy.didPresentAutomatically(); try b.markGiftPresented(first, automatic: true)
        #expect(policy.eligible(inbox: b.receivedGifts, readyIds: [first], presentations: [:]).isEmpty)
        clock.advance(86400); let second = try a.sendGift(draft); try b.merge(a.operations)
        policy.noteFirstSync(inboxIds: b.receivedGifts.map(\.id))
        #expect(policy.eligible(inbox: b.receivedGifts, readyIds: [first, second], presentations: [:]).isEmpty)
        var nextLaunch = GiftLaunchPolicy(cachedInboxIds: b.receivedGifts.map(\.id))
        let states = [first: b.presentation(first), second: b.presentation(second)]
        #expect(nextLaunch.eligible(inbox: b.receivedGifts, readyIds: [first, second], presentations: states) == [second])
        nextLaunch.noteUserInteraction()
        #expect(nextLaunch.eligible(inbox: b.receivedGifts, readyIds: [first, second], presentations: states).isEmpty)
    }
}

func makeImage(in directory: URL) throws -> URL {
    let width = 8200, height = 64
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let bytes = c.data!.assumingMemoryBound(to: UInt8.self)
    var random: UInt32 = 0x12345678
    for i in 0..<(width * height * 4) { random ^= random << 13; random ^= random >> 17; random ^= random << 5; bytes[i] = UInt8(truncatingIfNeeded: random) }
    let url = directory.appendingPathComponent("original-photo.png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, c.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw TogetherError.invalid("fixture image") }; return url
}
func makeAudio(in directory: URL) throws -> URL {
    let count: UInt32 = 100_000
    var bytes = Data("RIFF".utf8)
    func le(_ value: UInt32) -> Data { Data([UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8((value >> 24) & 255)]) }
    bytes.append(le(36 + count * 2)); bytes.append(Data("WAVEfmt ".utf8)); bytes.append(le(16)); bytes.append(Data([1,0,1,0])); bytes.append(le(44_100)); bytes.append(le(88_200)); bytes.append(Data([2,0,16,0])); bytes.append(Data("data".utf8)); bytes.append(le(count * 2)); bytes.append(Data(repeating: 0, count: Int(count * 2)))
    let url = directory.appendingPathComponent("voice.wav"); try bytes.write(to: url); return url
}
