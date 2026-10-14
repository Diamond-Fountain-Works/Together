import Foundation
import Observation
import CryptoKit
@preconcurrency import Network

public enum PairingConnectionState: String, Sendable { case unpaired = "Unpaired", waiting = "Waiting for Partner", connected = "Connected", syncing = "Syncing", offline = "Offline", error = "Error" }
@MainActor @Observable public final class PairingService {
    public private(set) var state: PairingConnectionState = .unpaired
    public private(set) var proposal: PairingProposal?
    public private(set) var invitationCode: String?
    public private(set) var invitationExpiresAt: Date?
    public private(set) var errorMessage: String?
    public private(set) var lastSynchronizedAt: Date?
    public private(set) var completedSyncCount = 0
    public private(set) var retryDelay: Double = 0
    public private(set) var busy = false
    public private(set) var pairedFeedback = 0
    public var isOnline: Bool { state == .connected || state == .syncing }
    public var isConfigured: Bool { api != nil }
    public var needsMigration: Bool { engine.peer != nil && binding == nil }
    @ObservationIgnored private let engine: ReplicaEngine
    @ObservationIgnored private let transport: any SyncTransport
    @ObservationIgnored private var api: RelayAPI?
    @ObservationIgnored private var binding: RelayBinding?
    @ObservationIgnored private var pendingRoute: RelayRoute?
    @ObservationIgnored private var routeId: UUID?
    @ObservationIgnored private var ephemeral = Curve25519.KeyAgreement.PrivateKey()
    @ObservationIgnored private var hello: RelaySignedHello?
    @ObservationIgnored private var secure: RelaySecureSession?
    @ObservationIgnored private var localApproved = false
    @ObservationIgnored private var remoteApproved = false
    @ObservationIgnored private var serverPaired = false
    @ObservationIgnored private var logSession: OperationLogSyncSession?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var sender: Task<Void, Never>?
    @ObservationIgnored private var queue: [Data] = []
    @ObservationIgnored private var queuedBytes = 0
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var helloSentForPeer = false
    @ObservationIgnored private var peerPresent = false
    @ObservationIgnored private var openingRoute = false
    @ObservationIgnored private var monitor = NWPathMonitor()
    public init(engine: ReplicaEngine, serviceURL: URL?, transport: (any SyncTransport)? = nil) {
        self.engine = engine; self.transport = transport ?? RelayWebSocketTransport()
        binding = try? engine.repository.load(RelayBinding.self, key: "relay-binding")
        let address = binding?.serviceURL ?? serviceURL
        if let address { api = try? RelayAPI(base: address, identity: engine.identity) }
        state = engine.peer == nil ? .unpaired : .offline
        engine.onOperationsChanged = { [weak self] in self?.synchronize() }
        self.transport.onReceive = { [weak self] data in self?.receive(data) }
        self.transport.onError = { [weak self] error in self?.failed(error) }
        monitor.pathUpdateHandler = { [weak self] path in if path.status == .satisfied { Task { @MainActor in
            guard let self, self.enabled, self.binding != nil, !self.isOnline else { return }
            guard self.transport.state != .connecting, self.transport.state != .connected, !self.openingRoute else { return }
            self.attempt = 0; self.retry?.cancel(); self.retry = nil; self.scheduleReconnect()
        } } }
        monitor.start(queue: DispatchQueue(label: "com.together.relay.path"))
    }
    public func restore() {
        enabled = true
        guard let binding else { return }; routeId = binding.routeId
        Task { @MainActor [weak self] in await self?.resumeRoute() }
    }
    public func createInvitation() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let api else { throw TogetherError.invalid(Copy.text("copy.error.ac046ade4c99")) }
            enabled = true
            let invite = try await api.createInvitation(name: engine.ownProfile?.displayName ?? "我", expectedPeer: engine.peer?.descriptor)
            invitationCode = invite.code; invitationExpiresAt = invite.expiresAt; routeId = invite.routeId; errorMessage = nil; state = .waiting
            poll?.cancel(); poll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, self.enabled, let api = self.api, let id = self.routeId else { return }
                    do { let route = try await api.route(id); if route.members.count == 2 { self.pendingRoute = route; try await self.openRoute(route); return } }
                    catch { self.failed(error); return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } catch { failed(error) }
    }
    public func joinInvitation(_ code: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let api else { throw TogetherError.invalid(Copy.text("copy.error.ac046ade4c99")) }
            enabled = true
            let route = try await api.join(code: code, name: engine.ownProfile?.displayName ?? "我")
            try validateRoute(route); pendingRoute = route; routeId = route.routeId; invitationCode = nil; errorMessage = nil
            try await openRoute(route)
        } catch { failed(error) }
    }
    public func confirmPairing() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let secure, let routeId, let api, proposal != nil else { throw TogetherError.invalid(Copy.text("copy.error.e380dafc9f31")) }
            let route = try await api.confirm(routeId, transcript: secure.transcript); serverPaired = route.paired
            localApproved = true; enqueue(try CanonicalJSON.encode(RelayPacket(kind: "consent", consent: secure.consent(identity: engine.identity))))
            try activateIfReady()
        } catch { failed(error) }
    }
    public func rejectPairing() { disconnect(); proposal = nil; invitationCode = nil }
    public func disconnect() {
        enabled = false; poll?.cancel(); poll = nil; retry?.cancel(); retry = nil; resetSession(); transport.disconnect(); state = engine.peer == nil ? .unpaired : .offline
    }
    public func synchronize() { guard isOnline else { return }; logSession?.synchronize() }
    public func reconnect() { enabled = true; attempt = 0; retry?.cancel(); retry = nil; Task { @MainActor [weak self] in await self?.resumeRoute() } }
    private func validateRoute(_ route: RelayRoute) throws {
        guard !route.revoked, route.members.count == 2,
              route.members.contains(where: { $0.descriptor.deviceId == engine.identity.descriptor.deviceId && $0.descriptor.publicKey == engine.identity.descriptor.publicKey }),
              let remote = route.members.first(where: { $0.descriptor.deviceId != engine.identity.descriptor.deviceId }) else { throw TogetherError.invalid(Copy.text("copy.error.74c3af7a9477")) }
        if let peer = engine.peer { guard peer.descriptor.deviceId == remote.descriptor.deviceId, peer.descriptor.userId == remote.descriptor.userId, peer.descriptor.publicKey == remote.descriptor.publicKey, peer.descriptor.initialSpaceId == remote.descriptor.initialSpaceId else { throw TogetherError.invalid(Copy.text("copy.error.a82bbbd12564")) } }
        if let binding { guard binding.peerDeviceId == remote.descriptor.deviceId, binding.peerPublicKey == remote.descriptor.publicKey, binding.localDeviceId == engine.identity.descriptor.deviceId, binding.routeId == route.routeId else { throw TogetherError.invalid(Copy.text("copy.error.a23d12dc2813")) } }
    }
    private func resumeRoute() async {
        guard enabled, !openingRoute, let api, let id = binding?.routeId ?? routeId else { return }
        openingRoute = true; defer { openingRoute = false }
        do { let route = try await api.route(id); try validateRoute(route); pendingRoute = route; routeId = id; try await openRoute(route) }
        catch { failed(error) }
    }
    private func openRoute(_ route: RelayRoute) async throws {
        try validateRoute(route); guard let api else { return }
        resetSession(); serverPaired = route.paired; pendingRoute = route; routeId = route.routeId; state = .waiting
        hello = try RelaySecureSession.hello(identity: engine.identity, ephemeral: ephemeral, routeId: route.routeId, profileName: engine.ownProfile?.displayName ?? "我")
        let ticket = try await api.ticket(route.routeId)
        guard enabled else { return }
        try await transport.connect(.relay(url: api.websocketURL(route.routeId), ticket: ticket.ticket))
        if let hello { enqueue(try CanonicalJSON.encode(RelayPacket(kind: "hello", hello: hello))) }
    }
    private func clearPeerHandshake() {
        sender?.cancel(); sender = nil; queue = []; queuedBytes = 0; logSession?.invalidate(); logSession = nil
        secure = nil; localApproved = false; remoteApproved = false; proposal = nil
    }
    private func resetSession() {
        clearPeerHandshake()
        hello = nil; ephemeral = Curve25519.KeyAgreement.PrivateKey(); helloSentForPeer = false
    }
    private func receive(_ data: Data) {
        do {
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["kind"] as? String == "status" {
                let wasPresent = peerPresent
                serverPaired = object?["paired"] as? Bool ?? false
                peerPresent = object?["online"] as? Bool ?? false
                if peerPresent, !helloSentForPeer, let hello { helloSentForPeer = true; enqueue(try CanonicalJSON.encode(RelayPacket(kind: "hello", hello: hello))) }
                if !peerPresent {
                    // One rotation at a genuine peer disconnect gives the next
                    // session fresh keys/nonces. Duplicate status frames must
                    // not keep changing the hello while the peer reconnects.
                    if wasPresent {
                        resetSession()
                        if let route = pendingRoute { hello = try RelaySecureSession.hello(identity: engine.identity, ephemeral: ephemeral, routeId: route.routeId, profileName: engine.ownProfile?.displayName ?? "我") }
                    } else { clearPeerHandshake() }
                    state = .waiting; helloSentForPeer = false; return
                }
                try activateIfReady(); return
            }
            if object?["kind"] as? String == "waiting" { state = .waiting; return }
            let packet = try CanonicalJSON.decode(RelayPacket.self, from: data)
            switch packet.kind {
            case "hello":
                guard let remote = packet.hello, remote.verified(), let route = pendingRoute,
                      route.members.contains(where: { $0.descriptor.deviceId == remote.body.descriptor.deviceId && $0.descriptor.publicKey == remote.body.descriptor.publicKey }) else { throw TogetherError.invalid(Copy.text("copy.error.3ec52db5902b")) }
                if let secure, secure.remoteHello == remote { return }
                if secure != nil {
                    // Keep this socket's signed hello stable. Rotating our own
                    // ephemeral key in response to theirs causes symmetric
                    // re-key ping-pong and mismatched consent transcripts.
                    clearPeerHandshake()
                    if let hello { enqueue(try CanonicalJSON.encode(RelayPacket(kind: "hello", hello: hello))) }
                }
                guard let hello else { throw TogetherError.invalid(Copy.text("copy.error.92daf69006a1")) }
                let secure = try RelaySecureSession(identity: engine.identity, ephemeral: ephemeral, local: hello, remote: remote, expectedPeer: engine.peer?.descriptor)
                self.secure = secure
                if binding != nil {
                    localApproved = true; enqueue(try CanonicalJSON.encode(RelayPacket(kind: "consent", consent: secure.consent(identity: engine.identity))))
                } else {
                    let value = Int(secure.transcript.prefix(8), radix: 16) ?? 0
                    proposal = PairingProposal(id: route.routeId, name: remote.body.profileName, fingerprint: remote.body.descriptor.fingerprint, ownFingerprint: engine.identity.descriptor.fingerprint, verificationCode: String(format: "%06d", value % 1_000_000), deviceId: remote.body.descriptor.deviceId, userId: remote.body.descriptor.userId)
                }
                try activateIfReady()
            case "consent":
                guard let consent = packet.consent,
                      let remote = secure?.remoteHello.body.descriptor ?? engine.peer?.descriptor,
                      consent.verified(by: remote, transcript: consent.body.transcript) else { throw TogetherError.invalid(Copy.text("copy.error.1e116ef339c5")) }
                guard let secure, consent.body.transcript == secure.transcript else {
                    // An authenticated old-session consent grants nothing. A
                    // pinned pair may ignore it while awaiting current proof;
                    // first pairing still rejects any transcript mismatch.
                    if binding != nil { return }
                    throw TogetherError.invalid(Copy.text("copy.error.1e116ef339c5"))
                }
                remoteApproved = true; try activateIfReady()
            case "encrypted":
                guard isOnline, localApproved, remoteApproved, serverPaired, let secure, let logSession else { throw TogetherError.invalid(Copy.text("copy.error.23e90630fb77")) }
                let bytes = try secure.open(packet); try logSession.receive(CanonicalJSON.decode(WirePayload.self, from: bytes))
            default: throw TogetherError.invalid(Copy.text("copy.error.c26239f9baf2"))
            }
        } catch { failed(error) }
    }
    private func activateIfReady() throws {
        guard peerPresent, localApproved, remoteApproved, serverPaired, let secure, let routeId, let api, logSession == nil else { return }
        let remote = secure.remoteHello.body.descriptor
        let proposed = PairedPeer(descriptor: remote, host: engine.peer?.host ?? "127.0.0.1", port: engine.peer?.port ?? 0, approvedAt: engine.peer?.approvedAt ?? .now)
        let newBinding = RelayBinding(serviceURL: api.base, routeId: routeId, peerDeviceId: remote.deviceId, peerPublicKey: remote.publicKey, localDeviceId: engine.identity.descriptor.deviceId)
        let first = binding == nil
        try engine.bindRelay(peer: proposed, binding: newBinding); binding = newBinding; invitationCode = nil; invitationExpiresAt = nil; proposal = nil
        let sync = OperationLogSyncSession(engine: engine, remote: remote) { [weak self] payload in
            guard let self, let secure = self.secure else { return }
            do { self.enqueue(try CanonicalJSON.encode(secure.seal(CanonicalJSON.encode(payload)))) } catch { self.failed(error) }
        }
        sync.onSyncing = { [weak self] in self?.state = .syncing }
        sync.onConverged = { [weak self] in self?.state = .connected; self?.lastSynchronizedAt = .now; self?.completedSyncCount += 1; self?.errorMessage = nil; self?.attempt = 0; self?.retryDelay = 0 }
        sync.onError = { [weak self] error in self?.errorMessage = error.localizedDescription }
        logSession = sync; state = .syncing; if first { pairedFeedback += 1 }; sync.synchronize()
    }
    private func enqueue(_ data: Data) {
        guard data.count <= FrameDecoder.maximum, queuedBytes + data.count <= 8_388_608 else { failed(TogetherError.invalid(Copy.text("copy.error.079c79144a2f"))); return }
        queue.append(data); queuedBytes += data.count
        guard sender == nil else { return }
        sender = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.queue.isEmpty else { self?.sender = nil; return }
                let data = self.queue.removeFirst(); self.queuedBytes -= data.count
                do { try await self.transport.send(data) } catch {
                    guard !Task.isCancelled else { return }
                    self.sender = nil; self.failed(error); return
                }
            }
        }
    }
    private func failed(_ error: Error) {
        errorMessage = error.localizedDescription; state = .error; resetSession(); transport.disconnect(); scheduleReconnect()
    }
    private func scheduleReconnect() {
        guard enabled, binding != nil, retry == nil else { return }
        retryDelay = min(60, pow(2, Double(min(attempt, 6)))); attempt += 1; let delay = retryDelay
        retry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled, let self else { return }
            self.retry = nil; await self.resumeRoute()
        }
    }
}
