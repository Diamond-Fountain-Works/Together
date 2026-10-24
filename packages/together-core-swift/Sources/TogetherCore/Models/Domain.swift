import Foundation

public struct UserProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { userId }
    public var userId: UUID
    public var deviceId: UUID
    public var displayName: String
    public var relationshipLabel: String
    public var avatarData: Data?
    public var updatedAt: Date
    public var avatarAssetId: UUID? = nil
    public var avatarCrop: AvatarCrop? = nil
    public var role: RelationshipLabel { RelationshipLabel(relationshipLabel) }
    public init(userId: UUID, deviceId: UUID, displayName: String, relationshipLabel: String, avatarData: Data?, updatedAt: Date, avatarAssetId: UUID? = nil, avatarCrop: AvatarCrop? = nil) {
        self.userId = userId; self.deviceId = deviceId; self.displayName = displayName; self.relationshipLabel = relationshipLabel
        self.avatarData = avatarData; self.updatedAt = updatedAt; self.avatarAssetId = avatarAssetId; self.avatarCrop = avatarCrop
    }
    private enum CodingKeys: String, CodingKey { case userId, deviceId, displayName, relationshipLabel, avatarData, updatedAt, avatarAssetId, avatarCrop }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId); deviceId = try c.decode(UUID.self, forKey: .deviceId)
        displayName = try c.decode(String.self, forKey: .displayName)
        relationshipLabel = (try? c.decode(String.self, forKey: .relationshipLabel)) ?? "unknown"
        avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData); updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        avatarAssetId = try c.decodeIfPresent(UUID.self, forKey: .avatarAssetId); avatarCrop = try c.decodeIfPresent(AvatarCrop.self, forKey: .avatarCrop)
    }
}

public struct SharedSpace: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var memberIds: [UUID]
    public var timeZoneIdentifier: String
    public var sharedTimeZoneIdentifier: String { timeZoneIdentifier }
}

public enum TaskStatus: String, Codable, Sendable { case pending, completed, scheduled }
public struct TodoTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { taskId }
    public var taskId: UUID
    public var spaceId: UUID
    public var title: String
    public var notes: String
    public var createdBy: UUID
    public var assignedTo: UUID?
    public var dueAt: Date?
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var recurrenceRuleId: UUID?
    public var deletedAt: Date?
    public var occurrenceIndex: Int
    public var spawnedFromId: UUID?
    public var availableAt: Date?
    public var nextAt: Date?

    public func visibleStatus(at now: Date) -> TaskStatus {
        if status == .completed { return .completed }
        return (availableAt.map { $0 > now } ?? false) ? .scheduled : .pending
    }
}

public enum RecurrenceMode: String, Codable, CaseIterable, Sendable { case regular, flexible }
public enum RecurrenceUnit: String, Codable, CaseIterable, Sendable { case day, week, month }
public struct RecurrenceRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var spaceId: UUID
    public var mode: RecurrenceMode
    public var unit: RecurrenceUnit
    public var interval: Int
    public var anchorAt: Date
    public var timeZoneIdentifier: String
    public var createdBy: UUID
    public var updatedAt: Date
}

public struct CivilDate: Codable, Equatable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!; month = c.month!; day = c.day!
    }
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
        guard isValid else { return nil }
    }
    public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var display: String { display(language: LanguageSettings.shared.language) }
    public func display(language: AppLanguage) -> String {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard isValid, let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return iso }
        return Copy.formattedDate(date, dateStyle: .medium, timeStyle: .none, language: language, timeZone: zone)
    }
    public var isValid: Bool {
        guard (1900...3000).contains(year) else { return false }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = c.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let components = c.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day
    }
    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool { lhs.iso < rhs.iso }
}

public struct WishGrant: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { grantId }
    public var grantId: UUID
    public var spaceId: UUID
    public var fulfillerId: UUID
    public var beneficiaryId: UUID
    public var quantity: Int
    public var grantedOn: CivilDate
    public var createdAt: Date
    public var createdBy: UUID
    public var notes: String
}
public struct GrantAdjustment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var grantId: UUID
    public var delta: Int
    public var notes: String
    public var createdBy: UUID
    public var createdAt: Date
    public var isEffective: Bool
}
public enum WishStatus: String, Codable, Sendable { case open, completionRequested, fulfilled, conflict }
public struct WishItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { wishId }
    public var wishId: UUID
    public var grantId: UUID
    public var title: String
    public var description: String
    public var beneficiaryId: UUID
    public var fulfillerId: UUID
    public var createdBy: UUID
    public var status: WishStatus
    public var createdAt: Date
    public var fulfilledAt: Date?
    public var conflictReason: String?
}
public struct GrantBalance: Equatable, Sendable {
    public var total: Int
    public var fulfilled: Int
    public var occupied: Int
    public var remaining: Int { total - fulfilled }
    public var availableToDefine: Int { total - occupied }
}
public struct DomainConflict: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { operationId }
    public var operationId: UUID
    public var entityId: UUID
    public var reason: String
}
public struct DomainSnapshot: Equatable, Sendable {
    public var finance = FinanceSnapshot()
    public var profiles: [UUID: UserProfile] = [:]
    public var tasks: [UUID: TodoTask] = [:]
    public var rules: [UUID: RecurrenceRule] = [:]
    public var grants: [UUID: WishGrant] = [:]
    public var wishes: [UUID: WishItem] = [:]
    public var adjustments: [GrantAdjustment] = []
    public var conflicts: [DomainConflict] = []
    public var mediaAssets: [UUID: MediaAsset] = [:]
    public var gifts: [UUID: DailyLoveGift] = [:]
    public var space: SharedSpace?
    public init() {}
    public func balance(for grantId: UUID) -> GrantBalance {
        let total = (grants[grantId]?.quantity ?? 0) + adjustments.filter { $0.grantId == grantId && $0.isEffective }.reduce(0) { $0 + $1.delta }
        let items = wishes.values.filter { $0.grantId == grantId && $0.status != .conflict }
        return GrantBalance(total: total, fulfilled: items.filter { $0.status == .fulfilled }.count, occupied: items.count)
    }
}
