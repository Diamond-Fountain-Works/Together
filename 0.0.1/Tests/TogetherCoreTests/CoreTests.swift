import Foundation
import Testing
@testable import TogetherCore

@Suite("Core") @MainActor struct CoreTests {
    @Test func signaturesAndProfiles() throws {
        let identity = try DeviceIdentity()
        let repository = try TogetherRepository(inMemory: true)
        let engine = try ReplicaEngine(repository: repository, identity: identity)
        #expect(engine.ownProfile?.displayName == "我")
        #expect(engine.operations.allSatisfy { $0.verified(by: identity.descriptor) })
        try engine.updateProfile(name: "Alice", label: "Partner", avatar: nil)
        #expect(engine.ownProfile?.displayName == "Alice")
        let decoded = try CanonicalJSON.decode(SignedOperation.self, from: CanonicalJSON.encode(engine.operations.last!))
        #expect(decoded.verified(by: identity.descriptor))
    }
}
