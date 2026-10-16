import Foundation
import Testing
@testable import TogetherCore

@Suite("Device enrollment files and preserved storage", .serialized) @MainActor
struct DeviceEnrollmentTests {
  private func fixture() throws -> (ReplicationFixture, SpaceAuthorization, C1ReplicationBinding, URL) {
    let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("together-enrollment-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (f, trust, C1ReplicationBinding(serviceURL: URL(string: "https://relay.example.invalid")!, spaceId: trust.spaceId, legacyRouteId: UUID(), localDeviceId: f.a.descriptor.deviceId), root)
  }

  @Test func portableEnrollmentVectorsVerifyWithoutPrivateKeys() throws {
    var project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: project.appendingPathComponent("qa/project.json").path) { project.deleteLastPathComponent() }
    let target = project.appendingPathComponent("protocol/fixtures/device-enrollment-v1.json")
    if ProcessInfo.processInfo.environment["TOGETHER_EXPORT_ENROLLMENT_FIXTURES"] == "1" {
      let (f, initial, binding, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
      let now = Date(timeIntervalSince1970: 1791550000)
      let offer = try DeviceEnrollmentOffer.issue(identity: f.a, trust: initial, binding: binding, now: now)
      let device = try DeviceIdentity(userId: f.a.descriptor.userId, initialSpaceId: initial.spaceId, displayName: "Synthetic enrollment device", protocolVersion: 4)
      let request = try DeviceEnrollmentRequest.create(offer: offer, identity: device, now: now)
      var trust = initial; try trust.apply(trust.grant(device.descriptor, authorizedBy: f.a))
      let completion = try DeviceEnrollmentCompletion.issue(request: request, offer: offer, trust: trust, binding: binding, identity: f.a)
      let vectors = EnrollmentVectors(offer: offer, request: request, completion: completion, offerDigest: try offer.digest, requestDigest: try request.digest, offerCode: try offer.verificationCode, requestCode: try request.verificationCode)
      let object = try JSONSerialization.jsonObject(with: CanonicalJSON.encode(vectors))
      try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]).write(to: target)
    }
    let v = try CanonicalJSON.decode(EnrollmentVectors.self, from: Data(contentsOf: target))
    #expect(v.synthetic && v.version == 1)
    _ = try v.offer.verify(now: Date(timeIntervalSince1970: 1791550000))
    try v.request.verify(offer: v.offer)
    _ = try v.completion.verify(request: v.request, offer: v.offer)
    #expect(try v.offer.digest == v.offerDigest && v.request.digest == v.requestDigest)
    #expect(try v.offer.verificationCode == v.offerCode && v.request.verificationCode == v.requestCode)
    #expect(!String(decoding: try CanonicalJSON.encode(v), as: UTF8.self).contains("privateKey"))
  }
  @Test func independentRequestExpiryAndTamper() throws {
    let (f, trust, binding, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let now = Date(timeIntervalSince1970: 1791550000)
    let offer = try DeviceEnrollmentOffer.issue(identity: f.a, trust: trust, binding: binding, now: now)
    let workspace = DeviceEnrollmentWorkspace(root: root)
    #expect(throws: DeviceEnrollmentError.self) { try workspace.stage(offer: offer, name: "Synthetic Mac", verified: false, now: now) }
    let request = try workspace.stage(offer: offer, name: "Synthetic Mac", verified: true, now: now)
    #expect(request.body.device.userId == f.a.descriptor.userId)
    #expect(request.body.device.initialSpaceId == trust.spaceId)
    #expect(request.body.device.deviceId != f.a.descriptor.deviceId && request.body.device.publicKey != f.a.descriptor.publicKey)
    #expect(try workspace.stage(offer: offer, name: "Retry", verified: true, now: now) == request)
    #expect(throws: DeviceEnrollmentError.self) { try request.verify(offer: offer, now: now.addingTimeInterval(1800)) }
    var altered = request; altered.body.device.userId = f.b.descriptor.userId
    #expect(throws: ReplicationError.self) { try altered.verify(offer: offer) }
    altered = request; altered.body.device.displayName = "Altered"
    #expect(throws: ReplicationError.self) { try altered.verify(offer: offer) }
    let bytes = try CanonicalJSON.encode(request)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("privateKey"))
    #expect(try request.verificationCode == CanonicalJSON.decode(DeviceEnrollmentRequest.self, from: bytes).verificationCode)
  }
  @Test func completionIsBoundToRequestOwnerSpaceAndIndependentKey() throws {
    let (f, initial, binding, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let offer = try DeviceEnrollmentOffer.issue(identity: f.a, trust: initial, binding: binding, now: .now)
    let workspace = DeviceEnrollmentWorkspace(root: root)
    let request = try workspace.stage(offer: offer, name: "Synthetic Phone", verified: true, now: .now)
    var trust = initial; try trust.apply(trust.grant(request.body.device, authorizedBy: f.a))
    let done = try DeviceEnrollmentCompletion.issue(request: request, offer: offer, trust: trust, binding: binding, identity: f.a)
    _ = try done.verify(request: request, offer: offer)
    #expect(throws: DeviceEnrollmentError.self) { try workspace.complete(done, offerId: offer.body.id, verified: false) }
    let original = root.appendingPathComponent("original-marker"); try Data("synthetic preserved original".utf8).write(to: original)
    let replica = try workspace.complete(done, offerId: offer.body.id, verified: true)
    #expect(replica.usesReplication4 && replica.context.spaceId == initial.spaceId)
    #expect(replica.identity.descriptor == request.body.device)
    #expect(try Data(contentsOf: original) == Data("synthetic preserved original".utf8))
    #expect(try workspace.activeDirectory().path.contains(offer.body.id.uuidString))
    let saved = try #require(try replica.repository.load(DeviceDescriptor.self, key: "replication4/local-device"))
    #expect(saved == request.body.device && saved.protocolVersion == 4)
    var bad = done; bad.body.binding.serviceURL = URL(string: "https://wrong.example.invalid")!
    #expect(throws: ReplicationError.self) { try bad.verify(request: request, offer: offer) }
    var other = request; other.body.offerId = UUID()
    #expect(throws: ReplicationError.self) { try done.verify(request: other, offer: offer) }
    var revoked = trust
    try revoked.apply(revoked.revoke(request.body.device.deviceId, at: .init(), authorizedBy: f.a))
    #expect(throws: ReplicationError.self) { try DeviceEnrollmentCompletion.issue(request: request, offer: offer, trust: revoked, binding: binding, identity: f.a) }
  }
  @Test func existingBusinessDataAndSymlinkCannotBeReplaced() throws {
    let (f, trust, binding, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let offer = try DeviceEnrollmentOffer.issue(identity: f.a, trust: trust, binding: binding, now: .now)
    let original = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("Together.store")), identity: f.b, mediaRoot: root.appendingPathComponent("Media"))
    let task = try original.createTask(title: "Synthetic data must stay")
    let workspace = DeviceEnrollmentWorkspace(root: root)
    #expect(throws: DeviceEnrollmentError.self) { try workspace.stage(offer: offer, name: "Blocked", verified: true, now: .now, source: original) }
    #expect(original.snapshot.tasks[task] != nil && original.identity.descriptor == f.b.descriptor)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("active-replica.json").path))
    let outside = root.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Replicas"), withDestinationURL: outside)
    #expect(throws: DeviceEnrollmentError.self) { try workspace.stage(offer: offer, name: "Blocked", verified: true, now: .now) }
  }
  @Test func bothOriginalMacsMustSignExactCurrentHistory() async throws {
    let p = try TwoReplicas()
    var first = try await LegacyMigrationExchange.begin(p.a)
    #expect(first.genesis.signatures.count == 1)
    await #expect(throws: DeviceEnrollmentError.self) { try await first.cosign(p.b, verified: false) }
    first = try await first.cosign(p.b, verified: true)
    try first.genesis.verify(existingPins: p.a.context)
    #expect(first.genesis.signatures.count == 2)
    #expect(try await first.cosign(p.b, verified: true) == first)
    _ = try p.a.createTask(title: "Synthetic concurrent edit")
    await #expect(throws: ReplicationError.self) { try await first.validate(p.a) }
    #expect(!p.a.usesReplication4)
  }
  @Test func missingEnrollmentKeyNeverGeneratesAReplacement() throws {
    let (f, trust, binding, root) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
    let offer = try DeviceEnrollmentOffer.issue(identity: f.a, trust: trust, binding: binding, now: .now)
    let workspace = DeviceEnrollmentWorkspace(root: root)
    let request = try workspace.stage(offer: offer, name: "Synthetic lost-key test", verified: true, now: .now)
    let folder = root.appendingPathComponent("Replicas/\(offer.body.id)/Identity")
    try FileManager.default.removeItem(at: folder.appendingPathComponent("device-\(request.body.device.deviceId).key"))
    #expect(throws: DeviceEnrollmentError.self) { try workspace.stage(offer: offer, name: "Retry", verified: true, now: .now) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    // Also exercise a crash after the key-created intent but before request publication.
    try FileManager.default.removeItem(at: root.appendingPathComponent("Replicas/\(offer.body.id)/enrollment.json"))
    #expect(throws: DeviceEnrollmentError.self) { try workspace.stage(offer: offer, name: "Retry", verified: true, now: .now) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
  }
  @Test func missingActiveReplicaStoreFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("together-enrollment-pointer-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try CanonicalJSON.encode(UUID()).write(to: root.appendingPathComponent("active-replica.json"))
    #expect(throws: DeviceEnrollmentError.self) { try DeviceEnrollmentWorkspace(root: root).activeDirectory() }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Identity").path))
  }
}

private struct EnrollmentVectors: Codable {
  var synthetic = true
  var version = 1
  var offer: DeviceEnrollmentOffer
  var request: DeviceEnrollmentRequest
  var completion: DeviceEnrollmentCompletion
  var offerDigest: String
  var requestDigest: String
  var offerCode: String
  var requestCode: String
}
