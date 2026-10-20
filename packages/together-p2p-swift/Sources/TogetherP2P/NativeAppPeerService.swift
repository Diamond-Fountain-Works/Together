import Foundation
import Observation
import TogetherCore

private struct NativeAppBinding: Codable {
    var remote: NativePartnerContact
    var invitationId: UUID
}

/// Optional native-app transport adapter. The domain engine, signed log,
/// bootstrap, inventory, projector and receipt ledger are the existing core.
/// Production release targets do not link this package.
@MainActor @Observable public final class NativeAppPeerService {
    public private(set) var state: PairingConnectionState = .unpaired
    public private(set) var errorMessage: String?
    public private(set) var invitationCode: String?
    public private(set) var invitationExpiresAt: Date?
    public private(set) var verificationCode: String?
    public private(set) var remoteName = ""
    public private(set) var remoteFingerprint = ""
    public private(set) var paths: [P2PPath] = []
    public private(set) var completedSyncCount = 0
    public private(set) var latestOperationProgress: OperationDeliveryProgress?
    public private(set) var needsRecovery = false
    public private(set) var rejectedUnverifiedIncoming = 0
    public private(set) var lastUnverifiedIncomingError: String?
    public private(set) var stage = "idle"
    public var isOnline: Bool { state == .connected || state == .syncing }
    public var busy: Bool { state == .waiting && verificationCode == nil }
    @ObservationIgnored private let engine: ReplicaEngine
    @ObservationIgnored private let root: URL
    @ObservationIgnored private var endpoint: IrohEndpoint?
    @ObservationIgnored private var link: IrohFrameConnection?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var bootstrap: NativePartnerBootstrapChannel?
    @ObservationIgnored private var cipher: AuthorizedPeerCipher?
    @ObservationIgnored private var store: AuthorizedReplicationStore?
    @ObservationIgnored private var ledger: DeviceAcknowledgementLedger?
    @ObservationIgnored private var session: PagedReplicationSession?
    @ObservationIgnored private var media: AuthenticatedPeerMediaChannel?
    @ObservationIgnored private var contentWriter: OrderedEncryptedContentWriter?
    @ObservationIgnored private var remoteContact: NativePartnerContact?
    @ObservationIgnored private var localContact: NativePartnerContact?
    @ObservationIgnored private var pendingBinding: PeerTransportBinding?
    @ObservationIgnored private var binding: NativeAppBinding?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var phase = "idle"

    public init(engine: ReplicaEngine, root: URL) throws {
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        let allowed = ["/tmp", "/private/tmp", FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path]
        guard canonical.lastPathComponent.hasPrefix("together-native-app-"), allowed.contains(canonical.deletingLastPathComponent().path),
              engine.repository.storageURL?.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == canonical else {
            throw P2PTransportError.invalidAddress
        }
        self.engine = engine; self.root = canonical
        do {
            let saved = try engine.repository.load(NativeAppBinding.self, key: "native-app/peer-binding")
            let candidate = try engine.repository.load(NativeAppBinding.self, key: "native-app/pending-binding")
            if let value = saved ?? candidate, engine.usesReplication4 {
                try Self.verifyRestoredBinding(value, engine: engine, root: canonical)
                // Promotion repairs only the post-genesis local metadata gap.
                // A candidate alone never authorizes a device or creates trust.
                if saved == nil { try engine.repository.save(value, key: "native-app/peer-binding") }
                binding = value
            } else if saved != nil || engine.peer != nil || engine.isCompletingPartnership {
                throw ReplicationError.unauthorized
            }
            state = binding == nil ? .unpaired : .offline
        } catch {
            needsRecovery = true; state = .error
            errorMessage = Copy.text("native.error.pairingRecovery")
            stage = "blocked-pairing-recovery"
        }
        engine.onOperationsChanged = { [weak self] in self?.localOperationsChanged() }
        try? writeDiagnostic()
    }
    private static func verifyRestoredBinding(_ binding: NativeAppBinding, engine: ReplicaEngine, root: URL) throws {
        try binding.remote.verifySignature(expectedInvitationId: binding.invitationId)
        guard let archive = try engine.repository.load(AuthorizationArchive.self, key: "replication4/authorization"),
              let peer = engine.peer?.descriptor,
              peer == binding.remote.body.descriptor else { throw ReplicationError.unauthorized }
        let trust = try SpaceAuthorization.restore(archive, existingPins: engine.context)
        let roots = trust.genesis.body.roots
        guard roots.count == 2, Set(roots.map(\.deviceId)) == Set([engine.identity.descriptor.deviceId, peer.deviceId]),
              roots.contains(engine.identity.descriptor), roots.contains(peer),
              trust.containsActive(engine.identity.descriptor), trust.containsActive(peer),
              roots.allSatisfy({ $0.publicKey.map { String(format: "%02x", $0) }.joined() != binding.remote.body.endpointId }) else {
            throw ReplicationError.unauthorized
        }
        let keyURL = root.appendingPathComponent("native-transport.key")
        let info = try keyURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == 32 else { throw P2PTransportError.invalidAddress }
    }
    public func restore() { guard binding != nil, !needsRecovery else { return }; reconnect() }
    public func createInvitation() {
        guard binding == nil, !needsRecovery else { return }
        launch { service, endpoint, token in
            let id = UUID(), address = await endpoint.address()
            let contact = try NativePartnerContact.issue(identity: service.engine.identity, invitationId: id,
                endpointId: address.endpointId, relayURL: address.relayURL, directAddresses: address.directAddresses)
            service.localContact = contact
            service.invitationCode = String(decoding: try CanonicalJSON.encode(contact), as: UTF8.self)
            service.invitationExpiresAt = Date(timeIntervalSince1970: Double(contact.body.expiresAt) / 1000)
            service.state = .waiting; service.recordStage("waiting-for-partner")
            let link = try await service.waitForPartner(endpoint: endpoint, generation: token, expiresAt: contact.body.expiresAt)
            try await service.own(link, generation: token)
            let bytes = try await link.receive()
            try service.requireGeneration(token)
            let remote = try CanonicalJSON.decode(NativePartnerContact.self, from: bytes)
            try remote.verify(expectedInvitationId: id, connectedEndpointId: await link.remoteEndpointId())
            guard remote.body.descriptor.userId != service.engine.identity.descriptor.userId else { throw ReplicationError.unauthorized }
            try await link.send(CanonicalJSON.encode(contact))
            try service.requireGeneration(token)
            try await service.attach(link, remote: remote, invitationId: id)
        }
    }
    public func joinInvitation(_ text: String) {
        guard binding == nil, !needsRecovery else { return }
        do {
            guard let bytes = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), bytes.count <= 16_384 else { throw ReplicationError.bounds }
            let remote = try CanonicalJSON.decode(NativePartnerContact.self, from: bytes)
            try remote.verify()
            launch { service, endpoint, token in
                let address = await endpoint.address()
                let contact = try NativePartnerContact.issue(identity: service.engine.identity, invitationId: remote.body.invitationId,
                    endpointId: address.endpointId, relayURL: address.relayURL, directAddresses: address.directAddresses)
                service.localContact = contact
                service.recordStage("connecting-native-peer")
                let link = try await endpoint.connect(to: P2PAddress(endpointId: remote.body.endpointId, relayURL: remote.body.relayURL, directAddresses: remote.body.directAddresses))
                try await service.own(link, generation: token)
                try await link.send(CanonicalJSON.encode(contact))
                try service.requireGeneration(token)
                let echoed = try CanonicalJSON.decode(NativePartnerContact.self, from: await link.receive())
                try service.requireGeneration(token)
                try echoed.verify(expectedInvitationId: remote.body.invitationId, connectedEndpointId: await link.remoteEndpointId())
                guard echoed == remote else { throw ReplicationError.unauthorized }
                try await service.attach(link, remote: remote, invitationId: remote.body.invitationId)
            }
        } catch { fail(error) }
    }
    public func confirmPairing(verified: Bool) {
        Task { @MainActor in do { try await bootstrap?.confirm(verified: verified) } catch { fail(error) } }
    }
    public func disconnect() {
        enabled = false; retry?.cancel(); retry = nil; worker?.cancel(); worker = nil
        invitationCode = nil; invitationExpiresAt = nil
        closeSession(); state = binding == nil ? .unpaired : .offline; recordStage("offline")
        if let endpoint { self.endpoint = nil; Task { try? await endpoint.close() } }
    }
    public func reconnect() {
        guard let binding, !needsRecovery else { return }
        launch { service, endpoint, token in
            guard let archive = try service.engine.repository.load(AuthorizationArchive.self, key: "replication4/authorization") else { throw ReplicationError.unauthorized }
            let trust = try SpaceAuthorization.restore(archive, existingPins: service.engine.context)
            guard trust.containsActive(binding.remote.body.descriptor) else { throw ReplicationError.unauthorized }
            let link: IrohFrameConnection
            if service.engine.identity.descriptor.deviceId.uuidString < binding.remote.body.descriptor.deviceId.uuidString {
                link = try await endpoint.connect(to: P2PAddress(endpointId: binding.remote.body.endpointId,
                    relayURL: binding.remote.body.relayURL, directAddresses: binding.remote.body.directAddresses))
            } else { link = try await endpoint.accept(expectedEndpointId: binding.remote.body.endpointId) }
            try await service.own(link, generation: token)
            service.remoteContact = binding.remote
            try await service.beginReplication(trust: trust, link: link, generation: token)
            try service.requireGeneration(token)
            service.read(link)
        }
    }
    public func synchronize() {
        guard let session else { return }; state = .syncing
        let token = generation
        Task { @MainActor in
            do { try await session.synchronize(); try await refreshProgress() }
            catch { if token == generation { fail(error) } }
        }
    }
    private func localOperationsChanged() {
        // A previous operation's receipt says nothing about this new fact.
        // Clear it synchronously, including while intentionally offline.
        latestOperationProgress = nil
        try? writeDiagnostic()
        synchronize()
    }
    private func requireGeneration(_ token: UUID) throws {
        try Task.checkCancellation()
        guard enabled, generation == token else { throw CancellationError() }
    }
    private func own(_ link: IrohFrameConnection, generation token: UUID) async throws {
        do { try requireGeneration(token) }
        catch { await link.close(); throw error }
        self.link = link
    }
    private func waitForPartner(endpoint: IrohEndpoint, generation token: UUID, expiresAt: Int64) async throws -> IrohFrameConnection {
        // This budget bounds hostile pre-authentication work, without extending
        // connection timeouts or turning a bad signed contact into an accepted
        // peer. Cancel closes the endpoint as well as cancelling this task.
        for _ in 0..<16 {
            try requireGeneration(token)
            guard Date().timeIntervalSince1970 * 1000 < Double(expiresAt) else { throw ReplicationError.unauthorized }
            do { return try await endpoint.acceptForPartnerBootstrap() }
            catch let error as P2PUnverifiedIncomingError {
                try requireGeneration(token)
                rejectedUnverifiedIncoming += 1
                lastUnverifiedIncomingError = String(describing: error)
                recordStage("waiting-after-rejected-unverified-incoming")
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw ReplicationError.bounds
    }
    private func launch(_ action: @escaping @MainActor (NativeAppPeerService, IrohEndpoint, UUID) async throws -> Void) {
        let oldEndpoint = endpoint; endpoint = nil
        worker?.cancel(); retry?.cancel(); retry = nil; closeSession()
        enabled = true; state = .waiting; errorMessage = nil
        rejectedUnverifiedIncoming = 0; lastUnverifiedIncomingError = nil
        let token = generation
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // The pinned foreign accept future may ignore Task.cancel.
                // Closing its owning endpoint guarantees it cannot consume a
                // connection intended for this new attempt.
                try await oldEndpoint?.close()
                try requireGeneration(token)
                let endpoint = try await prepareEndpoint(generation: token)
                try requireGeneration(token)
                try await action(self, endpoint, token)
            } catch is CancellationError {} catch { if token == generation { fail(error) } }
        }
    }
    private func prepareEndpoint(generation token: UUID) async throws -> IrohEndpoint {
        if let endpoint { return endpoint }
        recordStage("binding-native-endpoint")
        let keyURL = root.appendingPathComponent("native-transport.key")
        let key: Data
        if FileManager.default.fileExists(atPath: keyURL.path) {
            key = try Data(contentsOf: keyURL); guard key.count == 32 else { throw P2PTransportError.invalidAddress }
        } else {
            guard binding == nil else { throw P2PTransportError.invalidAddress }
            key = IrohEndpoint.generateTransportKey(); try key.write(to: keyURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        let endpoint = try await IrohEndpoint.bind(secretKey: key, connectivity: .automatic,
            applicationProtocol: P2PTransportLimits.nativeAppALPN)
        do { try requireGeneration(token) }
        catch { try? await endpoint.close(); throw error }
        self.endpoint = endpoint
        guard try await endpoint.waitForRelayAddress(timeout: .seconds(15)) else { throw P2PTransportError.relayReadiness }
        try requireGeneration(token)
        return endpoint
    }
    private func attach(_ link: IrohFrameConnection, remote: NativePartnerContact, invitationId: UUID) async throws {
        // This is an untrusted routing candidate until the existing mutual
        // consent/bootstrap produces a valid co-signed authorization archive.
        // Persist before activation so a crash after that durable trust commit
        // cannot strand the app merely because its routing callback did not run.
        try engine.repository.save(NativeAppBinding(remote: remote, invitationId: invitationId), key: "native-app/pending-binding")
        self.link = link; remoteContact = remote; phase = "bootstrap"; state = .waiting
        remoteName = remote.body.descriptor.displayName; remoteFingerprint = remote.body.descriptor.fingerprint
        let token = generation
        let channel = try NativePartnerBootstrapChannel(engine: engine, invitationId: invitationId, remote: remote.body.descriptor,
            send: { bytes in guard token == self.generation else { throw CancellationError() }; try await link.send(bytes) },
            complete: { genesis, store in
                guard token == self.generation else { throw CancellationError() }
                self.store = store
                self.binding = NativeAppBinding(remote: remote, invitationId: invitationId)
                try self.engine.repository.save(self.binding!, key: "native-app/peer-binding")
                self.verificationCode = nil; self.invitationCode = nil; self.invitationExpiresAt = nil
                try await self.beginReplication(trust: SpaceAuthorization(genesis: genesis, existingPins: self.engine.context), link: link, generation: token)
            }, proposal: { code in self.verificationCode = code; self.remoteName = self.bootstrap?.remoteDisplayName ?? remote.body.descriptor.displayName; self.recordStage("awaiting-identity-confirmation") },
            failed: { error in if token == self.generation { self.fail(error) } })
        bootstrap = channel; read(link)
        try await channel.start()
    }
    private func read(_ link: IrohFrameConnection) {
        reader?.cancel(); let token = generation
        reader = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let bytes = try await link.receive()
                    try Task.checkCancellation(); guard token == generation else { return }
                    try await receive(bytes, over: link)
                }
            } catch is CancellationError {} catch { if token == generation { fail(error) } }
        }
    }
    private func receive(_ bytes: Data, over link: IrohFrameConnection) async throws {
        if let credential = try? CanonicalJSON.decode(PeerTransportBinding.self, from: bytes) {
            guard phase == "bootstrap" || phase == "binding", pendingBinding == nil else { throw ReplicationError.unauthorized }
            pendingBinding = credential
            if phase == "binding" { try await acceptBinding(over: link) }
            return
        }
        switch phase {
        case "bootstrap": try bootstrap?.receive(bytes)
        case "handshake":
            guard let cipher, let store else { throw ReplicationError.unauthorized }
            let trust = await store.authorization
            if let consent = try await cipher.handshake(bytes, authorization: trust) { try await link.send(consent) }
            if await cipher.isAuthenticated { try await authenticated(link) }
        case "replication":
            guard let cipher, let store, let session, let media else { throw ReplicationError.unauthorized }
            let clear = try await cipher.open(bytes, authorization: store.authorization)
            if let frame = try media.receive(clear) {
                try await session.receive(frame)
                try await refreshProgress()
            } else { try writeDiagnostic() }
        default: throw ReplicationError.unauthorized
        }
    }
    private func beginReplication(trust: SpaceAuthorization, link: IrohFrameConnection, generation token: UUID) async throws {
        try requireGeneration(token)
        recordStage("protocol4-endpoint-binding")
        phase = "binding"; state = .syncing
        if store == nil {
            let restored = try AuthorizedReplicationStore(repository: engine.repository, identity: engine.identity, authorization: trust)
            try await restored.restore()
            try requireGeneration(token); store = restored
        }
        guard let endpoint else { throw P2PTransportError.closed }
        let address = await endpoint.address()
        try requireGeneration(token)
        let credential = try PeerTransportBinding.issue(identity: engine.identity, endpointId: address.endpointId, authorization: trust)
        try await link.send(CanonicalJSON.encode(credential))
        try requireGeneration(token)
        if pendingBinding != nil { try await acceptBinding(over: link) }
    }
    private func acceptBinding(over link: IrohFrameConnection) async throws {
        guard let pendingBinding, let store, let remoteContact else { throw ReplicationError.unauthorized }
        let token = generation
        let trust = await store.authorization
        try pendingBinding.verify(endpointId: await link.remoteEndpointId(), authorization: trust)
        try requireGeneration(token)
        guard pendingBinding.body.device == remoteContact.body.descriptor else { throw ReplicationError.unauthorized }
        let cipher = try AuthorizedPeerCipher(identity: engine.identity, remote: pendingBinding,
            connectedEndpointId: await link.remoteEndpointId(), authorization: trust)
        try requireGeneration(token)
        self.cipher = cipher; self.pendingBinding = nil; phase = "handshake"
        try await link.send(cipher.hello)
    }
    private func authenticated(_ link: IrohFrameConnection) async throws {
        guard let store, let cipher, let remote = remoteContact?.body.descriptor else { throw ReplicationError.unauthorized }
        phase = "replication"; recordStage("authenticated-paged-sync")
        let ledger = DeviceAcknowledgementLedger(repository: engine.repository, index: store.index, identity: engine.identity)
        self.ledger = ledger
        let token = generation
        let writer = OrderedEncryptedContentWriter(sealAndSend: { bytes in
            let packet = try await cipher.seal(bytes, authorization: store.authorization)
            try Task.checkCancellation()
            try await link.send(packet)
        }, failed: { [weak self] error in
            if let self, self.generation == token { self.fail(error) }
        })
        contentWriter = writer
        let media = try AuthenticatedPeerMediaChannel(engine: engine, remote: remote,
            send: { [weak self] bytes in
                guard let self, self.generation == token else { return }
                writer.submit(bytes)
            })
        media.onError = { [weak self] error in
            guard let self, self.generation == token else { return }
            self.errorMessage = String(describing: error); try? self.writeDiagnostic()
        }
        self.media = media
        let session = PagedReplicationSession(store: store, ledger: ledger, remote: remote,
            send: { frame in try await writer.send(AuthenticatedPeerMediaChannel.encodeReplication(frame)) },
            onConverged: { [weak self] in await self?.converged(token: token) })
        self.session = session
        try await session.synchronize()
    }
    private func converged(token: UUID) async {
        guard token == generation, let store else { return }
        do {
            try await engine.refreshFromReplication(store)
            guard token == generation else { return }
            try media?.synchronize()
            guard token == generation else { return }
            completedSyncCount += 1; state = .connected; errorMessage = nil; attempt = 0
            paths = await link?.paths() ?? []; recordStage("converged")
            try await refreshProgress()
        } catch { if token == generation { fail(error) } }
    }
    private func refreshProgress() async throws {
        guard let ledger, let store, let operation = engine.operations.last(where: { $0.operation.deviceId == engine.identity.descriptor.deviceId }) else { return }
        let token = generation
        let entry = try await store.index.entry(for: operation.id)
        let progress = try await ledger.progress(for: entry, trust: store.authorization)
        guard generation == token,
              engine.operations.last(where: { $0.operation.deviceId == engine.identity.descriptor.deviceId })?.id == operation.id else { return }
        latestOperationProgress = progress
        paths = await link?.paths() ?? []
        try writeDiagnostic()
    }
    private func recordStage(_ stage: String) { self.stage = stage; try? writeDiagnostic() }
    private func writeDiagnostic() throws {
        struct Diagnostic: Encodable {
            var stage: String; var state: String; var operations: Int; var completedSyncCount: Int
            var partnerPersisted: Bool; var direct: Bool; var relayed: Bool; var error: String?
            var rejectedUnverifiedIncoming: Int; var lastUnverifiedIncomingError: String?
            var mediaProgress: [MediaProgress]
        }
        let selected = paths.filter(\.selected)
        let value = Diagnostic(stage: stage, state: state.rawValue, operations: engine.operations.count,
            completedSyncCount: completedSyncCount, partnerPersisted: latestOperationProgress?.partnerHasPersisted ?? false,
            direct: selected.contains(where: \.direct), relayed: selected.contains(where: \.relayed), error: errorMessage,
            rejectedUnverifiedIncoming: rejectedUnverifiedIncoming, lastUnverifiedIncomingError: lastUnverifiedIncomingError,
            mediaProgress: engine.mediaProgress.values.sorted { $0.assetId.uuidString < $1.assetId.uuidString })
        let url = root.appendingPathComponent("native-app-state.json")
        try CanonicalJSON.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func closeSession() {
        generation = UUID(); reader?.cancel(); reader = nil; bootstrap?.invalidate(); bootstrap = nil
        media?.invalidate(); media = nil; contentWriter?.invalidate(); contentWriter = nil
        if let session { Task { await session.invalidate() } }; session = nil
        if let link { Task { await link.close() } }; link = nil
        cipher = nil; store = nil; ledger = nil; pendingBinding = nil; phase = "idle"; verificationCode = nil; paths = []
    }
    private func fail(_ error: Error) {
        if binding == nil { invitationCode = nil; invitationExpiresAt = nil }
        errorMessage = String(describing: error); state = .error; recordStage("failed-" + stage); closeSession()
        if let endpoint { self.endpoint = nil; Task { try? await endpoint.close() } }
        guard enabled, binding != nil, retry == nil else { return }
        let delay = min(60, pow(2, Double(min(attempt, 6)))); attempt += 1
        retry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }; self.retry = nil; self.reconnect()
        }
    }
}
