import Foundation
import Testing
import ImageIO
@testable import TogetherCore

@Suite("Original Media & TCP Gifts") @MainActor struct MediaTransferTests {
    @Test func originalBytesPartialResumeHashAndDamagedMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-media-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeImage(in: root), owner = UUID(), space = UUID()
        let a = try MediaStore(root: root.appendingPathComponent("a")), b = try MediaStore(root: root.appendingPathComponent("b"))
        let asset = try a.importOriginal(from: source, type: .avatar, owner: owner, space: space, now: instant("2026-10-09T12:00:00Z"))
        #expect(asset.sha256 == (try a.digest(source)))
        let original = CGImageSourceCreateWithURL(a.originalURL(asset) as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as! [CFString: Any]
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 8200)
        #expect(asset.byteCount > Int64(MediaStore.chunkSize))
        #expect(try b.resumeOffset(asset) == 0 && !b.hasVerified(asset))
        let first = try a.readChunk(asset, offset: 0)
        try b.appendChunk(first, to: asset, offset: 0)
        #expect(try b.appendChunk(first, to: asset, offset: 0) == Int64(first.count))
        let reopened = try MediaStore(root: b.root)
        var offset = try reopened.resumeOffset(asset)
        #expect(offset == Int64(first.count))
        #expect(throws: (any Error).self) { try reopened.finishDownload(asset) }
        while offset < asset.byteCount { let chunk = try a.readChunk(asset, offset: offset); offset = try reopened.appendChunk(chunk, to: asset, offset: offset) }
        try reopened.finishDownload(asset)
        #expect(reopened.hasVerified(asset))
        #expect(try reopened.digest(reopened.originalURL(asset)) == asset.sha256)
        let preview = try reopened.thumbnail(asset, crop: AvatarCrop(zoom: 1.5))
        #expect(FileManager.default.fileExists(atPath: preview.path))
        #expect(try reopened.digest(reopened.originalURL(asset)) == asset.sha256) // crop never modifies source
        #expect(throws: (any Error).self) { try reopened.thumbnail(asset, crop: AvatarCrop(zoom: .nan)) }
        let bad = try MediaStore(root: root.appendingPathComponent("bad"))
        var badOffset: Int64 = 0
        while badOffset < asset.byteCount {
            var chunk = try a.readChunk(asset, offset: badOffset); if badOffset == 0 { chunk[0] ^= 1 }
            badOffset = try bad.appendChunk(chunk, to: asset, offset: badOffset)
        }
        #expect(throws: (any Error).self) { try bad.finishDownload(asset) }
        #expect(!bad.hasVerified(asset))
        #expect(try bad.resumeOffset(asset) == 0)
        let broken = root.appendingPathComponent("broken.png"); try Data("not a photo".utf8).write(to: broken)
        #expect(throws: (any Error).self) { try a.importOriginal(from: broken, type: .photo, owner: owner, space: space, now: .now) }
    }
    @Test func audioOnlyPhotoOnlyAndAllThreeContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-combinations-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), p = try TwoReplicas()
        let a = try ReplicaEngine(repository: p.a.repository, identity: p.a.identity, mediaRoot: root.appendingPathComponent("assets"), dateProvider: clock)
        let photo = try await a.importMedia(from: makeImage(in: root), type: .photo)
        let audio = try await a.importMedia(from: makeAudio(in: root), type: .audio)
        #expect(a.snapshot.mediaAssets[photo.id] == nil && a.snapshot.mediaAssets[audio.id] == nil) // drafts do not publish attachment metadata
        #expect(a.mediaAsset(photo.id)?.transferStatus == .verified)
        var draft = LoveGiftDraft(); draft.audioAssetId = audio.id
        let one = try a.sendGift(draft)
        #expect(a.snapshot.mediaAssets[audio.id] != nil && a.snapshot.mediaAssets[photo.id] == nil)
        #expect(a.snapshot.gifts[one]?.hasText == false && a.snapshot.gifts[one]?.audioAssetId == audio.id)
        clock.advance(86400); draft.audioAssetId = nil; draft.photoAssetId = photo.id
        let two = try a.sendGift(draft)
        #expect(a.snapshot.gifts[two]?.photoAssetId == photo.id && a.snapshot.gifts[two]?.hasText == false)
        clock.advance(86400); draft.text = "文字、声音和照片是一份爱意"; draft.audioAssetId = audio.id
        let three = try a.sendGift(draft)
        #expect(a.snapshot.gifts[three]?.assetIds.count == 2 && a.snapshot.gifts[three]?.hasText == true)
        #expect(throws: (any Error).self) { try a.sendGift(draft) }
        clock.advance(86400)
        #expect(throws: (any Error).self) { try a.sendGift(LoveGiftDraft()) }
        let unused = try await a.importMedia(from: makeAudio(in: root), type: .audio)
        try a.discardUnpublishedMedia(unused.id)
        #expect(a.mediaAsset(unused.id) == nil && !FileManager.default.fileExists(atPath: a.mediaStore.originalURL(unused).path))
    }
    @Test func realTCPMediaAcknowledgementReconnectAndAvatar() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-TCP-gift-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(instant("2026-10-09T12:00:00Z"))
        let ia = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!, timeZoneIdentifier: "Asia/Shanghai")
        let ib = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!, timeZoneIdentifier: "America/Los_Angeles")
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: ia, mediaRoot: root.appendingPathComponent("a-media"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: ib, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
        let netA = PeerService(engine: a), netB = PeerService(engine: b)
        defer { netA.stopListening(); netB.stopListening() }
        try netA.startListening(host: "127.0.0.1", port: 0, persist: false); try netB.startListening(host: "127.0.0.1", port: 0, persist: false)
        do { try await eventually { netA.boundPort > 0 && netB.boundPort > 0 } }
        catch { Issue.record("Listener ready: A \(netA.boundPort) / \(netA.errorMessage ?? "none"), B \(netB.boundPort) / \(netB.errorMessage ?? "none")"); throw error }
        // Simultaneous outgoing connections must converge to one authenticated session.
        try netA.connect(host: "127.0.0.1", port: netB.boundPort); try netB.connect(host: "127.0.0.1", port: netA.boundPort)
        do { try await eventually { netA.proposal != nil && netB.proposal != nil } }
        catch { Issue.record("Pairing proposals: A \(netA.state) / \(netA.errorMessage ?? "none"), B \(netB.state) / \(netB.errorMessage ?? "none")"); throw error }
        #expect(netA.proposal?.verificationCode == netB.proposal?.verificationCode)
        try netA.confirmPairing(); try netB.confirmPairing()
        do { try await eventually { netA.state == .connected && netB.state == .connected } }
        catch { Issue.record("Pairing activation: A \(netA.state) / \(netA.errorMessage ?? "none"), B \(netB.state) / \(netB.errorMessage ?? "none")"); throw error }
        netA.disconnect(); netB.disconnect()
        let source = try makeImage(in: root)
        let avatar = try await a.importMedia(from: source, type: .avatar); try a.setAvatar(assetId: avatar.id, crop: AvatarCrop(zoom: 1.2))
        let photo = try await a.importMedia(from: source, type: .photo)
        let audio = try await a.importMedia(from: makeAudio(in: root), type: .audio)
        var draft = LoveGiftDraft(); draft.text = "离线时准备的礼物"; draft.photoAssetId = photo.id; draft.audioAssetId = audio.id
        let id = try a.sendGift(draft)
        #expect(a.deliveryState(a.snapshot.gifts[id]!) == .pendingSync && b.receivedGifts.isEmpty)
        // Receive one persisted chunk ahead of reconnect to exercise resume instead of re-downloading.
        try b.merge(a.operations)
        try b.mediaStore.appendChunk(a.mediaStore.readChunk(photo, offset: 0), to: b.snapshot.mediaAssets[photo.id]!, offset: 0)
        #expect(!b.giftReady(b.snapshot.gifts[id]!))
        try netB.startListening(host: "127.0.0.1", port: 0, persist: false)
        do { try await eventually { netB.boundPort > 0 } }
        catch { Issue.record("Listener restart: B \(netB.boundPort) / \(netB.errorMessage ?? "none")"); throw error }
        try netA.connect(host: "127.0.0.1", port: netB.boundPort)
        try await eventually({ a.deliveryState(a.snapshot.gifts[id]!) == .synced && b.giftReady(b.snapshot.gifts[id]!) && b.mediaStore.hasVerified(b.snapshot.mediaAssets[avatar.id]!) }, seconds: 20)
        #expect(try b.mediaStore.digest(b.mediaStore.originalURL(b.snapshot.mediaAssets[photo.id]!)) == photo.sha256)
        #expect(b.partnerProfile?.avatarAssetId == avatar.id && b.partnerProfile?.avatarCrop?.zoom == 1.2)
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: ib, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
        #expect(reopened.receivedGifts.count == 1 && reopened.giftReady(reopened.receivedGifts[0]))
        #expect(reopened.mediaStore.hasVerified(reopened.snapshot.mediaAssets[avatar.id]!))
        try b.markGiftPresented(id, automatic: true); try b.markGiftOpened(id)
        try a.deleteGift(id)
        do { try await eventually { b.receivedGifts.isEmpty } }
        catch { Issue.record("Gift delete sync: A \(netA.state) / \(netA.errorMessage ?? "none") / \(a.operations.count) ops, B \(netB.state) / \(netB.errorMessage ?? "none") / \(b.operations.count) ops / deleted \(String(describing: b.snapshot.gifts[id]?.deletedAt))"); throw error }
        #expect(b.presentation(id).hasAutoPresented && b.presentation(id).openedAt != nil)
        #expect(a.hasSentGift(on: clock.now()))
    }
}
