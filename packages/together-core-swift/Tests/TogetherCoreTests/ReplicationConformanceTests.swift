import Foundation
import Testing

@testable import TogetherCore

private struct ReplicationVectors: Codable {
  var synthetic = true
  var protocolVersion = 4
  var authorization: AuthorizationArchive
  var authorizationDigest: String
  var record: ReplicationRecord
  var recordDigest: String
  var inventory: InventoryEntry
  var checkpoint: InventoryCheckpoint
  var receipt: SignedAcknowledgement
  var frames: [ReplicationFrame]
}
@Suite("Cross-platform replication 4 vectors") @MainActor struct ReplicationConformanceTests {
  private func target() throws -> URL {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<8 {
      if FileManager.default.fileExists(atPath: root.appendingPathComponent("qa/project.json").path)
      {
        return root.appendingPathComponent("protocol/fixtures/replication-v4.json")
      }
      root.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
  }
  @Test func ed25519AuthorizationContentCertificateAndAckVectors() async throws {
    let target = try target()
    if ProcessInfo.processInfo.environment["TOGETHER_EXPORT_REPLICATION_FIXTURES"] == "1" {
      let f = try ReplicationFixture()
      let phone = try DeviceIdentity(
        userId: f.a.descriptor.userId, displayName: "Synthetic phone",
        timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4)
      var trust = try SpaceAuthorization(genesis: f.genesis)
      try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
      let op = try f.operation(phone, title: "合成任务 / Synthetic ♡")
      let proof = try AuthorizedOperation.sign(
        op, identity: phone, trust: trust, previous: DeviceFrontier())
      let record = ReplicationRecord.authorized(proof)
      let entry = try InventoryEntry(record)
      let cp = try ReplicationHash.inventory([entry])
      let epoch = try #require(trust.devices[f.b.descriptor.deviceId]?.epochId)
      let body = AcknowledgementBody(
        spaceId: trust.spaceId, deviceId: f.b.descriptor.deviceId, epochId: epoch, entries: [entry])
      let receipt = SignedAcknowledgement(
        body: body, signature: try f.b.sign(CanonicalJSON.encode(body)))
      let pass = UUID()
      let request = UUID()
      let frames: [ReplicationFrame] = [
        .syncHint(UUID()), .inventoryStart(pass),
        .inventoryPage(
          pass, InventoryPage(checkpoint: cp, after: nil, entries: [entry], next: nil)),
        .inventoryNext(pass, op.id), .operationRequest(pass, request, [entry]),
        .operationBatch(pass, request, [record]), .inventoryFinished(pass, cp),
        .acknowledgement(receipt),
      ]
      let vectors = ReplicationVectors(
        authorization: trust.archive, authorizationDigest: try trust.digest, record: record,
        recordDigest: ReplicationHash.digest(try CanonicalJSON.encode(record)), inventory: entry,
        checkpoint: cp, receipt: receipt, frames: frames)
      let object = try JSONSerialization.jsonObject(with: CanonicalJSON.encode(vectors))
      try JSONSerialization.data(
        withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
      ).write(to: target)
    }
    let v = try CanonicalJSON.decode(ReplicationVectors.self, from: Data(contentsOf: target))
    let trust = try SpaceAuthorization.restore(v.authorization)
    #expect(v.synthetic && v.protocolVersion == 4)
    #expect(try trust.digest == v.authorizationDigest)
    guard case .authorized(let proof) = v.record else {
      Issue.record("Missing certification")
      return
    }
    _ = try proof.verify(in: trust)
    #expect(try InventoryEntry(v.record) == v.inventory)
    #expect(try ReplicationHash.inventory([v.inventory]) == v.checkpoint)
    #expect(try ReplicationHash.digest(CanonicalJSON.encode(v.record)) == v.recordDigest)
    let remote = try #require(trust.devices[v.receipt.body.deviceId]?.descriptor)
    try v.receipt.verify(in: trust, from: remote)
    for frame in v.frames {
      let bytes = try CanonicalJSON.encode(frame)
      let decoded = try CanonicalJSON.decode(ReplicationFrame.self, from: bytes)
      #expect(try CanonicalJSON.encode(decoded) == bytes)
      let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
      #expect(object?["kind"] is String)
    }
  }
}
