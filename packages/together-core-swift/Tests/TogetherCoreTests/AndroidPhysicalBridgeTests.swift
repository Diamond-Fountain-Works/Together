import Foundation
import Testing
@testable import TogetherCore

/// Dedicated native QA process, not Together.app. All paths are freshly created by the driver;
/// no production defaults, identity files, database or App executable are opened.
@Suite("Physical Android C1 acceptance") @MainActor struct AndroidPhysicalBridgeTests {
  struct Launch: Codable { var base: URL }
  struct Phone: Codable { var device: DeviceDescriptor; var task: UUID; var wish: UUID; var gift: UUID }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_RUN_PHYSICAL_ANDROID_BRIDGE"] == "1"))
  func independentlyEnrolledPhoneExchangesDurableBusinessAndOriginals() async throws {
    guard let path = ProcessInfo.processInfo.environment["TOGETHER_PHYSICAL_BRIDGE_DIR"] else { throw ReplicationError.bounds }
    let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    guard root.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path),
      root.lastPathComponent.hasPrefix("together-c-physical-") else { throw ReplicationError.bounds }
    let launch = try CanonicalJSON.decode(Launch.self, from: Data(contentsOf: root.appendingPathComponent("launch.json")))
    guard launch.base.scheme == "http", launch.base.host == "127.0.0.1" else { throw ReplicationError.bounds }
    let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_791_518_400))
    let ia = try DeviceIdentity(displayName: "Synthetic QA Mac A", protocolVersion: 3)
    let ib = try DeviceIdentity(displayName: "Synthetic QA Mac B", protocolVersion: 3)
    let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("a.store")), identity: ia, mediaRoot: root.appendingPathComponent("a-media"), dateProvider: clock)
    let b = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("b.store")), identity: ib, mediaRoot: root.appendingPathComponent("b-media"), dateProvider: clock)
    let oldA = PairingService(engine: a, serviceURL: launch.base), oldB = PairingService(engine: b, serviceURL: launch.base)
    defer { oldA.disconnect(); oldB.disconnect() }
    var stage = "legacy synthetic pairing"
    let started = ContinuousClock.now
    var timing: [String: Double] = [:]
    func checkpoint(_ name: String) { timing[name] = Double(started.duration(to: .now).components.seconds) }
    await oldA.createInvitation()
    await oldB.joinInvitation(try #require(oldA.invitationCode))
    try await wait(stage) { oldA.proposal != nil && oldB.proposal != nil }
    await oldA.confirmPairing(); await oldB.confirmPairing()
    try await wait(stage) { oldA.isOnline && oldB.isOnline && a.snapshot == b.snapshot }
    let legacyTask = try a.createTask(title: "Synthetic physical pre-enrollment history")
    let deleted = try b.createTask(title: "Synthetic tombstone")
    try b.deleteTask(deleted)
    try await wait(stage) { a.snapshot == b.snapshot }
    let originalSpace = a.context.spaceId
    oldA.disconnect(); oldB.disconnect()
    let cp = try await OperationInventoryIndex(repository: a.repository).checkpoint()
    let genesis = try SignedSpaceGenesis.sign(SpaceGenesisBody(context: a.context, legacyCheckpoint: cp), with: [ia, ib])
    let sa = try await C1ReplicationService.migrate(engine: a, genesis: genesis)
    let sb = try await C1ReplicationService.migrate(engine: b, genesis: genesis)
    defer { sa.stop(); sb.stop() }
    defer {
      let diagnostic: [String: String] = ["stage": stage, "aState": String(describing: sa.state), "bState": String(describing: sb.state), "aError": sa.errorMessage ?? "", "bError": sb.errorMessage ?? "", "aTasks": String(a.snapshot.tasks.count), "bTasks": String(b.snapshot.tasks.count)]
      try? CanonicalJSON.encode(diagnostic).write(to: root.appendingPathComponent("native-diagnostic.json"), options: .atomic)
    }
    await sa.start(); await sb.start()
    try await wait("native protocol4") { sa.state == .connected && sb.state == .connected }
    let grant = try b.grant(fulfiller: ib.descriptor.userId, beneficiary: ia.descriptor.userId, quantity: 3, date: CivilDate(year: 2026, month: 10, day: 9), notes: "Synthetic physical grant")
    _ = try a.deposit(FinanceAmount(original: "100.01"), by: ia.descriptor.userId, on: CivilDate(year: 2026, month: 10, day: 9))
    _ = try b.createRecurringBill(title: "Synthetic physical bill", amount: FinanceAmount(original: "68"), payment: .init(kind: .reserves), day: 9, timeZone: "Asia/Shanghai", startMonth: FinanceMonth(year: 2026, month: 10))
    let photo = try await b.importMedia(from: root.appendingPathComponent("synthetic.png"), type: .photo)
    let audio = try await b.importMedia(from: root.appendingPathComponent("synthetic.wav"), type: .audio)
    var draft = LoveGiftDraft(); draft.text = "Synthetic physical native gift"; draft.photoAssetId = photo.id; draft.audioAssetId = audio.id
    let gift = try b.sendGift(draft)
    try CanonicalJSON.encode(["legacyTask": legacyTask, "deletedTask": deleted, "grant": grant, "gift": gift]).write(to: root.appendingPathComponent("native-created.json"), options: .atomic)
    let offer = try await sa.createDeviceOffer()
    try CanonicalJSON.encode(offer).write(to: root.appendingPathComponent("offer.json"), options: .atomic)
    checkpoint("offer")
    stage = "independent phone request"
    try await wait(stage, seconds: 120) { exists(root, "request.json") }
    let request = try CanonicalJSON.decode(DeviceEnrollmentRequest.self, from: Data(contentsOf: root.appendingPathComponent("request.json")))
    let completion = try await sa.approveDeviceRequest(request, verified: true)
    #expect(completion.body.archive.genesis.body.spaceId == originalSpace)
    #expect(request.body.device.userId == ia.descriptor.userId)
    #expect(request.body.device.publicKey != ia.descriptor.publicKey)
    try CanonicalJSON.encode(completion).write(to: root.appendingPathComponent("completion.json"), options: .atomic)
    stage = "phone enrolled"
    try await wait(stage, seconds: 120) { exists(root, "phone-created.json") }
    let phone = try CanonicalJSON.decode(Phone.self, from: Data(contentsOf: root.appendingPathComponent("phone-created.json")))
    #expect(phone.device == request.body.device)
    stage = "live business and media"
    try await wait(stage, seconds: 90) { b.snapshot.tasks[phone.task] != nil && b.snapshot.wishes[phone.wish] != nil }
    try b.requestFulfillment(phone.wish)
    try await wait(stage, seconds: 90) {
      a.snapshot.wishes[phone.wish]?.status == .fulfilled && b.receivedGifts.contains { $0.id == phone.gift && b.giftReady($0) } && b.deliveryState(b.snapshot.gifts[gift]!) == .synced
    }
    #expect(try b.snapshot.finance.statistics().bookBalance == 1967)
    #expect(try b.snapshot.finance.statistics().personal.values.reduce(0,+) == 999)
    #expect(b.snapshot.finance.expenses.values.filter { $0.recurringBillId != nil }.count == 1)
    checkpoint("liveBusinessMedia")
    stage = "offline barrier"
    try await wait(stage) { exists(root, "phone-offline.json") }
    try a.append(entity: phone.task, type: .task, action: .patch, fields: ["title": .string("Synthetic Mac offline title")])
    _ = try b.createTask(title: "Synthetic Mac catch-up")
    try Data().write(to: root.appendingPathComponent("native-offline-written"), options: .atomic)
    stage = "phone reconnect convergence"
    try await wait(stage, seconds: 90) { a.snapshot.tasks[phone.task]?.notes == "Synthetic Android offline notes" && b.snapshot.tasks[phone.task]?.notes == "Synthetic Android offline notes" && exists(root,"phone-reconnected.json") }
    #expect(a.snapshot.tasks[phone.task]?.title == "Synthetic Mac offline title")
    let phoneOp = try #require(a.operations.first { $0.operation.entityId == phone.task && $0.operation.operationType == .create })
    let progress = try await sa.progress(for: phoneOp.id)
    #expect(progress.remotePersistedDevices.contains(phone.device.deviceId))
    let finalCheckpoint = try await OperationInventoryIndex(repository: a.repository).checkpoint()
    #expect(try await OperationInventoryIndex(repository: b.repository).checkpoint() == finalCheckpoint)
    checkpoint("reconnected")
    try CanonicalJSON.encode(finalCheckpoint).write(to: root.appendingPathComponent("native-checkpoint.json"), options: .atomic)
    stage = "phone real process restart"
    try await wait(stage, seconds: 120) { exists(root,"phone-restarted.json") }
    checkpoint("processRestart")
    try await sa.revokeDevice(phone.device.deviceId)
    try Data().write(to: root.appendingPathComponent("native-revoked"), options: .atomic)
    stage = "revocation rejected"
    try await wait(stage, seconds: 90) { exists(root,"phone-revoked.json") }
    #expect(a.context.spaceId == originalSpace && b.context.spaceId == originalSpace)
    let received = try #require(b.snapshot.gifts[phone.gift])
    #expect(received.assetIds.allSatisfy { b.snapshot.mediaAssets[$0].map(b.mediaStore.hasVerified) == true })
    let result: [String: String] = ["status": "PASS", "space": originalSpace.uuidString, "bookBalance": "1967", "personal": "999", "wish": "fulfilled", "legacyHistory": "retained", "revocation": "rejected", "photo": photo.sha256, "audio": audio.sha256, "host": "isolated native Swift test process"]
    try CanonicalJSON.encode(result).write(to: root.appendingPathComponent("native-result.json"), options: .atomic)
    try CanonicalJSON.encode(timing).write(to: root.appendingPathComponent("native-timing.json"), options: .atomic)
    stage = "complete"
  }
  private func exists(_ root: URL, _ name: String) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) }
  private struct Timeout: Error, CustomStringConvertible { let description: String }
  private func wait(_ label: String, seconds: Double = 60, _ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while !predicate() { guard ContinuousClock.now < deadline else { throw Timeout(description: "Physical bridge: \(label)") }; try await Task.sleep(for: .milliseconds(100)) }
  }
}
