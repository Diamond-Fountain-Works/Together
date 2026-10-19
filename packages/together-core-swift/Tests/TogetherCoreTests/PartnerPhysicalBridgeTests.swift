import Foundation
import Testing
@testable import TogetherCore

/// Synthetic partner roots only. The Mac app/production store are never launched.
@Suite("Native partner physical bridge", .serialized) @MainActor struct PartnerPhysicalBridgeTests {
    struct Launch: Codable { var base: URL; var androidInvites: Bool }
    struct Code: Codable { var code: String }
    struct Phone: Codable { var device: DeviceDescriptor; var task: UUID; var wish: UUID; var gift: UUID }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_PARTNER_BRIDGE_DIR"] != nil))
    func nativeMacPairsIndependentAndroidPartnerAndConverges() async throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TOGETHER_PARTNER_BRIDGE_DIR"])).standardizedFileURL
        guard root.lastPathComponent.hasPrefix("together-partner-"), root.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path) else { throw ReplicationError.bounds }
        let launch = try CanonicalJSON.decode(Launch.self, from: Data(contentsOf: root.appendingPathComponent("launch.json")))
        guard (launch.base.scheme == "https" && launch.base.host == "together-pairing-staging.together-connection-service.workers.dev") || (launch.base.scheme == "http" && launch.base.host == "127.0.0.1") else { throw ReplicationError.unauthorized }
        let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_791_518_400))
        let identity = try DeviceIdentity(displayName: "Synthetic QA Mac", protocolVersion: 3)
        let engine = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("mac.store")), identity: identity, mediaRoot: root.appendingPathComponent("mac-media"), dateProvider: clock)
        try engine.setProfile(name: "Synthetic QA Mac", label: .boyfriend)
        _ = try engine.createTask(title: "Synthetic Mac before pairing")
        let service = PairingService(engine: engine, serviceURL: launch.base)
        defer { service.disconnect() }
        var stage = "invitation"
        defer { try? CanonicalJSON.encode(["stage": stage,"state": String(describing: service.state),"error": service.errorMessage ?? ""]).write(to: root.appendingPathComponent("mac-diagnostic.json"), options: .atomic) }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }
        if launch.androidInvites {
            try await wait("phone invitation") { exists("phone-invitation.json") }
            let code = try CanonicalJSON.decode(Code.self, from: Data(contentsOf: root.appendingPathComponent("phone-invitation.json")))
            await service.joinInvitation(code.code)
        } else {
            await service.createInvitation()
            try CanonicalJSON.encode(Code(code: try #require(service.invitationCode))).write(to: root.appendingPathComponent("mac-invitation.json"), options: .atomic)
        }
        stage = "fingerprint and shared verification code"
        try await wait(stage) { service.proposal != nil }
        let proposal = try #require(service.proposal)
        try CanonicalJSON.encode(["code":proposal.verificationCode,"fingerprint":proposal.fingerprint]).write(to: root.appendingPathComponent("mac-verification.json"), options: .atomic)
        try await wait("driver verified equal codes") { exists("approved") }
        #expect(engine.peer == nil)
        await service.confirmPairing()
        stage = "partner history and Protocol 4"
        try await wait(stage) { engine.usesReplication4 && service.isOnline }
        #expect(engine.identity.descriptor == identity.descriptor)
        #expect(engine.context.members.count == 2)
        #expect(engine.snapshot.tasks.values.contains { $0.title == "Synthetic Android before pairing" })
        let task = try engine.createTask(title: "Synthetic Mac live task")
        let deleted = try engine.createTask(title: "Synthetic Mac tombstone"); try engine.deleteTask(deleted)
        let partner = try #require(engine.peer?.descriptor.userId)
        let grant = try engine.grant(fulfiller: identity.descriptor.userId, beneficiary: partner, quantity: 3, date: .init(year: 2026, month: 10, day: 9), notes: "Synthetic cross-network grant")
        _ = try engine.deposit(FinanceAmount(original: "100.01"), by: identity.descriptor.userId, on: .init(year: 2026, month: 10, day: 9))
        _ = try engine.createRecurringBill(title: "Synthetic cross-network bill", amount: FinanceAmount(original: "68"), payment: .init(kind: .reserves), day: 9, timeZone: "Asia/Shanghai", startMonth: .init(year: 2026, month: 10))
        let photo = try await engine.importMedia(from: root.appendingPathComponent("synthetic.png"), type: .photo)
        let audio = try await engine.importMedia(from: root.appendingPathComponent("synthetic.wav"), type: .audio)
        var draft = LoveGiftDraft(); draft.text = "Synthetic Mac sealed gift"; draft.photoAssetId = photo.id; draft.audioAssetId = audio.id
        let gift = try engine.sendGift(draft)
        try CanonicalJSON.encode(["task":task,"deleted":deleted,"grant":grant,"gift":gift]).write(to: root.appendingPathComponent("mac-created.json"), options: .atomic)
        stage = "phone business and verified originals"
        try await wait(stage) { exists("phone-created.json") }
        let phone = try CanonicalJSON.decode(Phone.self, from: Data(contentsOf: root.appendingPathComponent("phone-created.json")))
        #expect(phone.device.userId != identity.descriptor.userId)
        #expect(engine.peer?.descriptor == phone.device)
        try await wait(stage) { engine.snapshot.wishes[phone.wish] != nil }
        try engine.requestFulfillment(phone.wish)
        try await wait(stage) { engine.snapshot.wishes[phone.wish]?.status == .fulfilled && engine.receivedGifts.contains { $0.id == phone.gift && engine.giftReady($0) } && engine.deliveryState(engine.snapshot.gifts[gift]!) == .synced }
        #expect(try engine.snapshot.finance.statistics().bookBalance == 1967)
        #expect(try engine.snapshot.finance.statistics().personal.values.reduce(0,+) == 999)
        #expect(engine.snapshot.balance(for:grant).remaining == 2)
        #expect(engine.snapshot.finance.expenses.values.filter { $0.recurringBillId != nil }.count == 1)
        stage = "offline merge and reconnect"
        try await wait(stage) { exists("phone-offline.json") }
        try engine.append(entity:phone.task,type:.task,action:.patch,fields:["title":.string("Synthetic Mac offline title")])
        _ = try engine.createTask(title:"Synthetic Mac catch-up")
        try Data().write(to:root.appendingPathComponent("mac-offline-written"),options:.atomic)
        try await wait(stage) { exists("phone-reconnected.json") && engine.snapshot.tasks[phone.task]?.notes == "Synthetic Android offline notes" }
        #expect(engine.snapshot.tasks[phone.task]?.title == "Synthetic Mac offline title")
        let checkpoint = try await OperationInventoryIndex(repository:engine.repository).checkpoint()
        try CanonicalJSON.encode(checkpoint).write(to:root.appendingPathComponent("mac-checkpoint.json"),options:.atomic)
        stage = "phone force-stop and persistent reopen"
        try await wait(stage,seconds:180) { exists("phone-restarted.json") }
        #expect(try await OperationInventoryIndex(repository:engine.repository).checkpoint() == checkpoint)
        try CanonicalJSON.encode(["status":"PASS","transport":"native Swift + physical Android over HTTPS/WSS","bookBalance":"1967","personal":"999","wishRemaining":"2","checkpoint":checkpoint.digest]).write(to:root.appendingPathComponent("mac-result.json"),options:.atomic)
        stage = "complete"
    }
    private struct Timeout: Error { let stage:String }
    private func wait(_ stage:String,seconds:Double=90,_ predicate:()->Bool)async throws {
        let deadline=ContinuousClock.now.advanced(by:.seconds(seconds))
        while !predicate(){ guard ContinuousClock.now < deadline else{throw Timeout(stage:stage)}; try await Task.sleep(for:.milliseconds(100)) }
    }
}
