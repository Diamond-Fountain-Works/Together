import Foundation
import IrohLib
import Testing
import TogetherCore
@testable import TogetherP2P

private struct Pair {
    let a: DeviceIdentity, b: DeviceIdentity, trust: SpaceAuthorization
    init() throws {
        a = try DeviceIdentity(displayName: "Synthetic P2P A", protocolVersion: 4)
        b = try DeviceIdentity(displayName: "Synthetic P2P B", protocolVersion: 4)
        let body = try SpaceGenesisBody(context: ReplicaContext(local: a.descriptor, peer: b.descriptor),
            legacyCheckpoint: ReplicationHash.inventory([]))
        let bytes = try CanonicalJSON.encode(body)
        let proofs = try [a,b].map { DeviceSignature(deviceId: $0.descriptor.deviceId, signature: try $0.sign(bytes)) }.sorted { $0.deviceId.uuidString < $1.deviceId.uuidString }
        trust = try SpaceAuthorization(genesis: SignedSpaceGenesis(body: body, signatures: proofs))
    }
    func operation(_ id: DeviceIdentity, clock: Int64, entity: UUID = UUID(), deleted: Bool = false) throws -> SignedOperation {
        try id.sign(SyncOperation(operationId: UUID(), deviceId: id.descriptor.deviceId,
            actorId: id.descriptor.userId, entityId: entity, entityType: .task,
            operationType: deleted ? .delete : .create, lamportClock: clock,
            payload: deleted ? [:] : ["spaceId": .id(trust.spaceId), "createdBy": .id(id.descriptor.userId), "title": .string("Synthetic direct task")],
            createdAt: Date(timeIntervalSince1970: 1_791_532_800)))
    }
}

private actor LinkFailures {
    private var error: (any Error)?
    func record(_ value: any Error) { if error == nil { error = value } }
    func check() throws { if let error { throw error } }
}

@Suite("Real relay-disabled QUIC operation transport", .timeLimit(.minutes(1)))
struct P2PTransportTests {
    @Test func qaPresetReplacesBothApplicationQuicBindFamiliesWithoutInternet() async throws {
        let endpoint = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(),
            connectivity: .directOnly, loopbackQuicForQA: true)
        do {
            try await endpoint.requireLoopbackQuicForQA()
            let sockets = await endpoint.boundSockets()
            #expect(sockets.count == 2)
            #expect(sockets.contains { $0.hasPrefix("127.0.0.1:") })
            #expect(sockets.contains { $0.hasPrefix("[::1]:") })
            #expect(await endpoint.address().relayURL == nil)
            #expect(try await endpoint.waitForRelayAddress(timeout: .milliseconds(20)) == false)
        } catch { try? await endpoint.close(); throw error }
        try await endpoint.close()
        await #expect(throws: P2PTransportError.invalidAddress) {
            try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(),
                bindAddress: "127.0.0.1:0", loopbackQuicForQA: true)
        }
    }

    @Test func relayAddressWaitIsBoundedCancellableAndRequiresOpenEndpoint() async throws {
        let endpoint = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let start = ContinuousClock.now
        #expect(try await endpoint.waitForRelayAddress(timeout: .milliseconds(50)) == false)
        #expect(start.duration(to: .now) < .seconds(2))
        let pending = Task { try await endpoint.waitForRelayAddress(timeout: .seconds(15)) }
        try await Task.sleep(for: .milliseconds(20))
        pending.cancel()
        do { _ = try await pending.value; Issue.record("Cancelled helper-address wait unexpectedly succeeded") }
        catch is CancellationError { }
        catch { Issue.record("Unexpected cancellation error: \(error)") }
        try await endpoint.close()
        do { _ = try await endpoint.waitForRelayAddress(); Issue.record("Closed endpoint unexpectedly became ready") }
        catch P2PTransportError.closed { }
        catch { Issue.record("Unexpected closed-endpoint error: \(error)") }
        await #expect(throws: P2PTransportError.self) { try await endpoint.waitForRelayAddress(timeout: .zero) }
    }

    @Test @MainActor func signedPagedIncrementalSyncAckAndTombstoneOverDirectQuic() async throws {
        let f = try Pair()
        let ea = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let eb = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let aa = await ea.address(), ba = await eb.address()
        #expect(aa.relayURL == nil && ba.relayURL == nil)
        let accepting = Task { try await eb.accept(expectedEndpointId: aa.endpointId) }
        let left = try await ea.connect(to: ba)
        let aBinding = try PeerTransportBinding.issue(identity: f.a, endpointId: aa.endpointId, authorization: f.trust)
        let bBinding = try PeerTransportBinding.issue(identity: f.b, endpointId: ba.endpointId, authorization: f.trust)
        let ac = try AuthorizedPeerCipher(identity: f.a, remote: bBinding,
            connectedEndpointId: await left.remoteEndpointId(), authorization: f.trust)
        try await left.send(ac.hello)
        let right = try await accepting.value
        let bc = try AuthorizedPeerCipher(identity: f.b, remote: aBinding,
            connectedEndpointId: await right.remoteEndpointId(), authorization: f.trust)
        try await right.send(bc.hello)
        let aConsent = try #require(await ac.handshake(left.receive(), authorization: f.trust))
        let bConsent = try #require(await bc.handshake(right.receive(), authorization: f.trust))
        try await left.send(aConsent); try await right.send(bConsent)
        _ = try await ac.handshake(left.receive(), authorization: f.trust)
        _ = try await bc.handshake(right.receive(), authorization: f.trust)

        let sa = try AuthorizedReplicationStore(repository: TogetherRepository(inMemory: true), identity: f.a, authorization: f.trust)
        let sb = try AuthorizedReplicationStore(repository: TogetherRepository(inMemory: true), identity: f.b, authorization: f.trust)
        try await sa.restore(); try await sb.restore()
        let al = DeviceAcknowledgementLedger(repository: sa.repository, index: sa.index, identity: f.a)
        let bl = DeviceAcknowledgementLedger(repository: sb.repository, index: sb.index, identity: f.b)
        let target = UUID(); var first: SignedOperation?
        for n in 1...129 {
            let aop = try f.operation(f.a, clock: Int64(n), entity: n == 1 ? target : UUID())
            if n == 1 { first = aop }
            _ = try await sa.append(aop); _ = try await sb.append(f.operation(f.b, clock: Int64(n)))
        }
        let ab = PagedReplicationSession(store: sa, ledger: al, remote: f.b.descriptor,
            send: { frame in try await left.send(ac.seal(CanonicalJSON.encode(frame), authorization: sa.authorization)) })
        let bb = PagedReplicationSession(store: sb, ledger: bl, remote: f.a.descriptor,
            send: { frame in try await right.send(bc.seal(CanonicalJSON.encode(frame), authorization: sb.authorization)) })
        let failures = LinkFailures()
        let readA = Task {
            do { while !Task.isCancelled { try await ab.receive(CanonicalJSON.decode(ReplicationFrame.self, from: ac.open(left.receive(), authorization: sa.authorization))) } }
            catch { if !Task.isCancelled { await failures.record(error) }; throw error }
        }
        let readB = Task {
            do { while !Task.isCancelled { try await bb.receive(CanonicalJSON.decode(ReplicationFrame.self, from: bc.open(right.receive(), authorization: sb.authorization))) } }
            catch { if !Task.isCancelled { await failures.record(error) }; throw error }
        }
        defer { readA.cancel(); readB.cancel() }
        try await ab.synchronize(); try await bb.synchronize()
        try await waitForConvergence(sa, sb, count: 258, failures: failures)
        let entry = try await sa.index.entry(for: #require(first).id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(try await al.partnerHasPersisted(entry, trust: sa.authorization)), ContinuousClock.now < deadline { try await failures.check(); try await Task.sleep(for: .milliseconds(10)) }
        #expect(try await al.partnerHasPersisted(entry, trust: sa.authorization))
        _ = try await sb.append(f.operation(f.b, clock: 1000, entity: target, deleted: true))
        try await bb.synchronize(); try await waitForConvergence(sa, sb, count: 259, failures: failures)
        let ap = try OperationProjector.replay(sa.repository.allOperations(), context: await sa.projectionContext())
        let bp = try OperationProjector.replay(sb.repository.allOperations(), context: await sb.projectionContext())
        #expect(ap == bp); #expect(ap.tasks[target]?.deletedAt != nil)
        #expect(await left.paths().contains { $0.selected && $0.direct && !$0.relayed })
        #expect(await right.paths().contains { $0.selected && $0.direct && !$0.relayed })
        await left.close(); await right.close(); try await ea.close(); try await eb.close()
    }

    @Test func maliciousLengthIsRejectedBeforeFileSizedAllocation() async throws {
        let receiver = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let peer = try await Endpoint.bind(options: EndpointOptions(preset: presetMinimal(), relayMode: .disabled()))
        let address = await receiver.address()
        let accepting = Task { try await receiver.accept(expectedEndpointId: peer.id().description) }
        let connection = try await peer.connect(addr: EndpointAddr(id: EndpointId.fromString(s: address.endpointId), relayUrl: nil, addresses: address.directAddresses), alpn: P2PTransportLimits.alpn)
        let stream = try await connection.openBi()
        try await stream.send().writeAll(buf: Data([0xff, 0xff, 0xff, 0xff]))
        let incoming = try await accepting.value
        await #expect(throws: P2PTransportError.frameBounds) { try await incoming.receive() }
        await incoming.close(); try await receiver.close(); try await peer.close()
    }

    @MainActor private func waitForConvergence(_ a: AuthorizedReplicationStore, _ b: AuthorizedReplicationStore, count: Int, failures: LinkFailures) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            try await failures.check()
            // The observer can race durable imports. A changed snapshot is
            // retried here; errors inside the actual replication loops still
            // prevent convergence and fail the unchanged bounded deadline.
            do {
                if try await a.index.checkpoint() == b.index.checkpoint(), try a.repository.operationCount() == count { return }
            } catch ReplicationError.inventoryChanged { }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw P2PTransportError.closed
    }
}
