import Foundation
import Darwin
import CSQLite

/// Some OS releases change SQLite journaling while CoreData reads metadata,
/// despite its read-only option. Give that API an isolated consistent snapshot;
/// only an actual READONLY SQLite connection or a checked read-only FD reads
/// the original store here.
@MainActor enum ReadOnlyStoreSnapshot {
    static func withSnapshot<Value>(
        of sourceURL: URL,
        busyBudget: CompatibilityDuration = .milliseconds(250),
        maximumDuration: CompatibilityDuration = .seconds(30),
        _ inspect: (URL) throws -> Value
    ) throws -> Value {
        guard try SQLiteRepositoryBackend.ownedStoreExists(at: sourceURL) else {
            throw RepositoryError.unsupportedStorage
        }
        // SQLite can consult these files as part of opening the database.
        // Never accept a caller-controlled link or somebody else's sidecar.
        for suffix in ["-wal", "-shm", "-journal"] {
            _ = try SQLiteRepositoryBackend.ownedStoreExists(at: URL(fileURLWithPath: sourceURL.path + suffix))
        }
        let sourcePath = try canonicalParentPath(sourceURL)
        let temporaryParent = FileManager.default.temporaryDirectory
        guard let parentBytes = Darwin.realpath(temporaryParent.path, nil) else {
            throw RepositoryError.unsupportedStorage
        }
        let parent = String(cString: parentBytes); free(parentBytes)
        let directory = URL(fileURLWithPath: parent, isDirectory: true)
            .appendingPathComponent("Together-metadata-\(UUID().uuidString)", isDirectory: true)
        guard Darwin.mkdir(directory.path, 0o700) == 0 else { throw RepositoryError.unsupportedStorage }
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = directory.appendingPathComponent("metadata.sqlite")
        let descriptor = Darwin.open(snapshot.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw RepositoryError.unsupportedStorage }
        Darwin.close(descriptor)

        do {
            try copyStore(sourcePath: sourcePath, to: snapshot, busyBudget: busyBudget, maximumDuration: maximumDuration)
        } catch SnapshotReadError.missingWAL {
            // Apple's read-only VFS cannot open a checkpointed WAL database
            // after its sidecars are gone. Copy that stable main file through a
            // read-only FD; never enable immutable mode and ignore a real WAL.
            try copyStableMainWithoutWAL(sourcePath: sourcePath, to: snapshot, maximumDuration: maximumDuration)
        }
        try normalizeSnapshot(snapshot)
        return try inspect(snapshot)
    }

    private static func copyStore(sourcePath: String, to snapshot: URL, busyBudget: CompatibilityDuration, maximumDuration: CompatibilityDuration) throws {
        var source: OpaquePointer?
        let sourceResult = sqlite3_open_v2(sourcePath, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard sourceResult == SQLITE_OK, let source else {
            if let source { sqlite3_close(source) }
            if sourceResult & 0xff == SQLITE_CANTOPEN { throw SnapshotReadError.missingWAL }
            throw RepositoryError.unsupportedStorage
        }
        defer { sqlite3_close(source) }
        guard sqlite3_db_readonly(source, "main") == 1 else { throw RepositoryError.unsupportedStorage }
        // A just-released CoreData store can still be finishing its WAL close
        // on another queue. Apply the existing bounded budget to the first
        // read as well as backup steps; never restart an already-begun BEGIN.
        let readWait = max(0, min(busyBudget, maximumDuration).nanoseconds / 1_000_000)
        guard sqlite3_busy_timeout(source, Int32(clamping: readWait)) == SQLITE_OK else {
            throw RepositoryError.unsupportedStorage
        }
        // A read transaction pins one snapshot even if another process writes.
        let begun = sqlite3_exec(source, "BEGIN; PRAGMA schema_version;", nil, nil, nil)
        guard begun == SQLITE_OK else {
            if begun & 0xff == SQLITE_CANTOPEN { throw SnapshotReadError.missingWAL }
            throw RepositoryError.unsupportedStorage
        }
        defer { sqlite3_exec(source, "ROLLBACK", nil, nil, nil) }
        // Backup owns its existing explicit monotonic retry budget. Do not
        // nest this connection-level wait inside each subsequent backup step.
        guard sqlite3_busy_timeout(source, 0) == SQLITE_OK else { throw RepositoryError.unsupportedStorage }

        var destination: OpaquePointer?
        let destinationResult = sqlite3_open_v2(try canonicalParentPath(snapshot), &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard destinationResult == SQLITE_OK, let destination else {
            if let destination { sqlite3_close(destination) }
            throw RepositoryError.unsupportedStorage
        }
        do {
            // Copy a bounded page batch rather than loading the whole log into
            // memory. All writes, including journaling changes, target our file.
            guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
                throw RepositoryError.unsupportedStorage
            }
            let start = CompatibilityClock.now
            let busyDeadline = start.advanced(by: busyBudget)
            let deadline = start.advanced(by: maximumDuration)
            var result: Int32 = SQLITE_OK
            repeat {
                guard CompatibilityClock.now < deadline else {
                    sqlite3_backup_finish(backup)
                    throw RepositoryError.unsupportedStorage
                }
                result = sqlite3_backup_step(backup, 128)
                if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                    guard CompatibilityClock.now < busyDeadline else { break }
                    sqlite3_sleep(5)
                }
            } while result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED
            let finished = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finished == SQLITE_OK else { throw RepositoryError.unsupportedStorage }
        } catch {
            sqlite3_close(destination)
            throw error
        }
        guard sqlite3_close(destination) == SQLITE_OK else { throw RepositoryError.unsupportedStorage }
    }

    private static func normalizeSnapshot(_ snapshot: URL) throws {
        // Backup copies the source page header, including WAL mode. Reopen
        // only the private copy to normalize it into a self-contained database;
        // CoreData may then choose its own journaling without touching source.
        var normalized: OpaquePointer?
        let opened = sqlite3_open_v2(try canonicalParentPath(snapshot), &normalized, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard opened == SQLITE_OK, let normalized else {
            if let normalized { sqlite3_close(normalized) }
            throw RepositoryError.unsupportedStorage
        }
        defer { sqlite3_close(normalized) }
        guard sqlite3_exec(normalized, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw RepositoryError.unsupportedStorage
        }
    }

    private enum SnapshotReadError: Error { case missingWAL }

    private static func copyStableMainWithoutWAL(sourcePath: String, to snapshot: URL, maximumDuration: CompatibilityDuration) throws {
        guard try missingSidecars(sourcePath) else { throw RepositoryError.unsupportedStorage }
        let source = Darwin.open(sourcePath, O_RDONLY | O_NOFOLLOW)
        guard source >= 0 else { throw RepositoryError.unsupportedStorage }
        defer { Darwin.close(source) }
        var before = stat(), named = stat()
        guard Darwin.fstat(source, &before) == 0, Darwin.lstat(sourcePath, &named) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_uid == getuid(),
              sameFileState(before, named) else { throw RepositoryError.unsupportedStorage }
        var header = [UInt8](repeating: 0, count: 72)
        let readHeader = header.withUnsafeMutableBytes { Darwin.pread(source, $0.baseAddress, $0.count, 0) }
        guard readHeader == header.count,
              header.prefix(16) == Array("SQLite format 3\0".utf8)[...], header[18] == 2, header[19] == 2 else {
            throw RepositoryError.unsupportedStorage
        }
        let destination = Darwin.open(try canonicalParentPath(snapshot), O_WRONLY | O_TRUNC | O_NOFOLLOW)
        guard destination >= 0 else { throw RepositoryError.unsupportedStorage }
        defer { Darwin.close(destination) }
        let deadline = CompatibilityClock.now.advanced(by: maximumDuration)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            guard CompatibilityClock.now < deadline, try missingSidecars(sourcePath) else {
                throw RepositoryError.unsupportedStorage
            }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(source, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw RepositoryError.unsupportedStorage }
            if count == 0 { break }
            var written = 0
            while written < count {
                guard CompatibilityClock.now < deadline else { throw RepositoryError.unsupportedStorage }
                let result = buffer.withUnsafeBytes { Darwin.write(destination, $0.baseAddress!.advanced(by: written), count - written) }
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { throw RepositoryError.unsupportedStorage }
                written += result
            }
        }
        var after = stat(), finalName = stat(), copied = stat()
        guard Darwin.fstat(source, &after) == 0, Darwin.lstat(sourcePath, &finalName) == 0,
              Darwin.fstat(destination, &copied) == 0, copied.st_size == before.st_size,
              sameFileState(before, after), sameFileState(before, finalName), try missingSidecars(sourcePath) else {
            throw RepositoryError.unsupportedStorage
        }
        // This guards ordinary concurrent writers, not an adversarial process
        // with the same UID deliberately hiding mutations between observations.
    }

    private static func missingSidecars(_ path: String) throws -> Bool {
        for suffix in ["-wal", "-journal"] {
            var value = stat()
            if Darwin.lstat(path + suffix, &value) == 0 { return false }
            guard errno == ENOENT else { throw RepositoryError.unsupportedStorage }
        }
        return true
    }

    private static func sameFileState(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
          && a.st_mode == b.st_mode && a.st_uid == b.st_uid
          && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
          && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }

    private static func canonicalParentPath(_ url: URL) throws -> String {
        // Resolve the OS /var alias, never the untrusted final component.
        guard let bytes = Darwin.realpath(url.deletingLastPathComponent().path, nil) else {
            throw RepositoryError.unsupportedStorage
        }
        defer { free(bytes) }
        return String(cString: bytes) + "/" + url.lastPathComponent
    }
}
