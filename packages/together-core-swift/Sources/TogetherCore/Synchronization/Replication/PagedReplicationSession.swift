import CryptoKit
import Foundation

public enum ReplicationFrame: Codable, Sendable {
  case syncHint(UUID)
  case inventoryStart(UUID)
  case inventoryPage(UUID, InventoryPage)
  case inventoryNext(UUID, UUID)
  case operationRequest(UUID, UUID, [InventoryEntry])
  case operationBatch(UUID, UUID, [ReplicationRecord])
  case inventoryFinished(UUID, InventoryCheckpoint)
  case acknowledgement(SignedAcknowledgement)
}

/// One authenticated device pair. Each direction has a separate bounded scan,
/// one outstanding batch and explicit flow control. Reconnection starts a new
/// scan over durable facts/staging, never replays writes from an in-memory queue.
public actor PagedReplicationSession {
  public let store: AuthorizedReplicationStore
  public let ledger: DeviceAcknowledgementLedger
  public let remote: DeviceDescriptor
  private let send: @Sendable (ReplicationFrame) async throws -> Void
  private let onConverged: (@Sendable () async -> Void)?
  private var active = true
  private var inbound: UUID?
  private var source: (pass: UUID, snapshot: InventorySnapshot, next: UUID?)?
  private var expectedAfter: UUID?
  private var remoteCheckpoint: InventoryCheckpoint?
  private var pending: [InventoryEntry] = []
  private var pageNext: UUID?
  private var requested: (id: UUID, entries: [InventoryEntry])?
  private var incomingHash = SHA256()
  private var receivedCount = 0
  private var finishedInbound = false
  private var repeatAfterPass = false
  public private(set) var completedPasses = 0
  public private(set) var transferringOperations: Set<UUID> = []
  public init(
    store: AuthorizedReplicationStore, ledger: DeviceAcknowledgementLedger,
    remote: DeviceDescriptor,
    send: @escaping @Sendable (ReplicationFrame) async throws -> Void,
    onConverged: (@Sendable () async -> Void)? = nil
  ) {
    self.store = store
    self.ledger = ledger
    self.remote = remote
    self.send = send
    self.onConverged = onConverged
  }
  public func invalidate() async {
    active = false
    inbound = nil
    if let source { try? await store.index.releaseSnapshot(source.snapshot) }
    source = nil
    pending = []
    requested = nil
  }
  public func synchronize() async throws {
    guard active, await store.isActive(remote) else { return }
    // A local write must also wake the peer's pull direction. Dropping a
    // hint during an active pass would miss a later source snapshot.
    try await send(.syncHint(UUID()))
    try await beginPull()
  }
  private func beginPull() async throws {
    guard active else { return }
    guard inbound == nil else {
      repeatAfterPass = true
      return
    }
    let id = UUID()
    inbound = id
    expectedAfter = nil
    remoteCheckpoint = nil
    receivedCount = 0
    finishedInbound = false
    incomingHash = SHA256()
    incomingHash.update(data: Data("Together-Inventory-4\n".utf8))
    try await send(.inventoryStart(id))
  }
  public func receive(_ frame: ReplicationFrame) async throws {
    guard active, await store.isActive(remote) else { throw ReplicationError.unauthorized }
    guard try CanonicalJSON.encode(frame).count <= ReplicationProtocol.maximumBatchBytes + 8192
    else { throw ReplicationError.bounds }
    switch frame {
    case .syncHint: try await beginPull()
    case .inventoryStart(let id):
      if let source { try await store.index.releaseSnapshot(source.snapshot) }
      let snapshot = try await store.index.acquireSnapshot()
      let page = try await store.index.page(after: nil, snapshot: snapshot)
      source = (id, snapshot, page.next)
      try await send(.inventoryPage(id, page))
    case .inventoryNext(let id, let cursor):
      guard let source, source.pass == id, source.next == cursor else {
        throw ReplicationError.invalidPage
      }
      let page = try await store.index.page(after: cursor, snapshot: source.snapshot)
      self.source = (id, source.snapshot, page.next)
      try await send(.inventoryPage(id, page))
    case .inventoryPage(let id, let page):
      guard id == inbound, !finishedInbound, requested == nil, pending.isEmpty,
        page.after == expectedAfter
      else { throw ReplicationError.invalidPage }
      try page.validate()
      if let expected = remoteCheckpoint {
        guard expected == page.checkpoint else { throw ReplicationError.inventoryChanged }
      }
      remoteCheckpoint = page.checkpoint
      for entry in page.entries { incomingHash.update(data: ReplicationHash.inventoryLine(entry)) }
      receivedCount += page.entries.count
      guard receivedCount <= page.checkpoint.count else { throw ReplicationError.invalidPage }
      pageNext = page.next
      pending = try await store.missing(page.entries)
      try await advance()
    case .operationRequest(let pass, let request, let entries):
      guard let source, source.pass == pass, !entries.isEmpty, entries.count <= 32 else {
        throw ReplicationError.invalidPage
      }
      let records = try await store.records(entries)
      transferringOperations = Set(records.map { $0.operation.id })
      defer { transferringOperations = [] }
      try await send(.operationBatch(pass, request, records))
    case .operationBatch(let pass, let request, let records):
      guard pass == inbound, let outstanding = requested, outstanding.id == request,
        !records.isEmpty,
        records.count <= outstanding.entries.count
      else { throw ReplicationError.invalidPage }
      let expected = Array(outstanding.entries.prefix(records.count))
      let actual = try records.map { try InventoryEntry($0) }
      guard expected == actual else { throw ReplicationError.contentCollision }
      try await store.receive(records)
      let trust = await store.authorization
      if let receipt = try await ledger.receipt(entries: actual, trust: trust) {
        try await send(.acknowledgement(receipt))
      }
      pending.removeFirst(records.count)
      requested = nil
      try await advance()
    case .inventoryFinished(let id, let checkpoint):
      guard let source, source.pass == id, source.next == nil,
        source.snapshot.checkpoint == checkpoint
      else { throw ReplicationError.invalidPage }
      try await store.index.releaseSnapshot(source.snapshot)
      self.source = nil
      try await maybeConverged(checkpoint)
    case .acknowledgement(let receipt):
      let accepted = try await ledger.accept(receipt, from: remote, trust: store.authorization)
      if accepted, receipt.body.checkpoint != nil {
        completedPasses += 1
        await onConverged?()
      }
    }
  }
  private func advance() async throws {
    guard let id = inbound else { throw ReplicationError.invalidPage }
    if !pending.isEmpty {
      let request = UUID()
      let entries = Array(pending.prefix(32))
      requested = (request, entries)
      try await send(.operationRequest(id, request, entries))
      return
    }
    if let next = pageNext {
      expectedAfter = next
      pageNext = nil
      try await send(.inventoryNext(id, next))
      return
    }
    guard let checkpoint = remoteCheckpoint, receivedCount == checkpoint.count,
      ReplicationHash.hex(incomingHash.finalize()) == checkpoint.digest
    else { throw ReplicationError.invalidPage }
    finishedInbound = true
    inbound = nil
    try await send(.inventoryFinished(id, checkpoint))
    try await maybeConverged(checkpoint)
    if repeatAfterPass {
      repeatAfterPass = false
      try await beginPull()
    }
  }
  private func maybeConverged(_ checkpoint: InventoryCheckpoint) async throws {
    let trust = await store.authorization
    if let receipt = try await ledger.convergenceReceipt(for: checkpoint, trust: trust) {
      try await send(.acknowledgement(receipt))
    } else if inbound == nil {
      try await beginPull()
    }
  }
}
