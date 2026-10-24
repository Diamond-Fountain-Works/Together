import Foundation
import Combine
import CryptoKit
@preconcurrency import Network

public enum ConnectionState: String, Sendable { case disconnected = "Disconnected", pairing = "Pairing", connected = "Connected", syncing = "Syncing", error = "Error" }
public struct PairingProposal: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let fingerprint: String
    public let ownFingerprint: String
    public let verificationCode: String
    public let deviceId: UUID
    public let userId: UUID
}

@MainActor public final class PeerService: ObservableObject {
    @Published public private(set) var state: ConnectionState = .disconnected
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var boundPort: UInt16 = 0
    @Published public private(set) var localHost = "127.0.0.1"
    @Published public private(set) var proposal: PairingProposal?
    @Published public private(set) var lastSynchronizedAt: Date?
    @Published public private(set) var completedSyncCount = 0
    @Published public private(set) var retryDelay: Double = 0
    public var isOnline: Bool { state == .connected || state == .syncing }
    private let engine: ReplicaEngine
    private let queue = DispatchQueue(label: "com.together.network")
    private var listener: NWListener?
    private var sessions: [UUID: PeerSession] = [:]
    private var activeId: UUID?
    private var monitor = NWPathMonitor()
    private var reconnectTask: Task<Void, Never>?
    private var reconnectEnabled = true
    private var applyingRemote = false
    private var retryAttempt = 0
    private var resolving = false
    private var running = false
    private var automaticallyManagingListener = false
    private var listenerRecoveryTask: Task<Void, Never>?
    private var listenerStarting = false

    public init(engine: ReplicaEngine) {
        self.engine = engine
        engine.onOperationsChanged = { [weak self] in self?.broadcastState() }
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in
                guard let self, self.running else { return }
                self.recoverListenerIfNeeded()
                self.retryAttempt = 0; self.reconnectTask?.cancel(); self.reconnectTask = nil; self.scheduleReconnect()
            } }
        }
        monitor.start(queue: queue)
    }
    public func restore() {
        running = true
        automaticallyManagingListener = true
        do {
            let settings = try engine.repository.load(ListenerSettings.self, key: "listener") ?? ListenerSettings()
            let host = NetworkAddressPolicy.localTailscaleAddress() ?? "127.0.0.1"
            try startListening(host: host, port: settings.port)
        } catch { fail(error) }
        beginListenerRecovery()
    }
    public func startListening(host: String, port: UInt16, persist: Bool = true) throws {
        running = true
        guard NetworkAddressPolicy.allowed(host) else { throw TogetherError.invalid(Copy.text("copy.error.1a248a72dc76")) }
        listener?.cancel()
        boundPort = 0
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let created = try NWListener(using: parameters)
        listenerStarting = true
        localHost = host; listener = created; reconnectEnabled = true
        created.stateUpdateHandler = { [weak self, weak created] status in
            Task { @MainActor in
                guard let self, self.listener === created else { return }
                switch status {
                case .ready: self.listenerStarting = false; self.boundPort = created?.port?.rawValue ?? port; self.errorMessage = nil; self.scheduleReconnect()
                case .failed(let error): self.listenerStarting = false; self.boundPort = 0; self.fail(error)
                case .cancelled: self.listenerStarting = false; self.boundPort = 0
                default: break
                }
            }
        }
        created.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection, outgoing: false) } }
        created.start(queue: queue)
        if persist { try engine.repository.save(ListenerSettings(host: host, port: port, enabled: true), key: "listener") }
        if persist { automaticallyManagingListener = true; beginListenerRecovery() }
    }
    public func stopListening() {
        let port = boundPort > 0 ? boundPort : (try? engine.repository.load(ListenerSettings.self, key: "listener"))?.port ?? 58431
        running = false
        automaticallyManagingListener = false; listenerRecoveryTask?.cancel(); listenerRecoveryTask = nil
        disconnect(); listener?.cancel(); listener = nil; boundPort = 0; listenerStarting = false
        do { try engine.repository.save(ListenerSettings(host: localHost, port: port, enabled: false), key: "listener") } catch { fail(error) }
    }
    public func connect(host: String, port: UInt16) throws {
        guard boundPort > 0 else { throw TogetherError.invalid(Copy.text("copy.error.87e5c62d9ed5")) }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NetworkAddressPolicy.validHost(host), port > 0 else { throw TogetherError.invalid(Copy.text("copy.error.6d1b80ef0dbf")) }
        guard !resolving else { return }
        reconnectEnabled = true
        if NetworkAddressPolicy.allowed(host) {
            accept(NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp), outgoing: true, requestedHost: host)
        } else {
            resolving = true
            Task { @MainActor [weak self] in
                do {
                    let address = try await Task.detached { try NetworkAddressPolicy.resolve(host) }.value
                    guard let self else { return }; self.resolving = false
                    guard self.reconnectEnabled else { return }
                    self.accept(NWConnection(host: NWEndpoint.Host(address), port: NWEndpoint.Port(rawValue: port)!, using: .tcp), outgoing: true, requestedHost: host)
                } catch { self?.resolving = false; self?.fail(error); self?.scheduleReconnect() }
            }
        }
    }
    public func disconnect() {
        reconnectEnabled = false; reconnectTask?.cancel(); reconnectTask = nil
        for session in sessions.values { session.connection.cancel() }
        sessions = [:]; activeId = nil; proposal = nil; state = .disconnected
    }
    public func confirmPairing() throws {
        guard let proposal, let session = sessions[proposal.id], let hello = session.remoteHello else { throw TogetherError.invalid(Copy.text("copy.error.0d3785894f32")) }
        try engine.authorize(PairedPeer(descriptor: hello.descriptor, host: hello.listenHost, port: hello.listenPort))
        session.localApproved = true; self.proposal = nil
        enqueue(.approve, on: session)
        try activateIfReady(session)
    }
    public func rejectPairing() { if let id = proposal?.id { sessions[id]?.connection.cancel(); sessions.removeValue(forKey: id) }; proposal = nil; state = .disconnected }
    public func synchronize() { broadcastState() }

    private func accept(_ connection: NWConnection, outgoing: Bool, requestedHost: String? = nil) {
        guard sessions.count < 3, reconnectEnabled else { connection.cancel(); return }
        let hello = HandshakeHello(descriptor: engine.identity.descriptor, nonce: UUID(), profileName: engine.ownProfile?.displayName ?? "我", listenHost: localHost, listenPort: boundPort)
        let session = PeerSession(connection: connection, outgoing: outgoing, hello: hello)
        session.requestedHost = requestedHost
        sessions[session.id] = session
        connection.stateUpdateHandler = { [weak self] status in
            Task { @MainActor in
                guard let self, self.sessions[session.id] != nil else { return }
                switch status {
                case .ready: self.enqueue(.hello(session.localHello), on: session); self.receive(session)
                case .failed(let error): self.close(session, error: error)
                case .waiting(let error): self.close(session, error: error)
                case .cancelled: self.close(session, error: nil)
                default: break
                }
            }
        }
        connection.start(queue: queue)
        session.handshakeTimeout = Task { @MainActor [weak self] in
            try? await CompatibilityClock.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.activeId != session.id else { return }
            self.close(session, error: TogetherError.invalid(Copy.text("copy.error.f459dd8f6b10")))
        }
    }
    private func receive(_ session: PeerSession) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.sessions[session.id] != nil else { return }
                do {
                    if let data { for frame in try session.decoder.append(data) { try self.process(frame, session: session) } }
                    if let error { self.close(session, error: error) }
                    else if complete { self.close(session, error: nil) }
                    else { self.receive(session) }
                } catch { self.close(session, error: error) }
            }
        }
    }
    private func process(_ frame: Data, session: PeerSession) throws {
        let envelope = try CanonicalJSON.decode(WireEnvelope.self, from: frame)
        let payload = try CanonicalJSON.decode(WirePayload.self, from: envelope.unsigned.body)
        if case let .hello(hello) = payload {
            session.negotiatedVersion = try ProtocolNegotiation.select(remote: hello.supportedProtocolVersions)
            guard hello.descriptor.protocolVersion == engine.identity.descriptor.protocolVersion else { throw FinanceError.peerUpgrade }
            guard session.remoteHello == nil, hello.descriptor.publicKey.count == 32, hello.profileName.count <= 80,
                  hello.descriptor.initialTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil,
                  hello.descriptor.deviceId != engine.identity.descriptor.deviceId,
                  hello.descriptor.userId != engine.identity.descriptor.userId,
                  envelope.unsigned.senderDeviceId == hello.descriptor.deviceId,
                  envelope.verified(publicKey: hello.descriptor.publicKey), NetworkAddressPolicy.allowed(hello.listenHost), hello.listenPort > 0 else { throw TogetherError.invalid(Copy.text("copy.error.131e158009bb")) }
            if let peer = engine.peer {
                guard peer.descriptor.deviceId == hello.descriptor.deviceId, peer.descriptor.userId == hello.descriptor.userId, peer.descriptor.publicKey == hello.descriptor.publicKey else { throw TogetherError.invalid(Copy.text("copy.error.ed91b063c711")) }
            }
            session.remoteHello = hello
            let sorted = [session.localHello, hello].sorted { $0.descriptor.deviceId.uuidString < $1.descriptor.deviceId.uuidString }
            session.sessionId = SHA256.hash(data: try CanonicalJSON.encode(sorted)).map { String(format: "%02x", $0) }.joined()
            let localFirst = engine.identity.descriptor.deviceId.uuidString < hello.descriptor.deviceId.uuidString
            let candidates = sessions.values.filter { $0.remoteHello?.descriptor.deviceId == hello.descriptor.deviceId }.sorted {
                let a = $0.outgoing == localFirst, b = $1.outgoing == localFirst
                return a != b ? a : ($0.sessionId ?? "") < ($1.sessionId ?? "")
            }
            if let chosen = candidates.first {
                for candidate in candidates where candidate.id != chosen.id { close(candidate, error: nil) }
                if chosen.id != session.id { return }
            }
            enqueue(.proof, on: session)
            return
        }
        guard let remote = session.remoteHello, let sessionId = session.sessionId,
              envelope.unsigned.sessionId == sessionId, envelope.unsigned.senderDeviceId == remote.descriptor.deviceId,
              envelope.verified(publicKey: remote.descriptor.publicKey) else { throw TogetherError.invalid(Copy.text("copy.error.3dcfa2668f3f")) }
        switch payload {
        case .proof:
            session.proved = true
            if engine.peer != nil { session.localApproved = true; enqueue(.approve, on: session) }
            else {
                state = .pairing
                let number = Int(sessionId.prefix(8), radix: 16)! % 1_000_000
                proposal = PairingProposal(id: session.id, name: remote.profileName, fingerprint: remote.descriptor.fingerprint, ownFingerprint: engine.identity.descriptor.fingerprint, verificationCode: String(format: "%06d", number), deviceId: remote.descriptor.deviceId, userId: remote.descriptor.userId)
            }
            try activateIfReady(session)
        case .approve:
            guard session.proved else { throw TogetherError.invalid(Copy.text("copy.error.a23516e042fa")) }
            session.remoteApproved = true; try activateIfReady(session)
        case .state, .operation, .finished, .mediaRequest, .mediaChunk, .mediaComplete, .mediaVerified, .mediaFailure, .giftReceipt:
            try requireActive(session)
            applyingRemote = true; defer { applyingRemote = false }
            try session.sync?.receive(payload)
        case .goodbye: close(session, error: nil)
        case .hello: break
        }
    }
    private func activateIfReady(_ session: PeerSession) throws {
        guard session.proved && session.localApproved && session.remoteApproved else { return }
        guard let remote = session.remoteHello, engine.peer?.descriptor.publicKey == remote.descriptor.publicKey else { throw TogetherError.invalid(Copy.text("copy.error.e720b5e93f34")) }
        if activeId == session.id { return }
        if let activeId, let old = sessions[activeId] {
            let localFirst = engine.identity.descriptor.deviceId.uuidString < remote.descriptor.deviceId.uuidString
            let newPreferred = session.outgoing == localFirst
            let oldPreferred = old.outgoing == localFirst
            if !newPreferred && oldPreferred { session.connection.cancel(); return }
            if newPreferred == oldPreferred && (old.sessionId ?? "") < (session.sessionId ?? "") { session.connection.cancel(); return }
            old.connection.cancel()
        }
        activeId = session.id; proposal = nil; state = .syncing
        session.handshakeTimeout?.cancel()
        try engine.authorize(PairedPeer(descriptor: remote.descriptor, host: session.requestedHost ?? remote.listenHost, port: remote.listenPort))
        let sync = OperationLogSyncSession(engine: engine, remote: remote.descriptor) { [weak self, weak session] payload in
            if let self, let session, self.activeId == session.id { self.enqueue(payload, on: session) }
        }
        sync.onConverged = { [weak self] in self?.state = .connected; self?.lastSynchronizedAt = Date(); self?.completedSyncCount += 1; self?.retryAttempt = 0; self?.retryDelay = 0; self?.errorMessage = nil }
        sync.onSyncing = { [weak self] in self?.state = .syncing }
        sync.onError = { [weak self] error in self?.errorMessage = error.localizedDescription }
        session.sync = sync; sync.synchronize()
    }
    private func requireActive(_ session: PeerSession) throws {
        guard activeId == session.id, session.negotiatedVersion == 2, session.proved, session.localApproved, session.remoteApproved else { throw TogetherError.invalid(Copy.text("copy.error.13426e0cbffb")) }
    }
    private func enqueue(_ payload: WirePayload, on session: PeerSession) {
        session.sendQueue.append(payload)
        sendNext(session)
    }
    private func sendNext(_ session: PeerSession) {
        guard !session.sending, session.sendIndex < session.sendQueue.count, sessions[session.id] != nil else { return }
        do {
            let payload = session.sendQueue[session.sendIndex]
            let isHello: Bool; if case .hello = payload { isHello = true } else { isHello = false }
            let unsigned = WireUnsigned(senderDeviceId: engine.identity.descriptor.deviceId, sessionId: isHello ? nil : session.sessionId, body: try CanonicalJSON.encode(payload))
            let envelope = WireEnvelope(unsigned: unsigned, signature: try engine.identity.sign(CanonicalJSON.encode(unsigned)))
            let bytes = try FrameDecoder.encode(CanonicalJSON.encode(envelope))
            session.sending = true
            session.connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    session.sending = false; session.sendIndex += 1
                    if let error { self.close(session, error: error) }
                    else {
                        if session.sendIndex == session.sendQueue.count { session.sendQueue = []; session.sendIndex = 0 }
                        self.sendNext(session)
                    }
                }
            })
        } catch { close(session, error: error) }
    }
    private func broadcastState() {
        guard !applyingRemote, let id = activeId, let session = sessions[id] else { return }
        state = .syncing; enqueue(.state(engine.operations.map(\.id)), on: session)
    }
    private func close(_ session: PeerSession, error: Error?) {
        guard sessions.removeValue(forKey: session.id) != nil else { return }
        session.handshakeTimeout?.cancel(); session.sync?.invalidate()
        session.connection.cancel()
        if proposal?.id == session.id { proposal = nil }
        if activeId == session.id { activeId = nil; state = .disconnected }
        if let error, activeId == nil { fail(error) }
        scheduleReconnect()
    }
    private func scheduleReconnect() {
        guard reconnectEnabled, activeId == nil, boundPort > 0, engine.peer != nil, reconnectTask == nil, !resolving else { return }
        retryDelay = min(60, pow(2, Double(min(retryAttempt, 6))))
        retryAttempt += 1
        let delay = retryDelay
        reconnectTask = Task { @MainActor [weak self] in
            try? await CompatibilityClock.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard self.activeId == nil, self.sessions.isEmpty, let peer = self.engine.peer else { return }
            do { try self.connect(host: peer.host, port: peer.port) } catch { self.fail(error); self.scheduleReconnect() }
        }
    }
    private func recoverListenerIfNeeded() {
        guard running, automaticallyManagingListener else { return }
        let address = NetworkAddressPolicy.localTailscaleAddress() ?? "127.0.0.1"
        guard (boundPort == 0 && !listenerStarting) || address != localHost else { return }
        do {
            let settings = try engine.repository.load(ListenerSettings.self, key: "listener") ?? ListenerSettings()
            try startListening(host: address, port: settings.port)
        } catch { fail(error) }
    }
    private func beginListenerRecovery() {
        guard automaticallyManagingListener, listenerRecoveryTask == nil else { return }
        listenerRecoveryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await CompatibilityClock.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.running else { return }
                self.recoverListenerIfNeeded()
            }
        }
    }
    private func fail(_ error: Error) { state = .error; errorMessage = error.localizedDescription }
}

@MainActor private final class PeerSession {
    let id = UUID()
    let connection: NWConnection
    let outgoing: Bool
    let localHello: HandshakeHello
    var remoteHello: HandshakeHello?
    var sessionId: String?
    var decoder = FrameDecoder()
    var proved = false
    var localApproved = false
    var remoteApproved = false
    var sendQueue: [WirePayload] = []
    var sendIndex = 0
    var sending = false
    var requestedHost: String?
    var requestedAssets: Set<UUID> = []
    var verifyingAssets: Set<UUID> = []
    var receiptedGifts: Set<UUID> = []
    var handshakeTimeout: Task<Void, Never>?
    var requestedRemoteDigest: String?
    var negotiatedVersion: Int?
    var sync: OperationLogSyncSession?
    init(connection: NWConnection, outgoing: Bool, hello: HandshakeHello) { self.connection = connection; self.outgoing = outgoing; localHello = hello }
}
