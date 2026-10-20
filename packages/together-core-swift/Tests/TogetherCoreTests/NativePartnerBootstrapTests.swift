import Foundation
import Testing
@testable import TogetherCore

private struct NativePartnerContactVector: Decodable {
    var nowMs: Int64
    var bodyCanonical: String
    var contact: NativePartnerContact
}

@Suite("Native transport first-partnership adapter") @MainActor struct NativePartnerBootstrapTests {
    @Test func sharedSignedContactVectorRejectsTamperingExpiryAndEndpointSubstitution() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("qa/project.json").path) { break }
            root.deleteLastPathComponent()
        }
        let vector = try CanonicalJSON.decode(NativePartnerContactVector.self,
            from: Data(contentsOf: root.appendingPathComponent("protocol/fixtures/native-partner-contact-v1.json")))
        let now = Date(timeIntervalSince1970: Double(vector.nowMs) / 1_000)
        try vector.contact.verify(now: now)
        #expect(vector.contact.body.expiresAt - vector.contact.body.issuedAt == 28_800_000)
        #expect(String(data: try CanonicalJSON.encode(vector.contact.body), encoding: .utf8) == vector.bodyCanonical)
        #expect(throws: ReplicationError.self) { try vector.contact.verify(now: Date(timeIntervalSince1970: Double(vector.contact.body.expiresAt) / 1_000)) }
        #expect(throws: ReplicationError.self) { try vector.contact.verify(now: now, expectedInvitationId: UUID()) }
        #expect(throws: ReplicationError.self) { try vector.contact.verify(now: now, connectedEndpointId: String(repeating: "b", count: 64)) }
        var forged = vector.contact; forged.body.relayURL = "https://other.invalid/"
        #expect(throws: ReplicationError.self) { try forged.verify(now: now) }
        forged = vector.contact; forged.body.expiresAt = Int64.min
        #expect(throws: ReplicationError.self) { try forged.verify(now: now) }
        // An old contact can remain a pinned routing hint, but is not a fresh invitation.
        try vector.contact.verifySignature(connectedEndpointId: vector.contact.body.endpointId)
        let synthetic = try DeviceIdentity(protocolVersion: 4)
        var legacyBody = try NativePartnerContact.issue(identity: synthetic, invitationId: UUID(),
            endpointId: String(repeating: "b", count: 64), relayURL: "https://relay.example.invalid/",
            directAddresses: [], now: now).body
        legacyBody.expiresAt = legacyBody.issuedAt + 600_000
        let legacy = NativePartnerContact(body: legacyBody, signature: try synthetic.sign(CanonicalJSON.encode(legacyBody)))
        try legacy.verifySignature()
        #expect(throws: ReplicationError.self) { try legacy.verify(now: now) }
    }

    @Test func bothConsentsPrecedeHistoryAndExistingBootstrapActivatesSameDurableGenesis() async throws {
        let a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity(protocolVersion: 3))
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity(protocolVersion: 4))
        let first = try a.createTask(title: "Synthetic A before pairing")
        let second = try b.createTask(title: "Synthetic B before pairing")
        try a.setProfile(name: "Synthetic Mac", label: .boyfriend)
        try b.setProfile(name: "Synthetic Android", label: .girlfriend)
        let aId = a.identity.descriptor, bId = b.identity.descriptor, invitation = UUID()
        var aOut: [Data] = [], bOut: [Data] = [], errors: [Error] = []
        var completed: [SignedSpaceGenesis] = []
        let left = try NativePartnerBootstrapChannel(engine: a, invitationId: invitation, remote: bId,
            send: { aOut.append($0) }, complete: { genesis, _ in completed.append(genesis) },
            proposal: { _ in }, failed: { errors.append($0) })
        let right = try NativePartnerBootstrapChannel(engine: b, invitationId: invitation, remote: aId,
            send: { bOut.append($0) }, complete: { genesis, _ in completed.append(genesis) },
            proposal: { _ in }, failed: { errors.append($0) })
        defer { left.invalidate(); right.invalidate() }
        try await left.start(); try await right.start()
        for bytes in aOut { try right.receive(bytes) }; aOut.removeAll()
        for bytes in bOut { try left.receive(bytes) }; bOut.removeAll()
        #expect(left.verificationCode == right.verificationCode)
        #expect(left.remoteDisplayName == "Synthetic Android")
        #expect(right.remoteDisplayName == "Synthetic Mac")
        await #expect(throws: ReplicationError.self) { try await left.confirm(verified: false) }
        try await left.confirm(verified: true)
        for bytes in aOut { try right.receive(bytes) }; aOut.removeAll()
        #expect(a.peer == nil && b.peer == nil)
        #expect(!a.usesReplication4 && !b.usesReplication4)
        try await right.confirm(verified: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while completed.count != 2, errors.isEmpty, ContinuousClock.now < deadline {
            let fromA = aOut; aOut.removeAll()
            for bytes in fromA { try right.receive(bytes) }
            let fromB = bOut; bOut.removeAll()
            for bytes in fromB { try left.receive(bytes) }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(errors.isEmpty)
        #expect(completed.count == 2)
        #expect(completed.first == completed.last)
        #expect(a.identity.descriptor == aId && b.identity.descriptor == bId)
        #expect(a.usesReplication4 && b.usesReplication4)
        #expect(a.snapshot == b.snapshot)
        #expect(a.snapshot.tasks[first] != nil && a.snapshot.tasks[second] != nil)
        #expect(a.operations.count == b.operations.count)
        #expect(try a.repository.load(RelayBinding.self, key: "relay-binding") == nil)
        #expect(try b.repository.load(C1ReplicationBinding.self, key: "replication4/relay-binding") == nil)
        #expect(throws: ReplicationError.self) {
            try NativePartnerBootstrapChannel(engine: a, invitationId: invitation, remote: bId,
                send: { _ in }, complete: { _, _ in }, proposal: { _ in }, failed: { _ in })
        }
    }
}
