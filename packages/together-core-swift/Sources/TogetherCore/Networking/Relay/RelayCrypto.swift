import Foundation
import CryptoKit

/// A local ephemeral key may survive several legitimate peer reconnects.
/// Never reconstruct a prior transcript/counter pair under that same key.
struct RelayHandshakeHistory {
    private var used:Set<String>=[]
    mutating func accept(_ hello:RelaySignedHello)throws {
        let digest=ReplicationHash.digest(try CanonicalJSON.encode(hello))
        guard hello.verified(),used.count<64,used.insert(digest).inserted else{throw ReplicationError.unauthorized}
    }
}

struct RelayHelloBody: Codable, Equatable, Sendable {
    var protocolVersion = 1
    var routeId: UUID
    var descriptor: DeviceDescriptor
    var profileName: String
    var ephemeralKey: Data
    var nonce: UUID
    var replicationVersion: Int?
    var authorizationDigest: String?
}
struct RelaySignedHello: Codable, Equatable, Sendable {
    var body: RelayHelloBody
    var signature: Data
    func verified() -> Bool {
        guard [1, 2].contains(body.protocolVersion), [2, 3, 4].contains(body.descriptor.protocolVersion),
              (body.protocolVersion == 1 ? body.replicationVersion == nil && body.authorizationDigest == nil : body.replicationVersion == 4 && body.authorizationDigest.map(ReplicationHash.valid) == true), body.descriptor.publicKey.count == 32,
              body.ephemeralKey.count == 32, body.profileName.count <= 80,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: body.descriptor.publicKey),
              let bytes = try? CanonicalJSON.encode(body) else { return false }
        return key.isValidSignature(signature, for: bytes)
    }
}
struct RelayConsentBody: Codable, Sendable { var transcript: String; var deviceId: UUID; var approved = true }
struct RelaySignedConsent: Codable, Sendable {
    var body: RelayConsentBody
    var signature: Data
    func verified(by device: DeviceDescriptor, transcript: String) -> Bool {
        guard body.deviceId == device.deviceId, body.transcript == transcript, body.approved,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: device.publicKey), let bytes = try? CanonicalJSON.encode(body) else { return false }
        return key.isValidSignature(signature, for: bytes)
    }
}
struct RelayCipherHeader: Codable, Equatable, Sendable { var version = 1; var sessionId: String; var senderId: UUID; var recipientId: UUID; var sequence: UInt64 }
struct RelayPacket: Codable, Sendable {
    var kind: String
    var hello: RelaySignedHello?
    var consent: RelaySignedConsent?
    var header: RelayCipherHeader?
    var ciphertext: Data?
}

/// Standard CryptoKit primitives, with a documented application transcript/framing layer.
/// No claim of independent protocol review, Double Ratchet, encrypted at-rest files or mailbox delivery.
final class RelaySecureSession {
    let localHello: RelaySignedHello
    let remoteHello: RelaySignedHello
    let transcript: String
    private let outgoingKey: SymmetricKey
    private let incomingKey: SymmetricKey
    private let framingVersion: Int
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    init(identity: DeviceIdentity, ephemeral: Curve25519.KeyAgreement.PrivateKey, local: RelaySignedHello, remote: RelaySignedHello, expectedPeer: DeviceDescriptor? = nil, authorization: SpaceAuthorization? = nil, nativePartner: Bool = false) throws {
        guard local.verified(), remote.verified(), local.body.routeId == remote.body.routeId,
              local.body.descriptor == identity.descriptor, local.body.ephemeralKey == ephemeral.publicKey.rawRepresentation,
              remote.body.descriptor.deviceId != identity.descriptor.deviceId, local.body.protocolVersion == remote.body.protocolVersion else { throw TogetherError.invalid(Copy.text("copy.error.1bb768d4d83d")) }
        if let trust = authorization {
            guard local.body.protocolVersion == 2, local.body.routeId == trust.spaceId,
                  trust.containsActive(identity.descriptor), trust.containsActive(remote.body.descriptor),
                  try local.body.authorizationDigest == trust.digest, remote.body.authorizationDigest == local.body.authorizationDigest else { throw ReplicationError.unauthorized }
            framingVersion = 2
        } else {
            guard local.body.protocolVersion == 1, remote.body.descriptor.userId != identity.descriptor.userId else { throw ReplicationError.unauthorized }
            guard identity.descriptor.protocolVersion == remote.body.descriptor.protocolVersion ||
                    (nativePartner && [3, 4].contains(identity.descriptor.protocolVersion) && [3, 4].contains(remote.body.descriptor.protocolVersion)) else { throw FinanceError.peerUpgrade }
            framingVersion = 1
        }
        if let peer = expectedPeer {
            guard peer.deviceId == remote.body.descriptor.deviceId, peer.userId == remote.body.descriptor.userId,
                  peer.publicKey == remote.body.descriptor.publicKey, peer.initialSpaceId == remote.body.descriptor.initialSpaceId else { throw TogetherError.invalid(Copy.text("copy.error.c9b56a8dcd51")) }
        }
        localHello = local; remoteHello = remote
        let hellos = [local, remote].sorted { $0.body.descriptor.deviceId.uuidString < $1.body.descriptor.deviceId.uuidString }
        let digest = Data(SHA256.hash(data: try CanonicalJSON.encode(hellos)))
        transcript = digest.map { String(format: "%02x", $0) }.joined()
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote.body.ephemeralKey))
        let mine = identity.descriptor.deviceId.uuidString, theirs = remote.body.descriptor.deviceId.uuidString
        outgoingKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: digest, sharedInfo: Data("Together-Relay-\(framingVersion):\(mine):\(theirs)".utf8), outputByteCount: 32)
        incomingKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: digest, sharedInfo: Data("Together-Relay-\(framingVersion):\(theirs):\(mine)".utf8), outputByteCount: 32)
    }
    static func hello(identity: DeviceIdentity, ephemeral: Curve25519.KeyAgreement.PrivateKey, routeId: UUID, profileName: String, authorization: SpaceAuthorization? = nil) throws -> RelaySignedHello {
        if let authorization {guard authorization.spaceId == routeId, authorization.containsActive(identity.descriptor) else {throw ReplicationError.unauthorized}}
        let body = RelayHelloBody(protocolVersion: authorization == nil ? 1 : 2, routeId: routeId, descriptor: identity.descriptor, profileName: profileName, ephemeralKey: ephemeral.publicKey.rawRepresentation, nonce: UUID(), replicationVersion: authorization == nil ? nil : 4, authorizationDigest: try authorization?.digest)
        return RelaySignedHello(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
    }
    func consent(identity: DeviceIdentity) throws -> RelaySignedConsent {
        let body = RelayConsentBody(transcript: transcript, deviceId: identity.descriptor.deviceId)
        return RelaySignedConsent(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
    }
    func seal(_ bytes: Data) throws -> RelayPacket {
        guard bytes.count < 360_000, sent < 4_294_967_294 else { throw TogetherError.invalid(Copy.text("copy.error.91f104dcd050")) }
        sent += 1
        let header = RelayCipherHeader(version: framingVersion, sessionId: transcript, senderId: localHello.body.descriptor.deviceId, recipientId: remoteHello.body.descriptor.deviceId, sequence: sent)
        var nonceBytes = Data([0, 0, 0, 0]); var counter = sent.bigEndian; withUnsafeBytes(of: &counter) { nonceBytes.append(contentsOf: $0) }
        let box = try ChaChaPoly.seal(bytes, using: outgoingKey, nonce: ChaChaPoly.Nonce(data: nonceBytes), authenticating: CanonicalJSON.encode(header))
        return RelayPacket(kind: "encrypted", header: header, ciphertext: box.combined)
    }
    func open(_ packet: RelayPacket) throws -> Data {
        guard packet.kind == "encrypted", let header = packet.header, let data = packet.ciphertext,
              header.version == framingVersion, header.sessionId == transcript, header.senderId == remoteHello.body.descriptor.deviceId,
              header.recipientId == localHello.body.descriptor.deviceId, header.sequence == received + 1,
              data.count < 360_032 else { throw TogetherError.invalid(Copy.text("copy.error.0a7d59aa530e")) }
        let bytes = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: incomingKey, authenticating: CanonicalJSON.encode(header))
        received = header.sequence; return bytes
    }
}
