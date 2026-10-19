import Foundation
import Testing
@testable import TogetherCore

@Suite("Authorized P2P endpoint binding") struct PeerTransportBindingTests {
    @Test func cannotReplaceDeviceIdentityOrClaimAnEndpointWithoutItsSignature() throws {
        let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
        let endpoint = String(repeating: "a", count: 64)
        let signed = try PeerTransportBinding.issue(identity: f.a, endpointId: endpoint, authorization: trust)
        try signed.verify(endpointId: endpoint, authorization: trust)
        #expect(throws: ReplicationError.self) { try signed.verify(endpointId: String(repeating: "b", count: 64), authorization: trust) }
        var forged = signed; forged.body.endpointId = String(repeating: "b", count: 64)
        #expect(throws: ReplicationError.self) { try forged.verify(endpointId: forged.body.endpointId, authorization: trust) }
        let stranger = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
        #expect(throws: ReplicationError.self) { try PeerTransportBinding.issue(identity: stranger, endpointId: endpoint, authorization: trust) }
        #expect(throws: ReplicationError.self) { try PeerTransportBinding.issue(identity: f.a, endpointId: "bad", authorization: trust) }
    }

    @Test func currentAuthorizationRejectsRevokedAndStaleBindingsWithoutErasingHistory() throws {
        let f = try ReplicationFixture(); var trust = try SpaceAuthorization(genesis: f.genesis)
        let phone = try DeviceIdentity(userId: f.a.descriptor.userId, protocolVersion: 4)
        try trust.apply(trust.grant(phone.descriptor, authorizedBy: f.a))
        let binding = try PeerTransportBinding.issue(identity: phone, endpointId: String(repeating: "c", count: 64), authorization: trust)
        let op = try AuthorizedOperation.sign(f.operation(phone), identity: phone, trust: trust, previous: DeviceFrontier())
        try trust.apply(trust.revoke(phone.descriptor.deviceId,
            at: DeviceFrontier(sequence: 1, digest: op.digest), authorizedBy: f.a))
        #expect(throws: ReplicationError.self) { try binding.verify(endpointId: binding.body.endpointId, authorization: trust) }
        _ = try op.verify(in: trust)
        #expect(trust.spaceId == f.context.spaceId)
    }

    @Test func reuseExistingP4CipherAndRejectEarlyContentReplayAndOldSessions() async throws {
        let f = try ReplicationFixture(), trust = try SpaceAuthorization(genesis: f.genesis)
        let ad = try PeerTransportBinding.issue(identity: f.a, endpointId: String(repeating: "a", count: 64), authorization: trust)
        let bd = try PeerTransportBinding.issue(identity: f.b, endpointId: String(repeating: "b", count: 64), authorization: trust)
        let a = try AuthorizedPeerCipher(identity: f.a, remote: bd, connectedEndpointId: bd.body.endpointId, authorization: trust)
        let b = try AuthorizedPeerCipher(identity: f.b, remote: ad, connectedEndpointId: ad.body.endpointId, authorization: trust)
        await #expect(throws: ReplicationError.self) { try await a.seal(Data("private".utf8), authorization: trust) }
        let ac = try #require(await a.handshake(b.hello, authorization: trust))
        let bc = try #require(await b.handshake(a.hello, authorization: trust))
        _ = try await a.handshake(bc, authorization: trust); _ = try await b.handshake(ac, authorization: trust)
        let original = try await a.seal(Data("signed-log frame".utf8), authorization: trust)
        #expect(try await b.open(original, authorization: trust) == Data("signed-log frame".utf8))
        await #expect(throws: (any Error).self) { try await b.open(original, authorization: trust) }
        let a2 = try AuthorizedPeerCipher(identity: f.a, remote: bd, connectedEndpointId: bd.body.endpointId, authorization: trust)
        let b2 = try AuthorizedPeerCipher(identity: f.b, remote: ad, connectedEndpointId: ad.body.endpointId, authorization: trust)
        let ac2 = try #require(await a2.handshake(b2.hello, authorization: trust))
        let bc2 = try #require(await b2.handshake(a2.hello, authorization: trust))
        _ = try await a2.handshake(bc2, authorization: trust); _ = try await b2.handshake(ac2, authorization: trust)
        await #expect(throws: (any Error).self) { try await b2.open(original, authorization: trust) }
    }
}
