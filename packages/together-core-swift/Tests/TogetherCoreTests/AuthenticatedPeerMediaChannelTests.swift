import Foundation
import Testing
@testable import TogetherCore

private struct AuthenticatedContentVector: Decodable {
    var nativeAppALPN: String
    var legacyTransportALPN: String
    var canonicalEnvelopes: [String]
}

@Suite("Existing authenticated content and media adapter") @MainActor struct AuthenticatedPeerMediaChannelTests {
    @Test func sharedContentVectorsMatchExistingC1EncodingWithoutRawFrameFallback() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("qa/project.json").path) { break }
            root.deleteLastPathComponent()
        }
        let fixture = try CanonicalJSON.decode(AuthenticatedContentVector.self,
            from: Data(contentsOf: root.appendingPathComponent("protocol/fixtures/authenticated-content-v1.json")))
        #expect(fixture.nativeAppALPN == "together/p4/c1-content/1")
        #expect(fixture.legacyTransportALPN == "together/p4/1")
        #expect(fixture.canonicalEnvelopes.count == 7)
        for json in fixture.canonicalEnvelopes {
            let bytes = Data(json.utf8)
            let value = try CanonicalJSON.decode(C1Content.self, from: bytes)
            #expect(try CanonicalJSON.encode(value) == bytes)
        }
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        #expect(String(decoding: try AuthenticatedPeerMediaChannel.encodeReplication(.syncHint(id)), as: UTF8.self) == fixture.canonicalEnvelopes[0])
        #expect(throws: (any Error).self) { try CanonicalJSON.decode(C1Content.self, from: CanonicalJSON.encode(ReplicationFrame.syncHint(id))) }
    }

    @Test func existingMediaResumesOriginalBytesAndRequiresContentReceiptWithoutAddingLogFacts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-media-bridge-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let aId = try DeviceIdentity(protocolVersion: 3), bId = try DeviceIdentity(protocolVersion: 3)
        let a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: aId, mediaRoot: root.appendingPathComponent("a"))
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: bId, mediaRoot: root.appendingPathComponent("b"))
        try a.authorize(PairedPeer(descriptor: bId.descriptor, host: "127.0.0.1", port: 0))
        try b.authorize(PairedPeer(descriptor: aId.descriptor, host: "127.0.0.1", port: 0))
        let photo = try await a.importMedia(from: makeImage(in: root), type: .photo)
        var draft = LoveGiftDraft(); draft.photoAssetId = photo.id
        let giftId = try a.sendGift(draft)
        for _ in 0..<2 { try a.merge(b.operations); try b.merge(a.operations) }
        let checkpoint = try await OperationInventoryIndex(repository: a.repository).checkpoint()
        let genesis = try SignedSpaceGenesis.sign(SpaceGenesisBody(context: a.context, legacyCheckpoint: checkpoint), with: [aId, bId])
        _ = try await a.activateReplication4(AuthorizationArchive(genesis: genesis, events: []))
        _ = try await b.activateReplication4(AuthorizationArchive(genesis: genesis, events: []))
        let factCount = a.operations.count
        #expect(a.deliveryState(try #require(a.snapshot.gifts[giftId])) == .pendingSync)
        #expect(!b.giftReady(try #require(b.snapshot.gifts[giftId])))
        var fromA: [Data] = [], fromB: [Data] = [], errors: [Error] = []
        var sender = try AuthenticatedPeerMediaChannel(engine: a, remote: bId.descriptor, send: { fromA.append($0) })
        var receiver = try AuthenticatedPeerMediaChannel(engine: b, remote: aId.descriptor, send: { fromB.append($0) })
        sender.onError = { errors.append($0) }; receiver.onError = { errors.append($0) }
        defer { sender.invalidate(); receiver.invalidate() }
        try receiver.synchronize()
        for bytes in fromB { _ = try sender.receive(bytes) }; fromB.removeAll()
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while fromA.isEmpty, ContinuousClock.now < firstDeadline { try await Task.sleep(for: .milliseconds(2)) }
        _ = try receiver.receive(try #require(fromA.first))
        let partial = try b.mediaStore.resumeOffset(photo)
        #expect(partial > 0 && partial < photo.byteCount)
        #expect(a.deliveryState(try #require(a.snapshot.gifts[giftId])) == .pendingSync)

        // Only the authenticated media session changes; the same partial file,
        // fact log and independent original asset survive interruption.
        sender.invalidate(); receiver.invalidate(); fromA.removeAll(); fromB.removeAll()
        sender = try AuthenticatedPeerMediaChannel(engine: a, remote: bId.descriptor, send: { fromA.append($0) })
        receiver = try AuthenticatedPeerMediaChannel(engine: b, remote: aId.descriptor, send: { fromB.append($0) })
        sender.onError = { errors.append($0) }; receiver.onError = { errors.append($0) }
        try receiver.synchronize()
        if case .media(.mediaRequest(let asset, let offset)) = try CanonicalJSON.decode(C1Content.self, from: #require(fromB.first)) {
            #expect(asset == photo.id && offset == partial)
        } else { Issue.record("Expected the existing partial-file resume request") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while a.deliveryState(try #require(a.snapshot.gifts[giftId])) != .synced, errors.isEmpty, ContinuousClock.now < deadline {
            let requests = fromB; fromB.removeAll()
            for bytes in requests { _ = try sender.receive(bytes) }
            let responses = fromA; fromA.removeAll()
            for bytes in responses { _ = try receiver.receive(bytes) }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(errors.isEmpty)
        #expect(b.mediaStore.hasVerified(photo))
        #expect(try b.mediaStore.digest(b.mediaStore.originalURL(photo)) == photo.sha256)
        #expect(a.deliveryState(try #require(a.snapshot.gifts[giftId])) == .synced)
        #expect(a.operations.count == factCount && b.operations.count == factCount)
        let hint = UUID()
        if case .syncHint(let decoded)? = try receiver.receive(AuthenticatedPeerMediaChannel.encodeReplication(.syncHint(hint))) {
            #expect(decoded == hint)
        } else { Issue.record("Replication must remain on the existing paged session") }
        let legacyLogPacket = try CanonicalJSON.encode(C1Content.media(.operation(try #require(a.operations.first))))
        #expect(throws: (any Error).self) { try receiver.receive(legacyLogPacket) }
        #expect(b.operations.count == factCount)
    }
}
