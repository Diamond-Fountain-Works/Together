import Foundation
import CSQLite
import Testing
@testable import TogetherCore

@Suite("Read-only snapshot initialization lock recovery") @MainActor
struct ReadOnlyStoreSnapshotLockTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-snapshot-lock-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent("synthetic.sqlite")
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        try #require(sqlite3_exec(handle, "PRAGMA journal_mode=DELETE; CREATE TABLE fixture(value TEXT); INSERT INTO fixture VALUES('SYNTHETIC_SNAPSHOT_VALUE');", nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func transientInitializationLockUsesExistingBudgetAndKeepsSourceBytes() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try Data(contentsOf: url)
        let writer = SnapshotExclusiveWriter(path: url.path)
        defer { writer.release(); _ = writer.waitUntilFinished() }
        try #require(writer.waitUntilReady() && writer.error == nil)
        // Release from a separate queue: the synchronous read must wait for an
        // actual SQLite exclusive lock, not retry a mocked failure or sleep in
        // production. The existing 250ms budget remains unchanged.
        writer.releaseAfter(milliseconds: 75)
        let start = CompatibilityClock.now
        let value = try ReadOnlyStoreSnapshot.withSnapshot(of: url) { copy in
            var handle: OpaquePointer?
            try #require(sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
            defer { sqlite3_close(handle) }
            var row: OpaquePointer?
            try #require(sqlite3_prepare_v2(handle, "SELECT value FROM fixture", -1, &row, nil) == SQLITE_OK)
            defer { sqlite3_finalize(row) }
            try #require(sqlite3_step(row) == SQLITE_ROW)
            return String(cString: try #require(sqlite3_column_text(row, 0)))
        }
        #expect(value == "SYNTHETIC_SNAPSHOT_VALUE")
        #expect(start.duration(to: CompatibilityClock.now) >= .milliseconds(50))
        #expect(writer.waitUntilFinished() && writer.error == nil)
        #expect(try Data(contentsOf: url) == before)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
    }

    @Test func persistentInitializationLockRespectsMaximumDurationWithoutWriting() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = try Data(contentsOf: url)
        let writer = SnapshotExclusiveWriter(path: url.path)
        defer { writer.release(); _ = writer.waitUntilFinished() }
        try #require(writer.waitUntilReady() && writer.error == nil)
        let start = CompatibilityClock.now
        #expect(throws: RepositoryError.unsupportedStorage) {
            try ReadOnlyStoreSnapshot.withSnapshot(of: url, busyBudget: .seconds(2), maximumDuration: .milliseconds(20)) { _ in }
        }
        #expect(start.duration(to: CompatibilityClock.now) < .seconds(1))
        #expect(try Data(contentsOf: url) == before)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
        writer.release()
        #expect(writer.waitUntilFinished() && writer.error == nil)
    }
}

/// Own the SQLite connection entirely on one worker queue. Only semaphores and
/// an NSLock-protected diagnostic cross threads; no database handle is shared.
private final class SnapshotExclusiveWriter: @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private let unlock = DispatchSemaphore(value: 0)
    private let done = DispatchGroup()
    private let resultLock = NSLock()
    private var storedError: String?
    var error: String? { resultLock.lock(); defer { resultLock.unlock() }; return storedError }

    init(path: String) {
        done.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var handle: OpaquePointer?
            var signalled = false
            defer {
                if let handle { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil); sqlite3_close(handle) }
                if !signalled { ready.signal() }
                done.leave()
            }
            guard sqlite3_open(path, &handle) == SQLITE_OK,
                  sqlite3_exec(handle, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK else {
                fail("Synthetic writer could not hold the exclusive lock"); return
            }
            signalled = true
            ready.signal()
            if unlock.wait(timeout: .now() + 5) != .success { fail("Synthetic writer release timed out") }
        }
    }
    func waitUntilReady() -> Bool { ready.wait(timeout: .now() + 2) == .success }
    func release() { unlock.signal() }
    func releaseAfter(milliseconds: Int) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [self] in release() }
    }
    func waitUntilFinished() -> Bool { done.wait(timeout: .now() + 2) == .success }
    private func fail(_ message: String) { resultLock.lock(); storedError = message; resultLock.unlock() }
}
