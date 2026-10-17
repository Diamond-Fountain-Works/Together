import Foundation
import Testing
@testable import TogetherCore

/// A test-only native peer process driven by the Kotlin loopback harness.
/// Keys are generated here and never exported; every store is below a fresh temporary directory.
@Suite("Android Phase B real native bridge") @MainActor struct AndroidBusinessBridgeTests {
    struct Launch: Codable { var ownerA: UUID; var ownerB: UUID; var space: UUID; var base: URL; var route: UUID }
    struct Ready: Codable { var descriptors: [DeviceDescriptor] }
    struct Configuration: Codable { var archive: AuthorizationArchive }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_ANDROID_BRIDGE"] == "1"))
    func nativePeersExchangeTasksWishesFinanceAndOriginalMediaWithKotlin() async throws {
        guard let path = ProcessInfo.processInfo.environment["TOGETHER_ANDROID_BRIDGE_DIR"] else { throw ReplicationError.bounds }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        #expect(root.lastPathComponent.hasPrefix("together-b-swift-"))
        let launch = try CanonicalJSON.decode(Launch.self, from: Data(contentsOf: root.appendingPathComponent("launch.json")))
        #expect(launch.base.host == "127.0.0.1" && launch.base.scheme == "http")
        let a = try DeviceIdentity(userId: launch.ownerA, initialSpaceId: launch.space, protocolVersion: 4)
        let b = try DeviceIdentity(userId: launch.ownerB, initialSpaceId: launch.space, protocolVersion: 4)
        try CanonicalJSON.encode(Ready(descriptors: [a.descriptor, b.descriptor])).write(to: root.appendingPathComponent("descriptors.json"), options: .atomic)
        try await wait(label:"authorization") { FileManager.default.fileExists(atPath: root.appendingPathComponent("authorization.json").path) }
        let config = try CanonicalJSON.decode(Configuration.self, from: Data(contentsOf: root.appendingPathComponent("authorization.json")))
        let trust = try SpaceAuthorization.restore(config.archive)
        let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_791_518_400)) // 2026-10-09 04:00Z
        var services: [C1ReplicationService] = []
        var engines: [ReplicaEngine] = []
        defer { for s in services { s.stop() } }
        for (index, identity) in [a,b].enumerated() {
            let repository = try TogetherRepository(url: root.appendingPathComponent("native-\(index).store"))
            let binding = C1ReplicationBinding(serviceURL: launch.base, spaceId: launch.space, legacyRouteId: launch.route, localDeviceId: identity.descriptor.deviceId)
            try C1ReplicationService.prepareAuthorizedDevice(repository: repository, identity: identity, binding: binding, archive: trust.archive, trustedGenesisDigest: trust.genesis.digest)
            let store = try AuthorizedReplicationStore(repository: repository, identity: identity, authorization: trust)
            try await store.restore()
            let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: root.appendingPathComponent("native-media-\(index)"), dateProvider: clock)
            let service = try C1ReplicationService(engine: engine, binding: binding, store: store)
            engines.append(engine); services.append(service)
            await service.start()
        }
        let ea=engines[0], eb=engines[1]
        let task=try ea.createTask(title: "Synthetic native task", notes: "Native notes")
        let grant=try eb.grant(fulfiller: b.descriptor.userId, beneficiary: a.descriptor.userId, quantity: 3, date: CivilDate(year:2026,month:10,day:9), notes:"Synthetic grant")
        _ = try eb.deposit(FinanceAmount(original:"100.01"),by:b.descriptor.userId,on:CivilDate(year:2026,month:10,day:9))
        _ = try eb.createRecurringBill(title:"Synthetic native bill",amount:FinanceAmount(original:"68"),payment:.init(kind:.reserves),day:9,timeZone:"Asia/Shanghai",startMonth:FinanceMonth(year:2026,month:10))
        let photo=try await eb.importMedia(from:root.appendingPathComponent("synthetic.png"),type:.photo)
        let audio=try await eb.importMedia(from:root.appendingPathComponent("synthetic.wav"),type:.audio)
        var draft=LoveGiftDraft();draft.text="Synthetic native sealed gift";draft.photoAssetId=photo.id;draft.audioAssetId=audio.id
        let gift=try eb.sendGift(draft)
        var stage="initial task/wish sync"
        defer {
            let diagnostic:[String:String] = ["stage":stage,"aState":String(describing:services[0].state),"bState":String(describing:services[1].state),"aError":services[0].errorMessage ?? "","bError":services[1].errorMessage ?? "","aNotes":ea.snapshot.tasks[task]?.notes ?? "missing","bNotes":eb.snapshot.tasks[task]?.notes ?? "missing","bWish":eb.snapshot.wishes.values.map{String(describing:$0.status)}.sorted().joined(separator:","),"bReadyGifts":String(eb.receivedGifts.filter{eb.giftReady($0)}.count),"bOwnGiftState":String(describing:eb.deliveryState(eb.snapshot.gifts[gift]!))]
            try? CanonicalJSON.encode(diagnostic).write(to:root.appendingPathComponent("native-diagnostic.json"),options:.atomic)
        }
        try CanonicalJSON.encode(["task":task,"grant":grant,"gift":gift]).write(to:root.appendingPathComponent("native-created.json"),options:.atomic)
        try await wait(label:stage,seconds:90) { ea.snapshot.tasks.values.contains{$0.title=="Synthetic Kotlin task"} && eb.snapshot.wishes.values.contains{$0.title=="Synthetic Kotlin wish"} }
        let wish=try #require(eb.snapshot.wishes.values.first{$0.title=="Synthetic Kotlin wish"})
        try eb.requestFulfillment(wish.id)
        stage="confirmation and content receipt"
        try await wait(label:stage,seconds:90) { ea.snapshot.wishes[wish.id]?.status == .fulfilled && eb.receivedGifts.contains{eb.giftReady($0)} && eb.deliveryState(eb.snapshot.gifts[gift]!) == .synced }
        stage="offline barrier"
        try await wait(label:stage) { FileManager.default.fileExists(atPath:root.appendingPathComponent("offline").path) }
        try eb.append(entity:task,type:.task,action:.patch,fields:["title":.string("Native offline title")])
        try Data().write(to:root.appendingPathComponent("native-offline-written"),options:.atomic)
        stage="reconnect convergence"
        try await wait(label:stage,seconds:90) { ea.snapshot.tasks[task]?.notes=="Kotlin offline notes" && eb.snapshot.tasks[task]?.notes=="Kotlin offline notes" }
        let received=try #require(eb.receivedGifts.first)
        let stats=try eb.snapshot.finance.statistics()
        #expect(stats.bookBalance==1967)
        #expect(stats.personal.values.reduce(0,+)==999)
        #expect(eb.snapshot.finance.expenses.values.filter{$0.recurringBillId != nil}.count==1)
        #expect(eb.snapshot.wishes[wish.id]?.status == .fulfilled)
        #expect(received.assetIds.allSatisfy{eb.snapshot.mediaAssets[$0].map(eb.mediaStore.hasVerified) == true})
        let result:[String:String] = ["bookBalance":String(stats.bookBalance),"personal":String(stats.personal.values.reduce(0,+)),"wish":"fulfilled","photo":photo.sha256,"audio":audio.sha256,"status":"PASS"]
        try CanonicalJSON.encode(result).write(to:root.appendingPathComponent("native-result.json"),options:.atomic)
        stage="stop barrier"
        try await wait(label:stage) { FileManager.default.fileExists(atPath:root.appendingPathComponent("stop").path) }
        stage="complete"
    }
    private struct BridgeTimeout: Error, CustomStringConvertible { let description:String }
    private func wait(label:String,seconds:Double=60,_ condition:()->Bool) async throws {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() { guard Date()<deadline else {throw BridgeTimeout(description:"Native bridge timed out: \(label)")};try await Task.sleep(for:.milliseconds(100)) }
    }
}
