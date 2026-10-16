import CryptoKit
import Foundation
import Testing
@testable import TogetherCore

/// Public synthetic Kotlin output. This test does not load an app, a user store,
/// a device identity file, Keychain or the production Relay.
@Suite("Android Phase A native compatibility") @MainActor struct AndroidPhaseAConformanceTests {
  private struct Vector: Decodable {
    var synthetic: Bool
    var authorization: AuthorizationArchive
    var androidDevice: DeviceDescriptor
    var records: [ReplicationRecord]
    var androidHello: RelaySignedHello
    var swiftHello: RelaySignedHello
    var encryptedFromKotlin: RelayPacket
  }
  private func fixture() throws -> Vector {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<9 {
      let url = root.appendingPathComponent("protocol/fixtures/android-phase-a-v4.json")
      if FileManager.default.fileExists(atPath: url.path) {
        return try CanonicalJSON.decode(Vector.self, from: Data(contentsOf: url))
      }
      root.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
  }
  @Test func kotlinSignedHistoryProjectsWithUnmodifiedSwiftBusinessRules() throws {
    let vector = try fixture()
    #expect(vector.synthetic)
    let trust = try SpaceAuthorization.restore(vector.authorization)
    for record in vector.records {
      guard case .authorized(let proof) = record else { Issue.record("Not a Protocol 4 certificate"); return }
      _ = try proof.verify(in: trust)
    }
    let content = try Dictionary(uniqueKeysWithValues: vector.records.map { record in
      (record.operation.id, try InventoryEntry(record).contentDigest)
    })
    let context = try ReplicaContext(local: vector.androidDevice, authorization: trust, acceptedContent: content)
    let snapshot = OperationProjector.replay(vector.records.map(\.operation), context: context)
    #expect(snapshot.conflicts.isEmpty)
    #expect(snapshot.tasks[StableID.make("android-vector-task")]?.title == "Synthetic partner edit")
    #expect(snapshot.tasks[StableID.make("android-vector-task")]?.notes == "Synthetic independent field")
    #expect(snapshot.grants.values.reduce(0) { $0 + $1.quantity } == 5)
    #expect(snapshot.wishes.values.filter { $0.status == .fulfilled }.count == 1)
    let stats = try snapshot.finance.statistics()
    #expect(stats.bookBalance == 71_400)
    #expect(stats.totalExpenses == 28_701)
    #expect(snapshot.finance.expenses.count == 3)
    #expect(snapshot.gifts.values.filter(\.isEffective).count == 1)
    #expect(context.spaceId == trust.spaceId)
    #expect(context.members.count == 2)
  }
  @Test func cryptoKitOpensBouncyCastleTranscriptAndReplies() throws {
    let v = try fixture(), trust = try SpaceAuthorization.restore(v.authorization)
    let descriptor = v.swiftHello.body.descriptor
    // Known test-only seeds match the Kotlin fixture generator; never imported from a Mac identity.
    let identity = try DeviceIdentity(deviceId: descriptor.deviceId, userId: descriptor.userId,
      initialSpaceId: descriptor.initialSpaceId,
      privateKeyData: Data((0..<32).map { UInt8($0 + 60) }), displayName: descriptor.displayName,
      timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4)
    #expect(identity.descriptor == descriptor)
    let ephemeral = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(repeating: 92, count: 32))
    let session = try RelaySecureSession(identity: identity, ephemeral: ephemeral, local: v.swiftHello,
      remote: v.androidHello, authorization: trust)
    #expect(try session.open(v.encryptedFromKotlin) == Data("Synthetic cross-native encrypted payload".utf8))
    let reply = try session.seal(Data("Synthetic CryptoKit response".utf8))
    if let path = ProcessInfo.processInfo.environment["TOGETHER_ANDROID_RESPONSE_PATH"] {
      try CanonicalJSON.encode(reply).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
  }
}
