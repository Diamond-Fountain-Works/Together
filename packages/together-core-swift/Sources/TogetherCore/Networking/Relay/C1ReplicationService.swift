import CryptoKit
import Foundation
@preconcurrency import Network
import Combine

private struct C1DirectedPacket: Codable {
  var kind = "relay4"
  var senderDeviceId: UUID
  var recipientDeviceId: UUID
  var packet: RelayPacket
}
private struct C1Presence: Codable {
  var kind: String
  var spaceId: UUID
  var devices: [UUID]
  var authorizationDigest: String
}


@MainActor private final class C1PeerChannel {
  let remote: DeviceDescriptor
  let ephemeral: Curve25519.KeyAgreement.PrivateKey
  let hello: RelaySignedHello
  var secure: RelaySecureSession?
  var handshakeHistory=RelayHandshakeHistory()
  var approved = false
  var replication: PagedReplicationSession?
  var media: OperationLogSyncSession?
  init(remote: DeviceDescriptor, identity: DeviceIdentity, trust: SpaceAuthorization, name: String)
    throws
  {
    self.remote = remote
    ephemeral = Curve25519.KeyAgreement.PrivateKey()
    hello = try RelaySecureSession.hello(
      identity: identity, ephemeral: ephemeral, routeId: trust.spaceId, profileName: name,
      authorization: trust)
  }
}

/// Explicit protocol-4 C1 mode, using the same native WebSocket transport,
/// operation database, projector and chunked media implementation as protocol 3.
/// It is activated only after a verified, co-signed migration, never by an
/// untrusted server capability flag or a profile's claimed user ID.
@MainActor public final class C1ReplicationService: ObservableObject {
  @Published public private(set) var state: PairingConnectionState = .offline
  @Published public private(set) var errorMessage: String?
  @Published public private(set) var connectedDevices: Set<UUID> = []
  @Published public private(set) var completedSyncCount = 0
  public var onStateChanged: ((PairingConnectionState) -> Void)?
  public var onConverged: (() -> Void)?
  private let engine: ReplicaEngine
  private let transport: any SyncTransport
  private let api: RelayAPI
  private let binding: C1ReplicationBinding
  private let store: AuthorizedReplicationStore
  private let ledger: DeviceAcknowledgementLedger
  private var channels: [UUID: C1PeerChannel] = [:]
  private var incoming: [Data] = []
  private var incomingBytes = 0
  private var receiver: Task<Void, Never>?
  private var outgoing: [(Data, CheckedContinuation<Void, any Error>)] = []
  private var outgoingBytes = 0
  private var sender: Task<Void, Never>?
  private var retry: Task<Void, Never>?
  private var announcedRevision: UInt64 = 0
  private var attempt = 0
  private var enabled = false
  private var opening = false
  private var nextSendAt: CompatibilityClock.Instant?
  private var generation = UUID()
  private let monitor = NWPathMonitor()
  public init(
    engine: ReplicaEngine, binding: C1ReplicationBinding, store: AuthorizedReplicationStore,
    transport: (any SyncTransport)? = nil
  ) throws {
    guard binding.localDeviceId == engine.identity.descriptor.deviceId else {
      throw ReplicationError.unauthorized
    }
    self.engine = engine
    self.binding = binding
    self.store = store
    api = try RelayAPI(base: binding.serviceURL, identity: engine.identity)
    ledger = DeviceAcknowledgementLedger(
      repository: engine.repository, index: store.index, identity: engine.identity)
    self.transport = transport ?? RelayWebSocketTransport()
    engine.onOperationsChanged = { [weak self] in self?.synchronize() }
    self.transport.onReceive = { [weak self] bytes in self?.enqueueIncoming(bytes) }
    self.transport.onError = { [weak self] error in self?.failed(error) }
    monitor.pathUpdateHandler = { [weak self] path in
      if path.status == .satisfied {
        Task { @MainActor in
          guard let self, self.enabled, self.transport.state != .connected,
            self.transport.state != .connecting, !self.opening
          else { return }
          self.retry?.cancel()
          self.retry = nil
          self.attempt = 0
          await self.open()
        }
      }
    }
    monitor.start(queue: DispatchQueue(label: "com.together.c1.multidevice.path"))
  }
  public func progress(for operationId: UUID) async throws -> OperationDeliveryProgress {
    var transferring: Set<UUID> = []
    for (id, channel) in channels {
      if let session = channel.replication,
        await session.transferringOperations.contains(operationId)
      {
        transferring.insert(id)
      }
    }
    return try await ledger.progress(
      for: store.index.entry(for: operationId), trust: store.authorization,
      transferringTo: transferring)
  }
  public func authorizationArchive() async -> AuthorizationArchive {
    await store.authorization.archive
  }
  public func start() async {
    enabled = true
    await open()
  }
  public func stop() {
    enabled = false
    retry?.cancel()
    retry = nil
    reset()
    transport.disconnect()
    setState(.offline)
  }
  public func reconnect() async {
    enabled = true
    attempt = 0
    retry?.cancel()
    retry = nil
    await open()
  }
  public func synchronize() {
    announcedRevision = engine.repository.operationRevision
    let token = generation
    for channel in channels.values where channel.approved {
      Task { [weak self] in
        do { try await channel.replication?.synchronize() } catch {
          if let self, self.generation == token, self.enabled { self.failed(error) }
        }
      }
    }
  }
  public func devices() async -> [AuthorizedDevice] {
    await store.authorization.devices.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }
  public func createDeviceOffer(now: Date = Date()) async throws -> DeviceEnrollmentOffer {
    let offer = try await DeviceEnrollmentOffer.issue(identity: engine.identity, trust: store.authorization, binding: binding, now: now)
    try engine.repository.save(offer, key: "replication4/enrollment/offer/\(offer.body.id)")
    return offer
  }
  public func approveDeviceRequest(_ request: DeviceEnrollmentRequest, verified: Bool, now: Date = Date()) async throws -> DeviceEnrollmentCompletion {
    guard verified else { throw DeviceEnrollmentError.confirmationRequired }
    let prefix = "replication4/enrollment/", id = request.body.offerId.uuidString
    guard let offer = try engine.repository.load(DeviceEnrollmentOffer.self, key: prefix + "offer/" + id),
      offer.body.issuerDeviceId == engine.identity.descriptor.deviceId else { throw ReplicationError.unauthorized }
    try request.verify(offer: offer)
    if let done = try engine.repository.load(DeviceEnrollmentCompletion.self, key: prefix + "complete/" + id) {
      guard try done.body.requestDigest == request.digest else { throw ReplicationError.contentCollision }
      let current = await store.authorization
      guard current.containsActive(request.body.device) else { throw ReplicationError.revoked }
      if done.body.archive == current.archive { return done }
      // A retry must not export trust older than revocations already known by
      // the issuer. Re-sign the same request against current public history;
      // this does not issue another device grant or change its identity.
      let refreshed = try DeviceEnrollmentCompletion.issue(request: request, offer: offer,
        trust: current, binding: binding, identity: engine.identity)
      try engine.repository.save(refreshed, key: prefix + "complete/" + id)
      return refreshed
    }
    _ = try offer.verify(now: now)
    if let claimed = try engine.repository.load(String.self, key: prefix + "claimed/" + id) {
      guard try claimed == request.digest else { throw ReplicationError.contentCollision }
    } else { try engine.repository.save(request.digest, key: prefix + "claimed/" + id) }
    let trust = await store.authorization
    if let existing = trust.devices[request.body.device.deviceId] {
      guard existing.isActive, existing.descriptor == request.body.device else { throw ReplicationError.unauthorized }
    } else { try await addMyDevice(request.body.device) }
    let completion = try await DeviceEnrollmentCompletion.issue(request: request, offer: offer,
      trust: store.authorization, binding: binding, identity: engine.identity)
    try engine.repository.save(completion, key: prefix + "complete/" + id)
    return completion
  }
  /// The caller presents the independent new device fingerprint for explicit
  /// user confirmation before invoking this authorization command.
  public func addMyDevice(_ descriptor: DeviceDescriptor) async throws {
    let trust = await store.authorization
    let event = try trust.grant(descriptor, authorizedBy: engine.identity)
    try await publish(event, previous: trust)
  }
  public func revokeDevice(_ id: UUID) async throws {
    let trust = await store.authorization
    let frontier = try await store.frontier(deviceId: id)
    let event = try trust.revoke(id, at: frontier, authorizedBy: engine.identity)
    try await publish(event, previous: trust)
  }
  private func publish(_ event: SignedDeviceAuthorization, previous: SpaceAuthorization)
    async throws
  {
    let state = try await api.authorize4(binding.spaceId, event: event)
    _ = try state.verified(local: engine.identity.descriptor, previous: previous)
    try await store.updateAuthorization(state.archive)
    try await engine.refreshFromReplication(store)
    if enabled { await open() }
  }
  private func setState(_ value: PairingConnectionState) {
    state = value
    onStateChanged?(value)
  }
  private func open() async {
    guard enabled, !opening else { return }
    opening = true
    defer { opening = false }
    do {
      reset()
      transport.disconnect()
      setState(.waiting)
      let previous = await store.authorization
      let state = try await api.space4(binding.spaceId)
      _ = try state.verified(local: engine.identity.descriptor, previous: previous)
      try await store.updateAuthorization(state.archive)
      do { try await engine.refreshFromReplication(store) } catch ReplicationError
        .missingPredecessor
      { /* New device downloads its sealed baseline before projection. */  }
      let ticket = try await api.ticket4(binding.spaceId)
      guard enabled else { return }
      try await transport.connect(
        .relay(url: api.websocketURL4(binding.spaceId), ticket: ticket.ticket))
    } catch { if enabled { failed(error) } }
  }
  private func enqueueIncoming(_ bytes: Data) {
    guard enabled, bytes.count <= FrameDecoder.maximum, incomingBytes + bytes.count <= 8_388_608
    else {
      failed(ReplicationError.bounds)
      return
    }
    incoming.append(bytes)
    incomingBytes += bytes.count
    guard receiver == nil else { return }
    let token = generation
    receiver = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        guard let self, self.generation == token, !self.incoming.isEmpty else {
          self?.receiver = nil
          return
        }
        let data = self.incoming.removeFirst()
        self.incomingBytes -= data.count
        do { try await self.receive(data) } catch {
          if self.generation == token, self.enabled { self.failed(error) }
          return
        }
      }
    }
  }
  private func receive(_ bytes: Data) async throws {
    let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    if object?["kind"] as? String == "waiting4" { return }
    let trust = await store.authorization
    if object?["kind"] as? String == "status4" {
      let presence = try CanonicalJSON.decode(C1Presence.self, from: bytes)
      guard presence.spaceId == trust.spaceId, presence.devices.count <= 32,
        try presence.authorizationDigest == trust.digest
      else { throw ReplicationError.staleAuthorization }
      let online = Set(presence.devices).subtracting([engine.identity.descriptor.deviceId])
      for id in Set(channels.keys).subtracting(online) {
        if let channel = channels.removeValue(forKey: id) {
          channel.media?.invalidate()
          await channel.replication?.invalidate()
        }
        connectedDevices.remove(id)
      }
      for id in online.sorted(by: { $0.uuidString < $1.uuidString }) where channels[id] == nil {
        guard let remote = trust.devices[id], remote.revokedAt == nil else {
          throw ReplicationError.unauthorized
        }
        let channel = try C1PeerChannel(
          remote: remote.descriptor, identity: engine.identity, trust: trust,
          name: engine.ownProfile?.displayName ?? "")
        channels[id] = channel
        try await send(RelayPacket(kind: "hello", hello: channel.hello), to: id)
      }
      if connectedDevices.isEmpty { setState(.waiting) }
      return
    }
    let directed = try CanonicalJSON.decode(C1DirectedPacket.self, from: bytes)
    guard directed.kind == "relay4",
      directed.recipientDeviceId == engine.identity.descriptor.deviceId,
      let channel = channels[directed.senderDeviceId], trust.containsActive(channel.remote)
    else { throw ReplicationError.unauthorized }
    let packet = directed.packet
    switch packet.kind {
    case "hello":
      guard let remote = packet.hello, remote.body.descriptor.deviceId == channel.remote.deviceId,
        trust.containsActive(remote.body.descriptor)
      else { throw ReplicationError.unauthorized }
      if channel.secure?.remoteHello == remote { return }
      if channel.secure != nil {
        channel.approved = false
        channel.media?.invalidate()
        await channel.replication?.invalidate()
        channel.replication = nil
        try await send(
          RelayPacket(kind: "hello", hello: channel.hello), to: channel.remote.deviceId)
      }
      let secure = try RelaySecureSession(
        identity: engine.identity, ephemeral: channel.ephemeral, local: channel.hello,
        remote: remote, expectedPeer: channel.remote, authorization: trust)
      try channel.handshakeHistory.accept(remote)
      channel.secure = secure
      try await send(
        RelayPacket(kind: "consent", consent: secure.consent(identity: engine.identity)),
        to: channel.remote.deviceId)
    case "consent":
      guard let secure = channel.secure, let consent = packet.consent,
        consent.verified(by: channel.remote, transcript: secure.transcript)
      else { throw ReplicationError.unauthorized }
      if channel.approved { return }
      channel.approved = true
      connectedDevices.insert(channel.remote.deviceId)
      setState(.syncing)
      let remoteId = channel.remote.deviceId
      let token = generation
      let transcript = secure.transcript
      let replication = PagedReplicationSession(
        store: store, ledger: ledger, remote: channel.remote,
        send: { [weak self] frame in
          try await self?.sendContent(
            .replication(frame), to: remoteId, generation: token, transcript: transcript)
        },
        onConverged: { [weak self] in
          await self?.converged(remoteId, generation: token, transcript: transcript)
        })
      channel.replication = replication
      channel.media = OperationLogSyncSession(
        engine: engine, remote: channel.remote, mediaOnly: true
      ) { [weak self] payload in
        Task { @MainActor in
          do {
            try await self?.sendContent(
              .media(payload), to: remoteId, generation: token, transcript: transcript)
          } catch { if let self, self.generation == token, self.enabled { self.failed(error) } }
        }
      }
      try await replication.synchronize()
    case "encrypted":
      guard channel.approved, let secure = channel.secure, let replication = channel.replication
      else { throw ReplicationError.unauthorized }
      switch try CanonicalJSON.decode(C1Content.self, from: secure.open(packet)) {
      case .replication(let frame): try await replication.receive(frame)
      case .media(let payload):
        try channel.media?.receive(payload)
        if case .mediaFailure = payload {
          for peer in channels.values where peer.approved { try peer.media?.synchronizeMedia() }
        }
      }
    default: throw ReplicationError.incompatibleProtocol
    }
  }
  private func converged(_ id: UUID, generation token: UUID, transcript: String) async {
    guard enabled, generation == token, channels[id]?.secure?.transcript == transcript else {
      return
    }
    do {
      try await engine.refreshFromReplication(store)
      guard enabled, generation == token, channels[id]?.secure?.transcript == transcript else {
        return
      }
      try engine.reconcileRecurrence()
      try engine.reconcileFinanceBills()
      try channels[id]?.media?.synchronizeMedia()
      if announcedRevision != engine.repository.operationRevision { synchronize() }
      completedSyncCount += 1
      attempt = 0
      errorMessage = nil
      setState(.connected)
      onConverged?()
    } catch {
      if enabled, generation == token, channels[id]?.secure?.transcript == transcript {
        failed(error)
      }
    }
  }
  private func sendContent(
    _ value: C1Content, to id: UUID, generation token: UUID, transcript: String
  ) async throws {
    guard generation == token, channels[id]?.secure?.transcript == transcript else {
      throw CancellationError()
    }
    guard let channel = channels[id], channel.approved, let secure = channel.secure else {
      throw ReplicationError.unauthorized
    }
    try await send(secure.seal(CanonicalJSON.encode(value)), to: id)
  }
  private func send(_ packet: RelayPacket, to id: UUID) async throws {
    let bytes = try CanonicalJSON.encode(
      C1DirectedPacket(
        senderDeviceId: engine.identity.descriptor.deviceId, recipientDeviceId: id, packet: packet))
    guard enabled, bytes.count <= FrameDecoder.maximum, outgoingBytes + bytes.count <= 8_388_608
    else { throw ReplicationError.bounds }
    try await withCheckedThrowingContinuation { continuation in
      outgoing.append((bytes, continuation))
      outgoingBytes += bytes.count
      guard sender == nil else { return }
      let token = generation
      sender = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          guard let self, self.generation == token, !self.outgoing.isEmpty else {
            self?.sender = nil
            return
          }
          let (data, completion) = self.outgoing.removeFirst()
          self.outgoingBytes -= data.count
          do {
            let clock = CompatibilityClock()
            let now = clock.now
            let target = self.nextSendAt ?? now
            if target > now { try await clock.sleep(until: target) }
            guard self.generation == token, !Task.isCancelled else { throw CancellationError() }
            self.nextSendAt = max(clock.now, target).advanced(by: .milliseconds(10))
            try await self.transport.send(data)
            completion.resume()
          } catch {
            completion.resume(throwing: error)
            if self.generation == token, self.enabled { self.failed(error) }
            return
          }
        }
      }
    }
  }
  private func reset() {
    generation = UUID()
    nextSendAt = nil
    receiver?.cancel()
    receiver = nil
    sender?.cancel()
    sender = nil
    for channel in channels.values {
      channel.media?.invalidate()
      if let session = channel.replication { Task { await session.invalidate() } }
    }
    channels = [:]
    connectedDevices = []
    incoming = []
    incomingBytes = 0
    for (_, completion) in outgoing { completion.resume(throwing: CancellationError()) }
    outgoing = []
    outgoingBytes = 0
  }
  private func failed(_ error: Error) {
    errorMessage = error.localizedDescription
    reset()
    transport.disconnect()
    setState(.error)
    guard enabled, retry == nil else { return }
    let delay = min(60, pow(2, Double(min(attempt, 6))))
    attempt += 1
    retry = Task { @MainActor [weak self] in
      try? await CompatibilityClock.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self else { return }
      self.retry = nil
      await self.open()
    }
  }
}
