import Foundation

/// Business synchronization shared by authenticated legacy and relay sessions.
/// The caller must validate the session/device before passing a payload here.
@MainActor final class OperationLogSyncSession {
    let engine: ReplicaEngine
    let remote: DeviceDescriptor
    var send: (WirePayload) -> Void
    var onConverged: (() -> Void)?
    var onError: ((Error) -> Void)?
    var onSyncing: (() -> Void)?
    private(set) var applyingRemote = false
    private var active = true
    private var requestedRemoteDigest: String?
    private var completedDigest: String?
    private var requestedAssets: Set<UUID> = []
    private var verifyingAssets: Set<UUID> = []
    private var receiptedGifts: Set<UUID> = []
    init(engine: ReplicaEngine, remote: DeviceDescriptor, send: @escaping (WirePayload) -> Void) { self.engine = engine; self.remote = remote; self.send = send }
    func invalidate() { active = false }
    func synchronize() { guard active, !applyingRemote else { return }; onSyncing?(); send(.state(engine.operations.map(\.id))) }
    func receive(_ payload: WirePayload) throws {
        guard active, engine.peer?.descriptor.publicKey == remote.publicKey, engine.peer?.descriptor.deviceId == remote.deviceId else { throw TogetherError.invalid(Copy.text("copy.error.86b11800f661")) }
        switch payload {
        case .state(let known):
            guard known.count <= 10_000 else { throw TogetherError.invalid(Copy.text("copy.error.4ae3bb8028b1")) }
            onSyncing?()
            let ids = Set(known), local = Set(engine.operations.map(\.id)), digest = operationDigest(known)
            if !ids.isSubset(of: local), requestedRemoteDigest != digest { requestedRemoteDigest = digest; send(.state(Array(local))) }
            for op in engine.operations.sorted(by: { $0.operation.order < $1.operation.order }) where !ids.contains(op.id) { send(.operation(op)) }
            send(.finished(operationDigest(engine.operations.map(\.id))))
            if ids == local { try converged() }
        case .operation(let op):
            applyingRemote = true; defer { applyingRemote = false }; try engine.merge([op])
        case .finished(let digest):
            if digest == operationDigest(engine.operations.map(\.id)) { try converged() } else { send(.state(engine.operations.map(\.id))) }
        case .mediaRequest(let id, let offset):
            guard let asset = engine.snapshot.mediaAssets[id], asset.ownerId == engine.identity.descriptor.userId, offset >= 0, offset <= asset.byteCount else { throw TogetherError.invalid(Copy.text("copy.error.cb489af1d4f7")) }
            engine.setMediaProgress(MediaProgress(assetId: id, transferred: offset, total: asset.byteCount, status: .transferring))
            let store = engine.mediaStore
            Task { @MainActor [weak self] in
                do {
                    let bytes = try await Task.detached { try store.readChunk(asset, offset: offset) }.value
                    guard let self, self.active else { return }
                    self.send(bytes.isEmpty ? .mediaComplete(id, asset.sha256) : .mediaChunk(id, offset, bytes))
                } catch { self?.send(.mediaFailure(id, error.localizedDescription)) }
            }
        case .mediaChunk(let id, let offset, let bytes):
            guard let asset = engine.snapshot.mediaAssets[id], asset.ownerId == remote.userId, requestedAssets.contains(id) else { throw TogetherError.invalid(Copy.text("copy.error.6f3929a4168f")) }
            do {
                let next = try engine.mediaStore.appendChunk(bytes, to: asset, offset: offset)
                engine.setMediaProgress(MediaProgress(assetId: id, transferred: next, total: asset.byteCount, status: .transferring)); send(.mediaRequest(id, next))
            } catch { engine.setMediaProgress(MediaProgress(assetId: id, transferred: offset, total: asset.byteCount, status: .failed, error: error.localizedDescription)); throw error }
        case .mediaComplete(let id, let hash):
            guard let asset = engine.snapshot.mediaAssets[id], asset.ownerId == remote.userId, requestedAssets.contains(id), asset.sha256 == hash else { throw TogetherError.invalid(Copy.text("copy.error.b9a05e7703e0")) }
            verify(asset)
        case .mediaVerified(let id, let hash):
            guard let asset = engine.snapshot.mediaAssets[id], asset.ownerId == engine.identity.descriptor.userId, asset.sha256 == hash else { throw TogetherError.invalid(Copy.text("copy.error.b4c3e6bb90c0")) }
            engine.setMediaProgress(MediaProgress(assetId: id, transferred: asset.byteCount, total: asset.byteCount, status: .verified))
        case .mediaFailure(let id, let error):
            guard requestedAssets.remove(id) != nil, let asset = engine.snapshot.mediaAssets[id] else { return }
            engine.setMediaProgress(MediaProgress(assetId: id, transferred: (try? engine.mediaStore.resumeOffset(asset)) ?? 0, total: asset.byteCount, status: .failed, error: String(error.prefix(300))))
        case .giftReceipt(let receipt): try engine.acceptReceipt(receipt, from: remote)
        default: throw TogetherError.invalid(Copy.text("copy.error.4f82626d4550"))
        }
    }
    private func converged() throws {
        let digest = operationDigest(engine.operations.map(\.id))
        completedDigest = digest; onConverged?()
        let references = Set(engine.snapshot.profiles.values.compactMap(\.avatarAssetId) + engine.receivedGifts.flatMap(\.assetIds))
        for id in references {
            guard let asset = engine.snapshot.mediaAssets[id], asset.ownerId == remote.userId, !engine.mediaStore.hasVerified(asset), !requestedAssets.contains(id) else { continue }
            let offset = try engine.mediaStore.resumeOffset(asset); requestedAssets.insert(id)
            engine.setMediaProgress(MediaProgress(assetId: id, transferred: offset, total: asset.byteCount, status: .transferring)); send(.mediaRequest(id, offset))
        }
        sendReceipts()
    }
    private func sendReceipts() {
        guard active else { return }
        for gift in engine.receivedGifts where engine.giftReady(gift) && !receiptedGifts.contains(gift.id) {
            receiptedGifts.insert(gift.id); send(.giftReceipt(GiftReceipt(gift: gift, assets: engine.snapshot.mediaAssets)))
        }
    }
    private func verify(_ asset: MediaAsset) {
        guard !verifyingAssets.contains(asset.id) else { return }; verifyingAssets.insert(asset.id)
        let store = engine.mediaStore
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.verifyingAssets.remove(asset.id); self.requestedAssets.remove(asset.id) }
            do {
                try await Task.detached { try store.finishDownload(asset) }.value
                self.engine.setMediaProgress(MediaProgress(assetId: asset.id, transferred: asset.byteCount, total: asset.byteCount, status: .verified))
                if self.active { self.send(.mediaVerified(asset.id, asset.sha256)); self.sendReceipts() }
            } catch { self.engine.setMediaProgress(MediaProgress(assetId: asset.id, transferred: (try? store.resumeOffset(asset)) ?? 0, total: asset.byteCount, status: .failed, error: error.localizedDescription)); self.onError?(error) }
        }
    }
}
