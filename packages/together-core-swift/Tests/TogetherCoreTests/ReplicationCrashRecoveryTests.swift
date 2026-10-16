import Darwin
import Foundation
import Testing

@testable import TogetherCore

private final class CrashProbeBundleLocator: NSObject {}
@Suite("Isolated process-crash recovery", .serialized) struct ReplicationCrashRecoveryTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_CRASH_PROBE"] == "writer"))
  @MainActor func crashWriterProbeOnly() async throws {
    let root = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TOGETHER_CRASH_ROOT"]))
    guard root.lastPathComponent.hasPrefix("together-crash-") else {
      throw ReplicationError.unauthorized
    }
    let metadata = LocalIdentityMetadata()
    let a = try DeviceIdentity.persistent(
      deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
      directory: root.appendingPathComponent("Identity"), needsExistingIdentity: false,
      timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
    let b = try DeviceIdentity(protocolVersion: 3)
    let context = ReplicaContext(local: a.descriptor, peer: b.descriptor)
    let genesis = try SignedSpaceGenesis.sign(
      SpaceGenesisBody(context: context, legacyCheckpoint: ReplicationHash.inventory([])),
      with: [a, b])
    let trust = try SpaceAuthorization(genesis: genesis)
    let repo = try TogetherRepository(url: root.appendingPathComponent("crash.store"))
    try repo.save(metadata, key: "local-identity")
    try repo.save(a.descriptor, key: "test-public-identity")
    try repo.save(
      PairedPeer(descriptor: b.descriptor, host: "127.0.0.1", port: 0), key: "paired-peer")
    try repo.save(
      RelayBinding(
        serviceURL: URL(string: "https://relay.example.test")!, routeId: UUID(),
        peerDeviceId: b.descriptor.deviceId, peerPublicKey: b.descriptor.publicKey,
        localDeviceId: a.descriptor.deviceId), key: "relay-binding")
    func operation(_ id: DeviceIdentity, _ clock: Int64) throws -> SignedOperation {
      try id.sign(
        SyncOperation(
          deviceId: id.descriptor.deviceId, actorId: id.descriptor.userId, entityId: UUID(),
          entityType: .task, operationType: .create, lamportClock: clock,
          payload: [
            "spaceId": .id(context.spaceId), "createdBy": .id(id.descriptor.userId),
            "title": .string("Synthetic crash recovery"),
          ], createdAt: Date(timeIntervalSince1970: 1_791_532_800)))
    }
    let store = try AuthorizedReplicationStore(repository: repo, identity: a, authorization: trust)
    try await store.restore()
    let saved = try await store.append(operation(a, 1))
    let first = try AuthorizedOperation.sign(
      operation(b, 2), identity: b, trust: trust, previous: DeviceFrontier())
    let second = try AuthorizedOperation.sign(
      operation(b, 3), identity: b, trust: trust,
      previous: DeviceFrontier(sequence: 1, digest: first.digest))
    try await store.receive([.authorized(second)])
    try CanonicalJSON.encode(first).write(
      to: root.appendingPathComponent("missing-predecessor.json"))
    let remote = try AuthorizedReplicationStore(
      repository: TogetherRepository(inMemory: true), identity: b, authorization: trust)
    try await remote.restore()
    try await remote.receive([.authorized(saved)])
    let bl = DeviceAcknowledgementLedger(
      repository: remote.repository, index: remote.index, identity: b)
    let al = DeviceAcknowledgementLedger(repository: repo, index: store.index, identity: a)
    let receipt = try #require(
      await bl.receipt(entries: [InventoryEntry(ReplicationRecord.authorized(saved))], trust: trust)
    )
    _ = try await al.accept(receipt, from: b.descriptor, trust: trust)
    // Deliberate SIGKILL: no orderly database close, deinit or test teardown.
    Darwin.kill(Darwin.getpid(), SIGKILL)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_CRASH_PROBE"] != "writer"))
  @MainActor func killedWriterRestoresFactsStagingIdentityPairingAndReceipts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "together-crash-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = Bundle(for: CrashProbeBundleLocator.self)
    let binary = try #require(bundle.executableURL)
    let toolchain = URL(
      fileURLWithPath:
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr")
    let helper = toolchain.appendingPathComponent("libexec/swift/pm/swiftpm-testing-helper")
    let process = Process()
    process.executableURL = helper
    process.arguments = [
      "--test-bundle-path", binary.path, "--filter", "crashWriterProbeOnly", binary.path,
      "--testing-library", "swift-testing",
    ]
    var env = ProcessInfo.processInfo.environment
    env["TOGETHER_CRASH_PROBE"] = "writer"
    env["TOGETHER_CRASH_ROOT"] = root.path
    process.environment = env
    let output = root.appendingPathComponent("child.log")
    FileManager.default.createFile(atPath: output.path, contents: nil)
    let file = try FileHandle(forWritingTo: output)
    process.standardOutput = file
    process.standardError = file
    try process.run()
    await Task.detached { process.waitUntilExit() }.value
    try file.close()
    #expect(process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL)
    guard process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
    else {
      Issue.record("Crash child log: \(try String(contentsOf:output,encoding:.utf8))")
      return
    }
    let repo = try TogetherRepository(url: root.appendingPathComponent("crash.store"))
    let metadata = try #require(try repo.load(LocalIdentityMetadata.self, key: "local-identity"))
    let before = try #require(try repo.load(DeviceDescriptor.self, key: "test-public-identity"))
    let identity = try DeviceIdentity.persistent(
      deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
      directory: root.appendingPathComponent("Identity"), needsExistingIdentity: true,
      timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
    #expect(identity.descriptor == before)
    let trust = try SpaceAuthorization.restore(
      try #require(try repo.load(AuthorizationArchive.self, key: "replication4/authorization")))
    let store = try AuthorizedReplicationStore(
      repository: repo, identity: identity, authorization: trust)
    try await store.restore()
    #expect(try repo.operationCount() == 1)
    let entry = try await store.index.entry(for: try #require(repo.allOperations().first).id)
    let ledger = DeviceAcknowledgementLedger(
      repository: repo, index: store.index, identity: identity)
    #expect(try await ledger.partnerHasPersisted(entry, trust: trust))
    let missing = try CanonicalJSON.decode(
      AuthorizedOperation.self,
      from: Data(contentsOf: root.appendingPathComponent("missing-predecessor.json")))
    try await store.receive([.authorized(missing)])
    try await store.receive([.authorized(missing)])
    #expect(try repo.operationCount() == 3)
    let context = try await store.projectionContext()
    let projection = OperationProjector.replay(try repo.allOperations(), context: context)
    #expect(context.spaceId == trust.spaceId && projection.tasks.count == 3)
    #expect(
      try repo.load(PairedPeer.self, key: "paired-peer")?.descriptor.userId == context.peer?.userId)
    #expect(
      try repo.load(RelayBinding.self, key: "relay-binding")?.localDeviceId
        == identity.descriptor.deviceId)
  }
}
