import CryptoKit
import Foundation

/// A self-contained, signed routing invitation. It grants no business authority.
/// The two signed consents and existing co-signed genesis still establish trust.
public struct NativePartnerContactBody: Codable, Equatable, Sendable {
    public var version = 1
    public var transport = "iroh-quic"
    public var invitationId: UUID
    public var descriptor: DeviceDescriptor
    public var endpointId: String
    public var relayURL: String?
    public var directAddresses: [String]
    public var issuedAt: Int64
    public var expiresAt: Int64
}

public struct NativePartnerContact: Codable, Equatable, Sendable {
    public var body: NativePartnerContactBody
    public var signature: Data
    public static let validityMilliseconds: Int64 = 28_800_000

    public static func issue(identity: DeviceIdentity, invitationId: UUID, endpointId: String,
                             relayURL: String?, directAddresses: [String], now: Date = .now) throws -> Self {
        let milliseconds = now.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 8_000_000_000_000_000 else {
            throw ReplicationError.bounds
        }
        let issued = Int64(milliseconds.rounded(.down))
        let body = NativePartnerContactBody(invitationId: invitationId, descriptor: identity.descriptor,
            endpointId: endpointId, relayURL: relayURL, directAddresses: directAddresses,
            issuedAt: issued, expiresAt: issued + validityMilliseconds)
        let result = Self(body: body, signature: try identity.sign(CanonicalJSON.encode(body)))
        try result.verify(now: now)
        return result
    }

    /// Expiry applies to initial invitation use, never to an already pinned pair.
    public func verify(now: Date = .now, expectedInvitationId: UUID? = nil,
                       connectedEndpointId: String? = nil) throws {
        try verifySignature(expectedInvitationId: expectedInvitationId, connectedEndpointId: connectedEndpointId)
        let milliseconds = now.timeIntervalSince1970 * 1_000
        guard body.expiresAt == body.issuedAt + Self.validityMilliseconds,
              milliseconds.isFinite, milliseconds >= Double(body.issuedAt),
              milliseconds < Double(body.expiresAt) else { throw ReplicationError.unauthorized }
    }

    public func verifySignature(expectedInvitationId: UUID? = nil, connectedEndpointId: String? = nil) throws {
        guard body.version == 1, body.transport == "iroh-quic",
              expectedInvitationId == nil || expectedInvitationId == body.invitationId,
              connectedEndpointId == nil || connectedEndpointId == body.endpointId,
              body.issuedAt >= 0, body.issuedAt < 8_000_000_000_000_000,
              [body.issuedAt + Self.validityMilliseconds, body.issuedAt + 600_000].contains(body.expiresAt),
              [3, 4].contains(body.descriptor.protocolVersion), body.descriptor.publicKey.count == 32,
              !body.descriptor.displayName.isEmpty, body.descriptor.displayName.count <= 80,
              body.descriptor.initialTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil,
              body.endpointId.count == 64,
              body.endpointId.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              body.endpointId != body.descriptor.publicKey.map({ String(format: "%02x", $0) }).joined(),
              body.directAddresses.count <= 32,
              body.directAddresses.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              body.relayURL != nil || !body.directAddresses.isEmpty,
              signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: body.descriptor.publicKey),
              key.isValidSignature(signature, for: try CanonicalJSON.encode(body)) else {
            throw ReplicationError.unauthorized
        }
        if let relay = body.relayURL {
            guard relay.utf8.count <= 2_048, let url = URLComponents(string: relay),
                  url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { throw ReplicationError.unauthorized }
        }
    }
}
