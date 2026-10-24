import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import TogetherCore
import UniformTypeIdentifiers

@MainActor final class DeviceEnrollmentModel: ObservableObject {
    let model: ApplicationModel
    @Published var offer: DeviceEnrollmentOffer?
    @Published var request: DeviceEnrollmentRequest?
    @Published var completion: DeviceEnrollmentCompletion?
    @Published var migration: LegacyMigrationExchange?
    @Published var deviceName = TogetherPlatform.deviceName
    @Published var verifiedOffer = false
    @Published var verifiedRequest = false
    @Published var verifiedCompletion = false
    @Published var verifiedMigration = false
    @Published var busy = false
    @Published var error: String?
    @Published var status: String?
    @Published var revoking: AuthorizedDevice?
    @Published var devices: [AuthorizedDevice] = []
    init(model: ApplicationModel) {
        self.model = model
        #if DEBUG && os(macOS)
        if UIFixture.enabled { deviceName = Copy.text("device.default.name") }
        #endif
        if let root = model.engine.enrollmentRoot {
            let workspace = DeviceEnrollmentWorkspace(root: root)
            if let pending = workspace.pendingOffers.first {
                offer = pending; request = try? workspace.request(for: pending.body.id)
            }
        }
        refresh()
    }
    var service: C1ReplicationService? { model.network.multiDeviceService }
    var isController: Bool {
        model.engine.context.authorization?.root(for: model.engine.identity.descriptor.userId)?.deviceId == model.engine.identity.descriptor.deviceId
    }
    var hasLegacyRelay: Bool { (try? model.engine.repository.load(RelayBinding.self, key: "relay-binding")) != nil }
    var canJoin: Bool {
        !model.engine.usesReplication4 && model.engine.peer == nil && model.engine.enrollmentRoot != nil &&
        model.engine.operations.allSatisfy { $0.operation.actorId == model.engine.identity.descriptor.userId && $0.operation.entityType == .profile && $0.operation.entityId == model.engine.identity.descriptor.userId }
    }
    func refresh() { devices = model.engine.context.authorization?.devices.values.sorted { $0.id.uuidString < $1.id.uuidString } ?? [] }
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil; status = nil
        Task { @MainActor in
            defer { busy = false; refresh() }
            do { try await action() }
            catch let value as ReplicationError where value == .inventoryChanged { error = Copy.text("device.error.historyChanged") }
            catch { self.error = Copy.userError(error) }
        }
    }
    func createOffer() {
        run {
            guard let service = self.service else { throw ReplicationError.incompatibleProtocol }
            self.offer = try await service.createDeviceOffer()
            self.request = nil; self.completion = nil; self.verifiedRequest = false
            if let offer = self.offer { try await self.export(offer, filename: "device.file.offer") }
        }
    }
    func exportOfferAgain() { if let offer { run { try await self.export(offer, filename: "device.file.offer") } } }
    func importRequest() {
        run {
            guard let request = try await self.read(DeviceEnrollmentRequest.self) else { return }
            guard let offer = try self.model.engine.repository.load(DeviceEnrollmentOffer.self, key: "replication4/enrollment/offer/\(request.body.offerId)") else { throw ReplicationError.unauthorized }
            try request.verify(offer: offer)
            self.request = request; self.offer = offer; self.completion = nil; self.verifiedRequest = false
        }
    }
    func approveRequest() {
        run {
            guard let service = self.service, let request = self.request else { throw ReplicationError.unauthorized }
            let done = try await service.approveDeviceRequest(request, verified: self.verifiedRequest)
            self.completion = done
            self.status = Copy.text("device.status.authorized")
            try await self.export(done, filename: "device.file.completion")
        }
    }
    func exportCompletionAgain() { if let completion { run { try await self.export(completion, filename: "device.file.completion") } } }
    func importOffer() {
        run {
            guard self.canJoin else { throw DeviceEnrollmentError.existingData }
            guard let offer = try await self.read(DeviceEnrollmentOffer.self) else { return }
            _ = try offer.verify(now: Date())
            self.offer = offer; self.request = nil; self.completion = nil; self.verifiedOffer = false; self.verifiedCompletion = false
        }
    }
    func createRequest() {
        run {
            guard self.canJoin, let root = self.model.engine.enrollmentRoot, let offer = self.offer else { throw DeviceEnrollmentError.existingData }
            let request = try DeviceEnrollmentWorkspace(root: root).stage(offer: offer, name: self.deviceName, verified: self.verifiedOffer, now: Date(), source: self.model.engine)
            self.request = request
            try await self.export(request, filename: "device.file.request")
        }
    }
    func importCompletion() {
        run {
            guard self.canJoin, let offer = self.offer, let request = self.request else { throw DeviceEnrollmentError.existingData }
            guard let completion = try await self.read(DeviceEnrollmentCompletion.self) else { return }
            _ = try completion.verify(request: request, offer: offer)
            self.completion = completion; self.verifiedCompletion = false
        }
    }
    func useDevice() {
        run {
            guard self.canJoin, let root = self.model.engine.enrollmentRoot, let offer = self.offer, let completion = self.completion else { throw DeviceEnrollmentError.existingData }
            let engine = try DeviceEnrollmentWorkspace(root: root).complete(completion, offerId: offer.body.id, verified: self.verifiedCompletion, source: self.model.engine)
            self.model.switchToEnrolledReplica(engine)
        }
    }
    func beginMigration() {
        run {
            self.migration = try await LegacyMigrationExchange.begin(self.model.engine)
            self.verifiedMigration = false
            if let migration = self.migration { try await self.export(migration, filename: "device.file.migration") }
        }
    }
    func importMigration() {
        run {
            guard let migration = try await self.read(LegacyMigrationExchange.self) else { return }
            try await migration.validate(self.model.engine)
            self.migration = migration; self.verifiedMigration = false
        }
    }
    func signMigration() {
        run {
            guard let proposal = self.migration else { throw ReplicationError.unauthorized }
            self.migration = try await proposal.cosign(self.model.engine, verified: self.verifiedMigration)
            try await self.export(self.migration!, filename: "device.file.migration")
        }
    }
    func activateMigration() {
        run {
            guard let migration = self.migration else { throw ReplicationError.unauthorized }
            try await self.model.network.activateMigration(migration, verified: self.verifiedMigration)
            self.status = Copy.text("device.status.migrated"); self.migration = nil
        }
    }
    func revoke(_ device: AuthorizedDevice) {
        run {
            guard let service = self.service else { throw ReplicationError.unauthorized }
            try await service.revokeDevice(device.id)
            self.status = Copy.text("device.status.revoked")
        }
    }
    private func read<T: Decodable>(_ type: T.Type) async throws -> T? {
        guard let url = try await TogetherFilePanels.choose(types: [.json], directory: model.filePanelDirectory) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 524288 else { throw ReplicationError.bounds }
        return try CanonicalJSON.decode(type, from: Data(contentsOf: url))
    }
    private func export<T: Encodable>(_ value: T, filename: String) async throws {
        let bytes = try CanonicalJSON.encode(value)
        guard bytes.count <= 524288 else { throw ReplicationError.bounds }
        try await TogetherFilePanels.exportJSON(bytes, filename: Copy.text(filename), directory: model.filePanelDirectory)
    }
}
