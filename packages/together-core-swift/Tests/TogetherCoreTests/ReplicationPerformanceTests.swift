import Darwin
import Foundation
import Testing

@testable import TogetherCore

private actor SyntheticHistoryGenerator {
  let fixture: ReplicationFixture
  var next = 0
  init(_ fixture: ReplicationFixture) { self.fixture = fixture }
  func batch(_ count: Int) throws -> [SignedOperation] {
    var result: [SignedOperation] = []
    for _ in 0..<count {
      let index = next
      next += 1
      result.append(
        try fixture.operation(
          fixture.a, id: StableID.make("Synthetic-performance-op-\(index)"),
          clock: Int64(index + 1), entity: StableID.make("Synthetic-performance-task-\(index)")))
    }
    return result
  }
}
@Suite("Replication large-history acceptance", .serialized) struct ReplicationPerformanceTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_REPLICATION_PERF"] == "1"))
  @MainActor func hundredThousandSignedFactsBoundedPaginationRecoveryAndProjection() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "together-performance-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let count = 100_000
    let clock = ContinuousClock()
    let started = clock.now
    let f = try ReplicationFixture()
    let trust = try SpaceAuthorization(genesis: f.genesis)
    let generator = SyntheticHistoryGenerator(f)
    let a = try AuthorizedReplicationStore(
      repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: f.a,
      authorization: trust)
    let b = try AuthorizedReplicationStore(
      repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: f.b,
      authorization: trust)
    try await a.restore()
    try await b.restore()
    var slowestBatch: Double = 0
    for offset in stride(from: 0, to: count, by: 32) {
      let start = clock.now
      let ops = try await generator.batch(min(32, count - offset))
      _ = try await a.appendBatch(ops)
      slowestBatch = max(slowestBatch, seconds(start.duration(to: clock.now)))
      if offset % 10_000 < 32 { print("PERF_GENERATED \(offset+ops.count)") }
      await Task.yield()
    }
    let writeEnd = clock.now
    let wire = ReplicationTestWire()
    let al = DeviceAcknowledgementLedger(repository: a.repository, index: a.index, identity: f.a)
    let bl = DeviceAcknowledgementLedger(repository: b.repository, index: b.index, identity: f.b)
    let ab = PagedReplicationSession(
      store: a, ledger: al, remote: f.b.descriptor, send: { try await wire.send($0, to: 1) })
    let ba = PagedReplicationSession(
      store: b, ledger: bl, remote: f.a.descriptor, send: { try await wire.send($0, to: 0) })
    try await ab.synchronize()
    try await ba.synchronize()
    try await pump(wire, [ab, ba], limit: 100_000)
    let syncEnd = clock.now
    let cp = try await a.index.checkpoint()
    let other = try await b.index.checkpoint()
    #expect(cp.count == count && cp == other)
    #expect(try b.repository.operationCount() == count)
    #expect(await wire.largestFrame < 248192)
    #expect(await wire.largestQueue < 16)
    let reopened = try TogetherRepository(url: root.appendingPathComponent("b.store"))
    let recovery = try AuthorizedReplicationStore(
      repository: reopened, identity: f.b, authorization: trust)
    try await recovery.restore()
    #expect(try await recovery.index.checkpoint() == cp)
    let input = try await recovery.projectionInput()
    let context = input.context
    let log = input.operations
    let projected = await Task.detached { OperationProjector.replay(log, context: context) }.value
    #expect(projected.tasks.count == count && projected.conflicts.isEmpty)
    let events = await Task.detached { OperationProjector.changes(log, context: context) }.value
    #expect(events.count == count)
    let deltaStart = clock.now
    let first = try #require(log.first)
    let patch = try f.a.sign(
      SyncOperation(
        deviceId: f.a.descriptor.deviceId, actorId: f.a.descriptor.userId,
        entityId: first.operation.entityId, entityType: .task, operationType: .patch,
        lamportClock: Int64(count + 1), payload: ["title": .string("Synthetic scoped correction")]))
    let deltaContext = try ReplicaContext(
      local: f.a.descriptor, authorization: trust,
      acceptedContent: Dictionary(
        uniqueKeysWithValues: (log + [patch]).map { ($0.id, try InventoryEntry($0).contentDigest) })
    )
    let corrected = await Task.detached {
      ScopedProjection.replay(
        existing: projected, log: log + [patch], additions: [patch], context: deltaContext)
    }.value
    let cacheDelta = try ProjectionCacheDelta.rows(
      before: projected, after: corrected, additions: [patch])
    let deltaEnd = clock.now
    let oracle = await Task.detached {
      OperationProjector.replay(log + [patch], context: deltaContext)
    }.value
    #expect(corrected == oracle && cacheDelta.count == 1)
    let done = clock.now
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
      "synthetic": true, "count": count, "writeSeconds": seconds(started.duration(to: writeEnd)),
      "syncSeconds": seconds(writeEnd.duration(to: syncEnd)),
      "recoveryProjectionReviewSeconds": seconds(syncEnd.duration(to: deltaStart)),
      "scopedCorrectionAndContextSeconds": seconds(deltaStart.duration(to: deltaEnd)),
      "fullCorrectionOracleSeconds": seconds(deltaEnd.duration(to: done)),
      "scopedCacheRows": cacheDelta.count, "totalSeconds": seconds(started.duration(to: done)),
      "slowestLocalBatchSeconds": slowestBatch, "maxEncodedFrameBytes": await wire.largestFrame,
      "maxQueuedFrames": await wire.largestQueue, "frames": await wire.frames,
      "processPeakRSSBytes": usage.ru_maxrss, "databaseSchemaChanged": false,
      "realCrossWiFi": "NOT RUN",
    ]
    let bytes = try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: bytes, as: UTF8.self))
    if let path = ProcessInfo.processInfo.environment["TOGETHER_PERF_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: path))
    }
  }
}
private func seconds(_ duration: Duration) -> Double {
  let value = duration.components
  return Double(value.seconds) + Double(value.attoseconds) / 1e18
}
