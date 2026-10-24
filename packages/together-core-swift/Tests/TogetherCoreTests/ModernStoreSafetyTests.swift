import Foundation
import SwiftData
import CoreData
import CSQLite
import Testing
@testable import TogetherCore

@Suite("Existing modern stores are never guessed or downgraded") @MainActor struct ModernStoreSafetyTests {
    private func root() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Together-modern-safety-\(UUID())")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
    private func durableFiles(_ url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        // Shared-memory read marks are volatile SQLite synchronization state;
        // the database and WAL contain the durable data being protected.
        for suffix in ["", "-wal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) { result[suffix] = try Data(contentsOf: file) }
        }
        return result
    }
    @Test func automaticAndForcedModernRejectUnrelatedSQLiteWithoutWriting() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("foreign.sqlite"), textFile = root.appendingPathComponent("foreign.txt")
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE foreign_notes(value TEXT NOT NULL); INSERT INTO foreign_notes VALUES('SYNTHETIC_FOREIGN_SENTINEL');", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        try Data("SYNTHETIC_NON_SQLITE".utf8).write(to: textFile)
        for url in [file, textFile] {
            let bytes = try durableFiles(url)
            for selection in [RepositoryBackendSelection.automatic, .swiftData] {
                #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: url, backend: selection) }
                #expect(try durableFiles(url) == bytes)
            }
        }
    }
    @Test func unknownSameNamedFutureModelIsRejectedBeforeDataCanBeDowngraded() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        for version in [1, 2] {
            let url = root.appendingPathComponent("future-\(version).store")
            let schema = Schema([FutureStoreProbe.OperationRecord.self, FutureStoreProbe.LocalRecord.self, FutureStoreProbe.EntityRecord.self], version: .init(version, 0, 0))
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let future = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(future); context.autosaveEnabled = false
            context.insert(FutureStoreProbe.OperationRecord(operationId: "SYNTHETIC_FUTURE", body: Data([1, 2, 3]), futureField: "MUST_REMAIN"))
            try context.save()
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url, options: [NSReadOnlyPersistentStoreOption: true])
            let keys = Set((metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]).keys)
            #expect(keys == Set(["OperationRecord", "LocalRecord", "EntityRecord"]))
            let bytes = try durableFiles(url)
            for selection in [RepositoryBackendSelection.automatic, .swiftData] {
                #expect(throws: (any Error).self) { try TogetherRepository(url: url, backend: selection) }
                #expect(try durableFiles(url) == bytes)
            }
            #expect(try context.fetch(FetchDescriptor<FutureStoreProbe.OperationRecord>()).first?.futureField == "MUST_REMAIN")
        }
    }
    @Test func originalUnversionedSchemaRetainsSignedFactsAndIdentity() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("unversioned.store"), f = try ReplicationFixture(), op = try f.operation(f.a)
        let schema = Schema([OperationRecord.self, LocalRecord.self, EntityRecord.self])
        let original = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(original); context.autosaveEnabled = false
        context.insert(try OperationRecord(operation: op))
        let identity = LocalIdentityMetadata(deviceId: f.a.descriptor.deviceId, userId: f.a.descriptor.userId, spaceId: f.context.spaceId)
        let bytes = try CanonicalJSON.encode(identity)
        context.insert(LocalRecord(key: "local-identity", body: bytes)); try context.save()
        let reopened = try TogetherRepository(url: url)
        #expect(reopened.backendKind == .swiftData)
        #expect(try reopened.operationPage().map(\.bytes) == [CanonicalJSON.encode(op)])
        #expect(try reopened.localBytes(keys: ["local-identity"]).first?.bytes == bytes)
        #expect(try reopened.load(LocalIdentityMetadata.self, key: "local-identity")?.deviceId == identity.deviceId)
    }
}

@available(macOS 14, iOS 17, *)
private enum FutureStoreProbe {
    @Model final class OperationRecord {
        @Attribute(.unique) var operationId: String
        var body: Data
        var futureField: String
        init(operationId: String, body: Data, futureField: String) { self.operationId = operationId; self.body = body; self.futureField = futureField }
    }
    @Model final class LocalRecord {
        @Attribute(.unique) var key: String
        var body: Data
        init(key: String, body: Data) { self.key = key; self.body = body }
    }
    @Model final class EntityRecord {
        @Attribute(.unique) var key: String
        var entityType: String
        var body: Data
        init(key: String, entityType: String, body: Data) { self.key = key; self.entityType = entityType; self.body = body }
    }
}
