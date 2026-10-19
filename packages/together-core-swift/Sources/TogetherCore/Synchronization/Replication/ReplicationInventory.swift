import CryptoKit
import Foundation

public enum ReplicationError: LocalizedError, Equatable, Sendable {
  case bounds, inventoryChanged, contentCollision, invalidPage, unauthorized, invalidSignature
  case staleAuthorization, authorizationFork, missingPredecessor, revoked, invalidReceipt,
    incompatibleProtocol
  public var errorDescription: String? {
    Copy.text(self == .incompatibleProtocol ? "copy.error.eb6f75e7a5e4" : "copy.error.76ef9b5cd8a8")
  }
}
public enum ReplicationProtocol {
  public static let version = 4
  public static let inventoryPageSize = 128
  public static let operationBatchSize = 32
  public static let maximumBatchBytes = 240_000
  public static let relayAPIVersion = 2
}
public struct StoredOperationBytes: Sendable {
  public let id: String
  public let bytes: Data
  public init(id: String, bytes: Data) {
    self.id = id
    self.bytes = bytes
  }
}
public struct InventoryEntry: Codable, Equatable, Hashable, Sendable {
  public let operationId: UUID
  public let contentDigest: String
  public let certificationDigest: String?
  public init(operationId: UUID, contentDigest: String, certificationDigest: String? = nil) {
    self.operationId = operationId
    self.contentDigest = contentDigest
    self.certificationDigest = certificationDigest
  }
  public init(_ record: ReplicationRecord) throws {
    self.init(
      operationId: record.operation.id,
      contentDigest: ReplicationHash.digest(try CanonicalJSON.encode(record.operation)),
      certificationDigest: try {
        if case .authorized(let proof) = record { return try proof.digest }
        return nil
      }())
  }
  public init(_ operation: SignedOperation) throws {
    self.init(
      operationId: operation.id,
      contentDigest: ReplicationHash.digest(try CanonicalJSON.encode(operation)))
  }
  public var isValid: Bool {
    ReplicationHash.valid(contentDigest) && (certificationDigest.map(ReplicationHash.valid) ?? true)
  }
}
public enum ReplicationHash {
  public static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var result: [UInt8] = []; result.reserveCapacity(bytes.underestimatedCount * 2)
    for byte in bytes { result.append(digits[Int(byte >> 4)]); result.append(digits[Int(byte & 15)]) }
    return String(decoding: result, as: UTF8.self)
  }
  public static func digest(_ bytes: Data) -> String {
    hex(SHA256.hash(data: bytes))
  }
  public static func valid(_ text: String) -> Bool {
    text.utf8.count == 64
      && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  public static func inventoryLine(_ entry: InventoryEntry) -> Data {
    Data(
      (entry.operationId.uuidString + ":" + entry.contentDigest
        + (entry.certificationDigest.map { ":" + $0 } ?? "") + "\n").utf8)
  }
  public static func inventory(_ entries: [InventoryEntry]) throws -> InventoryCheckpoint {
    let sorted = entries.sorted { $0.operationId.uuidString < $1.operationId.uuidString }
    guard Set(sorted.map(\.operationId)).count == sorted.count, sorted.allSatisfy(\.isValid) else {
      throw ReplicationError.invalidPage
    }
    var hash = SHA256()
    hash.update(data: Data("Together-Inventory-4\n".utf8))
    for entry in sorted { hash.update(data: inventoryLine(entry)) }
    return InventoryCheckpoint(
      count: sorted.count, digest: ReplicationHash.hex(hash.finalize()))
  }
}
public struct InventoryCheckpoint: Codable, Equatable, Sendable {
  public let count: Int
  public let digest: String
  public init(count: Int, digest: String) {
    self.count = count
    self.digest = digest
  }
}
public struct InventoryPage: Codable, Equatable, Sendable {
  public let checkpoint: InventoryCheckpoint
  public let after: UUID?
  public let entries: [InventoryEntry]
  public let next: UUID?
  public init(checkpoint: InventoryCheckpoint, after: UUID?, entries: [InventoryEntry], next: UUID?)
  {
    self.checkpoint = checkpoint
    self.after = after
    self.entries = entries
    self.next = next
  }
  public func validate() throws {
    guard entries.count <= ReplicationProtocol.inventoryPageSize, checkpoint.count >= 0,
      ReplicationHash.valid(checkpoint.digest), entries.allSatisfy(\.isValid),
      Set(entries.map(\.operationId)).count == entries.count,
      entries.map({ $0.operationId.uuidString })
        == entries.map({ $0.operationId.uuidString }).sorted(),
      after.map({ cursor in entries.allSatisfy { cursor.uuidString < $0.operationId.uuidString } })
        ?? true,
      next == nil || (next == entries.last?.operationId && !entries.isEmpty)
    else { throw ReplicationError.invalidPage }
  }
}
public struct InventorySnapshot: Codable, Equatable, Sendable {
  public let id: UUID
  public let checkpoint: InventoryCheckpoint
}

/// Bounded database reads happen on the owning context; hashing/decoding runs
/// on this actor. The full operation list never becomes a wire inventory frame.
private enum InventoryProcess { static let id = UUID().uuidString }
public actor OperationInventoryIndex {
  private let repository: TogetherRepository
  private var prepared: (revision: UInt64, visibility: UInt64, snapshot: InventorySnapshot)?
  private var visibility: UInt64 = 0
  private var excluded: Set<UUID> = []
  private var preparing: Task<InventorySnapshot, Error>?
  private var retained: [UUID: Int] = [:]
  private var cleanedPreviousProcess = false
  public init(repository: TogetherRepository) { self.repository = repository }
  public func checkpoint() async throws -> InventoryCheckpoint {
    try await snapshot().checkpoint
  }
  public func snapshot() async throws -> InventorySnapshot {
    // A legitimate concurrent import/local write can invalidate an optimistic
    // scan. Rebuild a bounded number of times; never acknowledge a mixed view
    // or turn this expected race into a dead transport session.
    for attempt in 0..<8 {
      do { return try await snapshotAttempt() }
      catch ReplicationError.inventoryChanged {
        try Task.checkCancellation()
        guard attempt < 7 else { throw ReplicationError.inventoryChanged }
        try await Task.sleep(for: .milliseconds(1 << attempt))
      }
    }
    throw ReplicationError.inventoryChanged
  }
  private func snapshotAttempt() async throws -> InventorySnapshot {
    let revision = await repository.operationRevision
    if let prepared, prepared.revision == revision, prepared.visibility == visibility {
      return prepared.snapshot
    }
    if let preparing { return try await preparing.value }
    let scope = visibility
    let task = Task { try await self.prepareSnapshot(revision: revision, visibility: scope) }
    preparing = task
    do {
      let value = try await task.value
      preparing = nil
      let previous = prepared?.snapshot.id
      prepared = (revision, scope, value)
      if let previous, retained[previous] == nil { try await discard(previous) }
      return value
    } catch {
      preparing = nil
      throw error
    }
  }
  public func exclude(_ ids: Set<UUID>) {
    if ids != excluded {
      excluded = ids
      visibility &+= 1
    }
  }
  public func acquireSnapshot() async throws -> InventorySnapshot {
    let value = try await snapshot()
    retained[value.id, default: 0] += 1
    return value
  }
  public func releaseSnapshot(_ snapshot: InventorySnapshot) async throws {
    if let count = retained[snapshot.id], count > 1 {
      retained[snapshot.id] = count - 1
    } else {
      retained.removeValue(forKey: snapshot.id)
      if prepared?.snapshot.id != snapshot.id { try await discard(snapshot.id) }
    }
  }
  private func discard(_ id: UUID) async throws {
    let prefix = "replication4/inventory/\(InventoryProcess.id)/\(id)/"
    while true {
      let rows = try await repository.localPage(prefix: prefix, limit: 256)
      if rows.isEmpty { return }
      try await repository.commitReplication([], records: [:], removing: rows.map(\.id))
    }
  }
  private func pageKey(_ id: UUID, _ after: UUID?) -> String {
    "replication4/inventory/\(InventoryProcess.id)/\(id)/" + (after?.uuidString ?? "start")
  }
  private func prepareSnapshot(revision: UInt64, visibility: UInt64) async throws
    -> InventorySnapshot
  {
    if !cleanedPreviousProcess {
      cleanedPreviousProcess = true
      var cursor: String?
      repeat {
        let rows = try await repository.localPage(
          prefix: "replication4/inventory/", after: cursor, limit: 256)
        let orphaned = rows.filter {
          !$0.id.hasPrefix("replication4/inventory/" + InventoryProcess.id + "/")
        }
        try await repository.commitReplication([], records: [:], removing: orphaned.map(\.id))
        cursor = rows.count == 256 ? rows.last?.id : nil
      } while cursor != nil
    }
    let snapshotId = UUID()
    var after: String?
    var count = 0
    var hash = SHA256()
    var pageCursor: UUID?
    var pageEntries: [InventoryEntry] = []
    hash.update(data: Data("Together-Inventory-4\n".utf8))
    while true {
      let rows = try await repository.operationPage(after: after)
      for entry in try await entries(for: rows) {
        let id = entry.operationId
        if excluded.contains(id) { continue }
        pageEntries.append(entry)
        hash.update(data: ReplicationHash.inventoryLine(entry))
        count += 1
        if pageEntries.count == ReplicationProtocol.inventoryPageSize {
          try await repository.save(pageEntries, key: pageKey(snapshotId, pageCursor))
          pageCursor = pageEntries.last?.operationId
          pageEntries = []
        }
      }
      after = rows.last?.id
      if rows.count < ReplicationProtocol.inventoryPageSize { break }
      await Task.yield()
    }
    try await repository.save(pageEntries, key: pageKey(snapshotId, pageCursor))
    guard revision == (await repository.operationRevision), visibility == self.visibility else {
      try await discard(snapshotId)
      throw ReplicationError.inventoryChanged
    }
    let result = InventoryCheckpoint(
      count: count, digest: ReplicationHash.hex(hash.finalize()))
    return InventorySnapshot(id: snapshotId, checkpoint: result)
  }
  public func page(after: UUID?, checkpoint: InventoryCheckpoint) async throws -> InventoryPage {
    let frozen = try await snapshot()
    guard frozen.checkpoint == checkpoint else { throw ReplicationError.inventoryChanged }
    return try await page(after: after, snapshot: frozen)
  }
  public func page(after: UUID?, snapshot: InventorySnapshot) async throws -> InventoryPage {
    guard
      let entries = try await repository.load(
        [InventoryEntry].self, key: pageKey(snapshot.id, after))
    else { throw ReplicationError.invalidPage }
    let page = InventoryPage(
      checkpoint: snapshot.checkpoint, after: after, entries: entries,
      next: entries.count == ReplicationProtocol.inventoryPageSize ? entries.last?.operationId : nil
    )
    try page.validate()
    return page
  }
  public func missing(_ entries: [InventoryEntry]) async throws -> [InventoryEntry] {
    guard entries.count <= ReplicationProtocol.inventoryPageSize, entries.allSatisfy(\.isValid),
      Set(entries.map(\.operationId)).count == entries.count
    else { throw ReplicationError.invalidPage }
    let existing = try await repository.operationBytes(ids: entries.map(\.operationId))
    let byId = Dictionary(
      uniqueKeysWithValues: try await self.entries(for: existing).map { ($0.operationId, $0) })
    for entry in entries {
      if let existing = byId[entry.operationId], existing != entry {
        throw ReplicationError.contentCollision
      }
    }
    return entries.filter { byId[$0.operationId] == nil || excluded.contains($0.operationId) }
  }
  public func entry(for id: UUID) async throws -> InventoryEntry {
    guard !excluded.contains(id) else { throw ReplicationError.unauthorized }
    guard let row = try await repository.operationBytes(ids: [id]).first else {
      throw ReplicationError.invalidPage
    }
    let value = try await entries(for: [row])[0]
    guard !excluded.contains(id) else { throw ReplicationError.unauthorized }
    return value
  }
  private func entries(for rows: [StoredOperationBytes]) async throws -> [InventoryEntry] {
    let prefix = "replication4/proof/"
    let proofs = try await repository.localBytes(keys: rows.map { prefix + $0.id })
    let byId = Dictionary(
      uniqueKeysWithValues: proofs.map { ($0.id, ReplicationHash.digest($0.bytes)) })
    return try rows.map { row in
      guard let id = UUID(uuidString: row.id) else { throw ReplicationError.invalidPage }
      return InventoryEntry(
        operationId: id, contentDigest: ReplicationHash.digest(row.bytes),
        certificationDigest: byId[prefix + row.id])
    }
  }
  public func operations(_ requested: [InventoryEntry]) async throws -> [SignedOperation] {
    guard requested.count <= ReplicationProtocol.operationBatchSize,
      requested.allSatisfy(\.isValid),
      Set(requested.map(\.operationId)).count == requested.count
    else { throw ReplicationError.bounds }
    guard try await missing(requested).isEmpty else { throw ReplicationError.contentCollision }
    let rows = try await repository.operationBytes(ids: requested.map(\.operationId))
    let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.bytes) })
    var result: [SignedOperation] = []
    var total = 0
    for entry in requested {
      guard let bytes = byId[entry.operationId.uuidString],
        ReplicationHash.digest(bytes) == entry.contentDigest
      else { throw ReplicationError.contentCollision }
      if total + bytes.count > ReplicationProtocol.maximumBatchBytes { break }
      result.append(try CanonicalJSON.decode(SignedOperation.self, from: bytes))
      total += bytes.count
    }
    guard !result.isEmpty || requested.isEmpty else { throw ReplicationError.bounds }
    guard requested.allSatisfy({ !excluded.contains($0.operationId) }) else {
      throw ReplicationError.unauthorized
    }
    return result
  }
}
