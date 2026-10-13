import Foundation

public enum RelationshipLabel: String, Codable, CaseIterable, Sendable {
    case boyfriend, girlfriend, unknown
    public init(_ value: String?) {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "boyfriend", "男朋友", "小男友": self = .boyfriend
        case "girlfriend", "女朋友", "小女友": self = .girlfriend
        default: self = .unknown
        }
    }
    public var displayName: String { switch self { case .boyfriend: Copy.text("role.boyfriend"); case .girlfriend: Copy.text("role.girlfriend"); case .unknown: Copy.text("role.unknown") } }
    public var affectionateName: String { switch self { case .boyfriend: Copy.text("role.affection.boyfriend"); case .girlfriend: Copy.text("role.affection.girlfriend"); case .unknown: Copy.text("copy.status.034fc48ba584") } }
    public var pronoun: String { switch self { case .boyfriend: Copy.text("role.pronoun.boyfriend"); case .girlfriend: Copy.text("role.pronoun.girlfriend"); case .unknown: Copy.text("copy.status.034fc48ba584") } }
}
public enum LoveCopy {
    public static func prompt(partner: RelationshipLabel) -> String { partner == .unknown ? Copy.text("gift.prompt.unknown") : Copy.format("gift.prompt.known", partner.affectionateName) }
    public static func title(sender: RelationshipLabel, hasText: Bool) -> String {
        if sender == .unknown { return Copy.text(hasText ? "gift.title.unknown.text" : "gift.title.unknown.attachment") }
        return Copy.format(hasText ? "gift.title.known.text" : "gift.title.known.attachment", sender.affectionateName)
    }
    public static func introduction(sender: RelationshipLabel) -> String { sender == .unknown ? Copy.text("gift.intro.unknown") : Copy.format("gift.intro.known", sender.affectionateName) }
    public static func avatarPrompt(partner: RelationshipLabel) -> String { partner == .unknown ? Copy.text("gift.avatar.unknown") : Copy.format("gift.avatar.known", partner.affectionateName) }
    public static func ending(sender: RelationshipLabel) -> String { sender == .unknown ? Copy.text("gift.ending.unknown") : Copy.format("gift.ending.known", sender.pronoun) }
}
public protocol DateProvider: Sendable { func now() -> Date }
public struct SystemDateProvider: DateProvider { public init() {}; public func now() -> Date { Date() } }
public struct FixedDateProvider: DateProvider { public var date: Date; public init(_ date: Date) { self.date = date }; public func now() -> Date { date } }
public enum GiftCalendar {
    public static func dayKey(at date: Date, timeZoneIdentifier: String) throws -> String {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw TogetherError.invalid(Copy.text("error.invalid_shared_timezone")) }
        return CivilDate(date, timeZone: zone).iso
    }
    public static func slot(space: UUID, sender: UUID, day: String) -> String { "\(space.uuidString):\(sender.uuidString):\(day)" }
}
public struct DailyLoveGift: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { giftId }
    public var giftId: UUID
    public var spaceId: UUID
    public var senderId: UUID
    public var recipientId: UUID
    public var textContent: String?
    public var audioAssetId: UUID?
    public var photoAssetId: UUID?
    public var replyToGiftId: UUID?
    public var sentAt: Date
    public var sentDayKey: String
    public var sharedTimeZoneIdentifier: String
    public var deletedAt: Date?
    public var creationOperationId: UUID
    public var isEffective: Bool
    public var hasText: Bool { !(textContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var assetIds: [UUID] { [audioAssetId, photoAssetId].compactMap { $0 } }
}
public struct LoveGiftDraft: Codable, Equatable, Sendable {
    public var text = ""
    public var audioAssetId: UUID?
    public var photoAssetId: UUID?
    public var replyToGiftId: UUID?
    public init() {}
    public var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || audioAssetId != nil || photoAssetId != nil }
    public static let maximumCharacters = 4_000
}
public enum GiftDeliveryState: String, Codable, Sendable { case local = "Local", pendingSync = "Pending Sync", synced = "Synced" }
public struct GiftPresentationState: Codable, Equatable, Sendable {
    public var giftId: UUID
    public var hasAutoPresented = false
    public var autoPresentedAt: Date?
    public var openedAt: Date?
    public init(giftId: UUID) { self.giftId = giftId }
}
public struct GiftReceipt: Codable, Equatable, Sendable {
    public var giftId: UUID
    public var creationOperationId: UUID
    public var assetHashes: [UUID: String]
    public var recipientId: UUID
    public init(gift: DailyLoveGift, assets: [UUID: MediaAsset]) {
        giftId = gift.id; creationOperationId = gift.creationOperationId; recipientId = gift.recipientId
        assetHashes = Dictionary(uniqueKeysWithValues: gift.assetIds.compactMap { id in assets[id].map { (id, $0.sha256) } })
    }
}
