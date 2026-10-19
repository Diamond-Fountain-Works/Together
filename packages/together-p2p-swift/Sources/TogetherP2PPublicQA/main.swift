import Foundation
import TogetherCore
import TogetherP2P

private enum QAError: Error { case arguments, unsafeRoot, deadline(String), invalidState(String) }
private struct Launch: Codable {
    var role: String
    var mode: String
    var bindAddress: String?
    var deadlineSeconds: Int
}
private struct Contact: Codable { var address: P2PAddress; var binding: PeerTransportBinding }
private struct Result: Codable {
    var status: String
    var checkpoint: InventoryCheckpoint
    var partnerPersisted: Bool
    var paths: [P2PPath]
    var identityRetained: Bool
    var reopenCheckpointRetained: Bool
    var reopenedAcknowledgementRetained: Bool
    var tombstoneRetained: Bool
    var operationCount: Int
    var processPid: Int32
    var priorProcessPid: Int32? = nil
    var networkUsed: Bool? = nil
}
private actor Failures {
    private var error: (any Error)?
    func record(_ error: any Error) { if self.error == nil { self.error = error } }
    func check() throws { if let error { throw error } }
}

/// Physical acceptance harness, not the production application or pairing UI.
/// Only public trust/contact files pass through the driver. Signed business facts
/// travel exclusively through the authenticated QUIC stream.
@main @MainActor struct TogetherP2PPublicQA {
    static func main() async {
        var root: URL?
        do {
            let args = CommandLine.arguments
            guard args.count == 3, ["--root", "--reopen-root"].contains(args[1]) else { throw QAError.arguments }
            let value = URL(fileURLWithPath: args[2]).standardizedFileURL.resolvingSymlinksInPath()
            let parent = value.deletingLastPathComponent().path
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
            guard value.lastPathComponent.hasPrefix("together-p2p-public-"),
                  // Foundation canonicalizes /private/tmp back to /tmp on
                  // macOS; Python realpath does the opposite. Both are the
                  // same bounded system-temporary parent, never app storage.
                  [temporary, "/tmp", "/private/tmp"].contains(parent),
                  FileManager.default.fileExists(atPath: value.path) else { throw QAError.unsafeRoot }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: value.path)
            root = value
            if args[1] == "--reopen-root" { try await verifyAfterProcessRestart(value) }
            else { try await run(value) }
        } catch {
            if let root {
                try? write(["status": "FAIL", "error": String(describing: error)], "error.json", root)
            }
            // No endpoint addresses, keys or business text in the terminal log.
            if let guardError = error as? QAError {
                print("Together P2P physical QA failed: \(guardError). Inspect the private error artifact.")
            } else {
                print("Together P2P physical QA failed; inspect the private error artifact.")
            }
            exit(1)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, _ name: String, _ root: URL) throws -> T {
        let url = root.appendingPathComponent(name)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 262_144 else { throw QAError.invalidState("control bounds") }
        return try CanonicalJSON.decode(type, from: Data(contentsOf: url))
    }
    private static func write<T: Encodable>(_ value: T, _ name: String, _ root: URL) throws {
        let url = root.appendingPathComponent(name)
        try CanonicalJSON.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func wait(_ name: String, root: URL, deadline: ContinuousClock.Instant,
                             failures: Failures? = nil, condition: (() async throws -> Bool)? = nil) async throws {
        while true {
            try Task.checkCancellation()
            try await failures?.check()
            if let condition {
                if try await condition() { return }
            } else if FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) { return }
            guard ContinuousClock.now < deadline else { throw QAError.deadline(name) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    private static func stage(_ name: String, _ root: URL) throws {
        try write(["stage": name, "at": ISO8601DateFormatter().string(from: Date())], "stage.json", root)
        print("P2P QA stage: \(name)")
        fflush(stdout)
    }
    private static func run(_ root: URL) async throws {
        let launch = try read(Launch.self, "launch.json", root)
        guard ["initiator", "acceptor"].contains(launch.role),
              ["directOnly", "automatic"].contains(launch.mode),
              (30...300).contains(launch.deadlineSeconds) else { throw QAError.arguments }
        let deadline = ContinuousClock.now.advanced(by: .seconds(launch.deadlineSeconds))
        try stage("independent identity", root)
        let metadataURL = root.appendingPathComponent("metadata.json")
        let existing = FileManager.default.fileExists(atPath: metadataURL.path)
        let metadata = existing ? try read(LocalIdentityMetadata.self, "metadata.json", root) : LocalIdentityMetadata()
        if !existing { try write(metadata, "metadata.json", root) }
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId,
            spaceId: metadata.spaceId, directory: root.appendingPathComponent("identity"),
            needsExistingIdentity: existing, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4,
            displayName: "Synthetic public Mac")
        try write(identity.descriptor, "descriptor.json", root)
        try await wait("peer-descriptor.json", root: root, deadline: deadline)
        let peer = try read(DeviceDescriptor.self, "peer-descriptor.json", root)
        guard peer.deviceId != identity.descriptor.deviceId, peer.userId != identity.descriptor.userId,
              peer.protocolVersion == 4 else { throw QAError.invalidState("partner pins") }
        let pins = ReplicaContext(local: identity.descriptor, peer: peer)
        let body = SpaceGenesisBody(context: pins, legacyCheckpoint: try ReplicationHash.inventory([]))
        try write(body, "genesis-body.json", root)
        try await wait("peer-signature.json", root: root, deadline: deadline)
        let signature = try read(DeviceSignature.self, "peer-signature.json", root)
        guard signature.deviceId == peer.deviceId else { throw QAError.invalidState("genesis signer") }
        let own = DeviceSignature(deviceId: identity.descriptor.deviceId,
            signature: try identity.sign(CanonicalJSON.encode(body)))
        let trust = try SpaceAuthorization(genesis: SignedSpaceGenesis(body: body,
            signatures: [own, signature].sorted { $0.deviceId.uuidString < $1.deviceId.uuidString }), existingPins: pins)
        try write(trust.archive, "authorization.json", root)
        let keyURL = root.appendingPathComponent("transport.key")
        let key: Data
        if FileManager.default.fileExists(atPath: keyURL.path) {
            key = try Data(contentsOf: keyURL)
            guard key.count == 32 else { throw QAError.invalidState("transport key") }
        } else {
            key = IrohEndpoint.generateTransportKey()
            try key.write(to: keyURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        try stage("bind \(launch.mode)", root)
        let endpoint = try await IrohEndpoint.bind(secretKey: key,
            connectivity: launch.mode == "directOnly" ? .directOnly : .automatic,
            bindAddress: launch.bindAddress)
        do {
            let address = await endpoint.address()
            let binding = try PeerTransportBinding.issue(identity: identity, endpointId: address.endpointId, authorization: trust)
            try write(Contact(address: address, binding: binding), "contact.json", root)
            try await wait("peer-contact.json", root: root, deadline: deadline)
            let contact = try read(Contact.self, "peer-contact.json", root)
            try contact.binding.verify(endpointId: contact.address.endpointId, authorization: trust)
            guard contact.binding.body.device == peer else { throw QAError.invalidState("contact descriptor") }
            try stage("\(launch.role) QUIC", root)
            let link: IrohFrameConnection
            if launch.role == "initiator" { link = try await endpoint.connect(to: contact.address) }
            else { link = try await endpoint.accept(expectedEndpointId: contact.address.endpointId) }
            do { try await synchronize(root, identity: identity, peer: peer, trust: trust, link: link, deadline: deadline) }
            catch { await link.close(); throw error }
            await link.close()
            try await endpoint.close()
        } catch { try? await endpoint.close(); throw error }
    }

    private static func synchronize(_ root: URL, identity: DeviceIdentity, peer: DeviceDescriptor,
                                    trust: SpaceAuthorization, link: IrohFrameConnection,
                                    deadline: ContinuousClock.Instant) async throws {
        try stage("signed endpoint and Protocol 4 handshake", root)
        let remote = try read(Contact.self, "peer-contact.json", root)
        let cipher = try AuthorizedPeerCipher(identity: identity, remote: remote.binding,
            connectedEndpointId: await link.remoteEndpointId(), authorization: trust)
        try await link.send(cipher.hello)
        guard let consent = try await cipher.handshake(link.receive(), authorization: trust) else {
            throw QAError.invalidState("missing peer hello")
        }
        try await link.send(consent)
        _ = try await cipher.handshake(link.receive(), authorization: trust)
        guard await cipher.isAuthenticated else { throw QAError.invalidState("unauthenticated") }
        let repository = try TogetherRepository(url: root.appendingPathComponent("qa.store"))
        let store = try AuthorizedReplicationStore(repository: repository, identity: identity, authorization: trust)
        try await store.restore()
        let ledger = DeviceAcknowledgementLedger(repository: repository, index: store.index, identity: identity)
        guard try repository.operationCount() == 0 else { throw QAError.invalidState("nonempty first-run QA store") }
        var ownFirst: SignedOperation?
        for n in 1...129 {
            let op = try identity.sign(SyncOperation(operationId: UUID(), deviceId: identity.descriptor.deviceId,
                actorId: identity.descriptor.userId, entityId: UUID(), entityType: .task,
                operationType: .create, lamportClock: Int64(n), payload: ["spaceId": .id(trust.spaceId),
                    "createdBy": .id(identity.descriptor.userId), "title": .string("Synthetic public Mac task \(n)")],
                createdAt: Date(timeIntervalSince1970: 1_791_532_800)))
            if ownFirst == nil { ownFirst = op }
            _ = try await store.append(op)
        }
        let session = PagedReplicationSession(store: store, ledger: ledger, remote: peer,
            send: { frame in try await link.send(cipher.seal(CanonicalJSON.encode(frame), authorization: trust)) })
        let failures = Failures()
        let reader = Task {
            do {
                while !Task.isCancelled {
                    let clear = try await cipher.open(link.receive(), authorization: trust)
                    try await session.receive(CanonicalJSON.decode(ReplicationFrame.self, from: clear))
                }
            } catch { if !Task.isCancelled { await failures.record(error) } }
        }
        defer { reader.cancel() }
        try stage("paged signed facts and durable ACK", root)
        try await session.synchronize()
        try await wait("259 converged facts and durable partner receipt", root: root, deadline: deadline,
                       failures: failures) {
            guard try repository.operationCount() == 259, let ownFirst else { return false }
            let entry = try await store.index.entry(for: ownFirst.id)
            return try await ledger.partnerHasPersisted(entry, trust: trust)
        }
        let checkpoint = try await store.index.checkpoint()
        let entries = try repository.allOperations().filter { $0.operation.deviceId == identity.descriptor.deviceId }.map { try InventoryEntry($0) }
        for entry in entries {
            try await wait("each exact local fact persisted", root: root, deadline: deadline, failures: failures) {
                try await ledger.partnerHasPersisted(entry, trust: trust)
            }
        }
        let input = try await store.projectionInput()
        let projection = OperationProjector.replay(input.operations, context: input.context)
        guard projection.tasks.values.contains(where: { $0.deletedAt != nil }) else {
            throw QAError.invalidState("missing tombstone projection")
        }
        // Reopen durable bytes with a fresh repository/index/ledger. The sender
        // asserts actual signed receipt persistence, not socket send success.
        let reopenedIdentity = try DeviceIdentity.persistent(deviceId: identity.descriptor.deviceId,
            userId: identity.descriptor.userId, spaceId: identity.descriptor.initialSpaceId,
            directory: root.appendingPathComponent("identity"), needsExistingIdentity: true,
            timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4, displayName: "Synthetic public Mac")
        let reopenedRepository = try TogetherRepository(url: root.appendingPathComponent("qa.store"))
        let reopened = try AuthorizedReplicationStore(repository: reopenedRepository, identity: reopenedIdentity, authorization: trust)
        try await reopened.restore()
        let reopenedLedger = DeviceAcknowledgementLedger(repository: reopenedRepository, index: reopened.index, identity: reopenedIdentity)
        let retained = try await reopened.index.checkpoint() == checkpoint
        let retainedAck = try await reopenedLedger.partnerHasPersisted(reopened.index.entry(for: entries[0].operationId), trust: trust)
        guard retained, retainedAck, reopenedIdentity.descriptor == identity.descriptor else { throw QAError.invalidState("reopen") }
        let paths = await link.paths()
        guard paths.contains(where: { $0.selected }) else { throw QAError.invalidState("no selected path") }
        try write(Result(status: "PASS", checkpoint: checkpoint, partnerPersisted: true, paths: paths,
            identityRetained: true, reopenCheckpointRetained: retained,
            reopenedAcknowledgementRetained: retainedAck, tombstoneRetained: true,
            operationCount: 259, processPid: ProcessInfo.processInfo.processIdentifier), "result.json", root)
        try stage("verified; waiting for reciprocal result", root)
        try await wait("finish", root: root, deadline: deadline)
        await session.invalidate()
        reader.cancel()
        print("Together P2P physical QA passed (259 durable facts).")
    }

    /// Separate process, no socket and no new identity. Missing state is an
    /// explicit failure rather than silently starting another replica.
    private static func verifyAfterProcessRestart(_ root: URL) async throws {
        let original = try read(Result.self, "result.json", root)
        guard original.status == "PASS", original.checkpoint.count == 259,
              original.processPid != ProcessInfo.processInfo.processIdentifier,
              FileManager.default.fileExists(atPath: root.appendingPathComponent("qa.store").path) else {
            throw QAError.invalidState("a completed previous process is required")
        }
        let metadata = try read(LocalIdentityMetadata.self, "metadata.json", root)
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId,
            spaceId: metadata.spaceId, directory: root.appendingPathComponent("identity"),
            needsExistingIdentity: true, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4,
            displayName: "Synthetic public Mac")
        let expected = try read(DeviceDescriptor.self, "descriptor.json", root)
        let peer = try read(DeviceDescriptor.self, "peer-descriptor.json", root)
        guard identity.descriptor == expected else { throw QAError.invalidState("changed restart identity") }
        let trust = try SpaceAuthorization.restore(read(AuthorizationArchive.self, "authorization.json", root),
            existingPins: ReplicaContext(local: identity.descriptor, peer: peer))
        let repository = try TogetherRepository(url: root.appendingPathComponent("qa.store"))
        let store = try AuthorizedReplicationStore(repository: repository, identity: identity, authorization: trust)
        try await store.restore()
        let checkpoint = try await store.index.checkpoint()
        guard checkpoint == original.checkpoint, try repository.operationCount() == 259 else {
            throw QAError.invalidState("restart checkpoint")
        }
        let ledger = DeviceAcknowledgementLedger(repository: repository, index: store.index, identity: identity)
        let operations = try repository.allOperations()
        let own = operations.filter { $0.operation.deviceId == identity.descriptor.deviceId }
        guard own.count == 129 else { throw QAError.invalidState("restart local fact count") }
        for operation in own {
            guard try await ledger.partnerHasPersisted(store.index.entry(for: operation.id), trust: trust) else {
                throw QAError.invalidState("restart receipt")
            }
        }
        let input = try await store.projectionInput()
        let snapshot = OperationProjector.replay(input.operations, context: input.context)
        guard snapshot.tasks.count == 258, snapshot.tasks.values.filter({ $0.deletedAt != nil }).count == 1 else {
            throw QAError.invalidState("restart tombstone")
        }
        try write(Result(status: "PASS", checkpoint: checkpoint, partnerPersisted: true,
            paths: [], identityRetained: true, reopenCheckpointRetained: true,
            reopenedAcknowledgementRetained: true, tombstoneRetained: true,
            operationCount: 259, processPid: ProcessInfo.processInfo.processIdentifier,
            priorProcessPid: original.processPid, networkUsed: false), "reopen-result.json", root)
        print("Fresh-process QA reopen passed; no network or replacement identity.")
    }
}
