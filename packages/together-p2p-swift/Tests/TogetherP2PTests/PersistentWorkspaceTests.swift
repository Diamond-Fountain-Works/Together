import Foundation
import Testing
import TogetherCore
@testable import TogetherP2P

@Suite("Normal App persistent workspace boundary") @MainActor
struct PersistentWorkspaceTests {
    private func fixture() throws -> URL {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = package.appendingPathComponent(".build", isDirectory: true).appendingPathComponent("persistent-policy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
    @Test func acceptsOnlyTheExplicitTogetherRootOrEnrolledReplica() throws {
        let support = try fixture(); defer { try? FileManager.default.removeItem(at: support) }
        let root = support.appendingPathComponent("Together", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        #expect(try NativeAppPeerService.validatePersistentRoot(root, applicationSupportDirectory: support,
            storageURL: root.appendingPathComponent("Together.store")) == root)
        let enrolled = root.appendingPathComponent("Replicas").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: enrolled, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        #expect(try NativeAppPeerService.validatePersistentRoot(enrolled, applicationSupportDirectory: support,
            storageURL: enrolled.appendingPathComponent("Together.store")) == enrolled)
        #expect(throws: (any Error).self) {
            try NativeAppPeerService.validatePersistentRoot(support, applicationSupportDirectory: support,
                storageURL: support.appendingPathComponent("Together.store"))
        }
    }
    @Test func rejectsSymlinkStoreAndMismatchedRepositoryWithoutCreatingAnything() throws {
        let support = try fixture(); defer { try? FileManager.default.removeItem(at: support) }
        let root = support.appendingPathComponent("Together", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try NativeAppPeerService.validatePersistentRoot(root, applicationSupportDirectory: support,
                storageURL: support.appendingPathComponent("other.store"))
        }
        let outside = support.appendingPathComponent("outside.store")
        try Data("synthetic".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Together.store"), withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try NativeAppPeerService.validatePersistentRoot(root, applicationSupportDirectory: support,
                storageURL: root.appendingPathComponent("Together.store"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Identity").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("native-transport.key").path))
    }
    @Test func qaInitializerStillRejectsPersistentRoots() throws {
        let support = try fixture(); defer { try? FileManager.default.removeItem(at: support) }
        let root = support.appendingPathComponent("Together", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let engine = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("Together.store")),
                                       identity: DeviceIdentity(protocolVersion: 4))
        #expect(throws: (any Error).self) { try NativeAppPeerService(engine: engine, root: root) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("native-transport.key").path))
    }
}
