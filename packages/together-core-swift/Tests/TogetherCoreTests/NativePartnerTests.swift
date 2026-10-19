import Foundation
import Testing
import CryptoKit
@testable import TogetherCore

@Suite("Native partner pairing", .serialized) @MainActor struct NativePartnerTests {
    @Test func mixedRootVersionsRequireExplicitNativePurpose() throws {
        let a = try DeviceIdentity(protocolVersion: 3), b = try DeviceIdentity(protocolVersion: 4)
        let ka = Curve25519.KeyAgreement.PrivateKey(), kb = Curve25519.KeyAgreement.PrivateKey(), route = UUID()
        let ha = try RelaySecureSession.hello(identity: a, ephemeral: ka, routeId: route, profileName: "Synthetic A")
        let hb = try RelaySecureSession.hello(identity: b, ephemeral: kb, routeId: route, profileName: "Synthetic B")
        #expect(throws: (any Error).self) { try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb) }
        let left = try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb, nativePartner: true)
        let right = try RelaySecureSession(identity: b, ephemeral: kb, local: hb, remote: ha, nativePartner: true)
        let packet = try left.seal(Data("Synthetic private payload".utf8))
        #expect(try right.open(packet) == Data("Synthetic private payload".utf8))
        #expect(throws: (any Error).self) { try right.open(packet) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_RELAY_TESTS"] == "1"))
    func bothInvitationDirectionsKeepOwnHistoryAndActivateProtocol4() async throws {
        let origin = try #require(URL(string: ProcessInfo.processInfo.environment["TOGETHER_RELAY_TEST_URL"] ?? ""))
        for androidInvites in [false, true] {
            let a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity(protocolVersion: 3))
            let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity(protocolVersion: 4))
            let left = PairingService(engine: a, serviceURL: origin), right = PairingService(engine: b, serviceURL: origin)
            defer { left.disconnect(); right.disconnect() }
            let ownA = try a.createTask(title: "Synthetic pre-pair A"), ownB = try b.createTask(title: "Synthetic pre-pair B")
            let keyA = a.identity.descriptor, keyB = b.identity.descriptor
            let creator = androidInvites ? right : left, joiner = androidInvites ? left : right
            await creator.createInvitation(); await joiner.joinInvitation(try #require(creator.invitationCode))
            do { try await eventually({left.proposal != nil && right.proposal != nil}, seconds: 20) }
            catch { Issue.record("Handshake: \(left.errorMessage ?? "none") / \(right.errorMessage ?? "none")"); throw error }
            #expect(left.proposal?.verificationCode == right.proposal?.verificationCode)
            await left.confirmPairing(); #expect(a.peer == nil && b.peer == nil)
            await right.confirmPairing()
            do { try await eventually({a.usesReplication4 && b.usesReplication4 && left.isOnline && right.isOnline && a.snapshot == b.snapshot}, seconds: 30) }
            catch { Issue.record("Bootstrap: \(left.state) \(left.errorMessage ?? "none") / \(right.state) \(right.errorMessage ?? "none")"); throw error }
            #expect(a.identity.descriptor == keyA && b.identity.descriptor == keyB)
            #expect(a.context.spaceId == b.context.spaceId)
            #expect(b.snapshot.tasks[ownA] != nil && a.snapshot.tasks[ownB] != nil)
            #expect(!a.isCompletingPartnership && !b.isCompletingPartnership)
        }
    }
}
