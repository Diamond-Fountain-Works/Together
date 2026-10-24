import Foundation
import Testing
import TogetherCore
@testable import TogetherP2P

private struct StoredNativeBinding: Codable {
    var remote: NativePartnerContact
    var invitationId: UUID
}

@Suite("Native App pairing recovery", .timeLimit(.minutes(1))) @MainActor
struct NativeAppRecoveryTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("together-native-app-recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    private func paired(_ root: URL) async throws -> (ReplicaEngine, NativePartnerContact) {
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("Together.store")), identity: DeviceIdentity(protocolVersion: 4))
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity(protocolVersion: 4))
        _ = try a.createTask(title: "Synthetic recoverable local task")
        let invitation = UUID()
        let contact = try NativePartnerContact.issue(identity: b.identity, invitationId: invitation,
            endpointId: String(repeating: "b", count: 64), relayURL: "https://relay.example.invalid/", directAddresses: [])
        try a.repository.save(StoredNativeBinding(remote: contact, invitationId: invitation), key: "native-app/pending-binding")
        try Data(repeating: 7, count: 32).write(to: root.appendingPathComponent("native-transport.key"))
        var aOut: [Data] = [], bOut: [Data] = [], errors: [Error] = []
        var completed = 0
        let left = try NativePartnerBootstrapChannel(engine: a, invitationId: invitation, remote: b.identity.descriptor,
            send: { aOut.append($0) }, complete: { _, _ in completed += 1 }, proposal: { _ in }, failed: { errors.append($0) })
        let right = try NativePartnerBootstrapChannel(engine: b, invitationId: invitation, remote: a.identity.descriptor,
            send: { bOut.append($0) }, complete: { _, _ in completed += 1 }, proposal: { _ in }, failed: { errors.append($0) })
        defer { left.invalidate(); right.invalidate() }
        try await left.start(); try await right.start()
        for bytes in aOut { try right.receive(bytes) }; aOut.removeAll()
        for bytes in bOut { try left.receive(bytes) }; bOut.removeAll()
        try await left.confirm(verified: true); try await right.confirm(verified: true)
        let deadline = CompatibilityClock.now.advanced(by: .seconds(10))
        while completed != 2, errors.isEmpty, CompatibilityClock.now < deadline {
            let fromA = aOut; aOut.removeAll(); for bytes in fromA { try right.receive(bytes) }
            let fromB = bOut; bOut.removeAll(); for bytes in fromB { try left.receive(bytes) }
            try await CompatibilityClock.sleep(for: .milliseconds(5))
        }
        #expect(errors.isEmpty)
        #expect(completed == 2)
        #expect(a.usesReplication4)
        return (a, contact)
    }
    @Test func candidateWithoutAuthorizedGenesisDoesNotGrantTrust() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("Together.store")), identity: DeviceIdentity(protocolVersion: 4))
        let b = try DeviceIdentity(protocolVersion: 4), invitation = UUID()
        let contact = try NativePartnerContact.issue(identity: b, invitationId: invitation, endpointId: String(repeating: "b", count: 64), relayURL: "https://relay.example.invalid/", directAddresses: [])
        try a.repository.save(StoredNativeBinding(remote: contact, invitationId: invitation), key: "native-app/pending-binding")
        let service = try NativeAppPeerService(engine: a, root: root)
        #expect(service.state == .unpaired)
        #expect(!a.usesReplication4 && a.peer == nil)
        #expect(try a.repository.load(StoredNativeBinding.self, key: "native-app/peer-binding") == nil)
    }
    @Test func validCoSignedGenesisRepairsOnlyMissingRoutingCommit() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let (engine, contact) = try await paired(root)
        let identity = engine.identity.descriptor, ids = engine.operations.map(\.id), space = engine.context.spaceId
        let service = try NativeAppPeerService(engine: engine, root: root)
        #expect(!service.needsRecovery && service.state == .offline)
        let saved = try engine.repository.load(StoredNativeBinding.self, key: "native-app/peer-binding")
        #expect(saved?.remote == contact)
        #expect(engine.identity.descriptor == identity && engine.operations.map(\.id) == ids && engine.context.spaceId == space)
    }
    @Test func forgedCandidateAndMissingTransportKeyFailClosed() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let (engine, contact) = try await paired(root)
        var forged = contact; forged.body.endpointId = String(repeating: "a", count: 64)
        try engine.repository.save(StoredNativeBinding(remote: forged, invitationId: contact.body.invitationId), key: "native-app/pending-binding")
        let forgedService = try NativeAppPeerService(engine: engine, root: root)
        #expect(forgedService.needsRecovery && forgedService.state == .error)
        #expect(try engine.repository.load(StoredNativeBinding.self, key: "native-app/peer-binding") == nil)
        try engine.repository.save(StoredNativeBinding(remote: contact, invitationId: contact.body.invitationId), key: "native-app/pending-binding")
        try FileManager.default.removeItem(at: root.appendingPathComponent("native-transport.key"))
        let missingService = try NativeAppPeerService(engine: engine, root: root)
        #expect(missingService.needsRecovery)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("native-transport.key").path))
    }
    @Test func invalidFinalBindingCannotBeSilentlyReplacedByPendingCandidate() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let (engine, contact) = try await paired(root)
        var forged = contact; forged.body.invitationId = UUID()
        try engine.repository.save(StoredNativeBinding(remote: forged, invitationId: contact.body.invitationId), key: "native-app/peer-binding")
        let service = try NativeAppPeerService(engine: engine, root: root)
        #expect(service.needsRecovery)
        let saved = try engine.repository.load(StoredNativeBinding.self, key: "native-app/peer-binding")
        #expect(saved?.remote == forged)
    }
}
