import CryptoKit
import Foundation

/// Transport-neutral adapter around the existing first-partnership protocol.
/// Apps must validate both signed transport contacts and the native TLS endpoint
/// before calling this API. No route server or fabricated C1 binding is used.
@MainActor public final class NativePartnerBootstrapChannel {
    public private(set) var verificationCode: String?
    public private(set) var remoteDisplayName: String?
    private let engine: ReplicaEngine
    private let remote: DeviceDescriptor
    private let localHello: RelaySignedHello
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private let send: @MainActor (Data) async throws -> Void
    private let complete: @MainActor (SignedSpaceGenesis, AuthorizedReplicationStore) async throws -> Void
    private let proposal: @MainActor (String) -> Void
    private let failed: @MainActor (Error) -> Void
    private var secure: RelaySecureSession?
    private var bootstrap: PartnerBootstrapSession?
    private var localApproved = false
    private var remoteApproved = false
    private var valid = true
    private var started = false

    public init(engine: ReplicaEngine, invitationId: UUID, remote: DeviceDescriptor,
                send: @escaping @MainActor (Data) async throws -> Void,
                complete: @escaping @MainActor (SignedSpaceGenesis, AuthorizedReplicationStore) async throws -> Void,
                proposal: @escaping @MainActor (String) -> Void,
                failed: @escaping @MainActor (Error) -> Void) throws {
        guard !engine.usesReplication4, engine.peer == nil, !engine.isCompletingPartnership,
              remote.deviceId != engine.identity.descriptor.deviceId,
              remote.userId != engine.identity.descriptor.userId,
              [3, 4].contains(remote.protocolVersion) else { throw ReplicationError.unauthorized }
        self.engine = engine; self.remote = remote; self.send = send
        self.complete = complete; self.proposal = proposal; self.failed = failed
        let key = Curve25519.KeyAgreement.PrivateKey(); ephemeral = key
        localHello = try RelaySecureSession.hello(identity: engine.identity, ephemeral: key,
            routeId: invitationId, profileName: engine.ownProfile?.displayName ?? engine.identity.descriptor.displayName)
    }

    public func start() async throws {
        guard valid, !started else { throw ReplicationError.unauthorized }
        started = true
        try await send(CanonicalJSON.encode(RelayPacket(kind: "hello", hello: localHello)))
    }

    public func receive(_ bytes: Data) throws {
        guard valid, started, bytes.count <= 360_032 else { throw ReplicationError.bounds }
        let packet = try CanonicalJSON.decode(RelayPacket.self, from: bytes)
        switch packet.kind {
        case "hello":
            guard secure == nil, let hello = packet.hello, hello.body.descriptor == remote else {
                throw ReplicationError.unauthorized
            }
            let session = try RelaySecureSession(identity: engine.identity, ephemeral: ephemeral,
                local: localHello, remote: hello, expectedPeer: remote, nativePartner: true)
            secure = session
            let number = Int(session.transcript.prefix(8), radix: 16) ?? 0
            let code = String(format: "%06d", number % 1_000_000)
            verificationCode = code; remoteDisplayName = hello.body.profileName; proposal(code)
        case "consent":
            guard let secure, let consent = packet.consent, !remoteApproved,
                  consent.verified(by: remote, transcript: secure.transcript) else {
                throw ReplicationError.unauthorized
            }
            remoteApproved = true; try beginIfReady()
        case "encrypted":
            guard localApproved, remoteApproved, let secure, let bootstrap else {
                throw ReplicationError.unauthorized
            }
            try bootstrap.receive(CanonicalJSON.decode(PartnerBootstrapFrame.self, from: secure.open(packet)))
        default: throw ReplicationError.incompatibleProtocol
        }
    }

    public func confirm(verified: Bool) async throws {
        guard valid, verified, !localApproved, let secure else { throw ReplicationError.unauthorized }
        localApproved = true
        try await send(CanonicalJSON.encode(RelayPacket(kind: "consent", consent: secure.consent(identity: engine.identity))))
        try beginIfReady()
    }

    public func invalidate() { valid = false; bootstrap?.invalidate(); bootstrap = nil }

    private func beginIfReady() throws {
        guard valid, localApproved, remoteApproved, bootstrap == nil, let secure else { return }
        try engine.bindNativePartnerForTransport(peer: PairedPeer(descriptor: remote, host: "", port: 0))
        let session = PartnerBootstrapSession(engine: engine, remote: remote,
            send: { [weak self, weak secure] frame in
                guard let self, self.valid, let secure, self.secure === secure else { throw CancellationError() }
                try await self.send(CanonicalJSON.encode(secure.seal(CanonicalJSON.encode(frame))))
            }, complete: { [weak self] genesis in
                guard let self, self.valid else { throw CancellationError() }
                try genesis.verify(existingPins: self.engine.context)
                let store = try await self.engine.activateReplication4(AuthorizationArchive(genesis: genesis, events: []))
                try self.engine.repository.save(false, key: "partner4/pending")
                try await self.complete(genesis, store)
            }, failed: { [weak self] error in if let self, self.valid { self.failed(error) } })
        bootstrap = session; session.start()
    }
}
