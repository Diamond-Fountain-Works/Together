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
    private func closedWALCopy(of source: URL, to target: URL) throws {
        try ReadOnlyStoreSnapshot.withSnapshot(of: source) { copy in
            try FileManager.default.copyItem(at: copy, to: target)
        }
        var handle: OpaquePointer?
        try #require(sqlite3_open(target.path, &handle) == SQLITE_OK)
        try #require(sqlite3_exec(handle, "PRAGMA journal_mode=WAL; PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_close(handle) == SQLITE_OK)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: target.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                if suffix == "-wal" { try #require((try Data(contentsOf: sidecar)).isEmpty) }
                try FileManager.default.removeItem(at: sidecar)
            }
        }
    }
    @Test func automaticAndForcedModernRejectUnrelatedSQLiteWithoutWriting() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let textFile = root.appendingPathComponent("foreign.txt")
        try Data("SYNTHETIC_NON_SQLITE".utf8).write(to: textFile)
        for mode in ["DELETE", "WAL"] {
            let file = root.appendingPathComponent("foreign-\(mode).sqlite")
            var db: OpaquePointer?
            #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
            #expect(sqlite3_exec(db, "PRAGMA journal_mode=\(mode); CREATE TABLE foreign_notes(value TEXT NOT NULL); INSERT INTO foreign_notes VALUES('SYNTHETIC_FOREIGN_SENTINEL');", nil, nil, nil) == SQLITE_OK)
            let bytes = try durableFiles(file)
            for selection in [RepositoryBackendSelection.automatic, .swiftData] {
                #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: file, backend: selection) }
                #expect(try durableFiles(file) == bytes)
            }
            #expect(sqlite3_close(db) == SQLITE_OK)
        }
        for mode in ["DELETE", "WAL"] {
            let file = root.appendingPathComponent("closed-\(mode).sqlite")
            var db: OpaquePointer?
            #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
            #expect(sqlite3_exec(db, "PRAGMA journal_mode=\(mode); CREATE TABLE fixture(value TEXT); INSERT INTO fixture VALUES('CLOSED_SENTINEL'); PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK)
            #expect(sqlite3_close(db) == SQLITE_OK)
            // Apple's SQLite can retain empty journals after a clean close.
            // Remove only this fully checkpointed synthetic fixture's sidecars
            // to construct an explicit missing-sidecar input for the test.
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: file.path + suffix)
                if FileManager.default.fileExists(atPath: sidecar.path) {
                    if suffix == "-wal" { try #require((try Data(contentsOf: sidecar)).isEmpty) }
                    try FileManager.default.removeItem(at: sidecar)
                }
            }
            // Start with a file whose original writer has never been touched
            // by metadata inspection. No absent durable sidecar may be created.
            #expect(!FileManager.default.fileExists(atPath: file.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: file.path + "-shm"))
            let before = try durableFiles(file)
            #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: file) }
            #expect(try durableFiles(file) == before)
            #expect(!FileManager.default.fileExists(atPath: file.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: file.path + "-shm"))
        }
        let bytes = try durableFiles(textFile)
        for selection in [RepositoryBackendSelection.automatic, .swiftData] {
            #expect(throws: RepositoryError.unsupportedStorage) { try TogetherRepository(url: textFile, backend: selection) }
            #expect(try durableFiles(textFile) == bytes)
            #expect(!FileManager.default.fileExists(atPath: textFile.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: textFile.path + "-shm"))
        }
    }
    @Test func metadataSnapshotIsPrivateConsistentBoundedAndRemoved() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("wal-source.sqlite")
        var source: OpaquePointer?
        #expect(sqlite3_open(url.path, &source) == SQLITE_OK)
        defer { sqlite3_close(source) }
        #expect(sqlite3_exec(source, "PRAGMA journal_mode=WAL; CREATE TABLE fixture(value TEXT); INSERT INTO fixture VALUES('LATEST_COMMITTED_WAL');", nil, nil, nil) == SQLITE_OK)
        let before = try durableFiles(url)
        var captured: URL?
        try ReadOnlyStoreSnapshot.withSnapshot(of: url) { snapshot in
            captured = snapshot
            let file = try FileManager.default.attributesOfItem(atPath: snapshot.path)
            let directory = try FileManager.default.attributesOfItem(atPath: snapshot.deletingLastPathComponent().path)
            #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect((directory[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            var copy: OpaquePointer?
            #expect(sqlite3_open_v2(snapshot.path, &copy, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
            defer { sqlite3_close(copy) }
            var row: OpaquePointer?
            try #require(sqlite3_prepare_v2(copy, "SELECT value FROM fixture", -1, &row, nil) == SQLITE_OK)
            defer { sqlite3_finalize(row) }
            try #require(sqlite3_step(row) == SQLITE_ROW)
            let bytes = try #require(sqlite3_column_text(row, 0))
            #expect(String(cString: bytes) == "LATEST_COMMITTED_WAL")
        }
        #expect(try durableFiles(url) == before)
        #expect(!FileManager.default.fileExists(atPath: try #require(captured).deletingLastPathComponent().path))
        #expect(sqlite3_exec(source, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE;", nil, nil, nil) == SQLITE_OK)
        let start = CompatibilityClock.now
        #expect(throws: RepositoryError.unsupportedStorage) {
            try ReadOnlyStoreSnapshot.withSnapshot(of: url, busyBudget: .milliseconds(20), maximumDuration: .seconds(1)) { _ in }
        }
        #expect(start.duration(to: CompatibilityClock.now) < .seconds(2))
        #expect(sqlite3_exec(source, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
    }

    @Test func legitimateDeleteModeStoreKeepsOriginalSignedBytesAndIdentity() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("valid-delete.store")
        let sourceURL = root.appendingPathComponent("valid-original.store")
        let f = try ReplicationFixture(), operation = try f.operation(f.a)
        let identity = LocalIdentityMetadata(deviceId: f.a.descriptor.deviceId, userId: f.a.descriptor.userId, spaceId: f.context.spaceId)
        try autoreleasepool {
            let schema = Schema([OperationRecord.self, LocalRecord.self, EntityRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: sourceURL, cloudKitDatabase: .none)])
            let context = ModelContext(container); context.autosaveEnabled = false
            context.insert(try OperationRecord(operation: operation))
            context.insert(LocalRecord(key: "local-identity", body: try CanonicalJSON.encode(identity)))
            try context.save()
        }
        // CoreData can retain its original handles past an autorelease pool.
        // Construct an independent valid DELETE-mode fixture instead of trying
        // to switch journaling underneath those legitimate open readers.
        try ReadOnlyStoreSnapshot.withSnapshot(of: sourceURL) { copy in
            try FileManager.default.copyItem(at: copy, to: url)
        }
        let original = try Data(contentsOf: url)
        #expect(original[18] == 1 && original[19] == 1)
        let reopened = try TogetherRepository(url: url)
        #expect(try reopened.operationPage().map(\.bytes) == [CanonicalJSON.encode(operation)])
        #expect(try reopened.load(LocalIdentityMetadata.self, key: "local-identity")?.deviceId == identity.deviceId)
    }
    @Test func legitimateWALStoreWithoutSidecarsKeepsSignedBytesAndIdentity() throws {
        guard #available(macOS 14, iOS 17, *) else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("valid-open.store"), url = root.appendingPathComponent("valid-closed.store")
        let f = try ReplicationFixture(), operation = try f.operation(f.a)
        let identity = LocalIdentityMetadata(deviceId: f.a.descriptor.deviceId, userId: f.a.descriptor.userId, spaceId: f.context.spaceId)
        let schema = Schema([OperationRecord.self, LocalRecord.self, EntityRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: original, cloudKitDatabase: .none)])
        let context = ModelContext(container); context.autosaveEnabled = false
        context.insert(try OperationRecord(operation: operation))
        context.insert(LocalRecord(key: "local-identity", body: try CanonicalJSON.encode(identity)))
        try context.save()
        try closedWALCopy(of: original, to: url)
        let bytes = try durableFiles(url)
        #expect(bytes[""]?[18] == 2 && bytes[""]?[19] == 2)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: url.path + "-shm"))
        try ReadOnlyStoreSnapshot.withSnapshot(of: url) { snapshot in
            let readonly = ModelConfiguration(schema: schema, url: snapshot, allowsSave: false, cloudKitDatabase: .none)
            _ = try ModelContainer(for: schema, configurations: [readonly])
        }
        #expect(try durableFiles(url) == bytes)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: url.path + "-shm"))
        let reopened = try TogetherRepository(url: url)
        #expect(try reopened.operationPage().map(\.bytes) == [CanonicalJSON.encode(operation)])
        #expect(try reopened.load(LocalIdentityMetadata.self, key: "local-identity")?.deviceId == identity.deviceId)
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
            let closed = root.appendingPathComponent("future-\(version)-closed.store")
            try closedWALCopy(of: url, to: closed)
            for candidate in [url, closed] {
                let bytes = try durableFiles(candidate)
                for selection in [RepositoryBackendSelection.automatic, .swiftData] {
                    #expect(throws: (any Error).self) { try TogetherRepository(url: candidate, backend: selection) }
                    #expect(try durableFiles(candidate) == bytes)
                }
            }
            #expect(!FileManager.default.fileExists(atPath: closed.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: closed.path + "-shm"))
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
