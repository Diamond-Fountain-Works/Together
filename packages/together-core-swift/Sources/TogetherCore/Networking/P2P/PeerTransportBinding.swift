import CryptoKit
import Foundation

/// Additive transport credential; never replaces a Protocol 4 device identity.
/// Addresses may change, but the TLS endpoint key is pinned by this signature.
public struct PeerTransportBindingBody: Codable, Equatable, Sendable {
    public var version = 1
    public var transport = "iroh-quic"
    public var spaceId: UUID
    public var device: DeviceDescriptor
    public var endpointId: String
    public var authorizationDigest: String
}

public struct PeerTransportBinding: Codable, Equatable, Sendable {
    public var body: PeerTransportBindingBody
    public var signature: Data

    public static func issue(identity: DeviceIdentity, endpointId: String,
                             authorization: SpaceAuthorization) throws -> Self {
        guard authorization.containsActive(identity.descriptor), validEndpoint(endpointId),
              independentEndpoint(endpointId, authorization: authorization) else {
            throw ReplicationError.unauthorized
        }
        let body = PeerTransportBindingBody(spaceId: authorization.spaceId,
            device: identity.descriptor, endpointId: endpointId,
            authorizationDigest: try authorization.digest)
        return Self(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
    }

    public func verify(endpointId: String, authorization: SpaceAuthorization) throws {
        guard body.version == 1, body.transport == "iroh-quic",
              body.spaceId == authorization.spaceId,
              body.authorizationDigest == (try authorization.digest),
              authorization.containsActive(body.device),
              Self.validEndpoint(endpointId), body.endpointId == endpointId,
              Self.independentEndpoint(endpointId, authorization: authorization),
              signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: body.device.publicKey),
              key.isValidSignature(signature, for: try CanonicalJSON.encode(body)) else {
            throw ReplicationError.unauthorized
        }
    }

    private static func validEndpoint(_ id: String) -> Bool {
        id.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func independentEndpoint(_ id: String, authorization: SpaceAuthorization) -> Bool {
        !authorization.devices.values.contains {
            $0.descriptor.publicKey.map { String(format: "%02x", $0) }.joined() == id
        }
    }
}

/// Reuses the existing signed Protocol 4 hello/consent and authenticated cipher.
/// A successful QUIC connection is insufficient: both the TLS endpoint binding
/// and the current authorization archive are checked before opening content.
public actor AuthorizedPeerCipher {
    public let hello: Data
    public private(set) var isAuthenticated = false
    private let identity: DeviceIdentity
    private let remote: PeerTransportBinding
    private let localHello: RelaySignedHello
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private var secure: RelaySecureSession?

    public init(identity: DeviceIdentity, remote: PeerTransportBinding,
                connectedEndpointId: String, authorization: SpaceAuthorization) throws {
        try remote.verify(endpointId: connectedEndpointId, authorization: authorization)
        guard authorization.containsActive(identity.descriptor),
              remote.body.device.deviceId != identity.descriptor.deviceId else {
            throw ReplicationError.unauthorized
        }
        self.identity = identity; self.remote = remote
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        self.ephemeral = ephemeral
        let local = try RelaySecureSession.hello(identity: identity, ephemeral: ephemeral,
            routeId: authorization.spaceId, profileName: identity.descriptor.displayName,
            authorization: authorization)
        localHello = local
        hello = try CanonicalJSON.encode(RelayPacket(kind: "hello", hello: local))
    }

    private func validate(_ authorization: SpaceAuthorization) throws {
        let digest = try authorization.digest
        guard authorization.containsActive(identity.descriptor),
              authorization.containsActive(remote.body.device),
              remote.body.authorizationDigest == digest,
              localHello.body.authorizationDigest == digest else {
            throw ReplicationError.staleAuthorization
        }
        // The immutable endpoint credential was signature-verified at init.
        // Matching current trust here avoids re-verifying it for every frame.
    }

    /// Send a returned consent on the same ordered stream. No implicit pairing:
    /// this API accepts only devices already authorized by the supplied archive.
    public func handshake(_ bytes: Data, authorization: SpaceAuthorization) throws -> Data? {
        try validate(authorization)
        guard bytes.count <= 16_384, !isAuthenticated else { throw ReplicationError.bounds }
        let packet = try CanonicalJSON.decode(RelayPacket.self, from: bytes)
        switch packet.kind {
        case "hello":
            guard secure == nil, let hello = packet.hello,
                  hello.body.descriptor == remote.body.device else { throw ReplicationError.unauthorized }
            let channel = try RelaySecureSession(identity: identity, ephemeral: ephemeral,
                local: localHello, remote: hello, expectedPeer: remote.body.device,
                authorization: authorization)
            secure = channel
            return try CanonicalJSON.encode(RelayPacket(kind: "consent", consent: channel.consent(identity: identity)))
        case "consent":
            guard let secure, let consent = packet.consent,
                  consent.verified(by: remote.body.device, transcript: secure.transcript) else {
                throw ReplicationError.unauthorized
            }
            isAuthenticated = true
            return nil
        default: throw ReplicationError.unauthorized
        }
    }

    public func seal(_ content: Data, authorization: SpaceAuthorization) throws -> Data {
        try validate(authorization)
        guard isAuthenticated, let secure else { throw ReplicationError.unauthorized }
        return try CanonicalJSON.encode(secure.seal(content))
    }

    public func open(_ packet: Data, authorization: SpaceAuthorization) throws -> Data {
        try validate(authorization)
        guard isAuthenticated, let secure, packet.count <= 524_288 else {
            throw ReplicationError.unauthorized
        }
        return try secure.open(CanonicalJSON.decode(RelayPacket.self, from: packet))
    }
}
