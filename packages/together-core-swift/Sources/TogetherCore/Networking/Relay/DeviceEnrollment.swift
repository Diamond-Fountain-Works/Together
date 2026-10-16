import Foundation

/// Public, signed enrollment files. They never contain an identity private key,
/// operation payload, local storage path or a reusable Relay credential.
public struct DeviceEnrollmentOffer: Codable, Equatable, Sendable {
  public struct Body: Codable, Equatable, Sendable {
    public var kind = "Together-Device-Offer-1"
    public var id: UUID
    public var issuerDeviceId: UUID
    public var ownerId: UUID
    public var archive: AuthorizationArchive
    public var binding: C1ReplicationBinding
    public var expiresAt: Date
  }
  public var body: Body
  public var signature: Data
  public var digest: String { get throws { ReplicationHash.digest(try CanonicalJSON.encode(self)) } }
  public var verificationCode: String { get throws { try EnrollmentCode.format(digest) } }
  public func verify(now: Date? = nil) throws -> SpaceAuthorization {
    let trust = try SpaceAuthorization.restore(body.archive)
    guard body.kind == "Together-Device-Offer-1", body.binding.spaceId == trust.spaceId,
      let root = trust.root(for: body.ownerId), root.deviceId == body.issuerDeviceId,
      body.binding.localDeviceId == root.deviceId, trust.containsActive(root),
      SignedSpaceGenesis.verify(signature, bytes: try CanonicalJSON.encode(body), key: root.publicKey)
    else { throw ReplicationError.unauthorized }
    _ = try RelayAPI.validatedBase(body.binding.serviceURL)
    if let now, now >= body.expiresAt { throw DeviceEnrollmentError.expired }
    return trust
  }
  public static func issue(identity: DeviceIdentity, trust: SpaceAuthorization,
    binding: C1ReplicationBinding, now: Date) throws -> Self {
    guard trust.root(for: identity.descriptor.userId)?.deviceId == identity.descriptor.deviceId,
      trust.containsActive(identity.descriptor) else { throw ReplicationError.unauthorized }
    let body = Body(id: UUID(), issuerDeviceId: identity.descriptor.deviceId,
      ownerId: identity.descriptor.userId, archive: trust.archive, binding: binding,
      expiresAt: now.addingTimeInterval(30 * 60))
    return try CanonicalJSON.decode(Self.self, from: CanonicalJSON.encode(Self(body: body,
      signature: identity.sign(CanonicalJSON.encode(body)))))
  }
}

public struct DeviceEnrollmentRequest: Codable, Equatable, Sendable {
  public struct Body: Codable, Equatable, Sendable {
    public var kind = "Together-Device-Request-1"
    public var offerId: UUID
    public var offerDigest: String
    public var device: DeviceDescriptor
  }
  public var body: Body
  public var signature: Data
  public var digest: String { get throws { ReplicationHash.digest(try CanonicalJSON.encode(self)) } }
  public var verificationCode: String { get throws { try EnrollmentCode.format(digest) } }
  public static func create(offer: DeviceEnrollmentOffer, identity: DeviceIdentity, now: Date) throws -> Self {
    let trust = try offer.verify(now: now)
    guard identity.descriptor.userId == offer.body.ownerId,
      identity.descriptor.initialSpaceId == trust.spaceId,
      trust.devices[identity.descriptor.deviceId] == nil else { throw ReplicationError.unauthorized }
    let body = Body(offerId: offer.body.id, offerDigest: try offer.digest, device: identity.descriptor)
    return Self(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
  }
  public func verify(offer: DeviceEnrollmentOffer, now: Date? = nil) throws {
    let trust = try offer.verify(now: now)
    guard body.kind == "Together-Device-Request-1", body.offerId == offer.body.id,
      try body.offerDigest == offer.digest, body.device.userId == offer.body.ownerId,
      body.device.initialSpaceId == trust.spaceId, body.device.protocolVersion == 4,
      body.device.publicKey.count == 32, !body.device.displayName.isEmpty,
      body.device.displayName.count <= 80, trust.devices[body.device.deviceId] == nil,
      SignedSpaceGenesis.verify(signature, bytes: try CanonicalJSON.encode(body), key: body.device.publicKey)
    else { throw ReplicationError.unauthorized }
  }
}

public struct DeviceEnrollmentCompletion: Codable, Equatable, Sendable {
  public struct Body: Codable, Equatable, Sendable {
    public var kind = "Together-Device-Completion-1"
    public var requestDigest: String
    public var archive: AuthorizationArchive
    public var binding: C1ReplicationBinding
  }
  public var body: Body
  public var signature: Data
  public static func issue(request: DeviceEnrollmentRequest, offer: DeviceEnrollmentOffer,
    trust: SpaceAuthorization, binding: C1ReplicationBinding, identity: DeviceIdentity) throws -> Self {
    try request.verify(offer: offer)
    guard identity.descriptor.deviceId == offer.body.issuerDeviceId,
      trust.containsActive(request.body.device) else { throw ReplicationError.unauthorized }
    var target = binding; target.localDeviceId = request.body.device.deviceId
    let body = Body(requestDigest: try request.digest, archive: trust.archive, binding: target)
    return Self(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
  }
  public func verify(request: DeviceEnrollmentRequest, offer: DeviceEnrollmentOffer) throws -> SpaceAuthorization {
    try request.verify(offer: offer)
    let prior = try offer.verify(), trust = try SpaceAuthorization.restore(body.archive)
    guard body.kind == "Together-Device-Completion-1", try body.requestDigest == request.digest,
      try prior.genesis.digest == trust.genesis.digest, prior.events.allSatisfy(trust.events.contains),
      trust.containsActive(request.body.device), body.binding.localDeviceId == request.body.device.deviceId,
      body.binding.spaceId == trust.spaceId, body.binding.serviceURL == offer.body.binding.serviceURL,
      body.binding.legacyRouteId == offer.body.binding.legacyRouteId,
      let root = trust.root(for: offer.body.ownerId),
      SignedSpaceGenesis.verify(signature, bytes: try CanonicalJSON.encode(body), key: root.publicKey)
    else { throw ReplicationError.unauthorized }
    return trust
  }
}

public enum EnrollmentCode {
  // 96 bits, shown on both devices; not a short online pairing password.
  public static func format(_ digest: String) -> String {
    let text = String(digest.prefix(24)).uppercased()
    return stride(from: 0, to: text.count, by: 4).map { String(text.dropFirst($0).prefix(4)) }.joined(separator: " ")
  }
}
public enum DeviceEnrollmentError: LocalizedError {
  case expired, confirmationRequired, existingData, invalidWorkspace, identityUnavailable
  public var errorDescription: String? {
    switch self {
    case .expired: Copy.text("device.error.expired")
    case .confirmationRequired: Copy.text("device.error.confirm")
    case .existingData: Copy.text("device.error.existingData")
    case .invalidWorkspace: Copy.text("device.error.workspace")
    case .identityUnavailable: Copy.text("device.error.identityUnavailable")
    }
  }
}

/// The original store/identity are never renamed, cleared or repurposed. A new
/// same-user identity lives in a separate controlled replica directory.
@MainActor public struct DeviceEnrollmentWorkspace {
  public let root: URL
  public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }
  private func directory(_ id: UUID) -> URL { root.appendingPathComponent("Replicas", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
  private func checked(_ url: URL) throws -> URL {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    guard resolved.path == url.standardizedFileURL.path,
      resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw DeviceEnrollmentError.invalidWorkspace }
    return resolved
  }
  private func validateSource(_ source: ReplicaEngine?) throws {
    if let source {
      guard source.enrollmentRoot?.resolvingSymlinksInPath() == root,
        source.peer == nil, !source.usesReplication4,
        try source.repository.load(RelayBinding.self, key: "relay-binding") == nil,
        source.operations.allSatisfy({ $0.operation.entityType == .profile && $0.operation.actorId == source.identity.descriptor.userId && $0.operation.entityId == source.identity.descriptor.userId }) else { throw DeviceEnrollmentError.existingData }
    } else if FileManager.default.fileExists(atPath: root.appendingPathComponent("Together.store").path) {
      throw DeviceEnrollmentError.existingData
    }
  }
  public func stage(offer: DeviceEnrollmentOffer, name: String, verified: Bool, now: Date, source: ReplicaEngine? = nil) throws -> DeviceEnrollmentRequest {
    guard verified else { throw DeviceEnrollmentError.confirmationRequired }
    try validateSource(source)
    let trust = try offer.verify(now: now)
    let folder = try checked(directory(offer.body.id))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let pending = folder.appendingPathComponent("enrollment.json")
    if FileManager.default.fileExists(atPath: pending.path) {
      let existing = try CanonicalJSON.decode(StagedEnrollment.self, from: Data(contentsOf: pending))
      guard existing.offer == offer else { throw ReplicationError.contentCollision }
      try existing.request.verify(offer: offer, now: now)
      let d = existing.request.body.device
      guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Identity/device-\(d.deviceId).key").path) else { throw DeviceEnrollmentError.identityUnavailable }
      let key = try DeviceIdentity.persistent(deviceId: d.deviceId, userId: d.userId, spaceId: d.initialSpaceId,
        directory: folder.appendingPathComponent("Identity"), needsExistingIdentity: true,
        timeZoneIdentifier: d.initialTimeZoneIdentifier ?? "Etc/UTC", protocolVersion: d.protocolVersion, displayName: d.displayName)
      guard key.descriptor == d else { throw IdentityStorageError.identityMismatch }
      return existing.request
    }
    let displayName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    guard !displayName.isEmpty else { throw ReplicationError.unauthorized }
    let intentURL = folder.appendingPathComponent("enrollment-intent.json")
    var intent: EnrollmentIntent
    if FileManager.default.fileExists(atPath: intentURL.path) {
      intent = try CanonicalJSON.decode(EnrollmentIntent.self, from: Data(contentsOf: intentURL))
      guard intent.ownerId == offer.body.ownerId, intent.spaceId == trust.spaceId else { throw ReplicationError.unauthorized }
    } else {
      let keys = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Identity"), includingPropertiesForKeys: nil)) ?? []
      guard keys.isEmpty else { throw DeviceEnrollmentError.invalidWorkspace }
      intent = EnrollmentIntent(deviceId: UUID(), ownerId: offer.body.ownerId, spaceId: trust.spaceId, keyCreated: false)
      try CanonicalJSON.encode(intent).write(to: intentURL, options: .withoutOverwriting)
    }
    // This generates a key only for a not-yet-created intent. A missing key
    // after creation is a recovery error, never permission to rotate identity.
    if intent.keyCreated {
      guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Identity/device-\(intent.deviceId).key").path) else { throw DeviceEnrollmentError.identityUnavailable }
    }
    let identity = try DeviceIdentity.persistent(deviceId: intent.deviceId, userId: intent.ownerId, spaceId: trust.spaceId,
      directory: folder.appendingPathComponent("Identity"), needsExistingIdentity: intent.keyCreated,
      timeZoneIdentifier: trust.genesis.body.sharedTimeZoneIdentifier, protocolVersion: 4, displayName: displayName)
    intent.keyCreated = true
    try CanonicalJSON.encode(intent).write(to: intentURL, options: .atomic)
    let requestBody = DeviceEnrollmentRequest.Body(offerId: offer.body.id, offerDigest: try offer.digest, device: identity.descriptor)
    let request = DeviceEnrollmentRequest(body: requestBody, signature: try identity.sign(CanonicalJSON.encode(requestBody)))
    try request.verify(offer: offer, now: now)
    try CanonicalJSON.encode(StagedEnrollment(offer: offer, request: request)).write(to: pending, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
    return request
  }
  public func complete(_ completion: DeviceEnrollmentCompletion, offerId: UUID, verified: Bool, source: ReplicaEngine? = nil, dateProvider: any DateProvider = SystemDateProvider()) throws -> ReplicaEngine {
    guard verified else { throw DeviceEnrollmentError.confirmationRequired }
    try validateSource(source)
    let folder = try checked(directory(offerId))
    let staged = try CanonicalJSON.decode(StagedEnrollment.self, from: Data(contentsOf: folder.appendingPathComponent("enrollment.json")))
    let trust = try completion.verify(request: staged.request, offer: staged.offer)
    let d = staged.request.body.device
    guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Identity/device-\(d.deviceId).key").path) else { throw DeviceEnrollmentError.identityUnavailable }
    let identity = try DeviceIdentity.persistent(deviceId: d.deviceId, userId: d.userId, spaceId: d.initialSpaceId,
      directory: folder.appendingPathComponent("Identity"), needsExistingIdentity: true,
      timeZoneIdentifier: trust.genesis.body.sharedTimeZoneIdentifier, protocolVersion: 4, displayName: d.displayName)
    guard identity.descriptor.publicKey == d.publicKey else { throw ReplicationError.unauthorized }
    let repository = try TogetherRepository(url: folder.appendingPathComponent("Together.store"))
    if try repository.load(AuthorizationArchive.self, key: "replication4/authorization") == nil {
      try C1ReplicationService.prepareAuthorizedDevice(repository: repository, identity: identity,
        binding: completion.body.binding, archive: trust.archive, trustedGenesisDigest: trust.genesis.digest)
    } else {
      let prior = try repository.load(AuthorizationArchive.self, key: "replication4/authorization")!
      guard try SpaceAuthorization.restore(prior).genesis.digest == trust.genesis.digest else { throw ReplicationError.unauthorized }
    }
    let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: folder.appendingPathComponent("Media"), dateProvider: dateProvider, enrollmentRoot: root)
    let marker = root.appendingPathComponent("active-replica.json")
    if FileManager.default.fileExists(atPath: marker.path) {
      guard try CanonicalJSON.decode(UUID.self, from: Data(contentsOf: marker)) == offerId else { throw DeviceEnrollmentError.existingData }
    } else {
      try CanonicalJSON.encode(offerId).write(to: marker, options: .withoutOverwriting)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }
    return engine
  }
  public func activeDirectory() throws -> URL {
    let marker = root.appendingPathComponent("active-replica.json")
    guard FileManager.default.fileExists(atPath: marker.path) else { return root }
    _ = try checked(marker)
    let id = try CanonicalJSON.decode(UUID.self, from: Data(contentsOf: marker))
    let folder = try checked(directory(id))
    guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Together.store").path) else { throw DeviceEnrollmentError.invalidWorkspace }
    return folder
  }
  public var pendingOffers: [DeviceEnrollmentOffer] {
    let folders = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Replicas"), includingPropertiesForKeys: nil)) ?? []
    return folders.compactMap { folder in
      guard (try? checked(folder)) != nil, let bytes = try? Data(contentsOf: folder.appendingPathComponent("enrollment.json")),
        let pending = try? CanonicalJSON.decode(StagedEnrollment.self, from: bytes) else { return nil }
      return pending.offer
    }
  }
  public func request(for offerId: UUID) throws -> DeviceEnrollmentRequest {
    try CanonicalJSON.decode(StagedEnrollment.self, from: Data(contentsOf: checked(directory(offerId)).appendingPathComponent("enrollment.json"))).request
  }
  private struct StagedEnrollment: Codable { var offer: DeviceEnrollmentOffer; var request: DeviceEnrollmentRequest }
  private struct EnrollmentIntent: Codable { var deviceId: UUID; var ownerId: UUID; var spaceId: UUID; var keyCreated: Bool }
}

public struct LegacyMigrationExchange: Codable, Equatable, Sendable {
  public var kind = "Together-Legacy-Migration-4"
  public var genesis: SignedSpaceGenesis
  public var verificationCode: String { get throws { EnrollmentCode.format(ReplicationHash.digest(try CanonicalJSON.encode(genesis.body))) } }
  @MainActor public static func begin(_ engine: ReplicaEngine) async throws -> Self {
    let body = try await C1ReplicationService.migrationProposal(engine: engine)
    return Self(genesis: SignedSpaceGenesis(body: body, signatures: [try await C1ReplicationService.signMigrationProposal(engine: engine, proposal: body)]))
  }
  @MainActor public func validate(_ engine: ReplicaEngine) async throws {
    guard kind == "Together-Legacy-Migration-4", try await C1ReplicationService.migrationProposal(engine: engine) == genesis.body,
      !genesis.signatures.isEmpty, genesis.signatures.count <= 2,
      Set(genesis.signatures.map(\.deviceId)).count == genesis.signatures.count else { throw ReplicationError.inventoryChanged }
    for proof in genesis.signatures {
      guard let d = genesis.body.roots.first(where: { $0.deviceId == proof.deviceId }),
        SignedSpaceGenesis.verify(proof.signature, bytes: try CanonicalJSON.encode(genesis.body), key: d.publicKey) else { throw ReplicationError.invalidSignature }
    }
  }
  @MainActor public func cosign(_ engine: ReplicaEngine, verified: Bool) async throws -> Self {
    guard verified else { throw DeviceEnrollmentError.confirmationRequired }
    try await validate(engine)
    var copy = self
    if !copy.genesis.signatures.contains(where: { $0.deviceId == engine.identity.descriptor.deviceId }) {
      copy.genesis.signatures.append(try await C1ReplicationService.signMigrationProposal(engine: engine, proposal: genesis.body))
      copy.genesis.signatures.sort { $0.deviceId.uuidString < $1.deviceId.uuidString }
    }
    return copy
  }
}
