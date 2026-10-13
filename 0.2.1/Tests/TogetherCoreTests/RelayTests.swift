import Foundation
import Testing
import CryptoKit
@testable import TogetherCore

@Suite("Relay security") @MainActor struct RelaySecurityTests {
    private func sessions() throws -> (RelaySecureSession, RelaySecureSession, DeviceIdentity, DeviceIdentity) {
        let a = try DeviceIdentity(), b = try DeviceIdentity(), ka = Curve25519.KeyAgreement.PrivateKey(), kb = Curve25519.KeyAgreement.PrivateKey(), route = UUID()
        let ha = try RelaySecureSession.hello(identity: a, ephemeral: ka, routeId: route, profileName: "A")
        let hb = try RelaySecureSession.hello(identity: b, ephemeral: kb, routeId: route, profileName: "B")
        return (try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb), try RelaySecureSession(identity: b, ephemeral: kb, local: hb, remote: ha), a, b)
    }
    @Test func encryptedRoundtripTamperReplayAndReflection() throws {
        let (a,b,_,_) = try sessions(); #expect(a.transcript == b.transcript)
        let bytes = Data("private operation and gift content".utf8), packet = try a.seal(bytes)
        #expect(packet.ciphertext != bytes)
        #expect(try b.open(packet) == bytes)
        #expect(throws: (any Error).self) { try b.open(packet) }
        #expect(throws: (any Error).self) { try a.open(packet) }
        var damaged = try a.seal(bytes); damaged.ciphertext![15] ^= 1
        #expect(throws: (any Error).self) { try b.open(damaged) }
        let (freshA,freshB,_,_) = try sessions()
        #expect(throws: (any Error).self) { try freshB.open(packet) }
        #expect(try freshB.open(freshA.seal(bytes)) == bytes)
    }
    @Test func invalidHandshakePinAndConsentAreRejected() throws {
        let a = try DeviceIdentity(), b = try DeviceIdentity(), attacker = try DeviceIdentity(), ka = Curve25519.KeyAgreement.PrivateKey(), kb = Curve25519.KeyAgreement.PrivateKey(), route = UUID()
        let ha = try RelaySecureSession.hello(identity: a, ephemeral: ka, routeId: route, profileName: "A")
        var hb = try RelaySecureSession.hello(identity: b, ephemeral: kb, routeId: route, profileName: "B")
        #expect(throws: (any Error).self) { try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb, expectedPeer: attacker.descriptor) }
        hb.body.profileName = "forged"
        #expect(!hb.verified())
        #expect(throws: (any Error).self) { try RelaySecureSession(identity: a, ephemeral: ka, local: ha, remote: hb) }
        let (sa,_,ia,ib) = try sessions()
        #expect(try sa.consent(identity: ia).verified(by: ia.descriptor, transcript: sa.transcript))
        #expect(!(try sa.consent(identity: ia).verified(by: ib.descriptor, transcript: sa.transcript)))
    }
    @Test func migrationPreservesExistingSpaceTasksWishesAndRefusesReplacement() throws {
        let p = try TwoReplicas(); let before = p.a.context.spaceId
        let task = try p.a.createTask(title: "Keep existing task")
        let grant = try p.a.grant(fulfiller: p.a.identity.descriptor.userId, beneficiary: p.b.identity.descriptor.userId, quantity: 2, date: CivilDate(year: 2026, month: 10, day: 9), notes: "")
        let binding = RelayBinding(serviceURL: URL(string: "https://relay.example.test")!, routeId: UUID(), peerDeviceId: p.b.identity.descriptor.deviceId, peerPublicKey: p.b.identity.descriptor.publicKey, localDeviceId: p.a.identity.descriptor.deviceId)
        try p.a.bindRelay(peer: p.a.peer!, binding: binding)
        #expect(p.a.context.spaceId == before && p.a.snapshot.tasks[task] != nil && p.a.snapshot.grants[grant] != nil)
        #expect(try p.a.repository.load(RelayBinding.self, key: "relay-binding") == binding)
        let attacker = try DeviceIdentity()
        let bad = RelayBinding(serviceURL: binding.serviceURL, routeId: UUID(), peerDeviceId: attacker.descriptor.deviceId, peerPublicKey: attacker.descriptor.publicKey, localDeviceId: p.a.identity.descriptor.deviceId)
        #expect(throws: (any Error).self) { try p.a.bindRelay(peer: PairedPeer(descriptor: attacker.descriptor, host: "127.0.0.1", port: 0), binding: bad) }
        #expect(p.a.context.spaceId == before && p.a.snapshot.tasks[task] != nil)
    }
    @Test func lateFirstSyncDefersUntilNextLaunchAndCachedGiftDoesNotWait() throws {
        let p = try TwoReplicas(); var draft = LoveGiftDraft(); draft.text = "private"
        let id = try p.a.sendGift(draft); try p.exchange()
        let clock = TestClock(instant("2026-10-09T12:00:00Z"))
        var late = GiftLaunchPolicy(cachedInboxIds: [], clock: clock); clock.advance(20); late.noteFirstSync(inboxIds: [id])
        #expect(late.eligible(inbox: p.b.receivedGifts, readyIds: [id], presentations: [:]).isEmpty)
        let restarted = GiftLaunchPolicy(cachedInboxIds: [id], clock: clock)
        #expect(restarted.eligible(inbox: p.b.receivedGifts, readyIds: [id], presentations: [:]) == [id])
    }
    @Test func serviceURLAndOfflineSafety() throws {
        let engine = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: DeviceIdentity())
        #expect(throws: (any Error).self) { try RelayAPI(base: URL(string: "http://public.example.com")!, identity: engine.identity) }
        for origin in ["https://relay.example.test/path", "https://relay.example.test?token=value", "https://user:secret@relay.example.test"] {
            #expect(throws: (any Error).self) { try RelayAPI(base: URL(string: origin)!, identity: engine.identity) }
        }
        let service = PairingService(engine: engine, serviceURL: nil)
        service.restore(); #expect(!service.isOnline && !service.isConfigured && service.state == .unpaired)
        let task = try engine.createTask(title: "Offline usable")
        #expect(engine.snapshot.tasks[task] != nil)
    }
}

@Suite("Original photo export") @MainActor struct PhotoExportTests {
    @Test func exportedPhotoKeepsFormatDimensionsBytesAndInternalOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-export-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let store = try MediaStore(root: root.appendingPathComponent("media"))
        let source = try makeImage(in: root), asset = try store.importOriginal(from: source, type: .photo, owner: UUID(), space: UUID(), now: .now)
        let output = root.appendingPathComponent("saved.png")
        try store.exportOriginal(asset, to: output)
        #expect(try store.digest(output) == asset.sha256)
        #expect(try store.digest(store.originalURL(asset)) == asset.sha256)
        #expect(throws: (any Error).self) { try store.exportOriginal(asset, to: root.appendingPathComponent("wrong.jpg")) }
        #expect(throws: (any Error).self) { try store.exportOriginal(asset, to: store.originalURL(asset)) }
        var invalid = asset; invalid.sha256 = String(repeating: "0", count: 64)
        #expect(throws: (any Error).self) { try store.exportOriginal(invalid, to: root.appendingPathComponent("invalid.png")) }
    }
}

@Suite("Workers relay integration") @MainActor struct RelayIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_RELAY_TESTS"] == "1")) func storedVersionTwoRelayPairUpgradesWithoutNewInvitation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-relay-upgrade-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(instant("2026-10-09T04:00:00Z")), da = UUID(), db = UUID(), ua = UUID(), ub = UUID(), spa = UUID(), spb = UUID()
        func identity(_ a: Bool, version: Int) throws -> DeviceIdentity { try DeviceIdentity(deviceId: a ? da : db, userId: a ? ua : ub, initialSpaceId: a ? spa : spb, privateKeyData: Data(repeating: a ? 31 : 32, count: 32), timeZoneIdentifier: "Asia/Shanghai", protocolVersion: version) }
        let oldA = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: identity(true, version: 2), dateProvider: clock)
        let oldB = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: identity(false, version: 2), dateProvider: clock)
        let url = try #require(URL(string: ProcessInfo.processInfo.environment["TOGETHER_RELAY_TEST_URL"] ?? "http://127.0.0.1:8787")), timeout: Double = url.scheme == "https" ? 90 : 20
        let oldLeft = PairingService(engine: oldA, serviceURL: url), oldRight = PairingService(engine: oldB, serviceURL: url)
        defer { oldLeft.disconnect(); oldRight.disconnect() }
        let task = try oldA.createTask(title: "PRESERVE_OLD_ROUTE_FIXTURE")
        await oldLeft.createInvitation(); await oldRight.joinInvitation(try #require(oldLeft.invitationCode))
        try await eventually({ oldLeft.proposal != nil && oldRight.proposal != nil }, seconds: timeout)
        await oldLeft.confirmPairing(); await oldRight.confirmPairing()
        try await eventually({ oldLeft.isOnline && oldRight.isOnline && oldA.snapshot == oldB.snapshot }, seconds: timeout)
        let space = oldA.context.spaceId, route = try #require(try oldA.repository.load(RelayBinding.self, key: "relay-binding")).routeId
        oldLeft.disconnect(); oldRight.disconnect()
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: identity(true, version: 3), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: identity(false, version: 3), dateProvider: clock)
        #expect(a.peer?.descriptor.protocolVersion == 2 && a.identity.descriptor.publicKey == oldA.identity.descriptor.publicKey)
        let sa = PairingService(engine: a, serviceURL: url), sb = PairingService(engine: b, serviceURL: url)
        defer { sa.disconnect(); sb.disconnect() }
        sa.restore(); sb.restore()
        try await eventually({ sa.isOnline && sb.isOnline && a.peer?.descriptor.protocolVersion == 3 && b.peer?.descriptor.protocolVersion == 3 }, seconds: timeout)
        #expect(sa.proposal == nil && sb.proposal == nil && a.context.spaceId == space && b.snapshot.tasks[task] != nil)
        #expect(try a.repository.load(RelayBinding.self, key: "relay-binding")?.routeId == route)
        _ = try a.deposit(FinanceAmount(original: "2000"), by: ua, on: CivilDate(year: 2026, month: 10, day: 9))
        try await eventually({ a.snapshot.finance == b.snapshot.finance && b.snapshot.finance.reserves.count == 1 }, seconds: timeout)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_RELAY_TESTS"] == "1")) func invitationMutualConfirmEncryptedLogMediaReconnectAndPersistentMigration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-relay-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock(instant("2026-10-09T12:00:00Z")), ia = try DeviceIdentity(protocolVersion: 3), ib = try DeviceIdentity(protocolVersion: 3)
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: ia, mediaRoot: root.appendingPathComponent("a-media"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: ib, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
        let url = try #require(URL(string: ProcessInfo.processInfo.environment["TOGETHER_RELAY_TEST_URL"] ?? "http://127.0.0.1:8787")), sa = PairingService(engine: a, serviceURL: url), sb = PairingService(engine: b, serviceURL: url)
        let networkTimeout: Double = url.scheme == "https" ? 90 : 20
        defer { sa.disconnect(); sb.disconnect() }
        try a.setProfile(name: "Relay fixture A", label: .boyfriend)
        try b.setProfile(name: "Relay fixture B", label: .girlfriend)
        let keep = try a.createTask(title: "Pre-pair offline task")
        await sa.createInvitation()
        let code = try #require(sa.invitationCode)
        await sb.joinInvitation(code)
        do { try await eventually({ sa.proposal != nil && sb.proposal != nil }, seconds: networkTimeout) }
        catch { Issue.record("Relay handshake: \(sa.errorMessage ?? "none") / \(sb.errorMessage ?? "none")"); throw error }
        #expect(sa.proposal?.verificationCode == sb.proposal?.verificationCode)
        #expect(a.peer == nil && b.peer == nil)
        await sa.confirmPairing(); #expect(a.peer == nil)
        await sb.confirmPairing()
        do { try await eventually({ sa.isOnline && sb.isOnline && a.snapshot == b.snapshot }, seconds: networkTimeout) }
        catch { Issue.record("Relay consent/sync: \(sa.state) \(sa.errorMessage ?? "none") / \(sb.state) \(sb.errorMessage ?? "none")"); throw error }
        #expect(b.snapshot.tasks[keep] != nil)
        #expect(b.partnerProfile?.role == .boyfriend && a.partnerProfile?.role == .girlfriend)
        let grant = try a.grant(fulfiller: ia.descriptor.userId, beneficiary: ib.descriptor.userId, quantity: 2, date: CivilDate(year: 2026, month: 10, day: 9), notes: "Relay fixture ledger")
        try await eventually({ b.snapshot.grants[grant] != nil }, seconds: networkTimeout)
        let wish = try b.createWish(grantId: grant, title: "Relay fixture wish", description: "")
        try await eventually({ a.snapshot.wishes[wish] != nil }, seconds: networkTimeout)
        try a.requestFulfillment(wish)
        try await eventually({ b.snapshot.wishes[wish]?.status == .completionRequested }, seconds: networkTimeout)
        try b.confirmFulfillment(wish)
        try await eventually({ a.snapshot.balance(for: grant).remaining == 1 }, seconds: networkTimeout)
        let financeDay = CivilDate(year: 2026, month: 10, day: 9)
        let deposit = try a.deposit(FinanceAmount(original: "100", currency: "USD", actualCNY: "701.23"), by: ia.descriptor.userId, on: financeDay)
        try await eventually({ b.snapshot.finance.reserves[deposit] != nil }, seconds: networkTimeout)
        let expense = try b.createExpense(title: "Relay financial AA fixture", amount: FinanceAmount(original: "100.01"), payment: .init(kind: .equalSplit, userIds: [ia.descriptor.userId, ib.descriptor.userId]), on: financeDay)
        let bill = try a.createRecurringBill(title: "Relay provisional fixture", amount: FinanceAmount(original: "68"), payment: .init(kind: .reserves), day: 8, timeZone: "Asia/Shanghai", startMonth: .init(year: 2026, month: 10))
        try await eventually({ a.snapshot.finance == b.snapshot.finance && a.snapshot.finance.expenses.count == 2 }, seconds: networkTimeout)
        #expect(b.snapshot.finance.expenses[expense] != nil)
        #expect(try a.snapshot.finance.statistics().bookBalance == 63323)
        let occurrence = StableID.make("finance-bill:\(bill.uuidString):2026-10")
        try b.reviewExpense(occurrence, status: .reconciled)
        try await eventually({ a.snapshot.finance.expenses[occurrence]?.status == .reconciled && a.snapshot.finance == b.snapshot.finance }, seconds: networkTimeout)
        let original = try makeImage(in: root), photo = try await a.importMedia(from: original, type: .photo)
        let avatar = try await a.importMedia(from: original, type: .avatar)
        try a.setAvatar(assetId: avatar.id)
        let audio = try await a.importMedia(from: makeAudio(in: root), type: .audio)
        var draft = LoveGiftDraft(); draft.text = "Encrypted fixture gift"; draft.photoAssetId = photo.id; draft.audioAssetId = audio.id
        let id = try a.sendGift(draft)
        #expect(a.deliveryState(a.snapshot.gifts[id]!) == .pendingSync)
        try await eventually({ b.receivedGifts.count == 1 && b.giftReady(b.receivedGifts[0]) && a.deliveryState(a.snapshot.gifts[id]!) == .synced && b.partnerProfile?.avatarAssetId == avatar.id && b.snapshot.mediaAssets[avatar.id].map(b.mediaStore.hasVerified) == true }, seconds: networkTimeout)
        #expect(try b.mediaStore.digest(b.mediaStore.originalURL(b.snapshot.mediaAssets[photo.id]!)) == photo.sha256)
        #expect(try b.mediaStore.digest(b.mediaStore.originalURL(b.snapshot.mediaAssets[audio.id]!)) == audio.sha256)
        #expect(try b.mediaStore.digest(b.mediaStore.originalURL(b.snapshot.mediaAssets[avatar.id]!)) == avatar.sha256)
        let space = a.context.spaceId
        sb.disconnect(); try b.createTask(title: "Offline B"); try a.createTask(title: "Offline A")
        try b.editExpense(expense, title: "Relay financial AA fixture", amount: FinanceAmount(original: "118.01"), payment: .init(kind: .equalSplit, userIds: [ia.descriptor.userId, ib.descriptor.userId]), on: financeDay, category: "", notes: "", dateEventId: nil)
        _ = try a.deposit(FinanceAmount(original: "200"), by: ia.descriptor.userId, on: financeDay)
        sb.restore()
        do { try await eventually({ sa.isOnline && sb.isOnline && a.snapshot == b.snapshot && a.snapshot.tasks.count == 3 }, seconds: networkTimeout) }
        catch { Issue.record("Relay reconnect: \(sa.state) \(sa.errorMessage ?? "none") / \(sb.state) \(sb.errorMessage ?? "none")"); throw error }
        #expect(a.context.spaceId == space && b.context.spaceId == space)
        #expect(sa.proposal == nil && sb.proposal == nil)
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: ib, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
        #expect(reopened.context.spaceId == space && reopened.snapshot.tasks.count == 3)
        #expect(reopened.snapshot.balance(for: grant).remaining == 1 && reopened.giftReady(reopened.receivedGifts[0]))
        #expect(reopened.snapshot.finance == b.snapshot.finance && reopened.snapshot.finance.expenses[expense]?.amount.finalCNYMinor == 11801)
        #expect(try reopened.snapshot.finance.statistics().bookBalance == 83323)
        #expect(try reopened.repository.load(RelayBinding.self, key: "relay-binding") != nil)
    }
}
