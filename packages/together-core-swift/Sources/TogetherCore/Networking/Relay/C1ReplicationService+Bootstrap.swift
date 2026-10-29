import Foundation

extension C1ReplicationService {
  public static func migrationProposal(engine: ReplicaEngine) async throws -> SpaceGenesisBody {
    guard !engine.usesReplication4, engine.peer != nil else { throw ReplicationError.unauthorized }
    let context = engine.context
    let log = engine.operations
    guard
      await Task.detached(operation: {
        log.allSatisfy { op in
          context.devices[op.operation.deviceId].map { op.verified(by: $0) } ?? false
        }
      }).value
    else { throw ReplicationError.invalidSignature }
    let checkpoint = try await OperationInventoryIndex(repository: engine.repository).checkpoint()
    return SpaceGenesisBody(context: context, legacyCheckpoint: checkpoint)
  }
  public static func signMigrationProposal(engine: ReplicaEngine, proposal: SpaceGenesisBody)
    async throws -> DeviceSignature
  {
    guard try await migrationProposal(engine: engine) == proposal else {
      throw ReplicationError.inventoryChanged
    }
    return DeviceSignature(
      deviceId: engine.identity.descriptor.deviceId,
      signature: try engine.identity.sign(CanonicalJSON.encode(proposal)))
  }
  /// Two original devices must sign one identical frozen-space/checkpoint
  /// proposal. This API never manufactures the partner's signature.
  public static func migrate(engine: ReplicaEngine, genesis: SignedSpaceGenesis) async throws
    -> C1ReplicationService
  {
    guard !engine.usesReplication4,
      let legacy = try engine.repository.load(RelayBinding.self, key: "relay-binding"),
      let peer = engine.peer
    else { throw ReplicationError.unauthorized }
    let trust = try SpaceAuthorization(
      genesis: genesis,
      existingPins: ReplicaContext(local: engine.identity.descriptor, peer: peer.descriptor))
    let index = OperationInventoryIndex(repository: engine.repository)
    guard try await index.checkpoint() == genesis.body.legacyCheckpoint else {
      throw ReplicationError.inventoryChanged
    }
    let api = try RelayAPI(base: legacy.serviceURL, identity: engine.identity)
    let remote = try await api.bootstrap4(
      legacyRouteId: legacy.routeId, authorization: trust.archive)
    _ = try remote.verified(local: engine.identity.descriptor, previous: trust)
    guard try await index.checkpoint() == genesis.body.legacyCheckpoint else { throw ReplicationError.inventoryChanged }
    let binding = C1ReplicationBinding(
      serviceURL: legacy.serviceURL, spaceId: trust.spaceId, legacyRouteId: legacy.routeId,
      localDeviceId: engine.identity.descriptor.deviceId)
    let store = try await engine.activateReplication4(remote.archive)
    try engine.repository.save(binding, key: "replication4/relay-binding")
    return try C1ReplicationService(engine: engine, binding: binding, store: store)
  }
  /// The bootstrap digest must be obtained from an already trusted device,
  /// after the new device's independent public key has been authorized.
  public static func prepareAuthorizedDevice(
    repository: TogetherRepository, identity: DeviceIdentity, binding: C1ReplicationBinding,
    archive: AuthorizationArchive, trustedGenesisDigest: String
  ) throws {
    let trust = try SpaceAuthorization.restore(archive)
    guard try trust.genesis.digest == trustedGenesisDigest,
      trust.containsActive(identity.descriptor),
      binding.localDeviceId == identity.descriptor.deviceId, binding.spaceId == trust.spaceId,
      try repository.operationCount() == 0
    else { throw ReplicationError.unauthorized }
    if let prior = try repository.load(LocalIdentityMetadata.self, key: "local-identity") {
      guard prior.deviceId == identity.descriptor.deviceId,
        prior.userId == identity.descriptor.userId,
        prior.spaceId == identity.descriptor.initialSpaceId
      else { throw ReplicationError.unauthorized }
    }
    try repository.saveAtomically([
      "replication4/authorization": CanonicalJSON.encode(trust.archive),
      "replication4/relay-binding": CanonicalJSON.encode(binding),
      "local-identity": CanonicalJSON.encode(
        LocalIdentityMetadata(
          deviceId: identity.descriptor.deviceId, userId: identity.descriptor.userId,
          spaceId: identity.descriptor.initialSpaceId)),
      "replication4/local-device": CanonicalJSON.encode(identity.descriptor),
      "initial-time-zone": CanonicalJSON.encode(trust.genesis.body.sharedTimeZoneIdentifier),
    ])
  }
}
