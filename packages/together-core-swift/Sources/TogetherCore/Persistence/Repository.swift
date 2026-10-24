import Foundation
import SwiftData

public struct LocalIdentityMetadata: Codable, Sendable {
    public var deviceId: UUID
    public var userId: UUID
    public var spaceId: UUID
    public init(deviceId: UUID = UUID(), userId: UUID = UUID(), spaceId: UUID = UUID()) {
        self.deviceId = deviceId; self.userId = userId; self.spaceId = spaceId
    }
}

public enum RepositoryBackendSelection: Sendable { case automatic, swiftData, legacySQLite }

@MainActor protocol RepositoryBackend: AnyObject {
    var operationRevision: UInt64 { get }
    func allOperations() throws -> [SignedOperation]
    func insert(_ operations: [SignedOperation]) throws
    func commitGift(_ operations: [SignedOperation], giftId: UUID, slot: String, replicationRecords: [String: Data]) throws
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T?
    func save<T: Encodable>(_ value: T, key: String) throws
    func operationCount() throws -> Int
    func operationPage(after: String?, limit: Int) throws -> [StoredOperationBytes]
    func operationBytes(ids: [UUID]) throws -> [StoredOperationBytes]
    func commitReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String]) throws
    func commitCertified(_ operations: [SignedOperation], records: [String: Data], removing: [String], headKey: String, expectedHead: DeviceFrontier, authorizationDigest: String) throws
    func localBytes(keys: [String]) throws -> [StoredOperationBytes]
    func localPage(prefix: String, after: String?, limit: Int) throws -> [StoredOperationBytes]
    func localAtOrBefore(prefix: String, suffix: String) throws -> StoredOperationBytes?
    func saveAtomically(_ records: [String: Data]) throws
    func cacheRows(_ rows: [ProjectionCacheRow], expectedRevision: UInt64) throws -> Bool
    func cache(_ snapshot: DomainSnapshot) throws
}

/// Storage selection never rewrites an existing store. SwiftData keeps its exact
/// historical @Model classes; older systems use the bundled SQLite library.
/// A marked legacy SQLite store remains on that backend after an OS upgrade.
@MainActor public final class TogetherRepository {
    public let storageURL: URL?
    public let backendKind: RepositoryBackendSelection
    private let backend: any RepositoryBackend
    public var operationRevision: UInt64 { backend.operationRevision }

    @available(macOS 14, iOS 17, *)
    public var swiftDataContainer: ModelContainer? { (backend as? SwiftDataRepositoryBackend)?.container }
    /// Compatibility accessor for the existing SwiftData migration harness.
    /// Legacy callers use the repository methods, never a SwiftData context.
    @available(macOS 14, iOS 17, *)
    public var container: ModelContainer {
        guard let container = swiftDataContainer else { preconditionFailure("This repository uses legacy SQLite storage") }
        return container
    }

    public init(url: URL? = nil, inMemory: Bool = false, backend selection: RepositoryBackendSelection = .automatic) throws {
        storageURL = url
        let existing = try url.map { try SQLiteRepositoryBackend.ownedStoreExists(at: $0) } ?? false
        let legacy = try url.map { try SQLiteRepositoryBackend.isLegacyStore(at: $0) } ?? false
        if selection == .legacySQLite || (selection == .automatic && legacy) {
            backend = try SQLiteRepositoryBackend(url: url, inMemory: inMemory)
            backendKind = .legacySQLite
        } else if #available(macOS 14, iOS 17, *) {
            // Never ask SwiftData to reinterpret a legacy database, even when
            // a caller explicitly requests the newer implementation.
            guard !legacy else { throw RepositoryError.unsupportedStorage }
            backend = try SwiftDataRepositoryBackend(url: url, inMemory: inMemory)
            backendKind = .swiftData
        } else {
            guard selection != .swiftData, !existing else { throw RepositoryError.unsupportedStorage }
            backend = try SQLiteRepositoryBackend(url: url, inMemory: inMemory)
            backendKind = .legacySQLite
        }
    }

    public func allOperations() throws -> [SignedOperation] { try backend.allOperations() }
    public func insert(_ operations: [SignedOperation]) throws { try backend.insert(operations) }
    public func commitGift(_ operations: [SignedOperation], giftId: UUID, slot: String, replicationRecords: [String: Data] = [:]) throws {
        try backend.commitGift(operations, giftId: giftId, slot: slot, replicationRecords: replicationRecords)
    }
    public func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? { try backend.load(type, key: key) }
    public func save<T: Encodable>(_ value: T, key: String) throws { try backend.save(value, key: key) }
    public func operationCount() throws -> Int { try backend.operationCount() }
    public func operationPage(after: String? = nil, limit: Int = 128) throws -> [StoredOperationBytes] { try backend.operationPage(after: after, limit: limit) }
    public func operationBytes(ids: [UUID]) throws -> [StoredOperationBytes] { try backend.operationBytes(ids: ids) }
    public func commitReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String] = []) throws {
        try backend.commitReplication(operations, records: records, removing: removing)
    }
    public func commitCertified(_ operations: [SignedOperation], records: [String: Data], removing: [String], headKey: String, expectedHead: DeviceFrontier, authorizationDigest: String) throws {
        try backend.commitCertified(operations, records: records, removing: removing, headKey: headKey, expectedHead: expectedHead, authorizationDigest: authorizationDigest)
    }
    public func localBytes(keys: [String]) throws -> [StoredOperationBytes] { try backend.localBytes(keys: keys) }
    public func localPage(prefix: String, after: String? = nil, limit: Int = 128) throws -> [StoredOperationBytes] { try backend.localPage(prefix: prefix, after: after, limit: limit) }
    public func localAtOrBefore(prefix: String, suffix: String) throws -> StoredOperationBytes? { try backend.localAtOrBefore(prefix: prefix, suffix: suffix) }
    public func saveAtomically(_ records: [String: Data]) throws { try backend.saveAtomically(records) }
    public func cacheRows(_ rows: [ProjectionCacheRow], expectedRevision: UInt64) throws -> Bool { try backend.cacheRows(rows, expectedRevision: expectedRevision) }
    public func cache(_ snapshot: DomainSnapshot) throws { try backend.cache(snapshot) }
}

public enum RepositoryError: LocalizedError, Equatable, Sendable {
    case reusedOperationId
    case unsupportedStorage
    case invalidStorage
    case sqliteFailure(Int32)
    public var errorDescription: String? {
        switch self {
        case .reusedOperationId: return Copy.text("copy.status.492c7e8b42f9")
        case .unsupportedStorage: return Copy.text("storage.error.unsupported")
        case .invalidStorage: return Copy.text("presentation.error.fileDamaged")
        case .sqliteFailure: return Copy.text("presentation.error.retry")
        }
    }
}
