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
    public let storageURL: URL?
    public let container: ModelContainer
    public private(set) var operationRevision: UInt64 = 0
    public init(url: URL? = nil, inMemory: Bool = false) throws {
        storageURL = url
        let schema = Schema([OperationRecord.self, LocalRecord.self, EntityRecord.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        container = try ModelContainer(for: schema, configurations: [config])
    }
    private func makeContext() -> ModelContext { let value = ModelContext(container); value.autosaveEnabled = false; return value }
    public func allOperations() throws -> [SignedOperation] { let context = makeContext(); return try context.fetch(FetchDescriptor<OperationRecord>()).map { try CanonicalJSON.decode(SignedOperation.self, from: $0.body) } }
    private func additions(_ operations: [SignedOperation], context: ModelContext) throws -> [SignedOperation] {
        // Query only the incoming unique index keys. Never fetch/decode the
        // entire historical log just to append a small network batch.
        let ids = operations.map { $0.id.uuidString }
        var existing: [String: Data] = [:]
        for start in stride(from: 0, to: ids.count, by: 256) {
            let keys = Array(ids[start..<min(start + 256, ids.count)])
            let query = FetchDescriptor<OperationRecord>(predicate: #Predicate { keys.contains($0.operationId) })
            for row in try context.fetch(query) { existing[row.operationId] = row.body }
        }
        var additions: [SignedOperation] = []
        for operation in operations {
            let bytes = try CanonicalJSON.encode(operation), key = operation.id.uuidString
            if let prior = existing[key] {
                guard prior == bytes else { throw RepositoryError.reusedOperationId }
            } else { additions.append(operation); existing[key] = bytes }
        }
        return additions
    }
    public func insert(_ operations: [SignedOperation]) throws {
        let context = makeContext()
        let additions = try additions(operations, context: context)
        do {
            for operation in additions { context.insert(try OperationRecord(operation: operation)) }
            try context.save()
            if !additions.isEmpty { operationRevision &+= 1 }
        } catch { context.rollback(); throw error }
    }
    public func commitGift(_ operations: [SignedOperation], giftId: UUID, slot: String, replicationRecords: [String: Data] = [:]) throws {
        let context = makeContext()
        let key = "gift-slot:\(slot)"
        do {
            try context.transaction {
                guard try load(UUID.self, key: key, context: context) == nil else { throw TogetherError.invalid(Copy.text("copy.error.90bff42b45e2")) }
                context.insert(LocalRecord(key: key, body: try CanonicalJSON.encode(giftId)))
                for operation in try additions(operations, context: context) { context.insert(try OperationRecord(operation: operation)) }
                for (key,body) in replicationRecords {
                    let wanted=key
                    var query=FetchDescriptor<LocalRecord>(predicate:#Predicate{$0.key==wanted});query.fetchLimit=1
                    if let row=try context.fetch(query).first {row.body=body} else {context.insert(LocalRecord(key:key,body:body))}
                }
                try context.save()
            }
            operationRevision &+= 1
        } catch { context.rollback(); throw error }
    }
    public func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try load(type, key: key, context: makeContext())
    }
    private func load<T: Decodable>(_ type: T.Type, key: String, context: ModelContext) throws -> T? {
        let wanted = key
        var descriptor = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key == wanted }); descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map { try CanonicalJSON.decode(type, from: $0.body) }
    }
    public func save<T: Encodable>(_ value: T, key: String) throws {
        let context = makeContext()
        let data = try CanonicalJSON.encode(value)
        let wanted = key
        var query = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key == wanted }); query.fetchLimit = 1
        if let row = try context.fetch(query).first { row.body = data }
        else { context.insert(LocalRecord(key: key, body: data)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    public func operationCount() throws -> Int { let context = makeContext(); return try context.fetchCount(FetchDescriptor<OperationRecord>()) }
    /// Bounded keyset scan over the existing unique UUID index. No schema change.
    public func operationPage(after: String? = nil, limit: Int = 128) throws -> [StoredOperationBytes] {
        let context = makeContext()
        guard (1...256).contains(limit) else { throw ReplicationError.bounds }
        let cursor = after ?? ""
        var query = FetchDescriptor<OperationRecord>(predicate: #Predicate { $0.operationId > cursor },
                                                     sortBy: [SortDescriptor(\.operationId, comparator: .lexical)])
        query.fetchLimit = limit
        return try context.fetch(query).map { StoredOperationBytes(id: $0.operationId, bytes: $0.body) }
    }
    public func operationBytes(ids: [UUID]) throws -> [StoredOperationBytes] {
        let context = makeContext()
        guard ids.count <= 256 else { throw ReplicationError.bounds }
        let keys = ids.map(\.uuidString)
        let query = FetchDescriptor<OperationRecord>(predicate: #Predicate { keys.contains($0.operationId) })
        return try context.fetch(query).map { StoredOperationBytes(id: $0.operationId, bytes: $0.body) }
    }
    /// Facts and their replication witness commit together; a failure rolls
    /// back both. Caller verifies authorization/signatures before this boundary.
    public func commitReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String] = []) throws {
        try commitReplication(operations, records: records, removing: removing, context: makeContext())
    }
    private func commitReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String], context: ModelContext) throws {
        let additions = try additions(operations, context: context)
        do {
            let rows = try additions.map(OperationRecord.init(operation:))
            let prior = try localRows(keys: Array(Set(records.keys).union(removing)), context: context)
            for (key, body) in records {
                if let row = prior[key] { if row.body != body { row.body = body } }
                else { context.insert(LocalRecord(key: key, body: body)) }
            }
            for row in rows { context.insert(row) }
            for key in removing where records[key] == nil { if let row = prior[key] { context.delete(row) } }
            try context.save()
            if !rows.isEmpty { operationRevision &+= 1 }
        } catch { context.rollback(); throw error }
    }
    public func commitCertified(_ operations:[SignedOperation],records:[String:Data],removing:[String],headKey:String,expectedHead:DeviceFrontier,authorizationDigest:String)throws {
        let context = makeContext()
        let actual=try load(DeviceFrontier.self,key:headKey,context:context) ?? DeviceFrontier()
        guard actual==expectedHead,let archive=try load(AuthorizationArchive.self,key:"replication4/authorization",context:context),try SpaceAuthorization.restore(archive).digest==authorizationDigest else{throw ReplicationError.staleAuthorization}
        try commitReplication(operations,records:records,removing:removing,context:context)
    }
    public func localBytes(keys:[String]) throws -> [StoredOperationBytes] {
        let context = makeContext()
        guard keys.count<=256 else {throw ReplicationError.bounds}
        return try context.fetch(FetchDescriptor<LocalRecord>(predicate:#Predicate{keys.contains($0.key)})).map{StoredOperationBytes(id:$0.key,bytes:$0.body)}
    }
    public func localPage(prefix: String, after: String? = nil, limit: Int = 128) throws -> [StoredOperationBytes] {
        let context = makeContext()
        guard (1...256).contains(limit) else { throw ReplicationError.bounds }
        let lower = after ?? prefix, upper = prefix + "~"
        var query = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key > lower && $0.key < upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical)])
        query.fetchLimit = limit
        return try context.fetch(query).map { StoredOperationBytes(id: $0.key, bytes: $0.body) }
    }
    public func localAtOrBefore(prefix: String, suffix: String) throws -> StoredOperationBytes? {
        let context = makeContext(), upper = prefix + suffix
        var query = FetchDescriptor<LocalRecord>(predicate: #Predicate { $0.key >= prefix && $0.key <= upper }, sortBy: [SortDescriptor(\.key, comparator: .lexical, order: .reverse)])
        query.fetchLimit = 1
        return try context.fetch(query).first.map { StoredOperationBytes(id: $0.key, bytes: $0.body) }
    }
    private func localRows(keys: [String], context: ModelContext) throws -> [String: LocalRecord] {
        var result: [String: LocalRecord] = [:]
        for offset in stride(from: 0, to: keys.count, by: 256) {
            let batch = Array(keys[offset..<min(offset+256,keys.count)])
            for row in try context.fetch(FetchDescriptor<LocalRecord>(predicate: #Predicate { batch.contains($0.key) })) { result[row.key] = row }
        }
        return result
    }
    public func saveAtomically(_ records: [String: Data]) throws {
        let context = makeContext()
        do { try context.transaction {
            let prior = try localRows(keys: Array(records.keys), context: context)
            for (key, body) in records {
                if let row = prior[key] { if row.body != body { row.body = body } }
                else { context.insert(LocalRecord(key: key, body: body)) }
            }
            try context.save()
        } } catch { context.rollback(); throw error }
    }
    public func cacheRows(_ rows:[ProjectionCacheRow],expectedRevision:UInt64)throws -> Bool {
        let context = makeContext()
        guard operationRevision==expectedRevision else{return false}
        guard rows.count<=256 else{throw ReplicationError.bounds}
        do {
            let keys=rows.map(\.key),prior=Dictionary(uniqueKeysWithValues:try context.fetch(FetchDescriptor<EntityRecord>(predicate:#Predicate{keys.contains($0.key)})).map{($0.key,$0)})
            for row in rows {
                if let body=row.bytes {if let old=prior[row.key]{old.body=body;old.entityType=row.type}else{context.insert(EntityRecord(key:row.key,entityType:row.type,body:body))}}
                else if let old=prior[row.key]{context.delete(old)}
            }
            try context.save();return true
        }catch{context.rollback();throw error}
    }
    public func cache(_ snapshot: DomainSnapshot) throws {
        let context = makeContext()
        var records: [(String, String, Data)] = []
        for item in snapshot.profiles.values { records.append(("profile:\(item.id)", "profile", try CanonicalJSON.encode(item))) }
        for item in snapshot.tasks.values { records.append(("task:\(item.id)", "task", try CanonicalJSON.encode(item))) }
        for item in snapshot.rules.values { records.append(("rule:\(item.id)", "recurrenceRule", try CanonicalJSON.encode(item))) }
        for item in snapshot.grants.values { records.append(("grant:\(item.id)", "wishGrant", try CanonicalJSON.encode(item))) }
        for item in snapshot.wishes.values { records.append(("wish:\(item.id)", "wishItem", try CanonicalJSON.encode(item))) }
        for item in snapshot.adjustments { records.append(("adjustment:\(item.id)", "grantAdjustment", try CanonicalJSON.encode(item))) }
        for item in snapshot.mediaAssets.values { records.append(("media:\(item.id)", "mediaAsset", try CanonicalJSON.encode(item))) }
        for item in snapshot.gifts.values { records.append(("gift:\(item.id)", "loveGift", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.reserves.values { records.append(("reserve:\(item.id)", "reserveEntry", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.expenses.values { records.append(("expense:\(item.id)", "expense", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.dateEvents.values { records.append(("dateEvent:\(item.id)", "dateEvent", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.bills.values { records.append(("bill:\(item.id)", "recurringBill", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.revisions.values { records.append(("billRevision:\(item.id)", "billRevision", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.occurrenceOverrides.values { records.append(("billOccurrence:\(item.id)", "billOccurrence", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.settings.values { records.append(("financeSettings:\(item.id)", "financeSettings", try CanonicalJSON.encode(item))) }
        for item in snapshot.finance.paymentMethods.values { records.append(("paymentMethod:\(item.id)", "paymentMethod", try CanonicalJSON.encode(item))) }
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
