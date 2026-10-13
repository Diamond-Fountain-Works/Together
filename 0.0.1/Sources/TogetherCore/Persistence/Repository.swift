import Foundation
import SwiftData

@Model public final class OperationRecord {
    @Attribute(.unique) public var operationId: String
    public var body: Data
    public init(operation: SignedOperation) throws { operationId = operation.id.uuidString; body = try CanonicalJSON.encode(operation) }
}
@Model public final class LocalRecord {
    @Attribute(.unique) public var key: String
    public var body: Data
    public init(key: String, body: Data) { self.key = key; self.body = body }
}
@Model public final class EntityRecord {
    @Attribute(.unique) public var key: String
    public var entityType: String
    public var body: Data
    public init(key: String, entityType: String, body: Data) { self.key = key; self.entityType = entityType; self.body = body }
}
public struct LocalIdentityMetadata: Codable, Sendable {
    public var deviceId: UUID
    public var userId: UUID
    public var spaceId: UUID
    public init(deviceId: UUID = UUID(), userId: UUID = UUID(), spaceId: UUID = UUID()) { self.deviceId = deviceId; self.userId = userId; self.spaceId = spaceId }
}
@MainActor public final class TogetherRepository {
    public let container: ModelContainer
    private let context: ModelContext
    public init(url: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema([OperationRecord.self, LocalRecord.self, EntityRecord.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container); context.autosaveEnabled = false
    }
    public func allOperations() throws -> [SignedOperation] { try context.fetch(FetchDescriptor<OperationRecord>()).map { try CanonicalJSON.decode(SignedOperation.self, from: $0.body) } }
    public func insert(_ operations: [SignedOperation]) throws {
        var existing = Dictionary(uniqueKeysWithValues: try allOperations().map { ($0.id, $0) })
        var additions: [SignedOperation] = []
        for operation in operations {
            if let prior = existing[operation.id] {
                guard try CanonicalJSON.encode(prior) == CanonicalJSON.encode(operation) else { throw RepositoryError.reusedOperationId }
            } else { additions.append(operation); existing[operation.id] = operation }
        }
        do { for operation in additions { context.insert(try OperationRecord(operation: operation)) }; try context.save() } catch { context.rollback(); throw error }
    }
    public func commitGift(_ operations: [SignedOperation], giftId: UUID, slot: String) throws {
        let key = "gift-slot:\(slot)"
        do {
            try context.transaction {
                guard try load(UUID.self, key: key) == nil else { throw TogetherError.invalid(Copy.text("copy.error.90bff42b45e2")) }
                context.insert(LocalRecord(key: key, body: try CanonicalJSON.encode(giftId)))
                for operation in operations { context.insert(try OperationRecord(operation: operation)) }
                try context.save()
            }
        } catch { context.rollback(); throw error }
    }
    public func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let wanted = key
        var descriptor = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key == wanted }); descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map { try CanonicalJSON.decode(type, from: $0.body) }
    }
    public func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try CanonicalJSON.encode(value)
        if let row = try context.fetch(FetchDescriptor<LocalRecord>()).first(where: { $0.key == key }) { row.body = data }
        else { context.insert(LocalRecord(key: key, body: data)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    public func saveAtomically(_ records: [String: Data]) throws {
        do { try context.transaction {
            for (key, body) in records {
                let wanted = key
                var query = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key == wanted }); query.fetchLimit = 1
                if let row = try context.fetch(query).first { row.body = body } else { context.insert(LocalRecord(key: key, body: body)) }
            }
            try context.save()
        } } catch { context.rollback(); throw error }
    }
    public func cache(_ snapshot: DomainSnapshot) throws {
        var records: [(String, String, Data)] = []
        for item in snapshot.profiles.values { records.append(("profile:\(item.id)", "profile", try CanonicalJSON.encode(item))) }
        for item in snapshot.tasks.values { records.append(("task:\(item.id)", "task", try CanonicalJSON.encode(item))) }
        for item in snapshot.rules.values { records.append(("rule:\(item.id)", "recurrenceRule", try CanonicalJSON.encode(item))) }
        for item in snapshot.grants.values { records.append(("grant:\(item.id)", "wishGrant", try CanonicalJSON.encode(item))) }
        for item in snapshot.wishes.values { records.append(("wish:\(item.id)", "wishItem", try CanonicalJSON.encode(item))) }
        for item in snapshot.adjustments { records.append(("adjustment:\(item.id)", "grantAdjustment", try CanonicalJSON.encode(item))) }
        for item in snapshot.mediaAssets.values { records.append(("media:\(item.id)", "mediaAsset", try CanonicalJSON.encode(item))) }
        for item in snapshot.gifts.values { records.append(("gift:\(item.id)", "loveGift", try CanonicalJSON.encode(item))) }
        let prior = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<EntityRecord>()).map { ($0.key, $0) })
        for (key, type, data) in records {
            if let row = prior[key] { if row.body != data { row.body = data } }
            else { context.insert(EntityRecord(key: key, entityType: type, body: data)) }
        }
        try context.save()
    }
}
public enum RepositoryError: LocalizedError {
    case reusedOperationId
    public var errorDescription: String? { Copy.text("copy.status.492c7e8b42f9") }
}
