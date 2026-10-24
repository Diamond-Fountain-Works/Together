import Foundation
import Combine
import Testing
import TogetherCore
@testable import TogetherApp

@Suite("Legacy-compatible application observation") @MainActor
struct AppObservationTests {
    @Test func nestedLegacyRepositoryChangeRefreshesTheExistingWorkspace() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        var invalidations = 0
        let token = model.objectWillChange.sink { invalidations += 1 }
        defer { token.cancel() }
        let oldDevice = model.engine.identity.descriptor.deviceId
        let id = try model.engine.createTask(title: "Synthetic observation task")
        #expect(invalidations > 0)
        #expect(model.pendingTasks.contains { $0.id == id })
        #expect(model.engine.identity.descriptor.deviceId == oldDevice)
        #expect(model.engine.repository.backendKind == .legacySQLite)
        #expect(try model.engine.repository.allOperations().contains { $0.operation.entityId == id })
    }
    @Test func unconfiguredPairingFailureRefreshesDerivedConnectionStateWithoutHTTP() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        var invalidations = 0
        let token = model.objectWillChange.sink { invalidations += 1 }
        defer { token.cancel() }
        #expect(!model.network.isConfigured)
        await model.network.createInvitation()
        #expect(invalidations > 0)
        #expect(model.connectionState == .error)
        #expect(!model.isOnline)
        #expect(model.network.errorMessage != nil)
        #expect(model.network.invitationCode == nil)
    }
    @Test func sceneFollowsTheCurrentSessionAndDetachesTheReplacedModel() throws {
        let first = try Fixture(), second = try Fixture()
        defer { first.cleanup(); second.cleanup() }
        let scene = TogetherSceneSession(model: first.model)
        var invalidations = 0
        let token = scene.objectWillChange.sink { invalidations += 1 }
        defer { token.cancel() }
        first.model.show(.giftHistory)
        #expect(invalidations > 0)
        scene.model = second.model
        let afterReplacement = invalidations
        first.model.dismissSheet()
        #expect(invalidations == afterReplacement)
        second.model.show(.giftHistory)
        #expect(invalidations > afterReplacement)
    }
    @MainActor private final class Fixture {
        let root: URL
        let suite: String
        let defaults: UserDefaults
        let model: ApplicationModel
        init() throws {
            var project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<5 { project.deleteLastPathComponent() }
            root = project.appendingPathComponent("qa/results/compatibility-20261024/observation-tests/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            suite = "com.together.ui-observation." + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileWriteUnknown) }
            self.defaults = defaults
            let repository = try TogetherRepository(url: root.appendingPathComponent("Together.store"), backend: .legacySQLite)
            let engine = try ReplicaEngine(repository: repository, identity: DeviceIdentity(), mediaRoot: root.appendingPathComponent("Media"))
            model = ApplicationModel(engine: engine, defaults: defaults, useBundledService: false)
        }
        func cleanup() {
            model.suspendNetworking()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
