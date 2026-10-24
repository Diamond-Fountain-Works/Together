import Foundation
import Darwin
import CSQLite

/// SQLite is supplied by the operating system. Its database contains the same
/// canonical signed-operation bytes and local records as the modern backend;
/// the on-disk tables are an implementation detail, never the wire format.
@MainActor final class SQLiteRepositoryBackend: RepositoryBackend {
    private static let applicationID: UInt32 = 0x54475448
    private static let schemaVersion: UInt32 = 1
    private let connection: SQLiteConnection
    private var db: OpaquePointer { connection.handle }
    private(set) var operationRevision: UInt64 = 0

    static func ownedStoreExists(at url: URL) throws -> Bool {
        var info = stat()
        let result = url.path.withCString { Darwin.lstat($0, &info) }
        if result != 0 {
            if errno == ENOENT { return false }
            throw RepositoryError.invalidStorage
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid() else { throw RepositoryError.invalidStorage }
        return true
    }

    static func isLegacyStore(at url: URL) throws -> Bool {
        guard try ownedStoreExists(at: url) else { return false }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let header = try file.read(upToCount: 72) ?? Data()
        guard header.count == 72, header.prefix(16) == Data("SQLite format 3\0".utf8) else { return false }
        func number(_ start: Int) -> UInt32 { header[start..<start+4].reduce(0) { ($0 << 8) | UInt32($1) } }
        guard number(68) == applicationID else { return false }
        guard number(60) == schemaVersion else { throw RepositoryError.unsupportedStorage }
        return true
    }

    init(url: URL?, inMemory: Bool) throws {
        let existed = try url.map { try Self.ownedStoreExists(at: $0) } ?? false
        if existed { guard try Self.isLegacyStore(at: url!) else { throw RepositoryError.unsupportedStorage } }
        guard url != nil || inMemory else { throw RepositoryError.unsupportedStorage }
        if let url, !existed {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Reserve our own new file exclusively and owner-only before
            // SQLite can create journals or WAL sidecars. A racing foreign
            // file is rejected, never initialized as an empty Together store.
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw RepositoryError.sqliteFailure(errno) }
            Darwin.close(descriptor)
        }
        // SQLite's NOFOLLOW checks all path components, including the OS's
        // /var alias. Resolve that alias after reserving a non-linked leaf.
        connection = try SQLiteConnection(path: url?.resolvingSymlinksInPath().path ?? ":memory:")
        sqlite3_busy_timeout(db, 5_000)
        if existed {
            guard try scalar("PRAGMA application_id") == Int64(Self.applicationID),
                  try scalar("PRAGMA user_version") == Int64(Self.schemaVersion) else { throw RepositoryError.unsupportedStorage }
            // Verify the known table shape without changing an existing store.
            for table in ["operations", "locals", "entities"] {
                let expected = table == "entities" ? ["id", "type", "body"] : ["id", "body"]
                var names: [String] = [], types: [String] = [], required: [Int32] = [], primary: [Int32] = []
                try query("PRAGMA table_info(\(table))") {
                    names.append(text($0, 1)); types.append(text($0, 2).uppercased())
                    required.append(sqlite3_column_int($0, 3)); primary.append(sqlite3_column_int($0, 5))
                }
                let expectedTypes = table == "entities" ? ["TEXT", "TEXT", "BLOB"] : ["TEXT", "BLOB"]
                guard names == expected, types == expectedTypes, required.allSatisfy({ $0 == 1 }),
                      primary == [1] + Array(repeating: 0, count: expected.count - 1) else { throw RepositoryError.invalidStorage }
            }
        } else {
            try transaction {
                try execute("PRAGMA application_id=\(Self.applicationID)")
                try execute("PRAGMA user_version=\(Self.schemaVersion)")
                try execute("CREATE TABLE operations(id TEXT PRIMARY KEY COLLATE BINARY NOT NULL, body BLOB NOT NULL) WITHOUT ROWID")
                try execute("CREATE TABLE locals(id TEXT PRIMARY KEY COLLATE BINARY NOT NULL, body BLOB NOT NULL) WITHOUT ROWID")
                try execute("CREATE TABLE entities(id TEXT PRIMARY KEY COLLATE BINARY NOT NULL, type TEXT NOT NULL, body BLOB NOT NULL) WITHOUT ROWID")
            }
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        // Ensure the format marker is visible in the main header even while a
        // connection remains open; reopening must not misidentify a WAL store.
        if !existed, url != nil { try execute("PRAGMA wal_checkpoint(FULL)") }
    }

    func allOperations() throws -> [SignedOperation] {
        var values: [SignedOperation] = []
        try query("SELECT body FROM operations ORDER BY id COLLATE BINARY") { values.append(try CanonicalJSON.decode(SignedOperation.self, from: blob($0, 0))) }
        return values
    }
    func insert(_ operations: [SignedOperation]) throws {
        let count = try transaction { try append(operations) }
        if count > 0 { operationRevision &+= 1 }
    }
    func commitGift(_ operations: [SignedOperation], giftId: UUID, slot: String, replicationRecords: [String: Data]) throws {
        try transaction {
            let key = "gift-slot:\(slot)"
            guard try localBody(key) == nil else { throw TogetherError.invalid(Copy.text("copy.error.90bff42b45e2")) }
            try setLocal(key, body: CanonicalJSON.encode(giftId))
            _ = try append(operations)
            for (key, body) in replicationRecords { try setLocal(key, body: body) }
        }
        operationRevision &+= 1
    }
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try localBody(key).map { try CanonicalJSON.decode(type, from: $0) }
    }
    func save<T: Encodable>(_ value: T, key: String) throws {
        try transaction { try setLocal(key, body: CanonicalJSON.encode(value)) }
    }
    func operationCount() throws -> Int { Int(try scalar("SELECT count(*) FROM operations")) }
    func operationPage(after: String?, limit: Int) throws -> [StoredOperationBytes] {
        guard (1...256).contains(limit) else { throw ReplicationError.bounds }
        return try rows("SELECT id,body FROM operations WHERE id>? ORDER BY id COLLATE BINARY LIMIT ?", [.text(after ?? ""), .integer(limit)])
    }
    func operationBytes(ids: [UUID]) throws -> [StoredOperationBytes] {
        guard ids.count <= 256 else { throw ReplicationError.bounds }
        guard !ids.isEmpty else { return [] }
        return try rows("SELECT id,body FROM operations WHERE id IN (\(marks(ids.count)))", ids.map { .text($0.uuidString) })
    }
    func commitReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String]) throws {
        let count = try transaction { try writeReplication(operations, records: records, removing: removing) }
        if count > 0 { operationRevision &+= 1 }
    }
    func commitCertified(_ operations: [SignedOperation], records: [String: Data], removing: [String], headKey: String, expectedHead: DeviceFrontier, authorizationDigest: String) throws {
        let count = try transaction {
            let actual = try load(DeviceFrontier.self, key: headKey) ?? DeviceFrontier()
            guard actual == expectedHead, let archive = try load(AuthorizationArchive.self, key: "replication4/authorization"),
                  try SpaceAuthorization.restore(archive).digest == authorizationDigest else { throw ReplicationError.staleAuthorization }
            return try writeReplication(operations, records: records, removing: removing)
        }
        if count > 0 { operationRevision &+= 1 }
    }
    func localBytes(keys: [String]) throws -> [StoredOperationBytes] {
        guard keys.count <= 256 else { throw ReplicationError.bounds }
        guard !keys.isEmpty else { return [] }
        return try rows("SELECT id,body FROM locals WHERE id IN (\(marks(keys.count)))", keys.map { .text($0) })
    }
    func localPage(prefix: String, after: String?, limit: Int) throws -> [StoredOperationBytes] {
        guard (1...256).contains(limit) else { throw ReplicationError.bounds }
        return try rows("SELECT id,body FROM locals WHERE id>? AND id<? ORDER BY id COLLATE BINARY LIMIT ?", [.text(after ?? prefix), .text(prefix + "~"), .integer(limit)])
    }
    func localAtOrBefore(prefix: String, suffix: String) throws -> StoredOperationBytes? {
        try rows("SELECT id,body FROM locals WHERE id>=? AND id<=? ORDER BY id COLLATE BINARY DESC LIMIT 1", [.text(prefix), .text(prefix + suffix)]).first
    }
    func saveAtomically(_ records: [String: Data]) throws {
        try transaction { for (key, body) in records { try setLocal(key, body: body) } }
    }
    func cacheRows(_ rows: [ProjectionCacheRow], expectedRevision: UInt64) throws -> Bool {
        guard rows.count <= 256 else { throw ReplicationError.bounds }
        guard operationRevision == expectedRevision else { return false }
        try transaction {
            for row in rows {
                if let body = row.bytes { try execute("INSERT OR REPLACE INTO entities(id,type,body) VALUES(?,?,?)", [.text(row.key), .text(row.type), .blob(body)]) }
                else { try execute("DELETE FROM entities WHERE id=?", [.text(row.key)]) }
            }
        }
        return true
    }
    func cache(_ snapshot: DomainSnapshot) throws {
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
        try transaction { for (key, type, body) in records { try execute("INSERT OR REPLACE INTO entities(id,type,body) VALUES(?,?,?)", [.text(key), .text(type), .blob(body)]) } }
    }

    private func append(_ operations: [SignedOperation]) throws -> Int {
        var count = 0
        for operation in operations {
            let id = operation.id.uuidString, bytes = try CanonicalJSON.encode(operation)
            let prior = try rows("SELECT id,body FROM operations WHERE id=?", [.text(id)]).first
            if let prior { guard prior.bytes == bytes else { throw RepositoryError.reusedOperationId } }
            else { try execute("INSERT INTO operations(id,body) VALUES(?,?)", [.text(id), .blob(bytes)]); count += 1 }
        }
        return count
    }
    private func writeReplication(_ operations: [SignedOperation], records: [String: Data], removing: [String]) throws -> Int {
        let count = try append(operations)
        for (key, body) in records { try setLocal(key, body: body) }
        for key in removing where records[key] == nil { try execute("DELETE FROM locals WHERE id=?", [.text(key)]) }
        return count
    }
    private func localBody(_ key: String) throws -> Data? { try rows("SELECT id,body FROM locals WHERE id=?", [.text(key)]).first?.bytes }
    private func setLocal(_ key: String, body: Data) throws { try execute("INSERT OR REPLACE INTO locals(id,body) VALUES(?,?)", [.text(key), .blob(body)]) }
    private func marks(_ count: Int) -> String { Array(repeating: "?", count: count).joined(separator: ",") }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try action(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func scalar(_ sql: String) throws -> Int64 {
        var result: Int64?
        try query(sql) { result = sqlite3_column_int64($0, 0) }
        guard let result else { throw RepositoryError.invalidStorage }
        return result
    }
    private func rows(_ sql: String, _ values: [SQLiteValue] = []) throws -> [StoredOperationBytes] {
        var result: [StoredOperationBytes] = []
        try query(sql, values) { result.append(StoredOperationBytes(id: text($0, 0), bytes: blob($0, 1))) }
        return result
    }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let p = sqlite3_column_text(statement, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }
    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        let size = Int(sqlite3_column_bytes(statement, column))
        guard size > 0, let p = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: p, count: size)
    }
    private func execute(_ sql: String, _ values: [SQLiteValue] = []) throws { try query(sql, values) { _ in } }
    private func query(_ sql: String, _ values: [SQLiteValue] = [], row: (OpaquePointer) throws -> Void) throws {
        var raw: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &raw, nil)
        guard code == SQLITE_OK, let statement = raw else { throw RepositoryError.sqliteFailure(code) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1), bound: Int32
            switch value {
            case .text(let text): bound = text.withCString { sqlite3_bind_text(statement, index, $0, Int32(text.utf8.count), transient) }
            case .blob(let data):
                if data.isEmpty { bound = sqlite3_bind_zeroblob(statement, index, 0) }
                else { bound = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) } }
            case .integer(let value): bound = sqlite3_bind_int64(statement, index, Int64(value))
            }
            guard bound == SQLITE_OK else { throw RepositoryError.sqliteFailure(bound) }
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw RepositoryError.sqliteFailure(result) }
            try row(statement)
        }
    }
}

private enum SQLiteValue { case text(String), blob(Data), integer(Int) }
private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer
    init(path: String) throws {
        let databasePath: String
        if path == ":memory:" { databasePath = path }
        else {
            // Foundation intentionally normalizes /private/var back to /var
            // on macOS. SQLite NOFOLLOW requires the actual POSIX path.
            guard let resolved = Darwin.realpath(path, nil) else { throw RepositoryError.sqliteFailure(errno) }
            databasePath = String(cString: resolved); free(resolved)
        }
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard result == SQLITE_OK, let handle else { if let handle { sqlite3_close(handle) }; throw RepositoryError.sqliteFailure(result) }
        self.handle = handle
    }
    deinit { sqlite3_close(handle) }
}
