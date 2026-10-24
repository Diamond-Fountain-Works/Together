import CryptoKit
import Foundation

/// Only carried inside the existing authenticated encrypted pairing channel.
/// This first-partnership exchange does not replace Protocol 4 anti-entropy.
struct PartnerBootstrapFrame: Codable, Sendable {
    var kind: String
    var operations: [SignedOperation]?
    var checkpoint: InventoryCheckpoint?
    var genesis: SignedSpaceGenesis?
}

@MainActor final class PartnerBootstrapSession {
    private let engine: ReplicaEngine
    private let remote: DeviceDescriptor
    private let send: @MainActor (PartnerBootstrapFrame) async throws -> Void
    private let complete: @MainActor (SignedSpaceGenesis) async throws -> Void
    private let failed: @MainActor (Error) -> Void
    private var outgoing: Task<Void, Never>?
    private var preparing: Task<Void, Never>?
    private var remoteCheckpoint: InventoryCheckpoint?
    private var receivedHash = SHA256()
    private var receivedCount = 0
    private var lastReceived: String?
    private var sentHistory = false
    private var receivedHistory = false
    private var localGenesis: SignedSpaceGenesis?
    private var remoteGenesis: SignedSpaceGenesis?
    private var sentReady = false
    private var sendingReady = false
    private var receivedReady = false
    private var finished = false
    private var valid = true
    private var expectedBatchAck: InventoryCheckpoint?
    private var receivedBatchAck: InventoryCheckpoint?

    init(engine: ReplicaEngine, remote: DeviceDescriptor,
         send: @escaping @MainActor (PartnerBootstrapFrame) async throws -> Void,
         complete: @escaping @MainActor (SignedSpaceGenesis) async throws -> Void,
         failed: @escaping @MainActor (Error) -> Void) {
        self.engine = engine; self.remote = remote; self.send = send
        self.complete = complete; self.failed = failed
        receivedHash.update(data: Data("Together-Inventory-4\n".utf8))
    }
    func invalidate() { valid = false; outgoing?.cancel(); preparing?.cancel() }
    func start() {
        guard outgoing == nil else { return }
        let history = engine.operations.filter { $0.operation.deviceId == engine.identity.descriptor.deviceId }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        outgoing = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let checkpoint = try ReplicationHash.inventory(history.map { try InventoryEntry($0) })
                try await send(PartnerBootstrapFrame(kind: "partner-history-start", checkpoint: checkpoint))
                var batch: [SignedOperation] = []; var size = 0
                for operation in history {
                    try Task.checkCancellation()
                    let bytes = try CanonicalJSON.encode(operation).count
                    guard bytes < 230_000 else { throw ReplicationError.bounds }
                    if batch.count == 32 || size + bytes > 230_000 {
                        try await sendBatch(batch)
                        batch = []; size = 0
                    }
                    batch.append(operation); size += bytes
                }
                if !batch.isEmpty { try await sendBatch(batch) }
                try await send(PartnerBootstrapFrame(kind: "partner-history-end", checkpoint: checkpoint))
                sentHistory = true; prepareGenesisIfReady()
            } catch is CancellationError {} catch { if valid { failed(error) } }
        }
    }
    func receive(_ frame: PartnerBootstrapFrame) throws {
        guard valid, !finished else { return }
        switch frame.kind {
        case "partner-history-start":
            guard remoteCheckpoint == nil, let checkpoint = frame.checkpoint,
                  checkpoint.count >= 0, ReplicationHash.valid(checkpoint.digest) else { throw ReplicationError.invalidPage }
            remoteCheckpoint = checkpoint
        case "partner-history":
            guard let expected = remoteCheckpoint, !receivedHistory, let operations = frame.operations,
                  !operations.isEmpty, operations.count <= 32,
                  try CanonicalJSON.encode(frame).count <= 240_000 else { throw ReplicationError.bounds }
            for operation in operations {
                guard operation.operation.deviceId == remote.deviceId, operation.verified(by: remote),
                      lastReceived == nil || lastReceived! < operation.id.uuidString else { throw ReplicationError.invalidSignature }
                receivedHash.update(data: ReplicationHash.inventoryLine(try InventoryEntry(operation)))
                receivedCount += 1; lastReceived = operation.id.uuidString
            }
            guard receivedCount <= expected.count else { throw ReplicationError.contentCollision }
            try engine.importPartnerHistory(operations)
            let receipt = InventoryCheckpoint(count: operations.count, digest: ReplicationHash.digest(try CanonicalJSON.encode(operations)))
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await send(PartnerBootstrapFrame(kind: "partner-history-ack", checkpoint: receipt)) }
                catch { if valid { failed(error) } }
            }
        case "partner-history-ack":
            guard let checkpoint = frame.checkpoint, checkpoint == expectedBatchAck else { throw ReplicationError.invalidReceipt }
            receivedBatchAck = checkpoint
        case "partner-history-end":
            guard !receivedHistory, let expected = remoteCheckpoint, frame.checkpoint == expected,
                  receivedCount == expected.count,
                  ReplicationHash.hex(receivedHash.finalize()) == expected.digest else { throw ReplicationError.contentCollision }
            receivedHistory = true; prepareGenesisIfReady()
        case "partner-genesis", "partner-ready":
            guard let genesis = frame.genesis else { throw ReplicationError.unauthorized }
            if let old = remoteGenesis, old.body != genesis.body { throw ReplicationError.contentCollision }
            let allowed = Set([engine.identity.descriptor.deviceId, remote.deviceId])
            guard !genesis.signatures.isEmpty, Set(genesis.signatures.map(\.deviceId)).count == genesis.signatures.count,
                  genesis.signatures.allSatisfy({ allowed.contains($0.deviceId) }),
                  let proof = genesis.signatures.first(where: { $0.deviceId == remote.deviceId }),
                  SignedSpaceGenesis.verify(proof.signature, bytes: try CanonicalJSON.encode(genesis.body), key: remote.publicKey) else { throw ReplicationError.invalidSignature }
            remoteGenesis = genesis
            if frame.kind == "partner-ready" { receivedReady = true }
            advanceGenesis()
        default: throw ReplicationError.incompatibleProtocol
        }
    }
    private func sendBatch(_ operations: [SignedOperation]) async throws {
        let checkpoint = InventoryCheckpoint(count: operations.count, digest: ReplicationHash.digest(try CanonicalJSON.encode(operations)))
        expectedBatchAck = checkpoint; receivedBatchAck = nil
        try await send(PartnerBootstrapFrame(kind: "partner-history", operations: operations))
        let deadline = CompatibilityClock.now.advanced(by: .seconds(20))
        while receivedBatchAck != checkpoint {
            try Task.checkCancellation()
            guard valid, CompatibilityClock.now < deadline else { throw ReplicationError.invalidReceipt }
            try await CompatibilityClock.sleep(for: .milliseconds(5))
        }
    }
    private func prepareGenesisIfReady() {
        guard valid, sentHistory, receivedHistory, preparing == nil else { return }
        preparing = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try engine.finishPartnerHistory()
                let checkpoint = try await OperationInventoryIndex(repository: engine.repository).checkpoint()
                try Task.checkCancellation()
                let body = SpaceGenesisBody(context: engine.context, legacyCheckpoint: checkpoint)
                localGenesis = SignedSpaceGenesis(body: body, signatures: [DeviceSignature(deviceId: engine.identity.descriptor.deviceId,
                    signature: try engine.identity.sign(CanonicalJSON.encode(body)))])
                try await send(PartnerBootstrapFrame(kind: "partner-genesis", genesis: localGenesis))
                advanceGenesis()
            } catch is CancellationError {} catch { if valid { failed(error) } }
        }
    }
    private func advanceGenesis() {
        guard valid, !finished, let local = localGenesis, let remote = remoteGenesis else { return }
        do {
            guard local.body == remote.body else { throw ReplicationError.inventoryChanged }
            let own = local.signatures.first { $0.deviceId == engine.identity.descriptor.deviceId }!
            guard let peer = remote.signatures.first(where: { $0.deviceId == self.remote.deviceId }) else { throw ReplicationError.invalidSignature }
            let genesis = SignedSpaceGenesis(body: local.body, signatures: [own, peer].sorted { $0.deviceId.uuidString < $1.deviceId.uuidString })
            try genesis.verify(existingPins: engine.context)
            try engine.repository.save(genesis, key: "partner4/genesis")
            if !sendingReady {
                sendingReady = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do { try await send(PartnerBootstrapFrame(kind: "partner-ready", genesis: genesis)); sentReady = true; finishIfReady(genesis) }
                    catch { if valid { failed(error) } }
                }
            }
            finishIfReady(genesis)
        } catch { failed(error) }
    }
    private func finishIfReady(_ genesis: SignedSpaceGenesis) {
        guard valid, !finished, sentReady, receivedReady else { return }
        finished = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await complete(genesis) } catch { if valid { failed(error) } }
        }
    }
}
